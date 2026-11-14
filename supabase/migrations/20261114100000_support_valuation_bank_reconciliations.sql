begin;

alter table public.bank_reconciliations
  add column control_basis text,
  add column reference_date date,
  add column reference_value numeric(15,2),
  add column source_valuation_id uuid references public.account_valuations(id) on delete restrict,
  add constraint bank_reconciliations_control_basis_check
    check (control_basis is null or control_basis in ('transactions', 'valuation')),
  add constraint bank_reconciliations_control_reference_consistent check (
    (status = 'draft'
      and control_basis is null and reference_date is null
      and reference_value is null and source_valuation_id is null)
    or
    (status = 'validated' and (
      (control_basis is null and reference_date is null
        and reference_value is null and source_valuation_id is null)
      or
      (control_basis = 'transactions' and reference_date is not null
        and reference_value is not null and source_valuation_id is null)
      or
      (control_basis = 'valuation' and reference_date is not null
        and reference_value is not null and source_valuation_id is not null)
    ))
  );

create index bank_reconciliations_source_valuation_id_idx
  on public.bank_reconciliations(source_valuation_id)
  where source_valuation_id is not null;

create or replace function public.is_valuation_financial_account_type(p_account_type text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_account_type in ('life_insurance', 'other_investment', 'securities_account');
$$;

create or replace function public.protect_reconciled_account_valuation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.bank_reconciliations reconciliation
    where reconciliation.source_valuation_id = old.id
      and reconciliation.status = 'validated'
      and reconciliation.control_basis = 'valuation'
  ) then
    raise exception using
      errcode = '55000',
      message = 'Cette valorisation est utilisée par un rapprochement validé et ne peut plus être modifiée ou supprimée.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger account_valuations_protect_reconciled
before update or delete on public.account_valuations
for each row execute function public.protect_reconciled_account_valuation();

create or replace function public.reject_valuation_bank_reconciliation_outstanding_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  valuation_account boolean;
begin
  select account.account_type::text in ('life_insurance', 'other_investment', 'securities_account')
  into valuation_account
  from public.bank_reconciliations reconciliation
  join public.bank_statements statement on statement.id = reconciliation.bank_statement_id
  join public.financial_accounts account on account.id = statement.financial_account_id
  where reconciliation.id = new.bank_reconciliation_id;

  if coalesce(valuation_account, false) then
    raise exception using
      errcode = '55000',
      message = 'Les comptes valorisés ne permettent pas le rapprochement détaillé.';
  end if;
  return new;
end;
$$;

create trigger bank_reconciliation_outstanding_reject_valuation
before insert or update on public.bank_reconciliation_outstanding_transactions
for each row execute function public.reject_valuation_bank_reconciliation_outstanding_transaction();

create or replace function public.activate_complete_bank_reconciliation(p_reconciliation_id uuid)
returns public.bank_reconciliations
language plpgsql
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  account_record public.financial_accounts%rowtype;
begin
  if auth.uid() is null then raise exception 'Rapprochement introuvable.'; end if;
  select * into reconciliation_record from public.bank_reconciliations where id = p_reconciliation_id for update;
  select account.* into account_record
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = reconciliation_record.bank_statement_id;
  if reconciliation_record.id is null or account_record.id is null
     or not public.can_manage_protected_person(account_record.protected_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;
  if reconciliation_record.status <> 'draft' then
    raise exception 'Seul un rapprochement en brouillon peut devenir détaillé.';
  end if;
  if public.is_valuation_financial_account_type(account_record.account_type::text) then
    raise exception using errcode = '55000', message = 'Les comptes valorisés ne permettent pas le rapprochement détaillé.';
  end if;
  update public.bank_reconciliations set reconciliation_mode = 'complete'
  where id = reconciliation_record.id returning * into reconciliation_record;
  return reconciliation_record;
end;
$$;

create or replace function public.enforce_bank_reconciliation_cancellation_consistency()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='draft' and new.status='validated' and new.control_basis is distinct from 'valuation' then
    if exists (
      select 1 from public.bank_reconciliation_outstanding_transactions item
      join public.transactions transaction on transaction.id=item.transaction_id
      where item.bank_reconciliation_id=new.id and transaction.cancelled_at is not null
    ) then
      raise exception using errcode='55000',
        message='Le brouillon contient une opération annulée. Révisez le rapprochement avant de le valider.';
    end if;
    if exists (
      select 1 from public.list_transaction_banking_impacts_for_reconciliation(new.id) impact
      where impact.acknowledgement_state='pending'
    ) then
      raise exception using errcode='55000',
        message='Chaque impact bancaire doit être reconnu et justifié avant la validation.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.get_bank_reconciliation_detailed_summary(p_reconciliation_id uuid)
returns table (
  calculated_balance numeric, outstanding_debits numeric, outstanding_credits numeric,
  explained_bank_balance numeric, residual_difference numeric, outstanding_count bigint
) language plpgsql stable security definer set search_path='' as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  account_record public.financial_accounts%rowtype;
  calculated_cents numeric; debit_cents numeric; credit_cents numeric; statement_cents numeric;
begin
  select * into reconciliation_record from public.bank_reconciliations where id=p_reconciliation_id;
  select * into statement_record from public.bank_statements where id=reconciliation_record.bank_statement_id;
  select * into account_record from public.financial_accounts where id=statement_record.financial_account_id;
  if reconciliation_record.id is null or reconciliation_record.reconciliation_mode<>'complete'
     or not public.can_read_protected_person(account_record.protected_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;
  if public.is_valuation_financial_account_type(account_record.account_type::text) then
    raise exception using errcode='55000', message='Les comptes valorisés ne permettent pas le rapprochement détaillé.';
  end if;
  if reconciliation_record.status='validated' then
    return query select reconciliation_record.calculated_balance,reconciliation_record.outstanding_debits,
      reconciliation_record.outstanding_credits,reconciliation_record.explained_bank_balance,
      reconciliation_record.residual_difference,
      (select count(*) from public.bank_reconciliation_outstanding_transactions item where item.bank_reconciliation_id=reconciliation_record.id);
    return;
  end if;
  select round(account_record.initial_balance*100)+coalesce(sum(case
    when transaction.transaction_type in ('income','transfer_in') then round(transaction.amount*100)
    else -round(transaction.amount*100) end),0)
  into calculated_cents from public.transactions transaction
  where transaction.financial_account_id=account_record.id
    and transaction.transaction_date<=statement_record.statement_end_date
    and transaction.cancelled_at is null;
  select
    coalesce(sum(case when transaction.transaction_type in ('expense','transfer_out') then round(transaction.amount*100) else 0 end),0),
    coalesce(sum(case when transaction.transaction_type in ('income','transfer_in') then round(transaction.amount*100) else 0 end),0)
  into debit_cents,credit_cents
  from public.bank_reconciliation_outstanding_transactions item
  join public.transactions transaction on transaction.id=item.transaction_id
  where item.bank_reconciliation_id=reconciliation_record.id and transaction.cancelled_at is null;
  statement_cents:=round(statement_record.statement_balance*100);
  return query select calculated_cents/100,debit_cents/100,credit_cents/100,
    (calculated_cents+debit_cents-credit_cents)/100,
    (statement_cents-calculated_cents-debit_cents+credit_cents)/100,
    (select count(*) from public.bank_reconciliation_outstanding_transactions item
      join public.transactions transaction on transaction.id=item.transaction_id
      where item.bank_reconciliation_id=reconciliation_record.id and transaction.cancelled_at is null);
end;
$$;

create or replace function public.validate_bank_reconciliation(p_reconciliation_id uuid)
returns public.bank_reconciliations
language plpgsql
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  account_record public.financial_accounts%rowtype;
  valuation_record public.account_valuations%rowtype;
  minimum_date date;
  calculated_balance_cents numeric;
  statement_balance_cents numeric;
  outstanding_debits_cents numeric := 0;
  outstanding_credits_cents numeric := 0;
  residual_difference_cents numeric;
  valuation_control boolean;
begin
  if auth.uid() is null then raise exception 'Rapprochement introuvable.'; end if;
  lock table public.transactions in share mode;
  lock table public.bank_reconciliation_outstanding_transactions in share mode;
  select * into reconciliation_record from public.bank_reconciliations where id=p_reconciliation_id for update;
  if reconciliation_record.id is null then raise exception 'Rapprochement introuvable.'; end if;
  select * into statement_record from public.bank_statements where id=reconciliation_record.bank_statement_id for update;
  select * into account_record from public.financial_accounts where id=statement_record.financial_account_id for share;
  if statement_record.id is null or account_record.id is null
     or not public.can_manage_protected_person(account_record.protected_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;
  if reconciliation_record.status<>'draft' then raise exception 'Seul un rapprochement en brouillon peut être validé.'; end if;
  if statement_record.statement_balance is null then raise exception 'Le solde du relevé doit être renseigné avant le contrôle.'; end if;
  minimum_date:=greatest(account_record.initial_balance_date,coalesce(account_record.opening_date,account_record.initial_balance_date));
  if statement_record.statement_end_date<minimum_date then raise exception 'Le relevé est antérieur à la première date rapprochable du compte.'; end if;
  if account_record.closing_date is not null and statement_record.statement_end_date>account_record.closing_date then raise exception 'Le relevé est postérieur à la clôture du compte.'; end if;

  valuation_control := public.is_valuation_financial_account_type(account_record.account_type::text);
  statement_balance_cents := round(statement_record.statement_balance * 100);

  if valuation_control then
    select * into valuation_record
    from public.account_valuations
    where financial_account_id = account_record.id
      and valuation_date = statement_record.statement_end_date
    for share;
    if valuation_record.id is null then
      raise exception using
        errcode = '55000',
        message = format('Aucune valorisation n''est enregistrée au %s. Ajoutez une valorisation à cette date pour contrôler ce relevé.', to_char(statement_record.statement_end_date, 'DD/MM/YYYY'));
    end if;
    calculated_balance_cents := round(valuation_record.value * 100);
    if statement_balance_cents <> calculated_balance_cents then
      raise exception using errcode='55000', message='L''écart de valorisation doit être nul avant la validation.';
    end if;
    update public.bank_reconciliations
    set status='validated', reconciliation_mode='simple', control_basis='valuation',
      reference_date=statement_record.statement_end_date, reference_value=valuation_record.value,
      source_valuation_id=valuation_record.id, calculated_balance=calculated_balance_cents/100,
      difference=(statement_balance_cents-calculated_balance_cents)/100,
      outstanding_debits=null, outstanding_credits=null, explained_bank_balance=null,
      residual_difference=null, validated_at=now(), validated_by=auth.uid()
    where id=reconciliation_record.id returning * into reconciliation_record;
    return reconciliation_record;
  end if;

  if reconciliation_record.reconciliation_mode='complete' and exists (
    select 1 from public.bank_reconciliation_outstanding_transactions item
    left join public.transactions transaction on transaction.id=item.transaction_id
    where item.bank_reconciliation_id=reconciliation_record.id
      and (transaction.id is null or transaction.cancelled_at is not null)
  ) then
    raise exception using errcode='55000',message='Le brouillon contient une opération annulée ou indisponible. Révisez le rapprochement avant de le valider.';
  end if;
  select round(account_record.initial_balance*100)+coalesce(sum(case
    when transaction.transaction_type in ('income','transfer_in') then round(transaction.amount*100)
    else -round(transaction.amount*100) end),0)
  into calculated_balance_cents from public.transactions transaction
  where transaction.financial_account_id=account_record.id
    and transaction.transaction_date<=statement_record.statement_end_date and transaction.cancelled_at is null;
  if reconciliation_record.reconciliation_mode='simple' and statement_balance_cents<>calculated_balance_cents then
    raise exception using errcode='55000',message='L''écart simple doit être nul avant la validation.';
  end if;
  if reconciliation_record.reconciliation_mode='complete' then
    select
      coalesce(sum(case when transaction.transaction_type in ('expense','transfer_out') then round(transaction.amount*100) else 0 end),0),
      coalesce(sum(case when transaction.transaction_type in ('income','transfer_in') then round(transaction.amount*100) else 0 end),0)
    into outstanding_debits_cents,outstanding_credits_cents
    from public.bank_reconciliation_outstanding_transactions item
    join public.transactions transaction on transaction.id=item.transaction_id
    where item.bank_reconciliation_id=reconciliation_record.id and transaction.cancelled_at is null;
    residual_difference_cents:=statement_balance_cents-calculated_balance_cents-outstanding_debits_cents+outstanding_credits_cents;
    if residual_difference_cents<>0 then
      raise exception using errcode='55000',message='L''écart résiduel doit être nul avant la validation.';
    end if;
    update public.bank_reconciliation_outstanding_transactions item
    set transaction_date_snapshot=transaction.transaction_date,transaction_type_snapshot=transaction.transaction_type,
      amount_snapshot=transaction.amount,label_snapshot=transaction.label
    from public.transactions transaction
    where item.bank_reconciliation_id=reconciliation_record.id and transaction.id=item.transaction_id
      and transaction.cancelled_at is null;
  end if;
  update public.bank_reconciliations set status='validated', control_basis='transactions',
    reference_date=statement_record.statement_end_date, reference_value=calculated_balance_cents/100,
    source_valuation_id=null, calculated_balance=calculated_balance_cents/100,
    difference=(statement_balance_cents-calculated_balance_cents)/100,
    outstanding_debits=case when reconciliation_mode='complete' then outstanding_debits_cents/100 else null end,
    outstanding_credits=case when reconciliation_mode='complete' then outstanding_credits_cents/100 else null end,
    explained_bank_balance=case when reconciliation_mode='complete' then (calculated_balance_cents+outstanding_debits_cents-outstanding_credits_cents)/100 else null end,
    residual_difference=case when reconciliation_mode='complete' then residual_difference_cents/100 else null end,
    validated_at=now(),validated_by=auth.uid()
  where id=reconciliation_record.id returning * into reconciliation_record;
  return reconciliation_record;
end;
$$;

revoke all on function public.is_valuation_financial_account_type(text),
  public.protect_reconciled_account_valuation(),
  public.reject_valuation_bank_reconciliation_outstanding_transaction(),
  public.activate_complete_bank_reconciliation(uuid),
  public.enforce_bank_reconciliation_cancellation_consistency(),
  public.get_bank_reconciliation_detailed_summary(uuid),
  public.validate_bank_reconciliation(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.activate_complete_bank_reconciliation(uuid),
  public.get_bank_reconciliation_detailed_summary(uuid),
  public.validate_bank_reconciliation(uuid)
to authenticated;

comment on column public.bank_reconciliations.control_basis is
  'Base figée lors des nouvelles validations : transactions ou valorisation exacte.';
comment on column public.bank_reconciliations.source_valuation_id is
  'Valorisation exacte figée par un rapprochement de compte valorisé.';

commit;
