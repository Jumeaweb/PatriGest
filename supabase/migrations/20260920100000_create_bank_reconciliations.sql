do $$
begin
  if exists (
    select 1
    from public.bank_statements
    where num_nulls(original_file_name, mime_type, file_size) not in (0, 3)
  ) then
    raise exception 'Preflight failed: incomplete bank statement document metadata.';
  end if;

end;
$$;

alter table public.bank_statements
  alter column original_file_name drop not null,
  alter column mime_type drop not null,
  alter column file_size drop not null,
  add constraint bank_statements_document_metadata_consistent check (
    (original_file_name is null and mime_type is null and file_size is null)
    or
    (original_file_name is not null and mime_type is not null and file_size is not null)
  );

create type public.bank_reconciliation_status as enum ('draft', 'validated');

create table public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  bank_statement_id uuid not null unique
    references public.bank_statements(id) on delete cascade,
  status public.bank_reconciliation_status not null default 'draft',
  calculated_balance numeric(15,2),
  difference numeric(16,2),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  validated_at timestamptz,
  validated_by uuid references auth.users(id) on delete set null,
  constraint bank_reconciliations_state_consistent check (
    (
      status = 'draft'
      and calculated_balance is null
      and difference is null
      and validated_at is null
      and validated_by is null
    )
    or
    (
      status = 'validated'
      and calculated_balance is not null
      and difference is not null
      and validated_at is not null
    )
  )
);

create or replace function public.validate_bank_reconciliation_statement_date()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  statement public.bank_statements%rowtype;
  account public.financial_accounts%rowtype;
  minimum_date date;
begin
  if tg_table_name = 'bank_statements' then
    if new.statement_end_date is not distinct from old.statement_end_date
       or not exists (
         select 1
         from public.bank_reconciliations reconciliation
         where reconciliation.bank_statement_id = old.id
       ) then
      return new;
    end if;

    statement.financial_account_id := new.financial_account_id;
    statement.statement_end_date := new.statement_end_date;
  else
    select * into statement
    from public.bank_statements
    where id = new.bank_statement_id;

    if statement.id is null then
      return new;
    end if;
  end if;

  select * into account
  from public.financial_accounts
  where id = statement.financial_account_id;

  if account.id is null then
    raise exception 'Compte introuvable.';
  end if;

  minimum_date := greatest(
    account.initial_balance_date,
    coalesce(account.opening_date, account.initial_balance_date)
  );

  if statement.statement_end_date < minimum_date then
    raise exception 'Le relevé est antérieur à la première date rapprochable du compte.';
  end if;

  if account.closing_date is not null and statement.statement_end_date > account.closing_date then
    raise exception 'Le relevé est postérieur à la clôture du compte.';
  end if;

  return new;
end;
$$;

create trigger bank_reconciliations_validate_statement_date
before insert or update of bank_statement_id, status
on public.bank_reconciliations
for each row execute function public.validate_bank_reconciliation_statement_date();

create trigger bank_statements_validate_reconciliation_date
before update of statement_end_date
on public.bank_statements
for each row execute function public.validate_bank_reconciliation_statement_date();

create or replace function public.protect_bank_reconciliation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  created_by_cleanup boolean;
  validated_by_cleanup boolean;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'Un rapprochement doit être créé en brouillon.';
    end if;
    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.status = 'validated' then
      raise exception 'Un rapprochement validé est définitivement figé.';
    end if;
    return old;
  end if;

  if pg_trigger_depth() > 1 then
    created_by_cleanup := new.created_by is not distinct from old.created_by
      or (
        old.created_by is not null
        and new.created_by is null
        and not exists (select 1 from auth.users where id = old.created_by)
      );
    validated_by_cleanup := new.validated_by is not distinct from old.validated_by
      or (
        old.validated_by is not null
        and new.validated_by is null
        and not exists (select 1 from auth.users where id = old.validated_by)
      );

    if created_by_cleanup
       and validated_by_cleanup
       and (
         to_jsonb(new) - 'created_by' - 'validated_by' - 'updated_at'
         = to_jsonb(old) - 'created_by' - 'validated_by' - 'updated_at'
       ) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if old.status = 'validated' then
    raise exception 'Un rapprochement validé est définitivement figé.';
  end if;

  if new.id is distinct from old.id
     or new.bank_statement_id is distinct from old.bank_statement_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du rapprochement ne peut pas être modifié.';
  end if;

  if new.status = 'validated'
     and (new.validated_by is null or new.validated_by is distinct from auth.uid()) then
    raise exception 'Le validateur doit être l''utilisateur authentifié.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger bank_reconciliations_protect_state
before insert or update or delete on public.bank_reconciliations
for each row execute function public.protect_bank_reconciliation();

create or replace function public.protect_bank_statement_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1
     and old.created_by is not null
     and new.created_by is null
     and (
       to_jsonb(new) - 'created_by' - 'updated_at'
       = to_jsonb(old) - 'created_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.created_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if exists (
    select 1
    from public.bank_reconciliations reconciliation
    where reconciliation.bank_statement_id = old.id
      and reconciliation.status = 'validated'
  ) then
    raise exception 'Un relevé rapproché est définitivement figé.';
  end if;

  if new.id is distinct from old.id
     or new.financial_account_id is distinct from old.financial_account_id
     or new.storage_path is distinct from old.storage_path
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du relevé ne peut pas être modifié.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_validated_bank_statement_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.bank_reconciliations reconciliation
    where reconciliation.bank_statement_id = old.id
      and reconciliation.status = 'validated'
  ) then
    raise exception 'Un relevé rapproché est définitivement figé.';
  end if;
  return old;
end;
$$;

create trigger bank_statements_protect_validated_delete
before delete on public.bank_statements
for each row execute function public.protect_validated_bank_statement_delete();

alter table public.bank_reconciliations enable row level security;

create policy "bank_reconciliations_select_accessible"
on public.bank_reconciliations
for select to authenticated
using (exists (
  select 1
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_reconciliations.bank_statement_id
    and public.can_read_protected_person(account.protected_person_id)
));

create policy "bank_reconciliations_insert_manage"
on public.bank_reconciliations
for insert to authenticated
with check (
  status = 'draft'
  and created_by = auth.uid()
  and exists (
    select 1
    from public.bank_statements statement
    join public.financial_accounts account on account.id = statement.financial_account_id
    where statement.id = bank_reconciliations.bank_statement_id
      and public.can_manage_protected_person(account.protected_person_id)
  )
);

create policy "bank_reconciliations_update_manage"
on public.bank_reconciliations
for update to authenticated
using (exists (
  select 1
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_reconciliations.bank_statement_id
    and public.can_manage_protected_person(account.protected_person_id)
))
with check (exists (
  select 1
  from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_reconciliations.bank_statement_id
    and public.can_manage_protected_person(account.protected_person_id)
));

create policy "bank_reconciliations_delete_manage"
on public.bank_reconciliations
for delete to authenticated
using (
  exists (
    select 1
    from public.bank_statements statement
    join public.financial_accounts account on account.id = statement.financial_account_id
    where statement.id = bank_reconciliations.bank_statement_id
      and public.can_manage_protected_person(account.protected_person_id)
  )
);

drop policy if exists "bank_statements_storage_insert_manage" on storage.objects;
create policy "bank_statements_storage_insert_manage" on storage.objects
for insert to authenticated with check (
  bucket_id = 'bank-statements'
  and array_length(storage.foldername(name), 1) = 6
  and (storage.foldername(name))[1] = 'protected-persons'
  and (storage.foldername(name))[3] = 'accounts'
  and (storage.foldername(name))[5] = 'statements'
  and storage.filename(name) = 'statement'
  and exists (
    select 1 from public.bank_statements bank_statement
    join public.financial_accounts account on account.id = bank_statement.financial_account_id
    where bank_statement.id = ((storage.foldername(name))[6])::uuid
      and bank_statement.financial_account_id = ((storage.foldername(name))[4])::uuid
      and bank_statement.storage_path = name
      and account.protected_person_id = ((storage.foldername(name))[2])::uuid
      and public.can_manage_protected_person(account.protected_person_id)
      and not exists (
        select 1 from public.bank_reconciliations reconciliation
        where reconciliation.bank_statement_id = bank_statement.id
          and reconciliation.status = 'validated'
      )
  )
);

drop policy if exists "bank_statements_storage_update_manage" on storage.objects;
create policy "bank_statements_storage_update_manage" on storage.objects
for update to authenticated using (
  bucket_id = 'bank-statements'
  and array_length(storage.foldername(name), 1) = 6
  and (storage.foldername(name))[1] = 'protected-persons'
  and (storage.foldername(name))[3] = 'accounts'
  and (storage.foldername(name))[5] = 'statements'
  and storage.filename(name) = 'statement'
  and exists (
    select 1 from public.bank_statements bank_statement
    join public.financial_accounts account on account.id = bank_statement.financial_account_id
    where bank_statement.id = ((storage.foldername(name))[6])::uuid
      and bank_statement.financial_account_id = ((storage.foldername(name))[4])::uuid
      and bank_statement.storage_path = name
      and account.protected_person_id = ((storage.foldername(name))[2])::uuid
      and public.can_manage_protected_person(account.protected_person_id)
      and not exists (
        select 1 from public.bank_reconciliations reconciliation
        where reconciliation.bank_statement_id = bank_statement.id
          and reconciliation.status = 'validated'
      )
  )
) with check (
  bucket_id = 'bank-statements'
  and array_length(storage.foldername(name), 1) = 6
  and (storage.foldername(name))[1] = 'protected-persons'
  and (storage.foldername(name))[3] = 'accounts'
  and (storage.foldername(name))[5] = 'statements'
  and storage.filename(name) = 'statement'
  and exists (
    select 1 from public.bank_statements bank_statement
    join public.financial_accounts account on account.id = bank_statement.financial_account_id
    where bank_statement.id = ((storage.foldername(name))[6])::uuid
      and bank_statement.financial_account_id = ((storage.foldername(name))[4])::uuid
      and bank_statement.storage_path = name
      and account.protected_person_id = ((storage.foldername(name))[2])::uuid
      and public.can_manage_protected_person(account.protected_person_id)
      and not exists (
        select 1 from public.bank_reconciliations reconciliation
        where reconciliation.bank_statement_id = bank_statement.id
          and reconciliation.status = 'validated'
      )
  )
);

drop policy if exists "bank_statements_storage_delete_manage" on storage.objects;
create policy "bank_statements_storage_delete_manage" on storage.objects
for delete to authenticated using (
  bucket_id = 'bank-statements'
  and array_length(storage.foldername(name), 1) = 6
  and (storage.foldername(name))[1] = 'protected-persons'
  and (storage.foldername(name))[3] = 'accounts'
  and (storage.foldername(name))[5] = 'statements'
  and storage.filename(name) = 'statement'
  and exists (
    select 1 from public.bank_statements bank_statement
    join public.financial_accounts account on account.id = bank_statement.financial_account_id
    where bank_statement.id = ((storage.foldername(name))[6])::uuid
      and bank_statement.financial_account_id = ((storage.foldername(name))[4])::uuid
      and bank_statement.storage_path = name
      and account.protected_person_id = ((storage.foldername(name))[2])::uuid
      and public.can_manage_protected_person(account.protected_person_id)
      and not exists (
        select 1 from public.bank_reconciliations reconciliation
        where reconciliation.bank_statement_id = bank_statement.id
          and reconciliation.status = 'validated'
      )
  )
);

grant select, insert, update, delete on public.bank_reconciliations to authenticated;

revoke all on function public.validate_bank_reconciliation_statement_date() from public;
revoke all on function public.protect_bank_reconciliation() from public;
revoke all on function public.protect_validated_bank_statement_delete() from public;
revoke all on function public.protect_bank_statement_identity() from public;
