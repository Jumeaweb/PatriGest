-- An unreconciled statement remains anchored to its legacy identity. Its
-- current PDF is resolved through the existing active-version projection.
create table public.bank_statement_file_transitions (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  person_id uuid not null,
  account_id uuid not null,
  statement_id uuid not null,
  expected_updated_at timestamptz,
  previous_version_id uuid,
  previous_revision bigint,
  payload jsonb not null,
  storage_path text not null unique,
  state text not null default 'reserved' check (state in ('reserved','published','retired')),
  storage_object_id uuid,
  storage_object_version text,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique (requested_by, request_id)
);
create unique index bank_statement_file_transitions_one_reserved
on public.bank_statement_file_transitions(statement_id) where state = 'reserved';

create table public.bank_statement_file_retirements (
  storage_object_id uuid primary key,
  storage_object_version text,
  statement_id uuid not null,
  storage_path text not null,
  reason text not null check (reason in ('replaced','deleted','unpublished')),
  recorded_at timestamptz not null default clock_timestamp(),
  removed_at timestamptz
);
create index bank_statement_file_retirements_path on public.bank_statement_file_retirements(storage_path);
create index bank_statement_file_retirements_pending on public.bank_statement_file_retirements(statement_id)
where removed_at is null;

create table public.bank_statement_deletion_receipts (
  statement_id uuid primary key,
  person_id uuid not null,
  account_id uuid not null,
  requested_by uuid not null references auth.users(id) on delete cascade,
  deleted_at timestamptz not null default clock_timestamp()
);

alter table public.bank_statement_file_transitions enable row level security;
alter table public.bank_statement_file_retirements enable row level security;
alter table public.bank_statement_deletion_receipts enable row level security;
revoke all on public.bank_statement_file_transitions, public.bank_statement_file_retirements, public.bank_statement_deletion_receipts
from public, anon, authenticated, service_role;

create function public.assert_writable_bank_statement_account(p_person uuid, p_account uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.financial_accounts account join public.protected_persons person
    on person.id = account.protected_person_id
  where account.id = p_account and person.id = p_person
    and person.status = 'active' and person.archived_at is null
  for share of person;
  if not found or auth.uid() is null or not public.can_manage_protected_person(p_person) then
    raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.';
  end if;
end;
$$;

create function public.assert_bank_statement_not_frozen(p_statement uuid)
returns void language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.bank_reconciliations entry
    where entry.bank_statement_id = p_statement and entry.status = 'validated')
    or exists (select 1 from public.management_report_bank_statement_document_versions entry
      where entry.bank_statement_id = p_statement)
    or exists (select 1 from public.bank_statement_document_corrections entry
      where entry.bank_statement_id = p_statement) then
    raise exception using errcode = '55000', message = 'Le document du relevé est figé.';
  end if;
end;
$$;

create function public.queue_bank_statement_file_retirement(p_statement uuid, p_path text, p_reason text)
returns void language sql set search_path = '' as $$
  insert into public.bank_statement_file_retirements(storage_object_id, storage_object_version, statement_id, storage_path, reason)
  select object.id, object.version, p_statement, object.name, p_reason
  from storage.objects object where object.bucket_id = 'bank-statements' and object.name = p_path
  on conflict (storage_object_id) do nothing;
$$;

create function public.reserve_unreconciled_bank_statement_file(
  p_person uuid, p_account uuid, p_statement uuid, p_expected_updated_at timestamptz,
  p_request uuid, p_payload jsonb
) returns table (id uuid, storage_path text, state text)
language plpgsql security definer set search_path = '' as $$
declare
  statement_row public.bank_statements%rowtype;
  active_row public.bank_statement_active_document_versions%rowtype;
  edit public.bank_statement_file_transitions%rowtype;
  candidate_id uuid := gen_random_uuid();
begin
  perform public.assert_writable_bank_statement_account(p_person, p_account);
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or coalesce(p_payload->>'sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_payload->>'size','') !~ '^[1-9][0-9]{0,7}$'
     or (p_payload->>'size')::int > 10485760
     or coalesce(length(btrim(p_payload->>'fileName')),0) not between 1 and 255
     or p_payload->>'endDate' is null then
    raise exception using errcode = '22023', message = 'Métadonnées du PDF invalides.';
  end if;

  -- All requests for one statement share this lock, including initial creation.
  perform pg_advisory_xact_lock(hashtextextended('bank-statement-document:' || p_statement, 0));
  if exists (select 1 from public.bank_statement_deletion_receipts receipt where receipt.statement_id = p_statement) then
    raise exception using errcode = '40001', message = 'Ce relevé a déjà été supprimé.';
  end if;
  select * into edit from public.bank_statement_file_transitions t
  where t.requested_by = auth.uid() and t.request_id = p_request;
  if found then
    if (edit.person_id, edit.account_id, edit.statement_id, edit.payload)
       is distinct from (p_person,p_account,p_statement,p_payload) then
      raise exception using errcode = '22023', message = 'Cette demande a déjà été utilisée avec un autre fichier.';
    end if;
    return query select edit.id, edit.storage_path, edit.state;
    return;
  end if;

  select * into statement_row from public.bank_statements statement
  where statement.id = p_statement and statement.financial_account_id = p_account for update;
  if (statement_row.id is null and p_expected_updated_at is not null)
     or (statement_row.id is not null and statement_row.updated_at is distinct from p_expected_updated_at) then
    raise exception using errcode = '40001', message = 'Le relevé a changé. Rechargez la page.';
  end if;
  if statement_row.id is not null then
    perform public.assert_bank_statement_not_frozen(p_statement);
    select * into active_row from public.bank_statement_active_document_versions version
    where version.bank_statement_id = p_statement for update;
  end if;
  if exists (select 1 from public.bank_statement_file_transitions t where t.statement_id = p_statement and t.state = 'reserved') then
    raise exception using errcode = '40001', message = 'Un dépôt est déjà en cours pour ce relevé.';
  end if;

  insert into public.bank_statement_file_transitions(id,requested_by,request_id,person_id,account_id,statement_id,
    expected_updated_at,previous_version_id,previous_revision,payload,storage_path)
  values(candidate_id,auth.uid(),p_request,p_person,p_account,p_statement,p_expected_updated_at,
    active_row.version_id,active_row.revision,p_payload,
    public.build_bank_statement_document_version_path(p_person,p_account,p_statement,candidate_id))
  returning * into edit;
  return query select edit.id, edit.storage_path, edit.state;
end;
$$;

create function public.can_upload_unreconciled_bank_statement_file(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.bank_statement_file_transitions t
  join public.protected_persons person on person.id = t.person_id
  join public.financial_accounts account on account.id = t.account_id and account.protected_person_id = person.id
  where t.storage_path = p_path and t.state = 'reserved' and t.requested_by = auth.uid()
    and person.status = 'active' and person.archived_at is null
    and public.can_manage_protected_person(person.id));
$$;

create policy bank_statement_staged_file_insert on storage.objects for insert to authenticated
with check (bucket_id = 'bank-statements' and owner_id = auth.uid()::text
  and public.can_upload_unreconciled_bank_statement_file(name));

-- Only the server that read and checked the actual object may attest to it.
create function public.verify_staged_bank_statement_file(p_edit uuid, p_object uuid, p_version text, p_sha256 text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.bank_statement_file_transitions edit
  set storage_object_id = object.id, storage_object_version = object.version
  from storage.objects object
  where edit.id = p_edit and edit.state = 'reserved' and edit.payload->>'sha256' = p_sha256
    and object.bucket_id = 'bank-statements' and object.name = edit.storage_path
    and object.id = p_object and object.version = p_version
    and object.metadata->>'size' = edit.payload->>'size'
    and lower(object.metadata->>'mimetype') = 'application/pdf';
  return found;
end;
$$;

create function public.publish_unreconciled_bank_statement_file(p_edit uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  edit public.bank_statement_file_transitions%rowtype;
  statement_row public.bank_statements%rowtype;
  active_row public.bank_statement_active_document_versions%rowtype;
  previous_path text;
begin
  select * into edit from public.bank_statement_file_transitions t where t.id = p_edit;
  if not found or edit.requested_by is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'Dépôt introuvable ou accès refusé.';
  end if;
  perform public.assert_writable_bank_statement_account(edit.person_id, edit.account_id);
  perform pg_advisory_xact_lock(hashtextextended('bank-statement-document:' || edit.statement_id, 0));
  select * into strict edit from public.bank_statement_file_transitions t where t.id = p_edit for update;
  if edit.state = 'published' then return; end if;
  if edit.state <> 'reserved' then
    raise exception using errcode = '40001', message = 'Ce dépôt a été annulé.';
  end if;

  select * into statement_row from public.bank_statements statement
  where statement.id = edit.statement_id and statement.financial_account_id = edit.account_id for update;
  perform public.assert_writable_bank_statement_account(edit.person_id, edit.account_id);
  if (statement_row.id is null) <> (edit.expected_updated_at is null)
     or statement_row.updated_at is distinct from edit.expected_updated_at then
    raise exception using errcode = '40001', message = 'Le relevé a changé. Rechargez la page.';
  end if;
  perform public.assert_bank_statement_not_frozen(edit.statement_id);

  select * into active_row from public.bank_statement_active_document_versions version
  where version.bank_statement_id = edit.statement_id for update;
  if (active_row.version_id,active_row.revision) is distinct from (edit.previous_version_id,edit.previous_revision) then
    raise exception using errcode = '40001', message = 'Le document actif a changé.';
  end if;
  perform 1 from storage.objects object where object.bucket_id = 'bank-statements'
    and object.name = edit.storage_path and object.id = edit.storage_object_id
    and object.version = edit.storage_object_version for update;
  if not found then raise exception using errcode = '55000', message = 'Le PDF vérifié est absent.'; end if;

  if statement_row.id is null then
    insert into public.bank_statements(id, financial_account_id, statement_start_date, statement_end_date,
      statement_balance, note, storage_path, created_by)
    values(edit.statement_id, edit.account_id, (edit.payload->>'startDate')::date,
      (edit.payload->>'endDate')::date, (edit.payload->>'balance')::numeric, edit.payload->>'note',
      replace(edit.storage_path, '/versions/' || edit.id || '/statement', '/statement'), auth.uid());
  end if;

  if active_row.version_id is not null then
    select version.storage_path into strict previous_path from public.bank_statement_document_versions version
    where version.id = active_row.version_id and version.bank_statement_id = edit.statement_id
      and version.version_number = 1;
    perform public.queue_bank_statement_file_retirement(edit.statement_id, previous_path, 'replaced');
    delete from public.bank_statement_active_document_versions where bank_statement_id = edit.statement_id;
    delete from public.bank_statement_document_versions where id = active_row.version_id;
  end if;

  -- The provisional document remains the initial version. Its stable active
  -- revision records replacements. A protected history starts at freezing.
  insert into public.bank_statement_document_versions(id, bank_statement_id, version_number, storage_path,
    path_kind, original_file_name, mime_type, file_size, sha256, integrity_status, verified_at, created_by, verified_by)
  values(edit.id,edit.statement_id,1,edit.storage_path,'versioned',btrim(edit.payload->>'fileName'),
    'application/pdf',(edit.payload->>'size')::bigint,edit.payload->>'sha256','verified',clock_timestamp(),auth.uid(),auth.uid());
  insert into public.bank_statement_active_document_versions(bank_statement_id,version_id,revision,updated_by)
  values(edit.statement_id,edit.id,coalesce(active_row.revision,0)+1,auth.uid());

  update public.bank_statements set storage_path = edit.storage_path,
    statement_start_date = (edit.payload->>'startDate')::date,
    statement_end_date = (edit.payload->>'endDate')::date, statement_balance = (edit.payload->>'balance')::numeric,
    note = edit.payload->>'note', original_file_name = btrim(edit.payload->>'fileName'),
    mime_type = 'application/pdf', file_size = (edit.payload->>'size')::bigint
  where id = edit.statement_id;
  update public.bank_statement_file_transitions set state = 'published', completed_at = clock_timestamp()
  where id = edit.id;
end;
$$;

create or replace function public.cleanup_unfrozen_bank_statement_document_versions()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  active_row public.bank_statement_active_document_versions%rowtype;
  previous_path text;
begin
  perform public.assert_bank_statement_not_frozen(old.id);
  select * into active_row from public.bank_statement_active_document_versions version
  where version.bank_statement_id = old.id for update;
  if not found then return old; end if;

  select version.storage_path into strict previous_path from public.bank_statement_document_versions version
  where version.id = active_row.version_id and version.bank_statement_id = old.id and version.version_number = 1;
  perform public.queue_bank_statement_file_retirement(old.id, previous_path, 'deleted');
  delete from public.bank_statement_active_document_versions where bank_statement_id = old.id;
  delete from public.bank_statement_document_versions where id = active_row.version_id;
  return old;
end;
$$;

create function public.delete_unreconciled_bank_statement(p_person uuid, p_account uuid, p_statement uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.assert_writable_bank_statement_account(p_person,p_account);
  perform pg_advisory_xact_lock(hashtextextended('bank-statement-document:' || p_statement, 0));
  -- Match reconciliation validation's lock order before taking the statement.
  perform 1 from public.bank_reconciliations reconciliation where reconciliation.bank_statement_id = p_statement for update;
  perform 1 from public.bank_statements statement
  where statement.id = p_statement and statement.financial_account_id = p_account for update;
  if not found then
    if exists (select 1 from public.bank_statement_deletion_receipts receipt
      where receipt.statement_id = p_statement and receipt.person_id = p_person
        and receipt.account_id = p_account and receipt.requested_by = auth.uid()) then return; end if;
    raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.';
  end if;
  perform public.assert_writable_bank_statement_account(p_person,p_account);
  delete from public.bank_statements where id = p_statement;
  insert into public.bank_statement_deletion_receipts(statement_id,person_id,account_id,requested_by)
  values(p_statement,p_person,p_account,auth.uid());
end;
$$;

create function public.detach_unreconciled_bank_statement_file(p_person uuid,p_account uuid,p_statement uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  active_row public.bank_statement_active_document_versions%rowtype;
  previous_path text;
begin
  perform public.assert_writable_bank_statement_account(p_person,p_account);
  perform pg_advisory_xact_lock(hashtextextended('bank-statement-document:' || p_statement, 0));
  perform 1 from public.bank_statements where id = p_statement and financial_account_id = p_account for update;
  if not found then raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.'; end if;
  perform public.assert_writable_bank_statement_account(p_person,p_account);
  perform public.assert_bank_statement_not_frozen(p_statement);
  select * into active_row from public.bank_statement_active_document_versions where bank_statement_id = p_statement for update;
  if not found then return; end if;
  select version.storage_path into strict previous_path from public.bank_statement_document_versions version
  where version.id = active_row.version_id and version.bank_statement_id = p_statement and version.version_number = 1;
  perform public.queue_bank_statement_file_retirement(p_statement,previous_path,'deleted');
  delete from public.bank_statement_active_document_versions where bank_statement_id = p_statement;
  delete from public.bank_statement_document_versions where id = active_row.version_id;
  update public.bank_statements set original_file_name = null, mime_type = null, file_size = null where id = p_statement;
end;
$$;
revoke all on function public.detach_unreconciled_bank_statement_file(uuid,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.detach_unreconciled_bank_statement_file(uuid,uuid,uuid) to authenticated;

create function public.reconcile_unpublished_bank_statement_file(p_edit uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare edit public.bank_statement_file_transitions%rowtype;
begin
  select * into edit from public.bank_statement_file_transitions where id = p_edit;
  if not found then return 'unknown'; end if;
  perform pg_advisory_xact_lock(hashtextextended('bank-statement-document:' || edit.statement_id, 0));
  select * into strict edit from public.bank_statement_file_transitions where id = p_edit for update;
  if edit.state = 'published' then return 'published'; end if;
  perform public.queue_bank_statement_file_retirement(edit.statement_id,edit.storage_path,'unpublished');
  if edit.state = 'reserved' then
    update public.bank_statement_file_transitions set state = 'retired', completed_at = clock_timestamp()
    where id = edit.id;
  end if;
  return 'retired';
end;
$$;

create function public.list_retired_bank_statement_files(p_statement uuid)
returns table (storage_path text) language sql stable security definer set search_path = '' as $$
  select job.storage_path from public.bank_statement_file_retirements job
  join storage.objects object on object.id = job.storage_object_id and object.name = job.storage_path
    and object.version is not distinct from job.storage_object_version and object.bucket_id = 'bank-statements'
  where job.statement_id = p_statement and job.removed_at is null
    and not exists (select 1 from public.bank_statement_document_versions version where version.storage_path = job.storage_path);
$$;

create function public.guard_retired_bank_statement_object()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.bank_statement_file_retirements job where job.storage_path = old.name)
     and not exists (select 1 from public.bank_statement_file_transitions edit where edit.storage_path = old.name and edit.state = 'retired') then
    return old;
  end if;
  -- An upload that finished after cancellation can be retired by a replay,
  -- but a late delete can never remove another object at the same path.
  update public.bank_statement_file_retirements job set removed_at = clock_timestamp()
  where job.storage_object_id = old.id and job.storage_object_version is not distinct from old.version
    and job.storage_path = old.name and job.removed_at is null
    and not exists (select 1 from public.bank_statement_document_versions version where version.storage_path = old.name);
  if not found then raise exception using errcode = '42501', message = 'Ce fichier de relevé ne peut pas être nettoyé.'; end if;
  return old;
end;
$$;

create trigger bank_statement_retirement_guard before delete on storage.objects
for each row when (old.bucket_id = 'bank-statements') execute function public.guard_retired_bank_statement_object();

revoke all on function public.assert_writable_bank_statement_account(uuid,uuid), public.assert_bank_statement_not_frozen(uuid),
  public.queue_bank_statement_file_retirement(uuid,text,text), public.reserve_unreconciled_bank_statement_file(uuid,uuid,uuid,timestamptz,uuid,jsonb),
  public.can_upload_unreconciled_bank_statement_file(text), public.verify_staged_bank_statement_file(uuid,uuid,text,text),
  public.publish_unreconciled_bank_statement_file(uuid), public.delete_unreconciled_bank_statement(uuid,uuid,uuid),
  public.reconcile_unpublished_bank_statement_file(uuid), public.list_retired_bank_statement_files(uuid),
  public.guard_retired_bank_statement_object() from public, anon, authenticated, service_role;
grant execute on function public.reserve_unreconciled_bank_statement_file(uuid,uuid,uuid,timestamptz,uuid,jsonb),
  public.can_upload_unreconciled_bank_statement_file(text), public.publish_unreconciled_bank_statement_file(uuid),
  public.delete_unreconciled_bank_statement(uuid,uuid,uuid) to authenticated;
grant execute on function public.verify_staged_bank_statement_file(uuid,uuid,text,text),
  public.reconcile_unpublished_bank_statement_file(uuid), public.list_retired_bank_statement_files(uuid) to service_role;


create or replace function public.register_initial_bank_statement_document_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_id uuid;
  active_row public.bank_statement_active_document_versions%rowtype;
begin
  select * into active_row
  from public.bank_statement_active_document_versions active
  where active.bank_statement_id = new.id
  for update;

  if found and exists (select 1 from public.bank_statement_document_versions version
    where version.id = active_row.version_id and version.path_kind = 'versioned') then
    if not exists (select 1 from public.bank_statement_document_versions version
      where version.id = active_row.version_id
        and (version.original_file_name,version.mime_type,version.file_size)
          is not distinct from (new.original_file_name,new.mime_type,new.file_size)) then
      raise exception using errcode = '55000', message = 'Le PDF doit être remplacé par une publication versionnée.';
    end if;
    return new;
  end if;

  if new.original_file_name is null
     or new.mime_type is null
     or new.file_size is null then
    if not found then return new; end if;

    perform public.assert_bank_statement_initial_document_mutable(
      new.id, active_row.version_id
    );
    delete from public.bank_statement_active_document_versions active
    where active.bank_statement_id = new.id
      and active.version_id = active_row.version_id;
    delete from public.bank_statement_document_versions version
    where version.id = active_row.version_id
      and version.bank_statement_id = new.id;
    return new;
  end if;

  if found then
    perform public.assert_bank_statement_initial_document_mutable(
      new.id, active_row.version_id
    );
    update public.bank_statement_document_versions version
    set original_file_name = new.original_file_name,
        mime_type = new.mime_type,
        file_size = new.file_size,
        sha256 = null,
        integrity_status = 'pending_hash',
        verified_at = null,
        verified_by = null
    where version.id = active_row.version_id
      and version.bank_statement_id = new.id;
    return new;
  end if;

  version_id := gen_random_uuid();
  insert into public.bank_statement_document_versions(
    id, bank_statement_id, version_number, storage_path, path_kind,
    original_file_name, mime_type, file_size, sha256, integrity_status,
    previous_version_id, correction_reason, created_by, created_at
  ) values (
    version_id, new.id, 1, new.storage_path, 'legacy',
    new.original_file_name, new.mime_type, new.file_size, null, 'pending_hash',
    null, null, new.created_by, coalesce(new.created_at, clock_timestamp())
  );
  insert into public.bank_statement_active_document_versions(
    bank_statement_id, version_id, revision, updated_by, updated_at
  ) values (new.id, version_id, 1, new.created_by, coalesce(new.created_at, clock_timestamp()));
  return new;
end;
$$;


-- Keep the legacy business projection aligned for administrative diagnostics.
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
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du relevé ne peut pas être modifié.';
  end if;

  if new.storage_path is distinct from old.storage_path then
    if current_user <> pg_get_userbyid((select relowner from pg_class where oid = 'public.bank_statement_file_transitions'::regclass)) then
      raise exception 'Le rattachement du relevé ne peut pas être modifié.';
    end if;
    if not exists (
      select 1 from public.bank_statement_active_document_versions active
      join public.bank_statement_file_transitions edit on edit.id = active.version_id
      where active.bank_statement_id = old.id and edit.statement_id = old.id
        and edit.storage_path = new.storage_path and edit.state = 'reserved'
    ) then
      raise exception 'Le rattachement du relevé ne peut pas être modifié.';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.resolve_canonical_document_storage_path(
  p_bucket_id text,p_object_path text
) returns table(is_canonical boolean,protected_person_id uuid,business_entity_type text,
  business_entity_id uuid,parent_entity_id uuid,document_kind text)
language plpgsql immutable security definer set search_path='' as $$
declare path_match text[];
  uuid_pattern constant text:='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
begin
  is_canonical:=false; protected_person_id:=null; business_entity_type:=null;
  business_entity_id:=null; parent_entity_id:=null; document_kind:=null;
  if p_bucket_id='transaction-proofs' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/transactions/('||uuid_pattern||
      ')/proofs/('||uuid_pattern||')/versions/('||uuid_pattern||')$');
    if path_match is null then
      path_match:=pg_catalog.regexp_match(p_object_path,
        '^protected-persons/('||uuid_pattern||')/transactions/('||uuid_pattern||')/proof$');
    end if;
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      business_entity_type:='transaction'; business_entity_id:=path_match[2]::uuid;
      document_kind:='transaction_proof';
    end if;
  elsif p_bucket_id='bank-statements' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/accounts/('||uuid_pattern||
      ')/statements/('||uuid_pattern||')(/versions/'||uuid_pattern||')?/statement$');
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      parent_entity_id:=path_match[2]::uuid; business_entity_type:='bank_statement';
      business_entity_id:=path_match[3]::uuid; document_kind:='bank_statement';
    end if;
  elsif p_bucket_id='management-reports' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/management-reports/('||uuid_pattern||
      ')/(management-report-draft[.]pdf|management-report[.]pdf)$');
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      business_entity_type:='management_report'; business_entity_id:=path_match[2]::uuid;
      document_kind:=case path_match[3] when 'management-report-draft.pdf'
        then 'management_report_draft' else 'management_report_final' end;
    end if;
  end if;
  return next;
end;
$$;
