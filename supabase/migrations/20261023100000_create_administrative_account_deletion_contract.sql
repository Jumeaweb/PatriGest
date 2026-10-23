-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C2
-- Contrat SQL de suppression administrative durable. Ce lot ne supprime
-- aucun compte Auth, ne mute aucun objet Storage et n'installe aucun trigger
-- sur storage.objects.

create table public.administrative_account_deletion_authorizations (
  id uuid primary key default gen_random_uuid(),
  administrator_subject_id uuid not null,
  administrator_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid not null,
  attempt_id uuid not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  document_plan jsonb not null check (jsonb_typeof(document_plan) = 'array'),
  document_plan_hash text not null check (document_plan_hash ~ '^[0-9a-f]{64}$'),
  document_count integer not null check (document_count between 0 and 1000),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  state text not null default 'active'
    check (state in ('active', 'sealed', 'cancelled')),
  state_changed_at timestamptz not null default clock_timestamp(),
  last_barrier_checked_at timestamptz,
  row_revision bigint not null default 0 check (row_revision >= 0),
  unique (administrator_subject_id, attempt_id),
  check (administrator_user_id is null
    or administrator_user_id = administrator_subject_id),
  check (expires_at > issued_at
    and expires_at <= issued_at + interval '10 minutes')
);

create index administrative_account_deletion_target_state_idx
on public.administrative_account_deletion_authorizations(
  target_user_id, state, expires_at desc
);

alter table public.administrative_account_deletion_authorizations
  enable row level security;
revoke all on table public.administrative_account_deletion_authorizations
from public, anon, authenticated, service_role;

create trigger administrative_account_deletion_authorizations_protected
before update or delete on public.administrative_account_deletion_authorizations
for each row execute function public.protect_document_operation_audit_rows();

create table public.administrative_account_deletion_events (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references
    public.administrative_account_deletion_authorizations(id) on delete restrict,
  sequence_number bigint not null check (sequence_number > 0),
  event_type text not null check (event_type in (
    'authorized', 'cancelled', 'neutralization_reserved', 'barrier_sealed'
  )),
  outcome text not null check (outcome in ('success', 'failure', 'information')),
  actor_subject_id uuid not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid not null,
  operation_id uuid references public.document_operations(id) on delete restrict,
  safe_code text check (
    safe_code is null or safe_code ~ '^[A-Z0-9_:-]{1,64}$'
  ),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (authorization_id, sequence_number)
);

create index administrative_account_deletion_events_authorization_idx
on public.administrative_account_deletion_events(
  authorization_id, sequence_number
);

alter table public.administrative_account_deletion_events enable row level security;
revoke all on table public.administrative_account_deletion_events
from public, anon, authenticated, service_role;

create trigger administrative_account_deletion_events_append_only
before update or delete on public.administrative_account_deletion_events
for each row execute function public.protect_document_operation_audit_rows();

-- Une neutralisation partage le moteur spécialisé existant, mais sa source
-- d'autorisation reste explicite et exclusive : personnelle ou administrative.
alter table public.account_storage_neutralizations
  alter column authorization_id drop not null,
  add column administrative_authorization_id uuid references
    public.administrative_account_deletion_authorizations(id) on delete restrict;

alter table public.account_storage_neutralizations
  add constraint account_storage_neutralizations_authorization_source_check
  check (num_nonnulls(authorization_id, administrative_authorization_id) = 1);

create index account_storage_neutralizations_admin_authorization_idx
on public.account_storage_neutralizations(administrative_authorization_id, phase)
where administrative_authorization_id is not null;

create function public.append_administrative_account_deletion_event(
  p_authorization_id uuid,
  p_event_type text,
  p_outcome text default 'success',
  p_operation_id uuid default null,
  p_safe_code text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
  next_sequence bigint;
begin
  select * into authorization_row
  from public.administrative_account_deletion_authorizations
  where id = p_authorization_id;
  if not found then
    raise exception using errcode = 'P4D02',
      message = 'Autorisation administrative introuvable.';
  end if;
  select coalesce(max(event.sequence_number), 0) + 1
  into next_sequence
  from public.administrative_account_deletion_events event
  where event.authorization_id = p_authorization_id;
  insert into public.administrative_account_deletion_events (
    authorization_id, sequence_number, event_type, outcome,
    actor_subject_id, actor_user_id, target_user_id, operation_id, safe_code
  ) values (
    authorization_row.id, next_sequence, p_event_type, p_outcome,
    authorization_row.administrator_subject_id,
    authorization_row.administrator_user_id,
    authorization_row.target_user_id, p_operation_id, p_safe_code
  );
  return next_sequence;
end;
$$;

create function public.administrative_account_deletion_business_blockers(
  p_administrator_user_id uuid,
  p_target_user_id uuid
)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_email text;
  blockers text[] := array[]::text[];
begin
  if p_administrator_user_id is null
     or p_target_user_id is null
     or not exists (
       select 1 from public.platform_administrators administrator
       where administrator.user_id = p_administrator_user_id
     ) then
    return array['ADMINISTRATOR_NOT_AUTHORIZED'];
  end if;
  if p_administrator_user_id = p_target_user_id then
    blockers := array_append(blockers, 'ADMINISTRATOR_SELF_DELETION');
  end if;
  if not exists (select 1 from auth.users account where account.id = p_target_user_id) then
    blockers := array_append(blockers, 'TARGET_AUTH_USER_MISSING');
    return blockers;
  end if;
  select lower(btrim(account.email)) into target_email
  from auth.users account where account.id = p_target_user_id;
  if exists (
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_target_user_id
       or administrator.appointed_by = p_target_user_id
  ) then blockers := array_append(blockers, 'PLATFORM_ADMINISTRATION_RELATION'); end if;
  if exists (
    select 1 from public.protected_persons person
    where person.owner_id = p_target_user_id
  ) then blockers := array_append(blockers, 'OWNED_PROTECTED_PERSON'); end if;
  if exists (
    select 1 from public.protected_person_access access_row
    where access_row.user_id = p_target_user_id
  ) then blockers := array_append(blockers, 'SHARED_DOSSIER_ACCESS'); end if;
  if exists (
    select 1 from public.protected_person_invitations invitation
    where invitation.accepted_at is null
      and invitation.revoked_at is null
      and invitation.declined_at is null
      and invitation.expires_at > clock_timestamp()
      and (
        invitation.invited_by = p_target_user_id
        or (target_email <> '' and lower(btrim(invitation.email)) = target_email)
      )
  ) then blockers := array_append(blockers, 'ACTIVE_DOSSIER_INVITATION'); end if;
  if exists (
    select 1 from public.categories category
    where category.owner_id = p_target_user_id
  ) then blockers := array_append(blockers, 'OWNED_CATEGORY'); end if;
  if exists (
    select 1 from public.transaction_documents document
    where document.created_by = p_target_user_id
  ) then blockers := array_append(blockers, 'TRANSACTION_DOCUMENT_AUTHOR'); end if;
  if exists (
    select 1 from public.bank_statements statement
    where statement.created_by = p_target_user_id
  ) then blockers := array_append(blockers, 'BANK_STATEMENT_AUTHOR'); end if;
  if exists (
    select 1 from public.management_reports report
    where report.created_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_AUTHOR'); end if;
  if exists (
    select 1 from public.management_report_documents document
    where document.generated_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_DOCUMENT_AUTHOR'); end if;
  if exists (
    select 1 from public.management_report_transmissions transmission
    where transmission.declared_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_TRANSMISSION_AUTHOR'); end if;
  if exists (
    select 1 from public.management_report_approvals approval
    where approval.declared_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_APPROVAL_AUTHOR'); end if;
  if exists (
    select 1 from public.management_report_difficulties difficulty
    where difficulty.declared_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_DIFFICULTY_AUTHOR'); end if;
  if exists (
    select 1 from public.management_report_account_selections selection
    where selection.created_by = p_target_user_id
  ) then blockers := array_append(blockers, 'MANAGEMENT_REPORT_SELECTION_AUTHOR'); end if;
  return blockers;
end;
$$;

create function public.assert_administrative_account_deletion_eligibility(
  p_target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  blockers text[];
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Suppression administrative non autorisée.';
  end if;
  blockers := public.administrative_account_deletion_business_blockers(
    caller_id, p_target_user_id
  );
  if cardinality(blockers) <> 0 then
    raise exception using errcode = 'P4D01',
      message = 'Le compte ne satisfait pas les conditions de suppression administrative.';
  end if;
end;
$$;

create function public.get_administrative_account_deletion_diagnostic(
  p_target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  blockers text[];
  storage_objects jsonb;
  anomalies text[] := array[]::text[];
  non_terminal_count bigint;
  unfinished_neutralization_count bigint;
  uncleared_backup_count bigint;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Diagnostic administratif non autorisé.';
  end if;
  blockers := public.administrative_account_deletion_business_blockers(
    caller_id, p_target_user_id
  );
  select coalesce(jsonb_agg(jsonb_build_object(
    'bucketId', object.bucket_id,
    'objectPath', object.name,
    'objectId', object.id,
    'objectVersion', object.version,
    'catalogByteSize', case
      when coalesce(object.metadata->>'size', '') ~ '^[0-9]+$'
        then (object.metadata->>'size')::bigint
      else null
    end,
    'catalogMimeType', object.metadata->>'mimetype',
    'canonical', resolution.is_canonical,
    'protectedPersonId', resolution.protected_person_id,
    'businessEntityType', resolution.business_entity_type,
    'businessEntityId', resolution.business_entity_id
  ) order by object.bucket_id, object.name), '[]'::jsonb)
  into storage_objects
  from storage.objects object
  cross join lateral public.resolve_canonical_document_storage_path(
    object.bucket_id, object.name
  ) resolution
  where object.bucket_id in (
    'transaction-proofs', 'bank-statements', 'management-reports'
  ) and (
    object.owner = p_target_user_id
    or object.owner_id = p_target_user_id::text
  );
  if exists (
    select 1 from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    where object.bucket_id in (
      'transaction-proofs', 'bank-statements', 'management-reports'
    ) and (object.owner = p_target_user_id
      or object.owner_id = p_target_user_id::text)
      and not resolution.is_canonical
  ) then anomalies := array_append(anomalies, 'NON_CANONICAL_STORAGE_OBJECT'); end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id in (
      'transaction-proofs', 'bank-statements', 'management-reports'
    ) and (object.owner = p_target_user_id
      or object.owner_id = p_target_user_id::text)
      and (object.version is null or btrim(object.version) = '')
  ) then anomalies := array_append(anomalies, 'STORAGE_VERSION_MISSING'); end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id in (
      'transaction-proofs', 'bank-statements', 'management-reports'
    ) and (object.owner = p_target_user_id
      or object.owner_id = p_target_user_id::text)
      and (
        coalesce(object.metadata->>'size', '') !~ '^[0-9]+$'
        or coalesce(object.metadata->>'mimetype', '') = ''
      )
  ) then anomalies := array_append(anomalies, 'STORAGE_METADATA_INCOMPLETE'); end if;
  if exists (
    select 1 from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    where object.bucket_id in (
      'transaction-proofs', 'bank-statements', 'management-reports'
    ) and (object.owner = p_target_user_id
      or object.owner_id = p_target_user_id::text)
      and resolution.is_canonical
      and not exists (
        select 1 from public.protected_persons person
        where person.id = resolution.protected_person_id
      )
  ) then anomalies := array_append(anomalies, 'PROTECTED_PERSON_MISSING'); end if;
  select count(*) into non_terminal_count
  from public.document_operations operation
  where operation.initiator_subject_id = p_target_user_id
    and operation.state not in (
      'completed', 'compensated', 'cancelled', 'administratively_resolved'
    );
  select count(*) into unfinished_neutralization_count
  from public.account_storage_neutralizations neutralization
  where neutralization.account_user_id = p_target_user_id
    and neutralization.phase <> 'finalized';
  select count(*) into uncleared_backup_count
  from public.document_operation_backups backup
  where backup.initiator_subject_id = p_target_user_id
    and backup.state <> 'deleted';
  if non_terminal_count <> 0 then
    anomalies := array_append(anomalies, 'NON_TERMINAL_DOCUMENT_OPERATION');
  end if;
  if unfinished_neutralization_count <> 0 then
    anomalies := array_append(anomalies, 'UNFINISHED_STORAGE_NEUTRALIZATION');
  end if;
  if uncleared_backup_count <> 0 then
    anomalies := array_append(anomalies, 'UNCLEARED_DURABLE_BACKUP');
  end if;
  return jsonb_build_object(
    'targetUserId', p_target_user_id,
    'eligible', cardinality(blockers) = 0,
    'businessBlockers', to_jsonb(blockers),
    'blockingAnomalies', to_jsonb(anomalies),
    'storageObjects', storage_objects,
    'nonTerminalOperationCount', non_terminal_count,
    'unfinishedNeutralizationCount', unfinished_neutralization_count,
    'unclearedBackupCount', uncleared_backup_count
  );
end;
$$;

create function public.normalize_administrative_account_deletion_plan(
  p_target_user_id uuid,
  p_document_plan jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  plan_length integer;
  normalized jsonb;
begin
  if p_target_user_id is null or jsonb_typeof(p_document_plan) <> 'array' then
    raise exception using errcode = 'P4D02',
      message = 'Plan documentaire administratif invalide.';
  end if;
  plan_length := jsonb_array_length(p_document_plan);
  if plan_length > 1000 then
    raise exception using errcode = 'P4D02',
      message = 'Plan documentaire administratif invalide.';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_document_plan) item
    where jsonb_typeof(item) <> 'object'
      or (item->>'ordinal') is null
      or (item->>'bucketId') not in (
        'transaction-proofs', 'bank-statements', 'management-reports'
      )
      or (item->>'objectPath') is null
      or (item->>'objectId') is null
      or (item->>'objectVersion') is null
      or btrim(item->>'objectVersion') = ''
      or coalesce(item->>'sha256', '') !~ '^[0-9a-f]{64}$'
      or (item->>'byteSize') is null
      or (item->>'byteSize')::bigint not between 1 and 20971520
      or (item->>'mimeType') not in (
        'application/pdf', 'image/jpeg', 'image/png'
      )
      or (item->>'protectedPersonId') is null
      or (item->>'businessEntityType') is null
      or (item->>'businessEntityId') is null
  ) then
    raise exception using errcode = 'P4D02',
      message = 'Plan documentaire administratif invalide.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'ordinal', (item->>'ordinal')::integer,
    'bucketId', item->>'bucketId',
    'objectPath', item->>'objectPath',
    'objectId', (item->>'objectId')::uuid,
    'objectVersion', item->>'objectVersion',
    'sha256', item->>'sha256',
    'byteSize', (item->>'byteSize')::bigint,
    'mimeType', item->>'mimeType',
    'protectedPersonId', (item->>'protectedPersonId')::uuid,
    'businessEntityType', item->>'businessEntityType',
    'businessEntityId', (item->>'businessEntityId')::uuid
  ) order by (item->>'ordinal')::integer), '[]'::jsonb)
  into normalized
  from jsonb_array_elements(p_document_plan) item;
  if normalized is distinct from p_document_plan
     or (select count(distinct (item->>'ordinal')::integer)
         from jsonb_array_elements(normalized) item) <> plan_length
     or exists (
       select 1 from jsonb_array_elements(normalized) with ordinality entry(item, position)
       where (item->>'ordinal')::integer <> position
     )
     or (select count(distinct (item->>'bucketId', item->>'objectPath'))
         from jsonb_array_elements(normalized) item) <> plan_length then
    raise exception using errcode = 'P4D02',
      message = 'Plan documentaire administratif invalide.';
  end if;
  if plan_length <> (
    select count(*) from storage.objects object
    where object.bucket_id in (
      'transaction-proofs', 'bank-statements', 'management-reports'
    ) and (object.owner = p_target_user_id
      or object.owner_id = p_target_user_id::text)
  ) or exists (
    select 1
    from jsonb_array_elements(normalized) item
    left join storage.objects object
      on object.bucket_id = item->>'bucketId'
     and object.name = item->>'objectPath'
     and object.id = (item->>'objectId')::uuid
     and object.version = item->>'objectVersion'
     and (object.owner = p_target_user_id
       or object.owner_id = p_target_user_id::text)
    cross join lateral public.resolve_canonical_document_storage_path(
      item->>'bucketId', item->>'objectPath'
    ) resolution
    where object.id is null
       or not resolution.is_canonical
       or not exists (
         select 1 from public.protected_persons person
         where person.id = resolution.protected_person_id
       )
       or resolution.protected_person_id is distinct from
          (item->>'protectedPersonId')::uuid
       or resolution.business_entity_type is distinct from
          item->>'businessEntityType'
       or resolution.business_entity_id is distinct from
          (item->>'businessEntityId')::uuid
  ) then
    raise exception using errcode = 'P4D03',
      message = 'Le plan ne correspond pas à l’inventaire Storage courant.';
  end if;
  return normalized;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = 'P4D02',
      message = 'Plan documentaire administratif invalide.';
end;
$$;

create function public.administrative_account_deletion_plan_hash(
  p_document_plan jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(convert_to(p_document_plan::text, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

create function public.issue_administrative_account_deletion_authorization(
  p_target_user_id uuid,
  p_attempt_id uuid,
  p_reason text,
  p_document_plan jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  issued_at_value timestamptz := clock_timestamp();
  normalized_plan jsonb;
  plan_hash_value text;
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
begin
  perform public.assert_administrative_account_deletion_eligibility(
    p_target_user_id
  );
  if p_attempt_id is null
     or p_reason is null
     or char_length(btrim(p_reason)) not between 1 and 2000 then
    raise exception using errcode = 'P4D02',
      message = 'Demande de suppression administrative invalide.';
  end if;
  select * into authorization_row
  from public.administrative_account_deletion_authorizations authz
  where authz.administrator_subject_id = caller_id
    and authz.attempt_id = p_attempt_id;
  if found and (
    authorization_row.target_user_id is distinct from p_target_user_id
    or authorization_row.reason is distinct from btrim(p_reason)
  ) then
    raise exception using errcode = 'P4D04',
      message = 'La tentative administrative est déjà utilisée pour une autre demande.';
  end if;
  normalized_plan := public.normalize_administrative_account_deletion_plan(
    p_target_user_id, p_document_plan
  );
  plan_hash_value := public.administrative_account_deletion_plan_hash(
    normalized_plan
  );
  insert into public.administrative_account_deletion_authorizations (
    administrator_subject_id, administrator_user_id, target_user_id,
    attempt_id, reason, document_plan, document_plan_hash, document_count,
    issued_at, expires_at
  ) values (
    caller_id, caller_id, p_target_user_id, p_attempt_id, btrim(p_reason),
    normalized_plan, plan_hash_value, jsonb_array_length(normalized_plan),
    issued_at_value, issued_at_value + interval '10 minutes'
  ) on conflict (administrator_subject_id, attempt_id) do nothing
  returning * into authorization_row;
  if authorization_row.id is null then
    select * into authorization_row
    from public.administrative_account_deletion_authorizations authz
    where authz.administrator_subject_id = caller_id
      and authz.attempt_id = p_attempt_id;
    if authorization_row.target_user_id is distinct from p_target_user_id
       or authorization_row.reason is distinct from btrim(p_reason)
       or authorization_row.document_plan is distinct from normalized_plan
       or authorization_row.document_plan_hash is distinct from plan_hash_value then
      raise exception using errcode = 'P4D04',
        message = 'La tentative administrative est déjà utilisée pour une autre demande.';
    end if;
  else
    perform public.append_administrative_account_deletion_event(
      authorization_row.id, 'authorized'
    );
  end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'administratorUserId', authorization_row.administrator_subject_id,
    'targetUserId', authorization_row.target_user_id,
    'attemptId', authorization_row.attempt_id,
    'planHash', authorization_row.document_plan_hash,
    'documentCount', authorization_row.document_count,
    'expiresAt', authorization_row.expires_at,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.cancel_administrative_account_deletion_authorization(
  p_authorization_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Annulation administrative non autorisée.';
  end if;
  select * into authorization_row
  from public.administrative_account_deletion_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.administrator_subject_id <> caller_id then
    raise exception using errcode = 'P4D01',
      message = 'Annulation administrative non autorisée.';
  end if;
  if authorization_row.state = 'sealed' then
    raise exception using errcode = 'P4D04',
      message = 'Une autorisation scellée ne peut plus être annulée.';
  end if;
  if authorization_row.state = 'active' then
    if authorization_row.row_revision <> p_expected_revision then
      raise exception using errcode = 'P4D04',
        message = 'La tentative administrative a changé.';
    end if;
    update public.administrative_account_deletion_authorizations
    set state = 'cancelled', state_changed_at = clock_timestamp(),
        row_revision = row_revision + 1
    where id = authorization_row.id returning * into authorization_row;
    perform public.append_administrative_account_deletion_event(
      authorization_row.id, 'cancelled'
    );
  end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.begin_administrative_account_storage_neutralization(
  p_authorization_id uuid,
  p_client_request_id uuid,
  p_bucket_id text,
  p_object_path text,
  p_expected_object_id uuid,
  p_expected_object_version text,
  p_expected_sha256 text,
  p_expected_byte_size bigint,
  p_mime_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
  plan_item jsonb;
  resolution record;
  object_row storage.objects%rowtype;
  existing_operation public.document_operations%rowtype;
  neutralization_row public.account_storage_neutralizations%rowtype;
  operation_id_value uuid;
  target_id_value uuid;
  signature jsonb;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Neutralisation administrative non autorisée.';
  end if;
  select * into authorization_row
  from public.administrative_account_deletion_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.administrator_subject_id <> caller_id
     or authorization_row.state <> 'active'
     or authorization_row.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P4D01',
      message = 'Autorisation administrative inactive ou expirée.';
  end if;
  perform public.assert_administrative_account_deletion_eligibility(
    authorization_row.target_user_id
  );
  if p_client_request_id is null then
    raise exception using errcode = 'P4D02',
      message = 'Demande de neutralisation administrative invalide.';
  end if;
  select item into plan_item
  from jsonb_array_elements(authorization_row.document_plan) item
  where item->>'bucketId' = p_bucket_id
    and item->>'objectPath' = p_object_path;
  if plan_item is null
     or (plan_item->>'objectId')::uuid is distinct from p_expected_object_id
     or plan_item->>'objectVersion' is distinct from p_expected_object_version
     or plan_item->>'sha256' is distinct from p_expected_sha256
     or (plan_item->>'byteSize')::bigint is distinct from p_expected_byte_size
     or plan_item->>'mimeType' is distinct from p_mime_type then
    raise exception using errcode = 'P4D03',
      message = 'La neutralisation ne correspond pas au plan autorisé.';
  end if;
  select * into resolution
  from public.resolve_canonical_document_storage_path(p_bucket_id, p_object_path);
  if not resolution.is_canonical
     or resolution.protected_person_id is distinct from
        (plan_item->>'protectedPersonId')::uuid
     or resolution.business_entity_type is distinct from
        plan_item->>'businessEntityType'
     or resolution.business_entity_id is distinct from
        (plan_item->>'businessEntityId')::uuid then
    raise exception using errcode = 'P4D03',
      message = 'La neutralisation ne correspond pas au plan autorisé.';
  end if;
  select * into object_row
  from storage.objects object
  where object.bucket_id = p_bucket_id and object.name = p_object_path
  for key share;
  if not found
     or object_row.id is distinct from p_expected_object_id
     or object_row.version is distinct from p_expected_object_version
     or (object_row.owner is distinct from authorization_row.target_user_id
       and object_row.owner_id is distinct from
         authorization_row.target_user_id::text) then
    raise exception using errcode = 'P4N03',
      message = 'L’objet Storage a changé depuis le plan administratif.';
  end if;
  signature := jsonb_build_array(jsonb_build_object(
    'ordinal', 1, 'bucket_id', p_bucket_id, 'object_path', p_object_path,
    'target_role', 'primary', 'forward_action', 'delete',
    'compensation_action', 'insert', 'expected_exists', true,
    'expected_object_id', p_expected_object_id,
    'expected_object_version', p_expected_object_version,
    'expected_sha256', p_expected_sha256,
    'expected_byte_size', p_expected_byte_size,
    'mime_type', p_mime_type,
    'administrative_authorization_id', authorization_row.id
  ));
  select * into existing_operation
  from public.document_operations operation
  where operation.initiator_subject_id = authorization_row.target_user_id
    and operation.client_request_id = p_client_request_id;
  if found then
    select * into neutralization_row
    from public.account_storage_neutralizations neutralization
    where neutralization.operation_id = existing_operation.id;
    if existing_operation.initiated_by is distinct from caller_id
       or existing_operation.initiator_kind <> 'platform_admin'
       or existing_operation.workflow <> 'account_storage_neutralization'
       or existing_operation.protected_person_id is distinct from
          resolution.protected_person_id
       or existing_operation.business_entity_type is distinct from
          resolution.business_entity_type
       or existing_operation.business_entity_id is distinct from
          resolution.business_entity_id
       or existing_operation.target_signature is distinct from signature
       or neutralization_row.administrative_authorization_id is distinct from
          authorization_row.id then
      raise exception using errcode = 'P4O04',
        message = 'La clé d’idempotence est déjà utilisée pour une autre demande.';
    end if;
    return jsonb_build_object(
      'operationId', existing_operation.id,
      'targetId', neutralization_row.target_id,
      'state', existing_operation.state,
      'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  insert into public.document_operations (
    protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
    workflow, business_entity_type, business_entity_id, client_request_id,
    target_signature
  ) values (
    resolution.protected_person_id, caller_id,
    authorization_row.target_user_id, 'platform_admin',
    'account_storage_neutralization', resolution.business_entity_type,
    resolution.business_entity_id, p_client_request_id, signature
  ) returning id into operation_id_value;
  insert into public.document_operation_targets (
    operation_id, ordinal, bucket_id, object_path, target_role,
    forward_action, compensation_action, expected_exists,
    expected_object_id, expected_object_version, expected_snapshot_captured_at
  ) values (
    operation_id_value, 1, p_bucket_id, p_object_path, 'primary',
    'delete', 'insert', true, p_expected_object_id,
    p_expected_object_version, clock_timestamp()
  ) returning id into target_id_value;
  begin
    insert into public.document_object_locks (
      bucket_id, object_path, target_id, operation_id
    ) values (
      p_bucket_id, p_object_path, target_id_value, operation_id_value
    );
  exception when unique_violation then
    raise exception using errcode = 'P4O05',
      message = 'Ce fichier est déjà réservé par une autre opération.';
  end;
  insert into public.account_storage_neutralizations (
    operation_id, target_id, authorization_id,
    administrative_authorization_id, account_user_id,
    expected_sha256, expected_byte_size, mime_type
  ) values (
    operation_id_value, target_id_value, null, authorization_row.id,
    authorization_row.target_user_id, p_expected_sha256,
    p_expected_byte_size, p_mime_type
  );
  perform public.append_account_storage_neutralization_event(
    operation_id_value, target_id_value, 'reserved', 'success', null,
    p_expected_object_id, p_expected_object_version,
    p_expected_byte_size, p_expected_sha256
  );
  perform public.append_administrative_account_deletion_event(
    authorization_row.id, 'neutralization_reserved', 'success',
    operation_id_value
  );
  return jsonb_build_object(
    'operationId', operation_id_value, 'targetId', target_id_value,
    'state', 'reserved', 'phase', 'reserved', 'revision', 0
  );
end;
$$;

-- Les événements de neutralisation reflètent désormais le véritable acteur :
-- compte supprimant son propre accès ou administrateur de plateforme.
create or replace function public.append_account_storage_neutralization_event(
  p_operation_id uuid,
  p_target_id uuid,
  p_event_type text,
  p_outcome text default 'success',
  p_safe_code text default null,
  p_observed_object_id uuid default null,
  p_observed_object_version text default null,
  p_observed_size bigint default null,
  p_observed_sha256 text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  operation_row public.document_operations%rowtype;
begin
  update public.document_operations operation
  set row_revision = operation.row_revision + 1,
      last_activity_at = clock_timestamp()
  where operation.id = p_operation_id
    and operation.workflow = 'account_storage_neutralization'
    and operation.initiator_kind in ('account_deletion', 'platform_admin')
  returning operation.* into operation_row;
  if not found then
    raise exception using errcode = 'P4N02',
      message = 'Neutralisation documentaire introuvable.';
  end if;
  insert into public.document_operation_events (
    operation_id, sequence_number, target_id, event_type, outcome,
    actor_id, actor_kind, safe_code, observed_object_id,
    observed_object_version, observed_size, observed_sha256
  ) values (
    operation_row.id, operation_row.row_revision, p_target_id, p_event_type,
    p_outcome, operation_row.initiated_by, operation_row.initiator_kind,
    p_safe_code, p_observed_object_id, p_observed_object_version,
    p_observed_size, p_observed_sha256
  );
  return operation_row.row_revision;
end;
$$;

create or replace function public.is_current_account_deletion_document_write_frozen()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.account_deletion_document_authorizations authz
    where authz.account_user_id = auth.uid()
      and (
        authz.state = 'sealed'
        or (authz.state = 'active'
          and authz.expires_at > statement_timestamp())
        or exists (
          select 1 from public.account_storage_neutralizations neutralization
          where neutralization.authorization_id = authz.id
            and neutralization.phase <> 'finalized'
        )
      )
  ) or exists (
    select 1
    from public.administrative_account_deletion_authorizations authz
    where authz.target_user_id = auth.uid()
      and (
        authz.state = 'sealed'
        or (authz.state = 'active'
          and authz.expires_at > statement_timestamp())
        or exists (
          select 1 from public.account_storage_neutralizations neutralization
          where neutralization.administrative_authorization_id = authz.id
            and neutralization.phase <> 'finalized'
        )
      )
  );
$$;

-- Une neutralisation administrative reste pilotable par le service durable et
-- consultable par l'administrateur initiateur, jamais par la cible sur la seule
-- base de son identité. Le parcours personnel historique reste inchangé.
create or replace function public.get_account_storage_neutralization_progress(
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_state text;
  original_present boolean;
  backup_present boolean;
begin
  select * into operation_row from public.document_operations
  where id = p_operation_id;
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id;
  if operation_row.id is null or neutralization_row.operation_id is null
     or not (
       auth.role() = 'service_role'
       or (
         neutralization_row.administrative_authorization_id is null
         and caller_id is not null
         and caller_id = neutralization_row.account_user_id
         and public.is_application_user_active()
       )
       or exists (
         select 1
         from public.administrative_account_deletion_authorizations authz
         where authz.id = neutralization_row.administrative_authorization_id
           and authz.administrator_subject_id = caller_id
           and public.is_platform_admin()
       )
     ) then
    raise exception using errcode = 'P4N01',
      message = 'Accès à la neutralisation documentaire refusé.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select state into backup_state from public.document_operation_backups
  where operation_id = p_operation_id and target_id = neutralization_row.target_id;
  select exists (
    select 1 from storage.objects object
    where object.bucket_id = target_row.bucket_id
      and object.name = target_row.object_path
  ) into original_present;
  select exists (
    select 1
    from public.document_operation_backups backup
    join storage.objects object
      on object.bucket_id = 'document-operation-backups'
     and object.name = backup.recovery_object_path
     and object.id = backup.recovery_object_id
     and object.version = backup.recovery_object_version
    where backup.operation_id = p_operation_id
      and backup.target_id = neutralization_row.target_id
      and backup.state in ('verified', 'restored')
  ) into backup_present;
  return jsonb_build_object(
    'operationId', operation_row.id,
    'state', operation_row.state,
    'operationRevision', operation_row.row_revision,
    'targetId', target_row.id,
    'bucketId', target_row.bucket_id,
    'objectPath', target_row.object_path,
    'phase', neutralization_row.phase,
    'resumePhase', neutralization_row.attention_from_phase,
    'revision', neutralization_row.row_revision,
    'backupState', backup_state,
    'objectPresent', original_present,
    'verifiedBackupPresent', backup_present,
    'recoveryRequired', (
      neutralization_row.phase in ('backup_verified', 'original_deleted')
      and not original_present
    ),
    'uncertain', neutralization_row.phase = 'attention_required',
    'expectedObjectId', target_row.expected_object_id,
    'expectedObjectVersion', target_row.expected_object_version,
    'recreatedObjectId', neutralization_row.recreated_object_id,
    'recreatedObjectVersion', neutralization_row.recreated_object_version,
    'expectedSha256', neutralization_row.expected_sha256,
    'expectedByteSize', neutralization_row.expected_byte_size
  );
end;
$$;

create function public.assert_administrative_account_deletion_barrier(
  p_authorization_id uuid,
  p_expected_revision bigint,
  p_expected_plan_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
  blockers text[];
  owned_object_count bigint;
  non_terminal_count bigint;
  uncleared_backup_count bigint;
  unfinished_neutralization_count bigint;
  completed_plan_count bigint;
  authorized_neutralization_count bigint;
  foreign_neutralization_count bigint;
  target_auth_exists boolean;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Barrière administrative non autorisée.';
  end if;
  select * into authorization_row
  from public.administrative_account_deletion_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.administrator_subject_id <> caller_id then
    raise exception using errcode = 'P4D01',
      message = 'Barrière administrative non autorisée.';
  end if;
  if authorization_row.document_plan_hash is distinct from p_expected_plan_hash
     or public.administrative_account_deletion_plan_hash(
       authorization_row.document_plan
     ) is distinct from authorization_row.document_plan_hash then
    raise exception using errcode = 'P4D03',
      message = 'Le plan documentaire administratif a divergé.';
  end if;
  select exists (
    select 1 from auth.users account
    where account.id = authorization_row.target_user_id
  ) into target_auth_exists;
  if authorization_row.state = 'sealed' and not target_auth_exists then
    return jsonb_build_object(
      'ready', true, 'alreadySealed', true,
      'targetAuthExists', false,
      'authorizationId', authorization_row.id,
      'targetUserId', authorization_row.target_user_id,
      'attemptId', authorization_row.attempt_id,
      'planHash', authorization_row.document_plan_hash,
      'revision', authorization_row.row_revision,
      'checkedAt', authorization_row.last_barrier_checked_at
    );
  end if;
  if authorization_row.state not in ('active', 'sealed')
     or not target_auth_exists
     or (
       authorization_row.state = 'active'
       and (
         authorization_row.expires_at <= clock_timestamp()
         or authorization_row.row_revision <> p_expected_revision
       )
     ) then
    raise exception using errcode = 'P4D01',
      message = 'Autorisation administrative inactive ou expirée.';
  end if;
  blockers := public.administrative_account_deletion_business_blockers(
    caller_id, authorization_row.target_user_id
  );
  if cardinality(blockers) <> 0 then
    raise exception using errcode = 'P4D05',
      message = 'La suppression Auth reste bloquée par les règles du compte.';
  end if;
  select count(*) into owned_object_count
  from storage.objects object
  where object.bucket_id in (
    'transaction-proofs', 'bank-statements', 'management-reports'
  ) and (object.owner = authorization_row.target_user_id
    or object.owner_id = authorization_row.target_user_id::text);
  select count(*) into non_terminal_count
  from public.document_operations operation
  where operation.initiator_subject_id = authorization_row.target_user_id
    and operation.state not in (
      'completed', 'compensated', 'cancelled', 'administratively_resolved'
    );
  select count(*) into uncleared_backup_count
  from public.document_operation_backups backup
  where backup.initiator_subject_id = authorization_row.target_user_id
    and backup.state <> 'deleted';
  select count(*) into unfinished_neutralization_count
  from public.account_storage_neutralizations neutralization
  where neutralization.account_user_id = authorization_row.target_user_id
    and neutralization.phase <> 'finalized';
  select count(*) into completed_plan_count
  from public.account_storage_neutralizations neutralization
  join public.document_operations operation
    on operation.id = neutralization.operation_id
  join public.document_operation_targets target
    on target.id = neutralization.target_id
  where neutralization.administrative_authorization_id = authorization_row.id
    and neutralization.phase = 'finalized'
    and operation.state = 'completed'
    and exists (
      select 1 from jsonb_array_elements(authorization_row.document_plan) item
      where item->>'bucketId' = target.bucket_id
        and item->>'objectPath' = target.object_path
        and (item->>'objectId')::uuid = target.expected_object_id
        and item->>'objectVersion' = target.expected_object_version
        and item->>'sha256' = neutralization.expected_sha256
        and (item->>'byteSize')::bigint = neutralization.expected_byte_size
    );
  select count(*) into authorized_neutralization_count
  from public.account_storage_neutralizations neutralization
  where neutralization.administrative_authorization_id = authorization_row.id;
  select count(*) into foreign_neutralization_count
  from public.account_storage_neutralizations neutralization
  join public.document_operations operation
    on operation.id = neutralization.operation_id
  where neutralization.account_user_id = authorization_row.target_user_id
    and operation.created_at >= authorization_row.issued_at
    and neutralization.administrative_authorization_id
        is distinct from authorization_row.id;
  if owned_object_count <> 0
     or non_terminal_count <> 0
     or uncleared_backup_count <> 0
     or unfinished_neutralization_count <> 0
     or authorized_neutralization_count <> authorization_row.document_count
     or foreign_neutralization_count <> 0
     or completed_plan_count <> authorization_row.document_count then
    raise exception using errcode = 'P4D05',
      message = 'La suppression Auth reste bloquée par l’état documentaire.';
  end if;
  if authorization_row.state = 'sealed' then
    update public.administrative_account_deletion_authorizations
    set last_barrier_checked_at = clock_timestamp()
    where id = authorization_row.id returning * into authorization_row;
    return jsonb_build_object(
      'ready', true, 'alreadySealed', true,
      'targetAuthExists', true,
      'authorizationId', authorization_row.id,
      'targetUserId', authorization_row.target_user_id,
      'attemptId', authorization_row.attempt_id,
      'planHash', authorization_row.document_plan_hash,
      'revision', authorization_row.row_revision,
      'checkedAt', authorization_row.last_barrier_checked_at
    );
  end if;
  update public.administrative_account_deletion_authorizations
  set state = 'sealed', state_changed_at = clock_timestamp(),
      last_barrier_checked_at = clock_timestamp(),
      row_revision = row_revision + 1
  where id = authorization_row.id returning * into authorization_row;
  perform public.append_administrative_account_deletion_event(
    authorization_row.id, 'barrier_sealed'
  );
  return jsonb_build_object(
    'ready', true, 'alreadySealed', false,
    'authorizationId', authorization_row.id,
    'targetUserId', authorization_row.target_user_id,
    'attemptId', authorization_row.attempt_id,
    'planHash', authorization_row.document_plan_hash,
    'revision', authorization_row.row_revision,
    'checkedAt', authorization_row.last_barrier_checked_at
  );
end;
$$;

-- La finalisation générique accepte les deux origines spécialisées sans
-- relâcher les contraintes applicables aux autres workflows.
create or replace function public.validate_document_operation_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  actor_anonymization boolean;
begin
  if (new.id, new.protected_person_id, new.initiator_subject_id,
      new.initiator_kind, new.workflow, new.business_entity_type,
      new.business_entity_id, new.client_request_id, new.target_signature,
      new.created_at)
     is distinct from
     (old.id, old.protected_person_id, old.initiator_subject_id,
      old.initiator_kind, old.workflow, old.business_entity_type,
      old.business_entity_id, old.client_request_id, old.target_signature,
      old.created_at) then
    raise exception using errcode = '42501',
      message = 'L’identité de l’opération documentaire est immuable.';
  end if;
  if old.state in (
    'completed', 'compensated', 'cancelled', 'administratively_resolved'
  ) then
    actor_anonymization := (
      (new.initiated_by is not distinct from old.initiated_by
        or (old.initiated_by is not null and new.initiated_by is null))
      and (new.resolution_by is not distinct from old.resolution_by
        or (old.resolution_by is not null and new.resolution_by is null))
      and (new.initiated_by is distinct from old.initiated_by
        or new.resolution_by is distinct from old.resolution_by)
      and (new.state, new.started_at, new.last_activity_at, new.closed_at,
           new.safe_error_code, new.resolution_reason, new.resolution_at,
           new.row_revision)
          is not distinct from
          (old.state, old.started_at, old.last_activity_at, old.closed_at,
           old.safe_error_code, old.resolution_reason, old.resolution_at,
           old.row_revision)
    );
    if actor_anonymization then return new; end if;
    raise exception using errcode = '23514',
      message = 'Une opération documentaire terminale est immuable.';
  end if;
  if new.state <> old.state and not (
    (old.state = 'reserved'
      and new.state in ('executing','compensating','attention_required','cancelled'))
    or (old.state = 'executing'
      and new.state in ('completed','compensating','attention_required'))
    or (old.state = 'compensating'
      and new.state in ('compensated','attention_required'))
    or (old.state = 'attention_required'
      and new.state in ('compensating','administratively_resolved'))
  ) then
    raise exception using errcode = '23514',
      message = 'Transition documentaire invalide.';
  end if;
  if new.state = 'completed' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id and target.application_state <> 'applied'
  ) and not (
    new.workflow = 'account_storage_neutralization'
    and new.initiator_kind in ('account_deletion', 'platform_admin')
    and exists (
      select 1 from public.account_storage_neutralizations neutralization
      where neutralization.operation_id = new.id
        and neutralization.phase = 'finalized'
    )
  ) then
    raise exception using errcode = '23514',
      message = 'Toutes les cibles doivent être appliquées avant la finalisation.';
  end if;
  if new.state = 'compensated' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id
      and target.application_state not in ('pending','compensated')
  ) then
    raise exception using errcode = '23514',
      message = 'Toutes les cibles appliquées doivent être compensées.';
  end if;
  if new.state = 'cancelled' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id and target.application_state <> 'pending'
  ) then
    raise exception using errcode = '23514',
      message = 'Une opération déjà appliquée ne peut pas être annulée.';
  end if;
  return new;
end;
$$;

revoke all on function
  public.append_administrative_account_deletion_event(uuid,text,text,uuid,text),
  public.administrative_account_deletion_business_blockers(uuid,uuid),
  public.assert_administrative_account_deletion_eligibility(uuid),
  public.get_administrative_account_deletion_diagnostic(uuid),
  public.normalize_administrative_account_deletion_plan(uuid,jsonb),
  public.administrative_account_deletion_plan_hash(jsonb),
  public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb),
  public.cancel_administrative_account_deletion_authorization(uuid,bigint),
  public.begin_administrative_account_storage_neutralization(
    uuid,uuid,text,text,uuid,text,text,bigint,text
  ),
  public.assert_administrative_account_deletion_barrier(uuid,bigint,text)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_administrative_account_deletion_diagnostic(uuid),
  public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb),
  public.cancel_administrative_account_deletion_authorization(uuid,bigint),
  public.begin_administrative_account_storage_neutralization(
    uuid,uuid,text,text,uuid,text,text,bigint,text
  ),
  public.assert_administrative_account_deletion_barrier(uuid,bigint,text)
to authenticated;

comment on table public.administrative_account_deletion_authorizations is
  'Autorisation administrative courte, liée à un acteur, une cible, une tentative et un plan documentaire immuable.';
comment on table public.administrative_account_deletion_events is
  'Journal immuable des décisions de suppression administrative durable.';
comment on function public.get_administrative_account_deletion_diagnostic(uuid) is
  'Diagnostic en lecture seule réservé aux administrateurs ; aucun contenu ni jeton documentaire n’est retourné.';
comment on function public.begin_administrative_account_storage_neutralization(
  uuid,uuid,text,text,uuid,text,text,bigint,text
) is
  'Réserve une neutralisation prévue par un plan administratif sans usurper l’identité Auth de la cible.';
comment on function public.assert_administrative_account_deletion_barrier(
  uuid,bigint,text
) is
  'Scelle le plan après revérification SQL ; aucune atomicité distribuée avec Storage ou Auth n’est affirmée.';
comment on function public.is_current_account_deletion_document_write_frozen() is
  'Gèle les mutations documentaires de la cible pendant une suppression personnelle ou administrative, y compris lorsqu’une neutralisation reste inachevée.';
