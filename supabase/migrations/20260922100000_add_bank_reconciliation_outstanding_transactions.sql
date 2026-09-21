alter table public.bank_reconciliations
  add column reconciliation_mode text not null default 'simple'
    check (reconciliation_mode in ('simple', 'complete')),
  add column outstanding_debits numeric(16,2),
  add column outstanding_credits numeric(16,2),
  add column explained_bank_balance numeric(16,2),
  add column residual_difference numeric(16,2),
  add constraint bank_reconciliations_detailed_state_consistent check (
    (
      reconciliation_mode = 'simple'
      and outstanding_debits is null
      and outstanding_credits is null
      and explained_bank_balance is null
      and residual_difference is null
    )
    or
    (
      reconciliation_mode = 'complete'
      and (
        (
          status = 'draft'
          and outstanding_debits is null
          and outstanding_credits is null
          and explained_bank_balance is null
          and residual_difference is null
        )
        or
        (
          status = 'validated'
          and outstanding_debits is not null
          and outstanding_credits is not null
          and explained_bank_balance is not null
          and residual_difference is not null
        )
      )
    )
  );

create table public.bank_reconciliation_outstanding_transactions (
  id uuid primary key default gen_random_uuid(),
  bank_reconciliation_id uuid not null
    references public.bank_reconciliations(id) on delete cascade,
  transaction_id uuid references public.transactions(id) on delete set null,
  transaction_id_snapshot uuid not null,
  transaction_date_snapshot date,
  transaction_type_snapshot text
    check (transaction_type_snapshot is null or transaction_type_snapshot in ('income', 'expense', 'transfer_in', 'transfer_out')),
  amount_snapshot numeric(14,2) check (amount_snapshot is null or amount_snapshot > 0),
  label_snapshot text check (label_snapshot is null or length(trim(label_snapshot)) > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint bank_reconciliation_outstanding_snapshot_consistent check (
    num_nulls(transaction_date_snapshot, transaction_type_snapshot, amount_snapshot, label_snapshot) in (0, 4)
  ),
  constraint bank_reconciliation_outstanding_transaction_unique
    unique (bank_reconciliation_id, transaction_id_snapshot)
);

create index bank_reconciliation_outstanding_reconciliation_idx
  on public.bank_reconciliation_outstanding_transactions(bank_reconciliation_id);
create index bank_reconciliation_outstanding_transaction_idx
  on public.bank_reconciliation_outstanding_transactions(transaction_id)
  where transaction_id is not null;

create or replace function public.protect_bank_reconciliation_outstanding_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  transaction_record public.transactions%rowtype;
  account_person_id uuid;
begin
  select * into reconciliation_record
  from public.bank_reconciliations
  where id = coalesce(new.bank_reconciliation_id, old.bank_reconciliation_id);

  if reconciliation_record.id is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  if tg_op = 'UPDATE'
     and old.created_by is not null
     and new.created_by is null
     and new.transaction_id is not distinct from old.transaction_id
     and (
       to_jsonb(new) - 'created_by'
       = to_jsonb(old) - 'created_by'
     )
     and not exists (select 1 from auth.users where id = old.created_by) then
    return new;
  end if;

  if reconciliation_record.status = 'validated' then
    if tg_op = 'UPDATE'
       and old.transaction_id is not null
       and new.transaction_id is null
       and (
         to_jsonb(new) - 'transaction_id'
         = to_jsonb(old) - 'transaction_id'
       ) then
      return new;
    end if;
    raise exception 'Les opérations d''un rapprochement validé sont définitivement figées.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.bank_reconciliation_id is distinct from old.bank_reconciliation_id
       or new.transaction_id is distinct from old.transaction_id
       or new.transaction_id_snapshot is distinct from old.transaction_id_snapshot
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'Le rattachement de l''opération en circulation ne peut pas être modifié.';
    end if;
    return new;
  end if;

  if reconciliation_record.status <> 'draft'
     or reconciliation_record.reconciliation_mode <> 'complete' then
    raise exception 'Le rapprochement détaillé doit être un brouillon.';
  end if;

  select * into statement_record
  from public.bank_statements
  where id = reconciliation_record.bank_statement_id;

  select * into transaction_record
  from public.transactions
  where id = new.transaction_id;

  select protected_person_id into account_person_id
  from public.financial_accounts
  where id = statement_record.financial_account_id;

  if auth.uid() is null
     or account_person_id is null
     or not public.can_manage_protected_person(account_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  if transaction_record.id is null
     or transaction_record.financial_account_id <> statement_record.financial_account_id then
    raise exception 'L''opération n''appartient pas au compte du relevé.';
  end if;

  if transaction_record.transaction_date > statement_record.statement_end_date then
    raise exception 'L''opération est postérieure au relevé.';
  end if;

  if new.transaction_id_snapshot is distinct from new.transaction_id
     or new.created_by is distinct from auth.uid()
     or num_nonnulls(
       new.transaction_date_snapshot,
       new.transaction_type_snapshot,
       new.amount_snapshot,
       new.label_snapshot
     ) <> 0 then
    raise exception 'Les snapshots sont réservés à la validation.';
  end if;

  return new;
end;
$$;

create trigger bank_reconciliation_outstanding_protect
before insert or update or delete
on public.bank_reconciliation_outstanding_transactions
for each row execute function public.protect_bank_reconciliation_outstanding_transaction();

create or replace function public.cleanup_draft_bank_reconciliation_outstanding_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.bank_reconciliation_outstanding_transactions outstanding
  using public.bank_reconciliations reconciliation
  where outstanding.transaction_id = old.id
    and reconciliation.id = outstanding.bank_reconciliation_id
    and reconciliation.status = 'draft';
  return old;
end;
$$;

create trigger transactions_cleanup_draft_reconciliation_outstanding
before delete on public.transactions
for each row execute function public.cleanup_draft_bank_reconciliation_outstanding_transaction();

alter table public.bank_reconciliation_outstanding_transactions enable row level security;

create policy "bank_reconciliation_outstanding_select_accessible"
on public.bank_reconciliation_outstanding_transactions
for select to authenticated
using (exists (
  select 1
  from public.bank_reconciliations reconciliation
  join public.bank_statements statement on statement.id = reconciliation.bank_statement_id
  join public.financial_accounts account on account.id = statement.financial_account_id
  where reconciliation.id = bank_reconciliation_outstanding_transactions.bank_reconciliation_id
    and public.can_read_protected_person(account.protected_person_id)
));

revoke all on public.bank_reconciliation_outstanding_transactions from authenticated;
grant select on public.bank_reconciliation_outstanding_transactions to authenticated;

create or replace function public.activate_complete_bank_reconciliation(p_reconciliation_id uuid)
returns public.bank_reconciliations
language plpgsql
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  account_person_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  select * into reconciliation_record
  from public.bank_reconciliations
  where id = p_reconciliation_id
  for update;

  select account.protected_person_id into account_person_id
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = reconciliation_record.bank_statement_id;

  if reconciliation_record.id is null
     or not public.can_manage_protected_person(account_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  if reconciliation_record.status <> 'draft' then
    raise exception 'Seul un rapprochement en brouillon peut devenir détaillé.';
  end if;

  update public.bank_reconciliations
  set reconciliation_mode = 'complete'
  where id = reconciliation_record.id
  returning * into reconciliation_record;

  return reconciliation_record;
end;
$$;

create or replace function public.add_bank_reconciliation_outstanding_transaction(
  p_reconciliation_id uuid,
  p_transaction_id uuid
)
returns public.bank_reconciliation_outstanding_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.bank_reconciliation_outstanding_transactions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  insert into public.bank_reconciliation_outstanding_transactions (
    bank_reconciliation_id,
    transaction_id,
    transaction_id_snapshot,
    created_by
  ) values (
    p_reconciliation_id,
    p_transaction_id,
    p_transaction_id,
    auth.uid()
  )
  returning * into result;

  return result;
end;
$$;

create or replace function public.remove_bank_reconciliation_outstanding_transaction(
  p_reconciliation_id uuid,
  p_transaction_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  account_person_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Rapprochement introuvable.';
  end if;

  select * into reconciliation_record
  from public.bank_reconciliations
  where id = p_reconciliation_id
  for update;

  select account.protected_person_id into account_person_id
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = reconciliation_record.bank_statement_id;

  if reconciliation_record.id is null
     or reconciliation_record.status <> 'draft'
     or reconciliation_record.reconciliation_mode <> 'complete'
     or not public.can_manage_protected_person(account_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  delete from public.bank_reconciliation_outstanding_transactions
  where bank_reconciliation_id = p_reconciliation_id
    and transaction_id_snapshot = p_transaction_id;

  if not found then
    raise exception 'Opération en circulation introuvable.';
  end if;
end;
$$;

create or replace function public.list_bank_reconciliation_candidate_transactions(
  p_reconciliation_id uuid,
  p_after_date date default null,
  p_after_created_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 51
)
returns table (
  transaction_id uuid,
  transaction_date date,
  transaction_created_at timestamptz,
  transaction_type text,
  label text,
  amount numeric,
  is_outstanding boolean,
  carried_from_previous boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  account_person_id uuid;
  previous_reconciliation_id uuid;
  previous_statement_end_date date;
  previous_validated_at timestamptz;
  safe_limit integer := least(greatest(coalesce(p_limit, 51), 1), 51);
begin
  select * into reconciliation_record
  from public.bank_reconciliations
  where id = p_reconciliation_id;

  select * into statement_record
  from public.bank_statements
  where id = reconciliation_record.bank_statement_id;

  select protected_person_id into account_person_id
  from public.financial_accounts
  where id = statement_record.financial_account_id;

  if reconciliation_record.id is null
     or reconciliation_record.reconciliation_mode <> 'complete'
     or not public.can_read_protected_person(account_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  if reconciliation_record.status = 'validated' then
    return query
    select
      item.transaction_id_snapshot,
      item.transaction_date_snapshot,
      item.created_at,
      item.transaction_type_snapshot,
      item.label_snapshot,
      item.amount_snapshot,
      true,
      false
    from public.bank_reconciliation_outstanding_transactions item
    where item.bank_reconciliation_id = reconciliation_record.id
      and (
        p_after_date is null
        or (item.transaction_date_snapshot, item.created_at, item.transaction_id_snapshot)
           > (p_after_date, p_after_created_at, p_after_id)
      )
    order by item.transaction_date_snapshot, item.created_at, item.transaction_id_snapshot
    limit safe_limit;
    return;
  end if;

  select reconciliation.id, statement.statement_end_date, reconciliation.validated_at
  into previous_reconciliation_id, previous_statement_end_date, previous_validated_at
  from public.bank_reconciliations reconciliation
  join public.bank_statements statement on statement.id = reconciliation.bank_statement_id
  where statement.financial_account_id = statement_record.financial_account_id
    and statement.statement_end_date < statement_record.statement_end_date
    and reconciliation.status = 'validated'
    and reconciliation.reconciliation_mode = 'complete'
  order by statement.statement_end_date desc, reconciliation.validated_at desc, reconciliation.id desc
  limit 1;

  return query
  select
    transaction.id,
    transaction.transaction_date,
    transaction.created_at,
    transaction.transaction_type,
    transaction.label,
    transaction.amount,
    current_outstanding.id is not null,
    previous_outstanding.id is not null
  from public.transactions transaction
  left join public.bank_reconciliation_outstanding_transactions current_outstanding
    on current_outstanding.bank_reconciliation_id = reconciliation_record.id
   and current_outstanding.transaction_id_snapshot = transaction.id
  left join public.bank_reconciliation_outstanding_transactions previous_outstanding
    on previous_outstanding.bank_reconciliation_id = previous_reconciliation_id
   and previous_outstanding.transaction_id_snapshot = transaction.id
  where transaction.financial_account_id = statement_record.financial_account_id
    and transaction.transaction_date <= statement_record.statement_end_date
    and (
      previous_reconciliation_id is null
      or transaction.transaction_date > previous_statement_end_date
      or transaction.updated_at > previous_validated_at
      or previous_outstanding.id is not null
      or current_outstanding.id is not null
    )
    and (
      p_after_date is null
      or (transaction.transaction_date, transaction.created_at, transaction.id)
         > (p_after_date, p_after_created_at, p_after_id)
    )
  order by transaction.transaction_date, transaction.created_at, transaction.id
  limit safe_limit;
end;
$$;

create or replace function public.get_bank_reconciliation_detailed_summary(p_reconciliation_id uuid)
returns table (
  calculated_balance numeric,
  outstanding_debits numeric,
  outstanding_credits numeric,
  explained_bank_balance numeric,
  residual_difference numeric,
  outstanding_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  reconciliation_record public.bank_reconciliations%rowtype;
  statement_record public.bank_statements%rowtype;
  account_record public.financial_accounts%rowtype;
  calculated_cents numeric;
  debit_cents numeric;
  credit_cents numeric;
  statement_cents numeric;
begin
  select * into reconciliation_record
  from public.bank_reconciliations
  where id = p_reconciliation_id;

  select * into statement_record
  from public.bank_statements
  where id = reconciliation_record.bank_statement_id;

  select * into account_record
  from public.financial_accounts
  where id = statement_record.financial_account_id;

  if reconciliation_record.id is null
     or reconciliation_record.reconciliation_mode <> 'complete'
     or not public.can_read_protected_person(account_record.protected_person_id) then
    raise exception 'Rapprochement introuvable.';
  end if;

  if reconciliation_record.status = 'validated' then
    return query select
      reconciliation_record.calculated_balance,
      reconciliation_record.outstanding_debits,
      reconciliation_record.outstanding_credits,
      reconciliation_record.explained_bank_balance,
      reconciliation_record.residual_difference,
      (select count(*) from public.bank_reconciliation_outstanding_transactions item
       where item.bank_reconciliation_id = reconciliation_record.id);
    return;
  end if;

  select
    round(account_record.initial_balance * 100)
      + coalesce(sum(case
          when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100)
          else -round(transaction.amount * 100)
        end), 0)
  into calculated_cents
  from public.transactions transaction
  where transaction.financial_account_id = account_record.id
    and transaction.transaction_date <= statement_record.statement_end_date;

  select
    coalesce(sum(case when transaction.transaction_type in ('expense', 'transfer_out') then round(transaction.amount * 100) else 0 end), 0),
    coalesce(sum(case when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100) else 0 end), 0)
  into debit_cents, credit_cents
  from public.bank_reconciliation_outstanding_transactions item
  join public.transactions transaction on transaction.id = item.transaction_id
  where item.bank_reconciliation_id = reconciliation_record.id;

  statement_cents := round(statement_record.statement_balance * 100);

  return query select
    calculated_cents / 100,
    debit_cents / 100,
    credit_cents / 100,
    (calculated_cents + debit_cents - credit_cents) / 100,
    (statement_cents - calculated_cents - debit_cents + credit_cents) / 100,
    (select count(*) from public.bank_reconciliation_outstanding_transactions item
     where item.bank_reconciliation_id = reconciliation_record.id);
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
  minimum_date date;
  calculated_balance_cents numeric;
  statement_balance_cents numeric;
  outstanding_debits_cents numeric := 0;
  outstanding_credits_cents numeric := 0;
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

  select
    round(account_record.initial_balance * 100)
    + coalesce(sum(case
        when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100)
        else -round(transaction.amount * 100)
      end), 0)
  into calculated_balance_cents
  from public.transactions transaction
  where transaction.financial_account_id = account_record.id
    and transaction.transaction_date <= statement_record.statement_end_date;

  statement_balance_cents := round(statement_record.statement_balance * 100);

  if reconciliation_record.reconciliation_mode = 'complete' then
    if exists (
      select 1
      from public.bank_reconciliation_outstanding_transactions item
      where item.bank_reconciliation_id = reconciliation_record.id
        and item.transaction_id is null
    ) then
      raise exception 'Une opération en circulation n''existe plus.';
    end if;

    select
      coalesce(sum(case when transaction.transaction_type in ('expense', 'transfer_out') then round(transaction.amount * 100) else 0 end), 0),
      coalesce(sum(case when transaction.transaction_type in ('income', 'transfer_in') then round(transaction.amount * 100) else 0 end), 0)
    into outstanding_debits_cents, outstanding_credits_cents
    from public.bank_reconciliation_outstanding_transactions item
    join public.transactions transaction on transaction.id = item.transaction_id
    where item.bank_reconciliation_id = reconciliation_record.id;

    update public.bank_reconciliation_outstanding_transactions item
    set transaction_date_snapshot = transaction.transaction_date,
        transaction_type_snapshot = transaction.transaction_type,
        amount_snapshot = transaction.amount,
        label_snapshot = transaction.label
    from public.transactions transaction
    where item.bank_reconciliation_id = reconciliation_record.id
      and transaction.id = item.transaction_id;
  end if;

  update public.bank_reconciliations
  set status = 'validated',
      calculated_balance = calculated_balance_cents / 100,
      difference = (statement_balance_cents - calculated_balance_cents) / 100,
      outstanding_debits = case when reconciliation_mode = 'complete' then outstanding_debits_cents / 100 else null end,
      outstanding_credits = case when reconciliation_mode = 'complete' then outstanding_credits_cents / 100 else null end,
      explained_bank_balance = case when reconciliation_mode = 'complete' then (calculated_balance_cents + outstanding_debits_cents - outstanding_credits_cents) / 100 else null end,
      residual_difference = case when reconciliation_mode = 'complete' then (statement_balance_cents - calculated_balance_cents - outstanding_debits_cents + outstanding_credits_cents) / 100 else null end,
      validated_at = now(),
      validated_by = auth.uid()
  where id = reconciliation_record.id
  returning * into reconciliation_record;

  return reconciliation_record;
end;
$$;

revoke all on function public.activate_complete_bank_reconciliation(uuid) from public;
revoke all on function public.add_bank_reconciliation_outstanding_transaction(uuid, uuid) from public;
revoke all on function public.remove_bank_reconciliation_outstanding_transaction(uuid, uuid) from public;
revoke all on function public.list_bank_reconciliation_candidate_transactions(uuid, date, timestamptz, uuid, integer) from public;
revoke all on function public.get_bank_reconciliation_detailed_summary(uuid) from public;
revoke all on function public.validate_bank_reconciliation(uuid) from public;
revoke all on function public.protect_bank_reconciliation_outstanding_transaction() from public;
revoke all on function public.cleanup_draft_bank_reconciliation_outstanding_transaction() from public;

grant execute on function public.activate_complete_bank_reconciliation(uuid) to authenticated;
grant execute on function public.add_bank_reconciliation_outstanding_transaction(uuid, uuid) to authenticated;
grant execute on function public.remove_bank_reconciliation_outstanding_transaction(uuid, uuid) to authenticated;
grant execute on function public.list_bank_reconciliation_candidate_transactions(uuid, date, timestamptz, uuid, integer) to authenticated;
grant execute on function public.get_bank_reconciliation_detailed_summary(uuid) to authenticated;
grant execute on function public.validate_bank_reconciliation(uuid) to authenticated;
