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
begin
  if auth.uid() is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  -- Transaction writers take ROW EXCLUSIVE on this table. SHARE therefore
  -- makes the accounting snapshot and the validation transition indivisible.
  lock table public.transactions in share mode;

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

  select
    round(account_record.initial_balance * 100)
    + coalesce(sum(
        case
          when transaction.transaction_type in ('income', 'transfer_in')
            then round(transaction.amount * 100)
          else -round(transaction.amount * 100)
        end
      ), 0)
  into calculated_balance_cents
  from public.transactions transaction
  where transaction.financial_account_id = account_record.id
    and transaction.transaction_date <= statement_record.statement_end_date;

  statement_balance_cents := round(statement_record.statement_balance * 100);

  update public.bank_reconciliations
  set status = 'validated',
      calculated_balance = calculated_balance_cents / 100,
      difference = (statement_balance_cents - calculated_balance_cents) / 100,
      validated_at = now(),
      validated_by = auth.uid()
  where id = reconciliation_record.id
  returning * into reconciliation_record;

  return reconciliation_record;
end;
$$;

drop policy if exists "bank_reconciliations_update_manage"
on public.bank_reconciliations;

revoke update on public.bank_reconciliations from authenticated;

revoke all on function public.validate_bank_reconciliation(uuid) from public;
grant execute on function public.validate_bank_reconciliation(uuid) to authenticated;
