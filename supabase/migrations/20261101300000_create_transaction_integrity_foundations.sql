alter table public.transactions
  add column revision bigint not null default 1,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid references auth.users(id) on delete set null;

alter table public.transactions
  add constraint transactions_revision_positive check (revision > 0),
  add constraint transactions_cancellation_consistency check (
    (cancelled_at is null and cancelled_by is null) or cancelled_at is not null
  );

alter table public.transfers
  add column revision bigint not null default 1,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid references auth.users(id) on delete set null;

alter table public.transfers
  add constraint transfers_revision_positive check (revision > 0),
  add constraint transfers_cancellation_consistency check (
    (cancelled_at is null and cancelled_by is null) or cancelled_at is not null
  );

create table public.financial_operation_requests (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid references auth.users(id) on delete set null,
  request_id uuid not null,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  operation_kind text not null check (operation_kind in (
    'transaction_create', 'transaction_correct', 'transaction_cancel',
    'transfer_create', 'transfer_correct', 'transfer_cancel'
  )),
  intent jsonb not null,
  result_entity_type text,
  result_entity_id uuid,
  result_revision bigint,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (requested_by, request_id),
  constraint financial_operation_requests_completion_consistency check (
    (completed_at is null and result_entity_type is null and result_entity_id is null and result_revision is null)
    or
    (completed_at is not null and result_entity_type is not null and result_entity_id is not null and result_revision is not null)
  )
);

create table public.transaction_changes (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  transaction_id uuid not null references public.transactions(id) on delete restrict,
  request_id uuid not null,
  change_kind text not null check (change_kind in ('correction', 'cancellation')),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  revision_before bigint not null,
  revision_after bigint not null,
  previous_values jsonb not null,
  new_values jsonb not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_by_name text not null,
  changed_at timestamptz not null default clock_timestamp(),
  unique (changed_by, request_id),
  check (revision_after = revision_before + 1)
);

create table public.transfer_changes (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  transfer_id uuid not null references public.transfers(id) on delete restrict,
  request_id uuid not null,
  change_kind text not null check (change_kind in ('correction', 'cancellation')),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  revision_before bigint not null,
  revision_after bigint not null,
  previous_values jsonb not null,
  new_values jsonb not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_by_name text not null,
  changed_at timestamptz not null default clock_timestamp(),
  unique (changed_by, request_id),
  check (revision_after = revision_before + 1)
);

create table public.transaction_document_history (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  transaction_id uuid not null references public.transactions(id) on delete restrict,
  transaction_change_id uuid not null references public.transaction_changes(id) on delete restrict,
  original_document_id uuid not null,
  storage_path text not null,
  file_name text not null,
  mime_type text not null,
  file_size bigint not null check (file_size > 0),
  original_created_by uuid references auth.users(id) on delete set null,
  original_created_at timestamptz not null,
  original_updated_at timestamptz not null,
  archived_by uuid references auth.users(id) on delete set null,
  archived_by_name text not null,
  archived_at timestamptz not null default clock_timestamp(),
  archive_reason text not null,
  unique (original_document_id),
  unique (storage_path)
);

create table public.transaction_banking_impacts (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  transaction_change_id uuid references public.transaction_changes(id) on delete restrict,
  transfer_change_id uuid references public.transfer_changes(id) on delete restrict,
  transaction_id uuid references public.transactions(id) on delete restrict,
  transfer_id uuid references public.transfers(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  effective_date date not null,
  impact_kind text not null check (impact_kind in ('reverse_previous', 'apply_current')),
  signed_amount numeric(14,2) not null check (signed_amount <> 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint transaction_banking_impacts_change_source check (
    ((transaction_change_id is not null)::integer + (transfer_change_id is not null)::integer) = 1
  ),
  constraint transaction_banking_impacts_entity_source check (
    ((transaction_id is not null)::integer + (transfer_id is not null)::integer) = 1
  )
);

create index transaction_changes_transaction_idx on public.transaction_changes(transaction_id, changed_at desc);
create index transfer_changes_transfer_idx on public.transfer_changes(transfer_id, changed_at desc);
create index transaction_document_history_transaction_idx on public.transaction_document_history(transaction_id, archived_at desc);
create index transaction_banking_impacts_account_idx on public.transaction_banking_impacts(financial_account_id, effective_date);

alter table public.financial_operation_requests enable row level security;
alter table public.transaction_changes enable row level security;
alter table public.transfer_changes enable row level security;
alter table public.transaction_document_history enable row level security;
alter table public.transaction_banking_impacts enable row level security;

create policy transaction_changes_select_accessible on public.transaction_changes
for select to authenticated using (public.can_read_protected_person(protected_person_id));
create policy transfer_changes_select_accessible on public.transfer_changes
for select to authenticated using (public.can_read_protected_person(protected_person_id));
create policy transaction_document_history_select_accessible on public.transaction_document_history
for select to authenticated using (public.can_read_protected_person(protected_person_id));
create policy transaction_banking_impacts_select_accessible on public.transaction_banking_impacts
for select to authenticated using (public.can_read_protected_person(protected_person_id));

revoke all on table public.financial_operation_requests from public, anon, authenticated, service_role;
revoke all on table public.transaction_changes from public, anon, authenticated, service_role;
revoke all on table public.transfer_changes from public, anon, authenticated, service_role;
revoke all on table public.transaction_document_history from public, anon, authenticated, service_role;
revoke all on table public.transaction_banking_impacts from public, anon, authenticated, service_role;
grant select on table public.transaction_changes, public.transfer_changes,
  public.transaction_document_history, public.transaction_banking_impacts to authenticated;

create function public.protect_financial_operation_audit_rows()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception using errcode = '42501', message = 'Un historique financier est immuable.';
end;
$$;

create trigger transaction_changes_immutable before update or delete on public.transaction_changes
for each row execute function public.protect_financial_operation_audit_rows();
create trigger transfer_changes_immutable before update or delete on public.transfer_changes
for each row execute function public.protect_financial_operation_audit_rows();
create trigger transaction_document_history_immutable before update or delete on public.transaction_document_history
for each row execute function public.protect_financial_operation_audit_rows();
create trigger transaction_banking_impacts_immutable before update or delete on public.transaction_banking_impacts
for each row execute function public.protect_financial_operation_audit_rows();

create function public.protect_financial_operation_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user <> 'postgres' and (
    new.cancelled_at is distinct from old.cancelled_at
    or new.cancelled_by is distinct from old.cancelled_by
    or new.revision is distinct from old.revision
  ) then
    raise exception using errcode = '42501', message = 'Utilisez la procédure financière sécurisée.';
  end if;
  return new;
end;
$$;

create function public.protect_direct_transaction_type_conversion()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if current_user <> 'postgres' and new.transaction_type is distinct from old.transaction_type then
    raise exception using errcode = '42501', message = 'Utilisez la procédure financière sécurisée.';
  end if;
  return new;
end;
$$;

create trigger transactions_01_protect_lifecycle before update on public.transactions
for each row execute function public.protect_financial_operation_lifecycle();
create trigger transactions_01_protect_type_conversion before update of transaction_type on public.transactions
for each row execute function public.protect_direct_transaction_type_conversion();
create trigger transfers_01_protect_lifecycle before update on public.transfers
for each row execute function public.protect_financial_operation_lifecycle();

create function public.set_transaction_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if public.is_referential_transaction_category_cleanup(old, new) then
    new.revision := old.revision;
    return new;
  end if;
  if (to_jsonb(new) - array['revision','updated_at'])
     is distinct from (to_jsonb(old) - array['revision','updated_at']) then
    new.revision := old.revision + 1;
  else
    new.revision := old.revision;
  end if;
  return new;
end;
$$;

create function public.set_transfer_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (to_jsonb(new) - array['revision','updated_at'])
     is distinct from (to_jsonb(old) - array['revision','updated_at']) then
    new.revision := old.revision + 1;
  else
    new.revision := old.revision;
  end if;
  return new;
end;
$$;

create trigger transactions_05_set_revision before update on public.transactions
for each row execute function public.set_transaction_revision();
create trigger transfers_05_set_revision before update on public.transfers
for each row execute function public.set_transfer_revision();

create function public.reject_future_financial_operation_date()
returns trigger language plpgsql security definer set search_path = '' as $$
declare operation_date date;
begin
  if tg_table_name = 'transactions' then
    operation_date := new.transaction_date;
  else
    operation_date := new.transfer_date;
  end if;
  if operation_date > current_date then
    raise exception using errcode = '22007', message = 'La date d’une opération réelle ne peut pas être future.';
  end if;
  return new;
end;
$$;

create trigger transactions_02_reject_future_date before insert or update of transaction_date on public.transactions
for each row execute function public.reject_future_financial_operation_date();
create trigger transfers_02_reject_future_date before insert or update of transfer_date on public.transfers
for each row execute function public.reject_future_financial_operation_date();

create or replace function public.manage_expense_proof_reference()
returns trigger language plpgsql security definer set search_path = '' as $$
declare person_id uuid; account_kind text; assigned_reference text; assigned_year integer;
begin
  select protected_person_id, account_type into person_id, account_kind
  from public.financial_accounts where id = new.financial_account_id;
  if person_id is null then raise exception 'Compte introuvable.'; end if;
  if new.transaction_type in ('income','expense')
     and account_kind in ('life_insurance','other_investment','securities_account') then
    raise exception 'Les recettes et dépenses nécessitent un compte transactionnel.';
  end if;
  if tg_op = 'INSERT' then
    new.proof_reference := case when new.transaction_type = 'expense'
      then public.next_proof_reference(person_id, new.transaction_date, new.id) else null end;
    return new;
  end if;
  if new.transaction_type <> 'expense' then
    new.proof_reference := null;
  elsif old.transaction_type = 'expense' and old.proof_reference is not null then
    if extract(year from new.transaction_date) <> extract(year from old.transaction_date) then
      raise exception 'Une dépense numérotée ne peut pas être déplacée vers une autre année.';
    end if;
    new.proof_reference := old.proof_reference;
  else
    select proof_reference, reference_year into assigned_reference, assigned_year
    from public.proof_reference_assignments where transaction_id = new.id;
    if assigned_reference is not null then
      if assigned_year <> extract(year from new.transaction_date)::integer then
        raise exception 'Une dépense déjà numérotée ne peut pas être déplacée vers une autre année.';
      end if;
      new.proof_reference := assigned_reference;
    else
      new.proof_reference := public.next_proof_reference(person_id, new.transaction_date, new.id);
    end if;
  end if;
  return new;
end;
$$;

create function public.verify_transfer_pair_integrity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare transfer_key uuid; transfer_row public.transfers%rowtype; leg_count integer;
begin
  if tg_table_name = 'transactions' then
    transfer_key := case when tg_op = 'DELETE' then old.transfer_id else new.transfer_id end;
  else
    transfer_key := case when tg_op = 'DELETE' then old.id else new.id end;
  end if;
  select * into transfer_row from public.transfers where id = transfer_key;
  if not found then return case when tg_op = 'DELETE' then old else new end; end if;
  select count(*) into leg_count from public.transactions where transfer_id = transfer_key;
  if leg_count <> 2 or not exists (
    select 1 from public.transactions source_leg
    join public.transactions destination_leg on destination_leg.transfer_id = source_leg.transfer_id
    where source_leg.transfer_id = transfer_key
      and source_leg.transaction_type = 'transfer_out'
      and destination_leg.transaction_type = 'transfer_in'
      and source_leg.financial_account_id = transfer_row.source_account_id
      and destination_leg.financial_account_id = transfer_row.destination_account_id
      and source_leg.transaction_date = transfer_row.transfer_date
      and destination_leg.transaction_date = transfer_row.transfer_date
      and source_leg.amount = transfer_row.amount and destination_leg.amount = transfer_row.amount
      and source_leg.cancelled_at is not distinct from transfer_row.cancelled_at
      and destination_leg.cancelled_at is not distinct from transfer_row.cancelled_at
  ) then
    raise exception using errcode = '23514', message = 'Les deux mouvements du virement sont incohérents.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create constraint trigger transactions_verify_transfer_pair
after insert or update or delete on public.transactions deferrable initially deferred
for each row execute function public.verify_transfer_pair_integrity();
create constraint trigger transfers_verify_transfer_pair
after insert or update on public.transfers deferrable initially deferred
for each row execute function public.verify_transfer_pair_integrity();

revoke all on function public.protect_financial_operation_audit_rows() from public, anon, authenticated, service_role;
revoke all on function public.protect_financial_operation_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.protect_direct_transaction_type_conversion() from public, anon, authenticated, service_role;
revoke all on function public.set_transaction_revision() from public, anon, authenticated, service_role;
revoke all on function public.set_transfer_revision() from public, anon, authenticated, service_role;
revoke all on function public.reject_future_financial_operation_date() from public, anon, authenticated, service_role;
revoke all on function public.verify_transfer_pair_integrity() from public, anon, authenticated, service_role;
revoke all on function public.manage_expense_proof_reference() from public, anon, authenticated, service_role;

comment on table public.financial_operation_requests is 'Clés d idempotence des mutations financières auditées.';
comment on table public.transaction_document_history is 'Métadonnées immuables des justificatifs retirés du rattachement courant sans supprimer l objet Storage.';
comment on table public.transaction_banking_impacts is 'Impacts bancaires à justifier lors du prochain rapprochement.';
