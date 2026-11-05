-- Les rapprochements validés conservent leurs snapshots. Seuls les brouillons
-- et les validations futures utilisent l'état courant non annulé.

begin;

create table public.transaction_banking_impact_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  impact_id uuid not null unique references public.transaction_banking_impacts(id) on delete restrict,
  bank_reconciliation_id uuid not null references public.bank_reconciliations(id) on delete cascade,
  justification text not null check (length(btrim(justification)) >= 3),
  acknowledged_by uuid references auth.users(id) on delete set null,
  acknowledged_by_name text not null,
  acknowledged_at timestamptz not null default clock_timestamp()
);

create index transaction_banking_impact_ack_reconciliation_idx
  on public.transaction_banking_impact_acknowledgements(bank_reconciliation_id);

alter table public.transaction_banking_impact_acknowledgements enable row level security;
create policy transaction_banking_impact_ack_select_accessible
on public.transaction_banking_impact_acknowledgements for select to authenticated
using (exists (
  select 1 from public.transaction_banking_impacts impact
  where impact.id=impact_id and public.can_read_protected_person(impact.protected_person_id)
));

revoke all on table public.transaction_banking_impact_acknowledgements
from public, anon, authenticated, service_role;
grant select on table public.transaction_banking_impact_acknowledgements to authenticated;

create trigger transaction_banking_impact_ack_immutable
before update or delete on public.transaction_banking_impact_acknowledgements
for each row execute function public.protect_financial_operation_audit_rows();

create function public.reject_cancelled_bank_reconciliation_outstanding_transaction()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.transaction_id is not null and exists (
    select 1 from public.transactions transaction
    where transaction.id=new.transaction_id and transaction.cancelled_at is not null
  ) then
    raise exception using errcode='55000',
      message='Une opération annulée ne peut pas être ajoutée au rapprochement.';
  end if;
  return new;
end;
$$;

create trigger bank_reconciliation_outstanding_00_reject_cancelled
before insert on public.bank_reconciliation_outstanding_transactions
for each row execute function public.reject_cancelled_bank_reconciliation_outstanding_transaction();

-- La branche validée lit uniquement les snapshots historiques. La branche
-- brouillon filtre avant LIMIT afin que la pagination ne perde aucune ligne.
create or replace function public.list_bank_reconciliation_candidate_transactions(
  p_reconciliation_id uuid,
  p_after_date date default null,
  p_after_created_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 51
) returns table (
  transaction_id uuid, transaction_date date, transaction_created_at timestamptz,
  transaction_type text, label text, amount numeric,
  is_outstanding boolean, carried_from_previous boolean
) language plpgsql stable security definer set search_path='' as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  account_person_id uuid;
  previous_reconciliation_id uuid;
  previous_statement_end_date date;
  previous_validated_at timestamptz;
  safe_limit integer:=least(greatest(coalesce(p_limit,51),1),51);
begin
  select * into reconciliation_record from public.bank_reconciliations where id=p_reconciliation_id;
  select * into statement_record from public.bank_statements where id=reconciliation_record.bank_statement_id;
  select protected_person_id into account_person_id from public.financial_accounts
  where id=statement_record.financial_account_id;
  if reconciliation_record.id is null or reconciliation_record.reconciliation_mode<>'complete'
     or not public.can_read_protected_person(account_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;
  if reconciliation_record.status='validated' then
    return query
    select item.transaction_id_snapshot,item.transaction_date_snapshot,item.created_at,
      item.transaction_type_snapshot,item.label_snapshot,item.amount_snapshot,true,false
    from public.bank_reconciliation_outstanding_transactions item
    where item.bank_reconciliation_id=reconciliation_record.id
      and (p_after_date is null or (item.transaction_date_snapshot,item.created_at,item.transaction_id_snapshot)>(p_after_date,p_after_created_at,p_after_id))
    order by item.transaction_date_snapshot,item.created_at,item.transaction_id_snapshot
    limit safe_limit;
    return;
  end if;
  select reconciliation.id,statement.statement_end_date,reconciliation.validated_at
  into previous_reconciliation_id,previous_statement_end_date,previous_validated_at
  from public.bank_reconciliations reconciliation
  join public.bank_statements statement on statement.id=reconciliation.bank_statement_id
  where statement.financial_account_id=statement_record.financial_account_id
    and statement.statement_end_date<statement_record.statement_end_date
    and reconciliation.status='validated' and reconciliation.reconciliation_mode='complete'
  order by statement.statement_end_date desc,reconciliation.validated_at desc,reconciliation.id desc limit 1;
  return query
  select transaction.id,transaction.transaction_date,transaction.created_at,
    transaction.transaction_type,transaction.label,transaction.amount,
    current_outstanding.id is not null,previous_outstanding.id is not null
  from public.transactions transaction
  left join public.bank_reconciliation_outstanding_transactions current_outstanding
    on current_outstanding.bank_reconciliation_id=reconciliation_record.id
   and current_outstanding.transaction_id_snapshot=transaction.id
  left join public.bank_reconciliation_outstanding_transactions previous_outstanding
    on previous_outstanding.bank_reconciliation_id=previous_reconciliation_id
   and previous_outstanding.transaction_id_snapshot=transaction.id
  where transaction.financial_account_id=statement_record.financial_account_id
    and transaction.transaction_date<=statement_record.statement_end_date
    and transaction.cancelled_at is null
    and (previous_reconciliation_id is null or transaction.transaction_date>previous_statement_end_date
      or transaction.updated_at>previous_validated_at or previous_outstanding.id is not null
      or current_outstanding.id is not null)
    and (p_after_date is null or (transaction.transaction_date,transaction.created_at,transaction.id)>(p_after_date,p_after_created_at,p_after_id))
  order by transaction.transaction_date,transaction.created_at,transaction.id
  limit safe_limit;
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

create function public.list_transaction_banking_impacts_for_reconciliation(p_reconciliation_id uuid)
returns table (
  impact_id uuid, transaction_id uuid, impact_kind text, signed_amount numeric,
  effective_date date, impact_created_at timestamptz,
  historical_reconciliation_id uuid, historical_statement_end_date date,
  acknowledgement_state text, acknowledgement_id uuid,
  justification text, acknowledged_at timestamptz
) language sql stable security definer set search_path='' as $$
  with current_context as (
    select reconciliation.id,statement.financial_account_id,statement.statement_end_date,account.protected_person_id
    from public.bank_reconciliations reconciliation
    join public.bank_statements statement on statement.id=reconciliation.bank_statement_id
    join public.financial_accounts account on account.id=statement.financial_account_id
    where reconciliation.id=p_reconciliation_id
      and public.can_read_protected_person(account.protected_person_id)
  )
  select impact.id,impact.transaction_id,impact.impact_kind,impact.signed_amount,
    impact.effective_date,impact.created_at,historical.id,historical.statement_end_date,
    case when acknowledgement.id is null then 'pending' else 'acknowledged' end,
    acknowledgement.id,acknowledgement.justification,acknowledgement.acknowledged_at
  from current_context context
  join public.transaction_banking_impacts impact on impact.financial_account_id=context.financial_account_id
  join lateral (
    select reconciliation.id,statement.statement_end_date
    from public.bank_reconciliations reconciliation
    join public.bank_statements statement on statement.id=reconciliation.bank_statement_id
    where statement.financial_account_id=context.financial_account_id
      and reconciliation.status='validated'
      and statement.statement_end_date>=impact.effective_date
      and reconciliation.validated_at<impact.created_at
    order by statement.statement_end_date desc,reconciliation.validated_at desc,reconciliation.id desc limit 1
  ) historical on context.statement_end_date>historical.statement_end_date
  left join public.transaction_banking_impact_acknowledgements acknowledgement
    on acknowledgement.impact_id=impact.id and acknowledgement.bank_reconciliation_id=context.id
  where not exists (
    select 1 from public.transaction_banking_impact_acknowledgements prior_ack
    join public.bank_reconciliations prior on prior.id=prior_ack.bank_reconciliation_id and prior.status='validated'
    where prior_ack.impact_id=impact.id and prior_ack.bank_reconciliation_id<>context.id
  )
  order by impact.created_at,impact.id;
$$;

create function public.acknowledge_transaction_banking_impact(
  p_reconciliation_id uuid,p_impact_id uuid,p_justification text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor_id uuid:=auth.uid(); reconciliation_record public.bank_reconciliations%rowtype;
  impact_record public.transaction_banking_impacts%rowtype; statement_record public.bank_statements%rowtype;
  account_record public.financial_accounts%rowtype; historical_end date; acknowledgement_record public.transaction_banking_impact_acknowledgements%rowtype;
begin
  if actor_id is null or length(btrim(coalesce(p_justification,'')))<3 then
    raise exception using errcode='22023',message='Une justification est obligatoire.';
  end if;
  select * into reconciliation_record from public.bank_reconciliations where id=p_reconciliation_id for update;
  select * into statement_record from public.bank_statements where id=reconciliation_record.bank_statement_id;
  select * into account_record from public.financial_accounts where id=statement_record.financial_account_id;
  select * into impact_record from public.transaction_banking_impacts where id=p_impact_id for share;
  if reconciliation_record.id is null or reconciliation_record.status<>'draft'
     or impact_record.id is null or impact_record.financial_account_id<>account_record.id
     or not public.can_manage_protected_person(account_record.protected_person_id) then
    raise exception using errcode='42501',message='Rapprochement ou impact introuvable.';
  end if;
  select statement.statement_end_date into historical_end
  from public.bank_reconciliations historical
  join public.bank_statements statement on statement.id=historical.bank_statement_id
  where statement.financial_account_id=account_record.id and historical.status='validated'
    and statement.statement_end_date>=impact_record.effective_date
    and historical.validated_at<impact_record.created_at
  order by statement.statement_end_date desc,historical.validated_at desc,historical.id desc limit 1;
  if historical_end is null or statement_record.statement_end_date<=historical_end then
    raise exception using errcode='55000',message='Cet impact ne relève pas de ce rapprochement.';
  end if;
  begin
    insert into public.transaction_banking_impact_acknowledgements(
      impact_id,bank_reconciliation_id,justification,acknowledged_by,acknowledged_by_name
    ) values(p_impact_id,p_reconciliation_id,btrim(p_justification),actor_id,public.financial_operation_actor_name(actor_id))
    returning * into acknowledgement_record;
  exception when unique_violation then
    select * into acknowledgement_record from public.transaction_banking_impact_acknowledgements where impact_id=p_impact_id;
    if acknowledgement_record.bank_reconciliation_id<>p_reconciliation_id
       or acknowledgement_record.justification<>btrim(p_justification) then
      raise exception using errcode='23505',message='Cet impact a déjà reçu une autre reconnaissance.';
    end if;
  end;
  return jsonb_build_object('id',acknowledgement_record.id,'impactId',p_impact_id,
    'reconciliationId',p_reconciliation_id,'acknowledgedAt',acknowledgement_record.acknowledged_at);
end;
$$;

create function public.enforce_bank_reconciliation_cancellation_consistency()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='draft' and new.status='validated' then
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

create trigger bank_reconciliations_05_enforce_cancellation_consistency
before update of status on public.bank_reconciliations
for each row execute function public.enforce_bank_reconciliation_cancellation_consistency();

-- La fonction reste volontairement complète : elle verrouille les mêmes objets,
-- refuse les brouillons incohérents puis calcule uniquement les lignes actives.
create or replace function public.validate_bank_reconciliation(p_reconciliation_id uuid)
returns public.bank_reconciliations language plpgsql security definer set search_path='' as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype; statement_record public.bank_statements%rowtype;
  account_record public.financial_accounts%rowtype; minimum_date date; calculated_balance_cents numeric;
  statement_balance_cents numeric; outstanding_debits_cents numeric:=0; outstanding_credits_cents numeric:=0;
begin
  if auth.uid() is null then raise exception 'Rapprochement introuvable.'; end if;
  lock table public.transactions in share mode;
  lock table public.bank_reconciliation_outstanding_transactions in share mode;
  select * into reconciliation_record from public.bank_reconciliations where id=p_reconciliation_id for update;
  if reconciliation_record.id is null then raise exception 'Rapprochement introuvable.'; end if;
  select * into statement_record from public.bank_statements where id=reconciliation_record.bank_statement_id for update;
  select * into account_record from public.financial_accounts where id=statement_record.financial_account_id for share;
  if statement_record.id is null or account_record.id is null
     or not public.can_manage_protected_person(account_record.protected_person_id) then raise exception 'Rapprochement introuvable.'; end if;
  if reconciliation_record.status<>'draft' then raise exception 'Seul un rapprochement en brouillon peut être validé.'; end if;
  if statement_record.statement_balance is null then raise exception 'Le solde du relevé doit être renseigné avant le contrôle.'; end if;
  minimum_date:=greatest(account_record.initial_balance_date,coalesce(account_record.opening_date,account_record.initial_balance_date));
  if statement_record.statement_end_date<minimum_date then raise exception 'Le relevé est antérieur à la première date rapprochable du compte.'; end if;
  if account_record.closing_date is not null and statement_record.statement_end_date>account_record.closing_date then raise exception 'Le relevé est postérieur à la clôture du compte.'; end if;
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
  statement_balance_cents:=round(statement_record.statement_balance*100);
  if reconciliation_record.reconciliation_mode='complete' then
    select
      coalesce(sum(case when transaction.transaction_type in ('expense','transfer_out') then round(transaction.amount*100) else 0 end),0),
      coalesce(sum(case when transaction.transaction_type in ('income','transfer_in') then round(transaction.amount*100) else 0 end),0)
    into outstanding_debits_cents,outstanding_credits_cents
    from public.bank_reconciliation_outstanding_transactions item
    join public.transactions transaction on transaction.id=item.transaction_id
    where item.bank_reconciliation_id=reconciliation_record.id and transaction.cancelled_at is null;
    update public.bank_reconciliation_outstanding_transactions item
    set transaction_date_snapshot=transaction.transaction_date,transaction_type_snapshot=transaction.transaction_type,
      amount_snapshot=transaction.amount,label_snapshot=transaction.label
    from public.transactions transaction
    where item.bank_reconciliation_id=reconciliation_record.id and transaction.id=item.transaction_id
      and transaction.cancelled_at is null;
  end if;
  update public.bank_reconciliations set status='validated',calculated_balance=calculated_balance_cents/100,
    difference=(statement_balance_cents-calculated_balance_cents)/100,
    outstanding_debits=case when reconciliation_mode='complete' then outstanding_debits_cents/100 else null end,
    outstanding_credits=case when reconciliation_mode='complete' then outstanding_credits_cents/100 else null end,
    explained_bank_balance=case when reconciliation_mode='complete' then (calculated_balance_cents+outstanding_debits_cents-outstanding_credits_cents)/100 else null end,
    residual_difference=case when reconciliation_mode='complete' then (statement_balance_cents-calculated_balance_cents-outstanding_debits_cents+outstanding_credits_cents)/100 else null end,
    validated_at=now(),validated_by=auth.uid()
  where id=reconciliation_record.id returning * into reconciliation_record;
  return reconciliation_record;
end;
$$;

revoke all on function public.reject_cancelled_bank_reconciliation_outstanding_transaction(),
  public.list_bank_reconciliation_candidate_transactions(uuid,date,timestamptz,uuid,integer),
  public.get_bank_reconciliation_detailed_summary(uuid),
  public.list_transaction_banking_impacts_for_reconciliation(uuid),
  public.acknowledge_transaction_banking_impact(uuid,uuid,text),
  public.enforce_bank_reconciliation_cancellation_consistency(),
  public.validate_bank_reconciliation(uuid)
from public,anon,authenticated,service_role;

grant execute on function public.list_bank_reconciliation_candidate_transactions(uuid,date,timestamptz,uuid,integer),
  public.get_bank_reconciliation_detailed_summary(uuid),
  public.list_transaction_banking_impacts_for_reconciliation(uuid),
  public.acknowledge_transaction_banking_impact(uuid,uuid,text),
  public.validate_bank_reconciliation(uuid)
to authenticated;

comment on table public.transaction_banking_impact_acknowledgements is
  'Reconnaissances explicites, justifiées et immuables des impacts bancaires lors du rapprochement suivant.';

commit;
