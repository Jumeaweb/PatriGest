-- PAT-RELEVES-01C
-- Fondations documentaires additives pour conserver toutes les versions PDF
-- d'un relevé bancaire. Cette migration ne modifie ni les données comptables
-- du relevé, ni les rapprochements, ni les snapshots de comptes de gestion.

create table public.bank_statement_document_versions (
  id uuid primary key default gen_random_uuid(),
  bank_statement_id uuid not null,
  version_number integer not null check (version_number > 0),
  storage_path text not null unique check (
    storage_path = btrim(storage_path)
    and storage_path <> ''
    and position(chr(92) in storage_path) = 0
    and storage_path !~ '(^/|(^|/)\.\.(/|$)|//)'
  ),
  path_kind text not null check (path_kind in ('legacy', 'versioned')),
  original_file_name text not null check (char_length(btrim(original_file_name)) between 1 and 255),
  mime_type text not null check (mime_type = 'application/pdf'),
  file_size bigint not null check (file_size between 1 and 10485760),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  integrity_status text not null check (integrity_status in ('pending_hash', 'verified')),
  verified_at timestamptz,
  previous_version_id uuid,
  correction_reason text check (
    correction_reason is null
    or char_length(btrim(correction_reason)) between 3 and 1000
  ),
  created_by uuid references auth.users(id) on delete set null,
  verified_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (bank_statement_id, version_number),
  unique (id, bank_statement_id),
  constraint bank_statement_document_versions_integrity_consistent check (
    (integrity_status = 'pending_hash' and sha256 is null and verified_at is null)
    or (integrity_status = 'verified' and sha256 is not null and verified_at is not null)
  ),
  constraint bank_statement_document_versions_reason_consistent check (
    (version_number = 1 and previous_version_id is null and correction_reason is null)
    or (version_number > 1 and previous_version_id is not null and correction_reason is not null)
  ),
  constraint bank_statement_document_versions_statement_fk
    foreign key (bank_statement_id)
    references public.bank_statements(id)
    on delete restrict,
  constraint bank_statement_document_versions_previous_fk
    foreign key (previous_version_id, bank_statement_id)
    references public.bank_statement_document_versions(id, bank_statement_id)
    on delete restrict
);

create index bank_statement_document_versions_statement_idx
on public.bank_statement_document_versions(bank_statement_id, version_number desc);

create table public.bank_statement_active_document_versions (
  bank_statement_id uuid primary key references public.bank_statements(id) on delete restrict,
  version_id uuid not null unique,
  revision bigint not null default 1 check (revision > 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  constraint bank_statement_active_document_versions_version_fk
    foreign key (version_id, bank_statement_id)
    references public.bank_statement_document_versions(id, bank_statement_id)
    on delete restrict
);

create table public.bank_statement_document_corrections (
  id uuid primary key default gen_random_uuid(),
  bank_statement_id uuid not null references public.bank_statements(id) on delete restrict,
  previous_version_id uuid not null,
  proposed_version_id uuid not null unique,
  expected_active_revision bigint not null check (expected_active_revision > 0),
  client_request_id uuid not null,
  requested_by uuid not null references auth.users(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 3 and 1000),
  proposed_storage_path text not null unique,
  proposed_file_name text not null check (char_length(btrim(proposed_file_name)) between 1 and 255),
  proposed_mime_type text not null default 'application/pdf' check (proposed_mime_type = 'application/pdf'),
  proposed_file_size bigint not null check (proposed_file_size between 1 and 10485760),
  proposed_sha256 text not null check (proposed_sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'reserved' check (state in ('reserved', 'completed', 'cancelled', 'attention_required')),
  storage_object_id uuid,
  storage_object_version text,
  row_revision bigint not null default 0 check (row_revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  last_activity_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  safe_error_code text check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_:-]{1,64}$'),
  unique (requested_by, client_request_id),
  constraint bank_statement_document_corrections_previous_fk
    foreign key (previous_version_id, bank_statement_id)
    references public.bank_statement_document_versions(id, bank_statement_id)
    on delete restrict,
  constraint bank_statement_document_corrections_state_consistent check (
    (state = 'reserved' and completed_at is null and safe_error_code is null)
    or (state = 'completed' and completed_at is not null and storage_object_id is not null
      and storage_object_version is not null and safe_error_code is null)
    or (state = 'cancelled' and completed_at is not null and storage_object_id is null
      and storage_object_version is null and safe_error_code is null)
    or (state = 'attention_required' and completed_at is null and safe_error_code is not null)
  )
);

create unique index bank_statement_document_corrections_open_statement_idx
on public.bank_statement_document_corrections(bank_statement_id)
where state in ('reserved', 'attention_required');

create index bank_statement_document_corrections_statement_idx
on public.bank_statement_document_corrections(bank_statement_id, created_at desc);

create table public.management_report_bank_statement_document_versions (
  management_report_document_id uuid not null
    references public.management_report_documents(id) on delete restrict,
  bank_statement_id uuid not null references public.bank_statements(id) on delete restrict,
  document_version_id uuid not null,
  pinned_at timestamptz not null default clock_timestamp(),
  primary key (management_report_document_id, bank_statement_id),
  constraint management_report_bank_statement_version_fk
    foreign key (document_version_id, bank_statement_id)
    references public.bank_statement_document_versions(id, bank_statement_id)
    on delete restrict
);

create index management_report_bank_statement_version_idx
on public.management_report_bank_statement_document_versions(document_version_id);

create function public.build_bank_statement_document_version_path(
  p_protected_person_id uuid,
  p_financial_account_id uuid,
  p_statement_id uuid,
  p_version_id uuid
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select 'protected-persons/' || p_protected_person_id::text
    || '/accounts/' || p_financial_account_id::text
    || '/statements/' || p_statement_id::text
    || '/versions/' || p_version_id::text || '/statement';
$$;

create function public.protect_bank_statement_document_immutable_rows()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare table_owner name;
begin
  select pg_catalog.pg_get_userbyid(class.relowner)
  into table_owner
  from pg_catalog.pg_class class
  where class.oid = tg_relid;

  if current_user <> table_owner then
    raise exception using errcode = '42501', message = 'L''historique documentaire du relevé est immuable.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger bank_statement_document_versions_immutable
before update or delete on public.bank_statement_document_versions
for each row execute function public.protect_bank_statement_document_immutable_rows();

create trigger management_report_bank_statement_versions_immutable
before update or delete on public.management_report_bank_statement_document_versions
for each row execute function public.protect_bank_statement_document_immutable_rows();

create function public.assert_bank_statement_initial_document_mutable(
  p_statement_id uuid,
  p_version_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.bank_statement_document_versions version
    join public.bank_statement_active_document_versions active
      on active.bank_statement_id = version.bank_statement_id
     and active.version_id = version.id
    where version.id = p_version_id
      and version.bank_statement_id = p_statement_id
      and version.version_number = 1
      and version.path_kind = 'legacy'
  ) then
    raise exception using errcode = '55000',
      message = 'Le document historique du relevé est définitivement figé.';
  end if;

  if exists (
    select 1 from public.bank_reconciliations reconciliation
    where reconciliation.bank_statement_id = p_statement_id
      and reconciliation.status = 'validated'
  ) or exists (
    select 1
    from public.management_report_bank_statement_document_versions pinned
    where pinned.bank_statement_id = p_statement_id
      and pinned.document_version_id = p_version_id
  ) or exists (
    select 1
    from public.bank_statement_document_corrections correction
    where correction.bank_statement_id = p_statement_id
      and correction.state <> 'cancelled'
  ) then
    raise exception using errcode = '55000',
      message = 'Le document historique du relevé est définitivement figé.';
  end if;
end;
$$;

create function public.register_initial_bank_statement_document_version()
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

create trigger bank_statements_register_initial_document_version
after insert or update of original_file_name, mime_type, file_size on public.bank_statements
for each row execute function public.register_initial_bank_statement_document_version();

create function public.cleanup_unfrozen_bank_statement_document_versions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare active_row public.bank_statement_active_document_versions%rowtype;
begin
  select * into active_row
  from public.bank_statement_active_document_versions active
  where active.bank_statement_id = old.id
  for update;
  if not found then return old; end if;

  perform public.assert_bank_statement_initial_document_mutable(
    old.id, active_row.version_id
  );
  delete from public.bank_statement_active_document_versions active
  where active.bank_statement_id = old.id
    and active.version_id = active_row.version_id;
  delete from public.bank_statement_document_versions version
  where version.id = active_row.version_id
    and version.bank_statement_id = old.id;
  return old;
end;
$$;

-- Exécuté après la protection historique existante grâce à son nom : un relevé
-- validé est refusé avant tout nettoyage, tandis qu'un relevé encore modifiable
-- peut conserver son parcours de suppression historique.
create trigger bank_statements_zz_cleanup_unfrozen_document_versions
before delete on public.bank_statements
for each row execute function public.cleanup_unfrozen_bank_statement_document_versions();

create function public.protect_bank_statement_document_storage_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_row public.bank_statement_document_versions%rowtype;
begin
  if old.bucket_id <> 'bank-statements' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select version.* into version_row
  from public.bank_statement_document_versions version
  where version.storage_path = old.name
  for update;
  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  perform public.assert_bank_statement_initial_document_mutable(
    version_row.bank_statement_id, version_row.id
  );

  update public.bank_statement_document_versions
  set sha256 = null,
      integrity_status = 'pending_hash',
      verified_at = null,
      verified_by = null
  where id = version_row.id;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger bank_statement_document_versions_protect_storage
before update or delete on storage.objects
for each row
when (old.bucket_id = 'bank-statements')
execute function public.protect_bank_statement_document_storage_version();

-- Les chemins et objets existants restent strictement inchangés. Leur empreinte
-- devra être calculée par le service documentaire lors d'une lecture contrôlée.
insert into public.bank_statement_document_versions(
  id, bank_statement_id, version_number, storage_path, path_kind,
  original_file_name, mime_type, file_size, sha256, integrity_status,
  previous_version_id, correction_reason, created_by, created_at
)
select gen_random_uuid(), statement.id, 1, statement.storage_path, 'legacy',
  statement.original_file_name, statement.mime_type, statement.file_size,
  null, 'pending_hash', null, null, statement.created_by, statement.created_at
from public.bank_statements statement
where statement.original_file_name is not null
  and statement.mime_type is not null
  and statement.file_size is not null
  and not exists (
    select 1 from public.bank_statement_document_versions version
    where version.bank_statement_id = statement.id
  );

insert into public.bank_statement_active_document_versions(
  bank_statement_id, version_id, revision, updated_by, updated_at
)
select version.bank_statement_id, version.id, 1, version.created_by, version.created_at
from public.bank_statement_document_versions version
where version.version_number = 1
on conflict (bank_statement_id) do nothing;

create function public.pin_management_report_bank_statement_document_versions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.preview_snapshot is null
     or new.document_type::text <> 'management_report'
     or jsonb_typeof(new.preview_snapshot -> 'statements') is distinct from 'array' then
    return new;
  end if;

  insert into public.management_report_bank_statement_document_versions(
    management_report_document_id, bank_statement_id, document_version_id
  )
  select new.id, statement.id, active.version_id
  from jsonb_array_elements(new.preview_snapshot -> 'statements') item
  join public.bank_statements statement
    on statement.id = case
      when item ->> 'statementId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (item ->> 'statementId')::uuid
      else null
    end
  join public.financial_accounts account on account.id = statement.financial_account_id
  join public.management_reports report on report.id = new.management_report_id
  join public.bank_statement_active_document_versions active on active.bank_statement_id = statement.id
  where account.protected_person_id = report.protected_person_id
  on conflict (management_report_document_id, bank_statement_id) do nothing;
  return new;
end;
$$;

create trigger management_report_documents_pin_bank_statement_versions
after insert on public.management_report_documents
for each row execute function public.pin_management_report_bank_statement_document_versions();

-- Les snapshots historiques ne sont pas réécrits : cette liaison séparée les
-- rattache à la version initiale qui était consultable avant toute correction.
insert into public.management_report_bank_statement_document_versions(
  management_report_document_id, bank_statement_id, document_version_id
)
select document.id, statement.id, active.version_id
from public.management_report_documents document
join public.management_reports report on report.id = document.management_report_id
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(document.preview_snapshot -> 'statements') = 'array'
    then document.preview_snapshot -> 'statements' else '[]'::jsonb end
) item
join public.bank_statements statement
  on statement.id = case
    when item ->> 'statementId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then (item ->> 'statementId')::uuid
    else null
  end
join public.financial_accounts account on account.id = statement.financial_account_id
join public.bank_statement_active_document_versions active on active.bank_statement_id = statement.id
where account.protected_person_id = report.protected_person_id
  and document.document_type::text = 'management_report'
on conflict (management_report_document_id, bank_statement_id) do nothing;

create function public.begin_bank_statement_document_correction(
  p_protected_person_id uuid,
  p_financial_account_id uuid,
  p_statement_id uuid,
  p_expected_active_revision bigint,
  p_client_request_id uuid,
  p_reason text,
  p_file_name text,
  p_file_size bigint,
  p_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  statement_row public.bank_statements%rowtype;
  person_row public.protected_persons%rowtype;
  active_row public.bank_statement_active_document_versions%rowtype;
  existing public.bank_statement_document_corrections%rowtype;
  operation_id uuid := gen_random_uuid();
  version_id uuid := gen_random_uuid();
  version_path text;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentification requise.';
  end if;
  if p_client_request_id is null or p_expected_active_revision is null
     or char_length(btrim(coalesce(p_reason, ''))) not between 3 and 1000
     or char_length(btrim(coalesce(p_file_name, ''))) not between 1 and 255
     or p_file_size is null or p_file_size not between 1 and 10485760
     or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Demande de correction documentaire invalide.';
  end if;

  select statement.* into statement_row
  from public.bank_statements statement
  where statement.id = p_statement_id
    and statement.financial_account_id = p_financial_account_id
  for update;
  if not found then
    raise exception using errcode = 'P4R01', message = 'Relevé introuvable ou accès refusé.';
  end if;

  select person.* into person_row
  from public.financial_accounts account
  join public.protected_persons person on person.id = account.protected_person_id
  where account.id = p_financial_account_id
    and person.id = p_protected_person_id
  for share of person;
  if not found then
    raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.';
  end if;
  if person_row.status <> 'active' or person_row.archived_at is not null
     or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.';
  end if;
  if not exists (
    select 1 from public.bank_reconciliations reconciliation
    where reconciliation.bank_statement_id = p_statement_id
      and reconciliation.status = 'validated'
  ) then
    raise exception using errcode = '55000', message = 'Cette correction est réservée aux relevés dont le rapprochement est validé.';
  end if;

  select * into active_row
  from public.bank_statement_active_document_versions active
  where active.bank_statement_id = p_statement_id
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'La version documentaire active est introuvable.';
  end if;

  select * into existing
  from public.bank_statement_document_corrections correction
  where correction.requested_by = caller_id
    and correction.client_request_id = p_client_request_id;
  if found then
    if existing.bank_statement_id is distinct from p_statement_id
       or existing.previous_version_id is distinct from active_row.version_id
       or existing.expected_active_revision is distinct from p_expected_active_revision
       or existing.reason is distinct from btrim(p_reason)
       or existing.proposed_file_name is distinct from btrim(p_file_name)
       or existing.proposed_file_size is distinct from p_file_size
       or existing.proposed_sha256 is distinct from p_sha256 then
      raise exception using errcode = 'P4R04', message = 'La clé d''idempotence est déjà utilisée pour une autre correction.';
    end if;
    return jsonb_build_object(
      'operationId', existing.id,
      'versionId', existing.proposed_version_id,
      'storagePath', existing.proposed_storage_path,
      'state', existing.state,
      'revision', existing.row_revision,
      'activeRevision', existing.expected_active_revision
    );
  end if;

  if active_row.revision <> p_expected_active_revision then
    raise exception using errcode = '40001', message = 'Le document actif a changé. Rechargez le relevé avant de recommencer.';
  end if;
  if exists (
    select 1 from public.bank_statement_document_corrections correction
    where correction.bank_statement_id = p_statement_id
      and correction.state in ('reserved', 'attention_required')
  ) then
    raise exception using errcode = '55000', message = 'Une correction documentaire est déjà en cours pour ce relevé.';
  end if;
  version_path := public.build_bank_statement_document_version_path(
    p_protected_person_id, p_financial_account_id, p_statement_id, version_id
  );
  insert into public.bank_statement_document_corrections(
    id, bank_statement_id, previous_version_id, proposed_version_id,
    expected_active_revision, client_request_id, requested_by, reason,
    proposed_storage_path, proposed_file_name, proposed_file_size, proposed_sha256
  ) values (
    operation_id, p_statement_id, active_row.version_id, version_id,
    p_expected_active_revision, p_client_request_id, caller_id, btrim(p_reason),
    version_path, btrim(p_file_name), p_file_size, p_sha256
  );
  return jsonb_build_object(
    'operationId', operation_id,
    'versionId', version_id,
    'storagePath', version_path,
    'state', 'reserved',
    'revision', 0,
    'activeRevision', active_row.revision
  );
end;
$$;

create function public.finalize_bank_statement_document_correction(
  p_operation_id uuid,
  p_expected_operation_revision bigint,
  p_storage_object_id uuid,
  p_storage_object_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.bank_statement_document_corrections%rowtype;
  active_row public.bank_statement_active_document_versions%rowtype;
  next_number integer;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentification requise.';
  end if;
  select * into operation_row
  from public.bank_statement_document_corrections correction
  where correction.id = p_operation_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;
  if operation_row.requested_by <> caller_id then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;
  if operation_row.state = 'completed' then
    return jsonb_build_object(
      'operationId', operation_row.id,
      'versionId', operation_row.proposed_version_id,
      'state', operation_row.state,
      'revision', operation_row.row_revision
    );
  end if;
  if operation_row.state <> 'reserved'
     or operation_row.row_revision <> p_expected_operation_revision then
    raise exception using errcode = '40001', message = 'La correction documentaire a changé. Rechargez son état.';
  end if;
  if not exists (
    select 1
    from public.bank_statements statement
    join public.financial_accounts account on account.id = statement.financial_account_id
    join public.protected_persons person on person.id = account.protected_person_id
    where statement.id = operation_row.bank_statement_id
      and person.status = 'active' and person.archived_at is null
      and public.can_manage_protected_person(person.id)
      and exists (
        select 1 from public.bank_reconciliations reconciliation
        where reconciliation.bank_statement_id = statement.id
          and reconciliation.status = 'validated'
      )
  ) then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;

  select * into active_row
  from public.bank_statement_active_document_versions active
  where active.bank_statement_id = operation_row.bank_statement_id
  for update;
  if not found then
    raise exception using errcode = '40001', message = 'Une autre correction documentaire a déjà été appliquée.';
  end if;
  if active_row.version_id <> operation_row.previous_version_id
     or active_row.revision <> operation_row.expected_active_revision then
    raise exception using errcode = '40001', message = 'Une autre correction documentaire a déjà été appliquée.';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'bank-statements'
      and object.name = operation_row.proposed_storage_path
      and object.id = p_storage_object_id
      and object.version = p_storage_object_version
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = 'application/pdf'
      and coalesce(
        case when object.metadata ->> 'size' ~ '^[0-9]+$'
          then (object.metadata ->> 'size')::bigint end,
        -1
      ) = operation_row.proposed_file_size
  ) then
    raise exception using errcode = '55000', message = 'Le nouveau PDF n''est pas vérifié dans le stockage privé.';
  end if;

  select coalesce(max(version.version_number), 0) + 1 into next_number
  from public.bank_statement_document_versions version
  where version.bank_statement_id = operation_row.bank_statement_id;

  insert into public.bank_statement_document_versions(
    id, bank_statement_id, version_number, storage_path, path_kind,
    original_file_name, mime_type, file_size, sha256, integrity_status,
    verified_at, previous_version_id, correction_reason, created_by, verified_by
  ) values (
    operation_row.proposed_version_id, operation_row.bank_statement_id, next_number,
    operation_row.proposed_storage_path, 'versioned', operation_row.proposed_file_name,
    operation_row.proposed_mime_type, operation_row.proposed_file_size,
    operation_row.proposed_sha256, 'verified', clock_timestamp(), operation_row.previous_version_id,
    operation_row.reason, caller_id, caller_id
  );
  update public.bank_statement_active_document_versions
  set version_id = operation_row.proposed_version_id,
      revision = revision + 1,
      updated_by = caller_id,
      updated_at = clock_timestamp()
  where bank_statement_id = operation_row.bank_statement_id
    and version_id = operation_row.previous_version_id
    and revision = operation_row.expected_active_revision;
  if not found then
    raise exception using errcode = '40001', message = 'Une autre correction documentaire a déjà été appliquée.';
  end if;
  update public.bank_statement_document_corrections
  set state = 'completed', storage_object_id = p_storage_object_id,
      storage_object_version = p_storage_object_version,
      row_revision = row_revision + 1,
      last_activity_at = clock_timestamp(), completed_at = clock_timestamp()
  where id = operation_row.id;
  return jsonb_build_object(
    'operationId', operation_row.id,
    'versionId', operation_row.proposed_version_id,
    'state', 'completed',
    'revision', operation_row.row_revision + 1,
    'activeRevision', active_row.revision + 1
  );
end;
$$;

create function public.verify_bank_statement_document_version_integrity(
  p_version_id uuid,
  p_storage_object_id uuid,
  p_storage_object_version text,
  p_sha256 text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare version_row public.bank_statement_document_versions%rowtype;
begin
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Empreinte documentaire invalide.';
  end if;
  select * into version_row
  from public.bank_statement_document_versions version
  where version.id = p_version_id
  for update;
  if not found then
    raise exception using errcode = 'P4R01', message = 'Version documentaire introuvable.';
  end if;
  if version_row.integrity_status = 'verified' then
    if version_row.sha256 is distinct from p_sha256 then
      raise exception using errcode = '55000', message = 'La version possède déjà une autre empreinte vérifiée.';
    end if;
    return;
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'bank-statements'
      and object.name = version_row.storage_path
      and object.id = p_storage_object_id
      and object.version = p_storage_object_version
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = version_row.mime_type
      and coalesce(
        case when object.metadata ->> 'size' ~ '^[0-9]+$'
          then (object.metadata ->> 'size')::bigint end,
        -1
      ) = version_row.file_size
  ) then
    raise exception using errcode = '55000', message = 'L''objet Storage de la version n''est pas vérifié.';
  end if;
  update public.bank_statement_document_versions
  set sha256 = p_sha256, integrity_status = 'verified',
      verified_at = clock_timestamp(), verified_by = null
  where id = version_row.id and integrity_status = 'pending_hash';
end;
$$;

create function public.cancel_bank_statement_document_correction(
  p_operation_id uuid,
  p_expected_operation_revision bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.bank_statement_document_corrections%rowtype;
begin
  select * into operation_row
  from public.bank_statement_document_corrections correction
  where correction.id = p_operation_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;
  if operation_row.requested_by <> caller_id then
    raise exception using errcode = '42501', message = 'Correction documentaire introuvable ou accès refusé.';
  end if;
  if operation_row.state = 'cancelled' then return; end if;
  if operation_row.state <> 'reserved'
     or operation_row.row_revision <> p_expected_operation_revision then
    raise exception using errcode = '40001', message = 'La correction documentaire ne peut plus être annulée.';
  end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id = 'bank-statements'
      and object.name = operation_row.proposed_storage_path
  ) then
    raise exception using errcode = '55000', message = 'Le PDF téléversé doit être repris ou vérifié avant toute annulation.';
  end if;
  update public.bank_statement_document_corrections
  set state = 'cancelled', row_revision = row_revision + 1,
      last_activity_at = clock_timestamp(), completed_at = clock_timestamp()
  where id = operation_row.id;
end;
$$;

create function public.get_bank_statement_document_history(p_statement_id uuid)
returns table (
  version_id uuid,
  version_number integer,
  storage_path text,
  original_file_name text,
  mime_type text,
  file_size bigint,
  sha256 text,
  integrity_status text,
  previous_version_id uuid,
  correction_reason text,
  created_by uuid,
  created_at timestamptz,
  is_active boolean,
  active_revision bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.bank_statements statement
    join public.financial_accounts account on account.id = statement.financial_account_id
    where statement.id = p_statement_id
      and public.can_read_protected_person(account.protected_person_id)
  ) then
    raise exception using errcode = '42501', message = 'Relevé introuvable ou accès refusé.';
  end if;
  return query
  select version.id, version.version_number, version.storage_path,
    version.original_file_name, version.mime_type, version.file_size,
    version.sha256, version.integrity_status, version.previous_version_id,
    version.correction_reason, version.created_by, version.created_at,
    active.version_id = version.id, active.revision
  from public.bank_statement_document_versions version
  join public.bank_statement_active_document_versions active
    on active.bank_statement_id = version.bank_statement_id
  where version.bank_statement_id = p_statement_id
  order by version.version_number desc;
end;
$$;

alter table public.bank_statement_document_versions enable row level security;
alter table public.bank_statement_active_document_versions enable row level security;
alter table public.bank_statement_document_corrections enable row level security;
alter table public.management_report_bank_statement_document_versions enable row level security;

create policy bank_statement_document_versions_select_accessible
on public.bank_statement_document_versions
for select to authenticated
using (exists (
  select 1 from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_statement_document_versions.bank_statement_id
    and public.can_read_protected_person(account.protected_person_id)
));

create policy bank_statement_active_document_versions_select_accessible
on public.bank_statement_active_document_versions
for select to authenticated
using (exists (
  select 1 from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_statement_active_document_versions.bank_statement_id
    and public.can_read_protected_person(account.protected_person_id)
));

create policy bank_statement_document_corrections_select_accessible
on public.bank_statement_document_corrections
for select to authenticated
using (exists (
  select 1 from public.bank_statements statement
  join public.financial_accounts account on account.id = statement.financial_account_id
  where statement.id = bank_statement_document_corrections.bank_statement_id
    and public.can_read_protected_person(account.protected_person_id)
));

create policy management_report_bank_statement_versions_select_accessible
on public.management_report_bank_statement_document_versions
for select to authenticated
using (exists (
  select 1 from public.management_report_documents document
  join public.management_reports report on report.id = document.management_report_id
  where document.id = management_report_bank_statement_document_versions.management_report_document_id
    and public.can_read_protected_person(report.protected_person_id)
));

grant select on public.bank_statement_document_versions,
  public.bank_statement_active_document_versions,
  public.bank_statement_document_corrections,
  public.management_report_bank_statement_document_versions
to authenticated;

revoke insert, update, delete on public.bank_statement_document_versions,
  public.bank_statement_active_document_versions,
  public.bank_statement_document_corrections,
  public.management_report_bank_statement_document_versions
from public, anon, authenticated, service_role;

drop policy if exists bank_statement_document_versions_storage_select_accessible on storage.objects;
create policy bank_statement_document_versions_storage_select_accessible
on storage.objects
for select to authenticated
using (
  bucket_id = 'bank-statements'
  and (
    exists (
      select 1
      from public.bank_statement_document_versions version
      join public.bank_statements statement on statement.id = version.bank_statement_id
      join public.financial_accounts account on account.id = statement.financial_account_id
      where version.storage_path = name
        and public.can_read_protected_person(account.protected_person_id)
    )
    or exists (
      select 1
      from public.bank_statement_document_corrections correction
      join public.bank_statements statement on statement.id = correction.bank_statement_id
      join public.financial_accounts account on account.id = statement.financial_account_id
      join public.protected_persons person on person.id = account.protected_person_id
      where correction.proposed_storage_path = name
        and correction.requested_by = auth.uid()
        and correction.state = 'reserved'
        and person.status = 'active' and person.archived_at is null
        and public.can_manage_protected_person(person.id)
    )
  )
);

drop policy if exists bank_statement_document_corrections_storage_insert_manage on storage.objects;
create policy bank_statement_document_corrections_storage_insert_manage
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'bank-statements'
  and owner_id = auth.uid()::text
  and exists (
    select 1
    from public.bank_statement_document_corrections correction
    join public.bank_statements statement on statement.id = correction.bank_statement_id
    join public.financial_accounts account on account.id = statement.financial_account_id
    join public.protected_persons person on person.id = account.protected_person_id
    where correction.proposed_storage_path = name
      and correction.requested_by = auth.uid()
      and correction.state = 'reserved'
      and person.status = 'active' and person.archived_at is null
      and public.can_manage_protected_person(person.id)
  )
);

revoke all on function public.build_bank_statement_document_version_path(uuid,uuid,uuid,uuid),
  public.protect_bank_statement_document_immutable_rows(),
  public.assert_bank_statement_initial_document_mutable(uuid,uuid),
  public.register_initial_bank_statement_document_version(),
  public.cleanup_unfrozen_bank_statement_document_versions(),
  public.protect_bank_statement_document_storage_version(),
  public.pin_management_report_bank_statement_document_versions()
from public, anon, authenticated, service_role;

revoke all on function public.begin_bank_statement_document_correction(uuid,uuid,uuid,bigint,uuid,text,text,bigint,text),
  public.finalize_bank_statement_document_correction(uuid,bigint,uuid,text),
  public.cancel_bank_statement_document_correction(uuid,bigint),
  public.verify_bank_statement_document_version_integrity(uuid,uuid,text,text),
  public.get_bank_statement_document_history(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.begin_bank_statement_document_correction(uuid,uuid,uuid,bigint,uuid,text,text,bigint,text),
  public.finalize_bank_statement_document_correction(uuid,bigint,uuid,text),
  public.cancel_bank_statement_document_correction(uuid,bigint),
  public.get_bank_statement_document_history(uuid)
to authenticated;

grant execute on function public.verify_bank_statement_document_version_integrity(uuid,uuid,text,text)
to service_role;

comment on table public.bank_statement_document_versions is
  'Versions PDF des relevés bancaires ; la version initiale suit le PDF avant gel, puis toutes les versions historiques sont immuables.';
comment on table public.bank_statement_document_corrections is
  'Réservations idempotentes des corrections documentaires, sans mutation des données comptables du relevé.';
comment on table public.management_report_bank_statement_document_versions is
  'Version du relevé figée pour chaque document de compte de gestion, sans réécriture du snapshot historique.';
