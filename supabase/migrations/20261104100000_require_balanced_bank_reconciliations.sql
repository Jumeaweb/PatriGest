begin;

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
  minimum_date date;
  calculated_balance_cents numeric;
  statement_balance_cents numeric;
  outstanding_debits_cents numeric := 0;
  outstanding_credits_cents numeric := 0;
  residual_difference_cents numeric;
begin
  if auth.uid() is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  lock table public.transactions in share mode;
  lock table public.bank_reconciliation_outstanding_transactions in share mode;

  select * into reconciliation_record
  from public.bank_reconciliations
  where id = p_reconciliation_id
  for update;

  if reconciliation_record.id is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  select * into statement_record
  from public.bank_statements
  where id = reconciliation_record.bank_statement_id
  for update;

  select * into account_record
  from public.financial_accounts
  where id = statement_record.financial_account_id
  for share;

  if statement_record.id is null
     or account_record.id is null
     or not public.can_manage_protected_person(account_record.protected_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  if reconciliation_record.status <> 'draft' then
    raise exception 'Seul un rapprochement en brouillon peut être validé.';
  end if;

  if statement_record.statement_balance is null then
    raise exception 'Le solde du relevé doit être renseigné avant le contrôle.';
  end if;

  minimum_date := greatest(
    account_record.initial_balance_date,
    coalesce(account_record.opening_date, account_record.initial_balance_date)
  );

  if statement_record.statement_end_date < minimum_date then
    raise exception 'Le relevé est antérieur à la première date rapprochable du compte.';
  end if;

  if account_record.closing_date is not null
     and statement_record.statement_end_date > account_record.closing_date then
    raise exception 'Le relevé est postérieur à la clôture du compte.';
  end if;

  if reconciliation_record.reconciliation_mode = 'complete' and exists (
    select 1
    from public.bank_reconciliation_outstanding_transactions item
    left join public.transactions transaction on transaction.id = item.transaction_id
    where item.bank_reconciliation_id = reconciliation_record.id
      and (transaction.id is null or transaction.cancelled_at is not null)
  ) then
    raise exception using
      errcode = '55000',
      message = 'Le brouillon contient une opération annulée ou indisponible. Révisez le rapprochement avant de le valider.';
  end if;

  select
    round(account_record.initial_balance * 100)
    + coalesce(sum(case
        when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100)
        else -round(transaction.amount * 100)
      end), 0)
  into calculated_balance_cents
  from public.transactions transaction
  where transaction.financial_account_id = account_record.id
    and transaction.transaction_date <= statement_record.statement_end_date
    and transaction.cancelled_at is null;

  statement_balance_cents := round(statement_record.statement_balance * 100);

  if reconciliation_record.reconciliation_mode = 'simple'
     and statement_balance_cents <> calculated_balance_cents then
    raise exception using
      errcode = '55000',
      message = 'L''écart simple doit être nul avant la validation.';
  end if;

  if reconciliation_record.reconciliation_mode = 'complete' then
    select
      coalesce(sum(case when transaction.transaction_type in ('expense', 'transfer_out') then round(transaction.amount * 100) else 0 end), 0),
      coalesce(sum(case when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100) else 0 end), 0)
    into outstanding_debits_cents, outstanding_credits_cents
    from public.bank_reconciliation_outstanding_transactions item
    join public.transactions transaction on transaction.id = item.transaction_id
    where item.bank_reconciliation_id = reconciliation_record.id
      and transaction.cancelled_at is null;

    residual_difference_cents := statement_balance_cents
      - calculated_balance_cents
      - outstanding_debits_cents
      + outstanding_credits_cents;

    if residual_difference_cents <> 0 then
      raise exception using
        errcode = '55000',
        message = 'L''écart résiduel doit être nul avant la validation.';
    end if;

    update public.bank_reconciliation_outstanding_transactions item
    set transaction_date_snapshot = transaction.transaction_date,
        transaction_type_snapshot = transaction.transaction_type,
        amount_snapshot = transaction.amount,
        label_snapshot = transaction.label
    from public.transactions transaction
    where item.bank_reconciliation_id = reconciliation_record.id
      and transaction.id = item.transaction_id
      and transaction.cancelled_at is null;
  end if;

  update public.bank_reconciliations
  set status = 'validated',
      calculated_balance = calculated_balance_cents / 100,
      difference = (statement_balance_cents - calculated_balance_cents) / 100,
      outstanding_debits = case when reconciliation_mode = 'complete' then outstanding_debits_cents / 100 else null end,
      outstanding_credits = case when reconciliation_mode = 'complete' then outstanding_credits_cents / 100 else null end,
      explained_bank_balance = case when reconciliation_mode = 'complete' then (calculated_balance_cents + outstanding_debits_cents - outstanding_credits_cents) / 100 else null end,
      residual_difference = case when reconciliation_mode = 'complete' then residual_difference_cents / 100 else null end,
      validated_at = now(),
      validated_by = auth.uid()
  where id = reconciliation_record.id
  returning * into reconciliation_record;

  return reconciliation_record;
end;
$$;

revoke all on function public.validate_bank_reconciliation(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.validate_bank_reconciliation(uuid)
to authenticated;

comment on function public.validate_bank_reconciliation(uuid) is
  'Valide atomiquement un rapprochement équilibré : écart simple nul ou écart résiduel nul selon le mode.';

commit;
