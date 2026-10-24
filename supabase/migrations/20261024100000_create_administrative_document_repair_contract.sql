-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C4A
-- Fondations SQL de réparation documentaire administrative. Cette migration
-- n'installe aucun trigger Storage et n'effectue aucune mutation physique.

create table public.document_repair_authorizations (
  id uuid primary key default gen_random_uuid(),
  administrator_subject_id uuid not null,
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  attempt_id uuid not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  repair_plan jsonb not null check (jsonb_typeof(repair_plan) = 'array'),
  repair_plan_hash text not null check (repair_plan_hash ~ '^[0-9a-f]{64}$'),
  target_count smallint not null check (target_count between 1 and 16),
  observed_operation_revision bigint not null check (observed_operation_revision >= 0),
  state text not null default 'active' check (state in ('active', 'cancelled', 'sealed')),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  state_changed_at timestamptz not null default clock_timestamp(),
  sealed_at timestamptz,
  cancelled_at timestamptz,
  row_revision bigint not null default 0 check (row_revision >= 0),
  unique (administrator_subject_id, attempt_id),
  unique (id, operation_id),
  check (expires_at > issued_at and expires_at <= issued_at + interval '10 minutes'),
  check ((state = 'sealed') = (sealed_at is not null)),
  check ((state = 'cancelled') = (cancelled_at is not null)),
  check (state = 'active' or state_changed_at >= issued_at)
);

create unique index document_repair_one_active_authorization_idx
on public.document_repair_authorizations(operation_id)
where state = 'active';

create index document_repair_authorizations_operation_idx
on public.document_repair_authorizations(operation_id, issued_at desc);

create table public.document_repair_items (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null,
  operation_id uuid not null,
  target_id uuid not null,
  ordinal smallint not null check (ordinal between 1 and 16),
  action text not null check (action in (
    'resume_compensation', 'restore_original', 'complete_backup_cleanup',
    'confirm_already_conform', 'accept_residual_state'
  )),
  expected_operation_revision bigint not null check (expected_operation_revision >= 0),
  expected_target_revision bigint not null check (expected_target_revision >= 0),
  expected_application_state text not null check (expected_application_state in (
    'pending', 'applied', 'compensating', 'compensated'
  )),
  expected_object_exists boolean not null,
  expected_object_id uuid,
  expected_object_version text,
  backup_id uuid,
  expected_backup_revision bigint,
  expected_backup_state text,
  residual_reason text check (
    residual_reason is null or char_length(btrim(residual_reason)) between 1 and 2000
  ),
  progress_state text not null default 'authorized' check (progress_state in (
    'authorized', 'executing', 'verification_required', 'verified'
  )),
  result_kind text check (result_kind in (
    'compensation_completed', 'restoration_completed', 'backup_cleanup_completed',
    'already_conform', 'residual_accepted'
  )),
  backup_disposition text check (backup_disposition in (
    'none', 'deleted', 'restored', 'retained_for_review'
  )),
  observed_object_exists boolean,
  observed_object_id uuid,
  observed_object_version text,
  observed_byte_size bigint check (observed_byte_size is null or observed_byte_size >= 0),
  observed_sha256 text check (
    observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'
  ),
  observation_source text check (
    observation_source is null or observation_source in ('storage_bytes', 'storage_catalog')
  ),
  observation_recorded_at timestamptz,
  verified_at timestamptz,
  row_revision bigint not null default 0 check (row_revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  unique (authorization_id, ordinal),
  unique (authorization_id, target_id),
  unique (id, authorization_id),
  foreign key (authorization_id, operation_id)
    references public.document_repair_authorizations(id, operation_id) on delete restrict,
  foreign key (target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict,
  foreign key (backup_id)
    references public.document_operation_backups(id) on delete restrict,
  check ((expected_object_id is null) = (expected_object_version is null)),
  check (expected_object_exists or expected_object_id is null),
  check (expected_object_version is null or btrim(expected_object_version) <> ''),
  check ((backup_id is null) = (expected_backup_revision is null)),
  check ((backup_id is null) = (expected_backup_state is null)),
  check ((action = 'accept_residual_state') = (residual_reason is not null)),
  check ((observed_object_id is null) = (observed_object_version is null)),
  check (observed_object_exists is distinct from false or observed_object_id is null),
  check (observed_object_version is null or btrim(observed_object_version) <> ''),
  check ((observed_byte_size is null) = (observed_sha256 is null)),
  check ((progress_state = 'verified') = (verified_at is not null)),
  check (
    (progress_state <> 'verified' and result_kind is null and backup_disposition is null)
    or
    (progress_state = 'verified' and result_kind is not null
      and backup_disposition is not null and observation_recorded_at is not null
      and observation_source is not null)
  ),
  check (
    progress_state not in ('verification_required', 'verified')
    or (
      observed_object_exists is not null
      and (
        (observed_object_exists
          and observed_object_id is not null
          and observed_byte_size is not null
          and observed_sha256 is not null
          and observation_source = 'storage_bytes')
        or
        (not observed_object_exists
          and observed_object_id is null
          and observed_byte_size is null
          and observed_sha256 is null
          and observation_source = 'storage_catalog')
      )
    )
  )
);

create index document_repair_items_operation_idx
on public.document_repair_items(operation_id, progress_state);

create table public.document_repair_events (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references public.document_repair_authorizations(id) on delete restrict,
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  item_id uuid,
  sequence_number bigint not null check (sequence_number > 0),
  event_type text not null check (event_type in (
    'authorized', 'cancelled', 'execution_started', 'verification_required',
    'target_verified', 'sealed'
  )),
  outcome text not null check (outcome in ('success', 'failure', 'information')),
  actor_subject_id uuid not null,
  safe_code text check (safe_code is null or safe_code ~ '^[A-Z0-9_:-]{1,64}$'),
  result_kind text check (result_kind is null or result_kind in (
    'compensation_completed', 'restoration_completed', 'backup_cleanup_completed',
    'already_conform', 'residual_accepted'
  )),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (authorization_id, sequence_number),
  foreign key (item_id, authorization_id)
    references public.document_repair_items(id, authorization_id) on delete restrict
);

create unique index document_repair_one_verified_event_per_item_idx
on public.document_repair_events(authorization_id, item_id, event_type)
where item_id is not null and event_type = 'target_verified';

alter table public.document_repair_authorizations enable row level security;
alter table public.document_repair_items enable row level security;
alter table public.document_repair_events enable row level security;

revoke all on table public.document_repair_authorizations,
  public.document_repair_items, public.document_repair_events
from public, anon, authenticated, service_role;

create function public.protect_document_repair_authorization()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501',
      message = 'Une autorisation de réparation est immuable.';
  end if;
  if (new.id, new.administrator_subject_id, new.operation_id, new.attempt_id,
      new.reason, new.repair_plan, new.repair_plan_hash, new.target_count,
      new.observed_operation_revision, new.issued_at, new.expires_at)
     is distinct from
     (old.id, old.administrator_subject_id, old.operation_id, old.attempt_id,
      old.reason, old.repair_plan, old.repair_plan_hash, old.target_count,
      old.observed_operation_revision, old.issued_at, old.expires_at) then
    raise exception using errcode = '42501',
      message = 'Le contexte de réparation est immuable.';
  end if;
  if old.state <> 'active' or new.state not in ('active', 'cancelled', 'sealed') then
    raise exception using errcode = '23514',
      message = 'Transition d’autorisation de réparation invalide.';
  end if;
  if new.state = old.state and (
    new.state_changed_at, new.sealed_at, new.cancelled_at, new.row_revision
  ) is distinct from (
    old.state_changed_at, old.sealed_at, old.cancelled_at, old.row_revision
  ) then
    raise exception using errcode = '42501',
      message = 'La progression de l’autorisation est immuable.';
  end if;
  if new.state <> old.state and (
    new.row_revision <> old.row_revision + 1
    or new.state_changed_at < old.state_changed_at
  ) then
    raise exception using errcode = '23514',
      message = 'Révision d’autorisation de réparation invalide.';
  end if;
  return new;
end;
$$;

create trigger document_repair_authorizations_protected
before update or delete on public.document_repair_authorizations
for each row execute function public.protect_document_repair_authorization();

create function public.protect_document_repair_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501',
      message = 'Une décision de réparation est immuable.';
  end if;
  if (new.id, new.authorization_id, new.operation_id, new.target_id, new.ordinal,
      new.action, new.expected_operation_revision, new.expected_target_revision,
      new.expected_application_state, new.expected_object_exists,
      new.expected_object_id, new.expected_object_version, new.backup_id,
      new.expected_backup_revision, new.expected_backup_state,
      new.residual_reason, new.created_at)
     is distinct from
     (old.id, old.authorization_id, old.operation_id, old.target_id, old.ordinal,
      old.action, old.expected_operation_revision, old.expected_target_revision,
      old.expected_application_state, old.expected_object_exists,
      old.expected_object_id, old.expected_object_version, old.backup_id,
      old.expected_backup_revision, old.expected_backup_state,
      old.residual_reason, old.created_at) then
    raise exception using errcode = '42501',
      message = 'Le plan de réparation est immuable.';
  end if;
  if new.progress_state <> old.progress_state and not (
    (old.progress_state = 'authorized' and new.progress_state = 'executing')
    or (old.progress_state = 'executing' and new.progress_state = 'verification_required')
    or (old.progress_state = 'verification_required' and new.progress_state = 'verified')
  ) then
    raise exception using errcode = '23514',
      message = 'Progression de réparation invalide.';
  end if;
  if old.progress_state = 'verified' then
    raise exception using errcode = '23514',
      message = 'Une vérification de réparation est immuable.';
  end if;
  if new.progress_state = old.progress_state and (
    new.result_kind, new.backup_disposition, new.observed_object_exists,
    new.observed_object_id, new.observed_object_version,
    new.observed_byte_size, new.observed_sha256, new.observation_source,
    new.observation_recorded_at, new.verified_at, new.row_revision
  ) is distinct from (
    old.result_kind, old.backup_disposition, old.observed_object_exists,
    old.observed_object_id, old.observed_object_version,
    old.observed_byte_size, old.observed_sha256, old.observation_source,
    old.observation_recorded_at, old.verified_at, old.row_revision
  ) then
    raise exception using errcode = '42501',
      message = 'Une preuve exige une transition de progression.';
  end if;
  if new.progress_state <> old.progress_state
     and new.row_revision <> old.row_revision + 1 then
    raise exception using errcode = '23514',
      message = 'Révision de progression de réparation invalide.';
  end if;
  if new.progress_state = 'verification_required' and (
    new.observed_object_exists is null
    or (
      new.observed_object_exists
      and (
        new.observed_object_id is null
        or new.observed_byte_size is null
        or new.observed_sha256 is null
        or new.observation_source <> 'storage_bytes'
      )
    )
    or (
      not new.observed_object_exists
      and (
        new.observed_object_id is not null
        or new.observed_byte_size is not null
        or new.observed_sha256 is not null
        or new.observation_source <> 'storage_catalog'
      )
    )
    or new.observation_recorded_at is null
  ) then
    raise exception using errcode = 'P4R07',
      message = 'L’observation documentaire est absente ou incohérente.';
  end if;
  if old.observation_recorded_at is not null and (
    new.observed_object_exists, new.observed_object_id,
    new.observed_object_version, new.observed_byte_size,
    new.observed_sha256, new.observation_source,
    new.observation_recorded_at
  ) is distinct from (
    old.observed_object_exists, old.observed_object_id,
    old.observed_object_version, old.observed_byte_size,
    old.observed_sha256, old.observation_source,
    old.observation_recorded_at
  ) then
    raise exception using errcode = '42501',
      message = 'Une observation documentaire enregistrée est immuable.';
  end if;
  if new.progress_state = 'verified' and (
    (new.action = 'resume_compensation' and new.result_kind <> 'compensation_completed')
    or (new.action = 'restore_original' and new.result_kind <> 'restoration_completed')
    or (new.action = 'complete_backup_cleanup' and new.result_kind <> 'backup_cleanup_completed')
    or (new.action = 'confirm_already_conform' and new.result_kind <> 'already_conform')
    or (new.action = 'accept_residual_state' and new.result_kind <> 'residual_accepted')
  ) then
    raise exception using errcode = '23514',
      message = 'La preuve de réparation ne correspond pas à la décision.';
  end if;
  return new;
end;
$$;

create trigger document_repair_items_protected
before update or delete on public.document_repair_items
for each row execute function public.protect_document_repair_item();

create trigger document_repair_events_append_only
before update or delete on public.document_repair_events
for each row execute function public.protect_document_operation_audit_rows();

create function public.document_repair_plan_hash(p_repair_plan jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(convert_to(p_repair_plan::text, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

create function public.append_document_repair_event(
  p_authorization_id uuid,
  p_event_type text,
  p_outcome text default 'success',
  p_item_id uuid default null,
  p_safe_code text default null,
  p_result_kind text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  next_sequence bigint;
begin
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found then
    raise exception using errcode = 'P4R02',
      message = 'Autorisation de réparation introuvable.';
  end if;
  select coalesce(max(event.sequence_number), 0) + 1 into next_sequence
  from public.document_repair_events event
  where event.authorization_id = p_authorization_id;
  insert into public.document_repair_events (
    authorization_id, operation_id, item_id, sequence_number, event_type,
    outcome, actor_subject_id, safe_code, result_kind
  ) values (
    authorization_row.id, authorization_row.operation_id, p_item_id,
    next_sequence, p_event_type, p_outcome,
    authorization_row.administrator_subject_id, p_safe_code, p_result_kind
  );
  return next_sequence;
end;
$$;

create function public.get_administrative_document_repair_diagnostic(
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
  targets jsonb;
  events jsonb;
  conflicting_locks jsonb;
  conflicting_neutralizations jsonb;
  active_authorization jsonb;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Diagnostic de réparation non autorisé.';
  end if;
  select * into operation_row
  from public.document_operations where id = p_operation_id;
  if not found then
    raise exception using errcode = 'P4R02',
      message = 'Opération documentaire introuvable.';
  end if;

  select jsonb_agg(jsonb_build_object(
    'targetId', target.id,
    'ordinal', target.ordinal,
    'bucketId', target.bucket_id,
    'objectPath', target.object_path,
    'targetRole', target.target_role,
    'forwardAction', target.forward_action,
    'compensationAction', target.compensation_action,
    'applicationState', target.application_state,
    'targetRevision', target.target_revision,
    'expectedObjectId', target.expected_object_id,
    'expectedObjectVersion', target.expected_object_version,
    'appliedObjectId', target.applied_object_id,
    'appliedObjectVersion', target.applied_object_version,
    'compensatedObjectId', target.compensated_object_id,
    'compensatedObjectVersion', target.compensated_object_version,
    'catalogObservation', jsonb_build_object(
      'exists', object.id is not null,
      'objectId', object.id,
      'objectVersion', object.version,
      'physicalBytesVerified', false
    ),
    'backup', case when backup.id is null then null else jsonb_build_object(
      'backupId', backup.id,
      'state', backup.state,
      'revision', backup.row_revision,
      'byteSize', backup.byte_size,
      'mimeType', backup.mime_type,
      'sha256', backup.sha256,
      'catalogObjectPresent', backup_object.id is not null,
      'catalogObjectId', backup_object.id,
      'catalogObjectVersion', backup_object.version,
      'physicalBytesVerified', false
    ) end,
    'lockPresent', object_lock.operation_id = operation_row.id
  ) order by target.ordinal) into targets
  from public.document_operation_targets target
  left join storage.objects object
    on object.bucket_id = target.bucket_id and object.name = target.object_path
  left join public.document_operation_backups backup
    on backup.operation_id = target.operation_id and backup.target_id = target.id
  left join storage.objects backup_object
    on backup_object.bucket_id = 'document-operation-backups'
   and backup_object.name = backup.recovery_object_path
   and backup_object.id = backup.recovery_object_id
   and backup_object.version = backup.recovery_object_version
  left join public.document_object_locks object_lock
    on object_lock.target_id = target.id and object_lock.operation_id = target.operation_id
  where target.operation_id = operation_row.id;

  select jsonb_agg(jsonb_build_object(
    'sequence', event.sequence_number,
    'targetId', event.target_id,
    'eventType', event.event_type,
    'outcome', event.outcome,
    'safeCode', event.safe_code,
    'observedObjectId', event.observed_object_id,
    'observedObjectVersion', event.observed_object_version,
    'observedSize', event.observed_size,
    'observedSha256', event.observed_sha256,
    'occurredAt', event.occurred_at
  ) order by event.sequence_number) into events
  from public.document_operation_events event
  where event.operation_id = operation_row.id;

  select jsonb_agg(jsonb_build_object(
    'bucketId', object_lock.bucket_id,
    'objectPath', object_lock.object_path,
    'operationId', object_lock.operation_id
  )) into conflicting_locks
  from public.document_operation_targets target
  join public.document_object_locks object_lock
    on object_lock.bucket_id = target.bucket_id
   and object_lock.object_path = target.object_path
   and object_lock.operation_id <> target.operation_id
  where target.operation_id = operation_row.id;

  select jsonb_agg(jsonb_build_object(
    'operationId', neutralization.operation_id,
    'phase', neutralization.phase
  )) into conflicting_neutralizations
  from public.document_operation_targets target
  join public.document_operation_targets other_target
    on other_target.bucket_id = target.bucket_id
   and other_target.object_path = target.object_path
   and other_target.operation_id <> target.operation_id
  join public.account_storage_neutralizations neutralization
    on neutralization.target_id = other_target.id
  where target.operation_id = operation_row.id
    and neutralization.phase <> 'finalized';

  select jsonb_build_object(
    'ownedByCaller',
      repair_authorization.administrator_subject_id = caller_id,
    'state', repair_authorization.state,
    'expiresAt', repair_authorization.expires_at
  ) || case
    when repair_authorization.administrator_subject_id = caller_id then
      jsonb_build_object(
        'authorizationId', repair_authorization.id,
        'attemptId', repair_authorization.attempt_id,
        'revision', repair_authorization.row_revision
      )
    else '{}'::jsonb
  end into active_authorization
  from public.document_repair_authorizations repair_authorization
  where repair_authorization.operation_id = operation_row.id
    and repair_authorization.state = 'active';

  return jsonb_build_object(
    'operationId', operation_row.id,
    'protectedPersonId', operation_row.protected_person_id,
    'workflow', operation_row.workflow,
    'businessEntityType', operation_row.business_entity_type,
    'businessEntityId', operation_row.business_entity_id,
    'state', operation_row.state,
    'revision', operation_row.row_revision,
    'safeErrorCode', operation_row.safe_error_code,
    'repairable', operation_row.state = 'attention_required'
      and operation_row.workflow not in ('account_storage_neutralization', 'administrative_repair'),
    'targets', coalesce(targets, '[]'::jsonb),
    'events', coalesce(events, '[]'::jsonb),
    'conflictingLocks', coalesce(conflicting_locks, '[]'::jsonb),
    'conflictingNeutralizations', coalesce(conflicting_neutralizations, '[]'::jsonb),
    'activeAuthorization', active_authorization,
    'physicalBytesVerified', false
  );
end;
$$;

create function public.normalize_administrative_document_repair_plan(
  p_operation_id uuid,
  p_expected_operation_revision bigint,
  p_repair_plan jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
  object_row storage.objects%rowtype;
  plan_item jsonb;
  normalized_item jsonb;
  normalized jsonb := '[]'::jsonb;
  target_id_value uuid;
  backup_id_value uuid;
  action_value text;
  residual_reason_value text;
  expected_exists_value boolean;
  object_found boolean;
  backup_found boolean;
  target_count_value integer;
begin
  select * into operation_row from public.document_operations
  where id = p_operation_id for update;
  if not found or operation_row.state <> 'attention_required'
     or operation_row.workflow in ('account_storage_neutralization', 'administrative_repair') then
    raise exception using errcode = 'P4R03',
      message = 'Cette opération documentaire n’est pas réparable par ce contrat.';
  end if;
  if operation_row.row_revision is distinct from p_expected_operation_revision then
    raise exception using errcode = 'P4R04',
      message = 'La révision de l’opération documentaire a changé.';
  end if;
  if jsonb_typeof(p_repair_plan) <> 'array'
     or jsonb_array_length(p_repair_plan) not between 1 and 16 then
    raise exception using errcode = 'P4R02',
      message = 'Plan de réparation invalide.';
  end if;
  select count(*) into target_count_value
  from public.document_operation_targets where operation_id = p_operation_id;
  if target_count_value <> jsonb_array_length(p_repair_plan) then
    raise exception using errcode = 'P4R03',
      message = 'Le plan doit couvrir exactement toutes les cibles.';
  end if;

  for plan_item in select value from jsonb_array_elements(p_repair_plan) loop
    begin
      target_id_value := (plan_item->>'targetId')::uuid;
      backup_id_value := nullif(plan_item->>'backupId', '')::uuid;
      expected_exists_value := (plan_item->>'expectedObjectExists')::boolean;
    exception when invalid_text_representation then
      raise exception using errcode = 'P4R02',
        message = 'Plan de réparation invalide.';
    end;
    action_value := plan_item->>'action';
    residual_reason_value := nullif(btrim(plan_item->>'residualReason'), '');
    select * into target_row from public.document_operation_targets
    where id = target_id_value and operation_id = p_operation_id for key share;
    if not found
       or target_row.target_revision is distinct from (plan_item->>'expectedTargetRevision')::bigint
       or target_row.application_state is distinct from plan_item->>'expectedApplicationState' then
      raise exception using errcode = 'P4R04',
        message = 'La cible documentaire a changé.';
    end if;
    if exists (
      select 1 from public.document_object_locks object_lock
      where object_lock.bucket_id = target_row.bucket_id
        and object_lock.object_path = target_row.object_path
        and object_lock.operation_id <> p_operation_id
    ) or not exists (
      select 1 from public.document_object_locks object_lock
      where object_lock.target_id = target_row.id
        and object_lock.operation_id = p_operation_id
    ) then
      raise exception using errcode = 'P4R06',
        message = 'La cible documentaire n’est pas verrouillée exclusivement.';
    end if;
    if exists (
      select 1
      from public.document_operation_targets other_target
      join public.account_storage_neutralizations neutralization
        on neutralization.target_id = other_target.id
      where other_target.bucket_id = target_row.bucket_id
        and other_target.object_path = target_row.object_path
        and other_target.operation_id <> p_operation_id
        and neutralization.phase <> 'finalized'
    ) then
      raise exception using errcode = 'P4R06',
        message = 'Une neutralisation de compte est en conflit avec la réparation.';
    end if;
    select * into object_row from storage.objects object
    where object.bucket_id = target_row.bucket_id
      and object.name = target_row.object_path for key share;
    object_found := found;
    if expected_exists_value is distinct from object_found
       or (object_found and (
         object_row.id is distinct from nullif(plan_item->>'expectedObjectId', '')::uuid
         or object_row.version is distinct from plan_item->>'expectedObjectVersion'
       ))
       or (not object_found and (
         nullif(plan_item->>'expectedObjectId', '') is not null
         or nullif(plan_item->>'expectedObjectVersion', '') is not null
       )) then
      raise exception using errcode = 'P4R04',
        message = 'L’observation du catalogue Storage a changé.';
    end if;

    select * into backup_row from public.document_operation_backups backup
    where backup.operation_id = p_operation_id and backup.target_id = target_row.id;
    backup_found := found;
    if backup_found is distinct from (backup_id_value is not null)
       or (backup_found and (
         backup_row.id is distinct from backup_id_value
         or backup_row.row_revision is distinct from (plan_item->>'expectedBackupRevision')::bigint
         or backup_row.state is distinct from plan_item->>'expectedBackupState'
       )) then
      raise exception using errcode = 'P4R04',
        message = 'La sauvegarde documentaire a changé.';
    end if;

    if action_value = 'resume_compensation' and (
      target_row.application_state not in ('applied', 'compensating')
      or target_row.compensation_action is null
    ) then
      raise exception using errcode = 'P4R03',
        message = 'La compensation ne peut pas être reprise pour cette cible.';
    elsif action_value = 'restore_original' and (
      not backup_found or backup_row.state not in ('verified', 'restored')
    ) then
      raise exception using errcode = 'P4R03',
        message = 'Aucune sauvegarde vérifiée ne permet cette restauration.';
    elsif action_value = 'complete_backup_cleanup' and (
      not backup_found or backup_row.state not in ('verified', 'restored', 'deleted')
    ) then
      raise exception using errcode = 'P4R03',
        message = 'Le nettoyage de sauvegarde n’est pas applicable.';
    elsif action_value = 'accept_residual_state' and residual_reason_value is null then
      raise exception using errcode = 'P4R02',
        message = 'L’acceptation d’un état résiduel exige un motif spécifique.';
    elsif action_value not in (
      'resume_compensation', 'restore_original', 'complete_backup_cleanup',
      'confirm_already_conform', 'accept_residual_state'
    ) then
      raise exception using errcode = 'P4R02',
        message = 'Action de réparation invalide.';
    end if;

    normalized_item := jsonb_build_object(
      'ordinal', target_row.ordinal,
      'targetId', target_row.id,
      'action', action_value,
      'expectedOperationRevision', operation_row.row_revision,
      'expectedTargetRevision', target_row.target_revision,
      'expectedApplicationState', target_row.application_state,
      'expectedObjectExists', object_found,
      'expectedObjectId', case when object_found then object_row.id else null end,
      'expectedObjectVersion', case when object_found then object_row.version else null end,
      'backupId', case when backup_found then backup_row.id else null end,
      'expectedBackupRevision', case when backup_found then backup_row.row_revision else null end,
      'expectedBackupState', case when backup_found then backup_row.state else null end,
      'residualReason', residual_reason_value
    );
    normalized := normalized || jsonb_build_array(normalized_item);
  end loop;
  if (select count(distinct (item->>'targetId'))
      from jsonb_array_elements(normalized) item) <> target_count_value then
    raise exception using errcode = 'P4R03',
      message = 'Le plan doit couvrir chaque cible une seule fois.';
  end if;
  return (
    select jsonb_agg(item order by (item->>'ordinal')::integer)
    from jsonb_array_elements(normalized) item
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = 'P4R02',
      message = 'Plan de réparation invalide.';
end;
$$;

create function public.issue_administrative_document_repair_authorization(
  p_operation_id uuid,
  p_expected_operation_revision bigint,
  p_attempt_id uuid,
  p_reason text,
  p_repair_plan jsonb
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
  authorization_row public.document_repair_authorizations%rowtype;
  item jsonb;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Autorisation de réparation refusée.';
  end if;
  if p_attempt_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 1 and 2000 then
    raise exception using errcode = 'P4R02',
      message = 'Demande de réparation invalide.';
  end if;
  select * into authorization_row
  from public.document_repair_authorizations repair_authorization
  where repair_authorization.administrator_subject_id = caller_id
    and repair_authorization.attempt_id = p_attempt_id;
  if found and (
    authorization_row.operation_id is distinct from p_operation_id
    or authorization_row.reason is distinct from btrim(p_reason)
  ) then
    raise exception using errcode = 'P4R05',
      message = 'La tentative de réparation est déjà utilisée pour une autre décision.';
  end if;
  normalized_plan := public.normalize_administrative_document_repair_plan(
    p_operation_id, p_expected_operation_revision, p_repair_plan
  );
  plan_hash_value := public.document_repair_plan_hash(normalized_plan);
  if authorization_row.id is null then
    select * into authorization_row
    from public.document_repair_authorizations repair_authorization
    where repair_authorization.administrator_subject_id = caller_id
      and repair_authorization.attempt_id = p_attempt_id;
  end if;
  if authorization_row.id is not null then
    if authorization_row.operation_id is distinct from p_operation_id
       or authorization_row.reason is distinct from btrim(p_reason)
       or authorization_row.repair_plan is distinct from normalized_plan
       or authorization_row.repair_plan_hash is distinct from plan_hash_value then
      raise exception using errcode = 'P4R05',
        message = 'La tentative de réparation est déjà utilisée pour une autre décision.';
    end if;
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'operationId', authorization_row.operation_id,
      'attemptId', authorization_row.attempt_id,
      'planHash', authorization_row.repair_plan_hash,
      'state', authorization_row.state,
      'expiresAt', authorization_row.expires_at,
      'revision', authorization_row.row_revision
    );
  end if;
  if exists (
    select 1 from public.document_repair_authorizations repair_authorization
    where repair_authorization.operation_id = p_operation_id
      and repair_authorization.state = 'active'
  ) or exists (
    select 1
    from public.document_repair_items repair_item
    join public.document_repair_authorizations repair_authorization
      on repair_authorization.id = repair_item.authorization_id
    where repair_authorization.operation_id = p_operation_id
      and repair_item.progress_state in (
        'executing', 'verification_required', 'verified'
      )
  ) then
    raise exception using errcode = 'P4R06',
      message = 'Une réparation est déjà en cours pour cette opération.';
  end if;
  begin
    insert into public.document_repair_authorizations (
      administrator_subject_id, operation_id, attempt_id, reason,
      repair_plan, repair_plan_hash, target_count, observed_operation_revision,
      issued_at, expires_at
    ) values (
      caller_id, p_operation_id, p_attempt_id, btrim(p_reason),
      normalized_plan, plan_hash_value, jsonb_array_length(normalized_plan),
      p_expected_operation_revision, issued_at_value,
      issued_at_value + interval '10 minutes'
    ) on conflict (administrator_subject_id, attempt_id) do nothing
    returning * into authorization_row;
  exception when unique_violation then
    raise exception using errcode = 'P4R06',
      message = 'Une réparation est déjà en cours pour cette opération.';
  end;
  if authorization_row.id is null then
    select * into authorization_row
    from public.document_repair_authorizations repair_authorization
    where repair_authorization.administrator_subject_id = caller_id
      and repair_authorization.attempt_id = p_attempt_id;
    if authorization_row.operation_id is distinct from p_operation_id
       or authorization_row.reason is distinct from btrim(p_reason)
       or authorization_row.repair_plan is distinct from normalized_plan
       or authorization_row.repair_plan_hash is distinct from plan_hash_value then
      raise exception using errcode = 'P4R05',
        message = 'La tentative de réparation est déjà utilisée pour une autre décision.';
    end if;
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'operationId', authorization_row.operation_id,
      'attemptId', authorization_row.attempt_id,
      'planHash', authorization_row.repair_plan_hash,
      'state', authorization_row.state,
      'expiresAt', authorization_row.expires_at,
      'revision', authorization_row.row_revision
    );
  end if;
  for item in select value from jsonb_array_elements(normalized_plan) loop
    insert into public.document_repair_items (
      authorization_id, operation_id, target_id, ordinal, action,
      expected_operation_revision, expected_target_revision,
      expected_application_state, expected_object_exists,
      expected_object_id, expected_object_version, backup_id,
      expected_backup_revision, expected_backup_state, residual_reason
    ) values (
      authorization_row.id, p_operation_id, (item->>'targetId')::uuid,
      (item->>'ordinal')::smallint, item->>'action',
      (item->>'expectedOperationRevision')::bigint,
      (item->>'expectedTargetRevision')::bigint,
      item->>'expectedApplicationState',
      (item->>'expectedObjectExists')::boolean,
      nullif(item->>'expectedObjectId', '')::uuid,
      nullif(item->>'expectedObjectVersion', ''),
      nullif(item->>'backupId', '')::uuid,
      nullif(item->>'expectedBackupRevision', '')::bigint,
      nullif(item->>'expectedBackupState', ''),
      nullif(item->>'residualReason', '')
    );
  end loop;
  perform public.append_document_repair_event(authorization_row.id, 'authorized');
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'operationId', authorization_row.operation_id,
    'attemptId', authorization_row.attempt_id,
    'planHash', authorization_row.repair_plan_hash,
    'state', authorization_row.state,
    'expiresAt', authorization_row.expires_at,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.get_administrative_document_repair_authorization(
  p_operation_id uuid,
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.document_repair_authorizations%rowtype;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Consultation de réparation non autorisée.';
  end if;
  select * into authorization_row
  from public.document_repair_authorizations repair_authorization
  where repair_authorization.administrator_subject_id = caller_id
    and repair_authorization.operation_id = p_operation_id
    and repair_authorization.attempt_id = p_attempt_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'operationId', authorization_row.operation_id,
    'attemptId', authorization_row.attempt_id,
    'reason', authorization_row.reason,
    'repairPlan', authorization_row.repair_plan,
    'planHash', authorization_row.repair_plan_hash,
    'state', authorization_row.state,
    'expiresAt', authorization_row.expires_at,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.cancel_administrative_document_repair_authorization(
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
  authorization_row public.document_repair_authorizations%rowtype;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Annulation de réparation non autorisée.';
  end if;
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found or authorization_row.administrator_subject_id <> caller_id then
    raise exception using errcode = 'P4R01',
      message = 'Annulation de réparation non autorisée.';
  end if;
  if authorization_row.state = 'sealed' then
    raise exception using errcode = 'P4R05',
      message = 'Une réparation scellée ne peut pas être annulée.';
  end if;
  if authorization_row.state = 'active' then
    if exists (
      select 1 from public.document_repair_items item
      where item.authorization_id = authorization_row.id
        and item.progress_state <> 'authorized'
    ) then
      raise exception using errcode = 'P4R07',
        message = 'Une réparation commencée doit être reprise ou vérifiée.';
    end if;
    if authorization_row.row_revision <> p_expected_revision then
      raise exception using errcode = 'P4R04',
        message = 'La révision de l’autorisation de réparation a changé.';
    end if;
    update public.document_repair_authorizations
    set state = 'cancelled', cancelled_at = clock_timestamp(),
        state_changed_at = clock_timestamp(), row_revision = row_revision + 1
    where id = authorization_row.id returning * into authorization_row;
    perform public.append_document_repair_event(authorization_row.id, 'cancelled');
  end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.assert_administrative_document_repair_sql_evidence(
  p_authorization_id uuid,
  p_require_operation_lock boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
begin
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id;
  if not found then
    raise exception using errcode = 'P4R02',
      message = 'Autorisation de réparation introuvable.';
  end if;

  if exists (
    select 1
    from public.document_repair_items item
    join public.document_operation_targets target
      on target.id = item.target_id
     and target.operation_id = item.operation_id
    left join storage.objects object
      on object.bucket_id = target.bucket_id
     and object.name = target.object_path
    left join public.document_object_locks object_lock
      on object_lock.target_id = target.id
     and object_lock.operation_id = target.operation_id
    left join public.document_operation_backups backup
      on backup.id = item.backup_id
     and backup.operation_id = item.operation_id
     and backup.target_id = item.target_id
    where item.authorization_id = authorization_row.id
      and (
        item.progress_state <> 'verified'
        or item.expected_operation_revision
          <> authorization_row.observed_operation_revision
        or target.target_revision <> item.expected_target_revision
        or target.application_state <> item.expected_application_state
        or (p_require_operation_lock and object_lock.operation_id is null)
        or (object.id is not null) is distinct from item.observed_object_exists
        or (
          item.observed_object_exists
          and (
            object.id is distinct from item.observed_object_id
            or object.version is distinct from item.observed_object_version
            or case
              when coalesce(object.metadata->>'size', '') ~ '^[0-9]+$'
                then (object.metadata->>'size')::bigint
                  is distinct from item.observed_byte_size
              else true
            end
          )
        )
        or not exists (
          select 1 from public.document_repair_events event
          where event.authorization_id = authorization_row.id
            and event.item_id = item.id
            and event.event_type = 'target_verified'
            and event.outcome = 'success'
            and event.result_kind = item.result_kind
        )
        or (item.backup_id is null and item.backup_disposition <> 'none')
        or (
          item.backup_id is not null
          and (
            backup.id is null
            or case item.backup_disposition
              when 'deleted' then backup.state <> 'deleted'
              when 'restored' then backup.state <> 'restored'
              when 'retained_for_review' then
                backup.state not in ('verified', 'restored', 'attention_required')
              else true
            end
          )
        )
      )
  ) then
    raise exception using errcode = 'P4R07',
      message = 'Les preuves SQL de la réparation sont absentes ou divergentes.';
  end if;

  if exists (
    select 1
    from public.document_operation_targets target
    join public.document_operation_targets other_target
      on other_target.bucket_id = target.bucket_id
     and other_target.object_path = target.object_path
     and other_target.operation_id <> target.operation_id
    join public.account_storage_neutralizations neutralization
      on neutralization.target_id = other_target.id
    where target.operation_id = authorization_row.operation_id
      and neutralization.phase <> 'finalized'
  ) then
    raise exception using errcode = 'P4R06',
      message = 'Une neutralisation de compte est en conflit avec la réparation.';
  end if;
end;
$$;

create function public.seal_administrative_document_repair(
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
  authorization_row public.document_repair_authorizations%rowtype;
  operation_row public.document_operations%rowtype;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Clôture de réparation non autorisée.';
  end if;
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found or authorization_row.administrator_subject_id <> caller_id then
    raise exception using errcode = 'P4R01',
      message = 'Clôture de réparation non autorisée.';
  end if;
  select * into operation_row from public.document_operations
  where id = authorization_row.operation_id for update;
  if authorization_row.state = 'sealed' then
    if authorization_row.repair_plan_hash is distinct from p_expected_plan_hash then
      raise exception using errcode = 'P4R05',
        message = 'Le plan de réparation a divergé.';
    end if;
    if operation_row.state <> 'administratively_resolved'
       or operation_row.safe_error_code not in (
         'ADMIN_REPAIR_VERIFIED', 'ADMIN_REPAIR_RESIDUAL_ACCEPTED'
       ) then
      raise exception using errcode = 'P4R04',
        message = 'L’opération documentaire scellée a divergé.';
    end if;
    perform public.assert_administrative_document_repair_sql_evidence(
      authorization_row.id, false
    );
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'operationId', authorization_row.operation_id,
      'state', authorization_row.state,
      'revision', authorization_row.row_revision
    );
  end if;
  if authorization_row.state <> 'active'
     or authorization_row.expires_at <= clock_timestamp()
     or authorization_row.row_revision <> p_expected_revision then
    raise exception using errcode = 'P4R05',
      message = 'Autorisation de réparation inactive ou expirée.';
  end if;
  if authorization_row.repair_plan_hash is distinct from p_expected_plan_hash
     or public.document_repair_plan_hash(authorization_row.repair_plan)
        is distinct from authorization_row.repair_plan_hash then
    raise exception using errcode = 'P4R05',
      message = 'Le plan de réparation a divergé.';
  end if;
  if operation_row.state <> 'attention_required'
     or operation_row.row_revision <> authorization_row.observed_operation_revision then
    raise exception using errcode = 'P4R04',
      message = 'L’opération documentaire a changé pendant la réparation.';
  end if;
  if exists (
    select 1 from public.document_repair_items item
    where item.authorization_id = authorization_row.id
      and item.progress_state <> 'verified'
  ) or (
    select count(*) from public.document_repair_items item
    where item.authorization_id = authorization_row.id
  ) <> authorization_row.target_count then
    raise exception using errcode = 'P4R07',
      message = 'La réparation ne dispose pas de toutes les preuves requises.';
  end if;
  perform public.assert_administrative_document_repair_sql_evidence(
    authorization_row.id, true
  );
  if exists (
    select 1
    from public.document_operation_backups backup
    where backup.operation_id = authorization_row.operation_id
      and backup.state <> 'deleted'
      and not exists (
        select 1 from public.document_repair_items item
        where item.authorization_id = authorization_row.id
          and item.target_id = backup.target_id
          and item.progress_state = 'verified'
          and (
            (item.backup_disposition = 'restored' and backup.state = 'restored')
            or (item.backup_disposition = 'retained_for_review'
              and item.result_kind = 'residual_accepted')
          )
      )
  ) then
    raise exception using errcode = 'P4R07',
      message = 'Une sauvegarde nécessaire reste sans décision vérifiée.';
  end if;
  perform public.transition_document_operation(
    authorization_row.operation_id, 'attention_required',
    'administratively_resolved',
    case when exists (
      select 1 from public.document_repair_items item
      where item.authorization_id = authorization_row.id
        and item.result_kind = 'residual_accepted'
    ) then 'ADMIN_REPAIR_RESIDUAL_ACCEPTED' else 'ADMIN_REPAIR_VERIFIED' end,
    authorization_row.reason
  );
  update public.document_repair_authorizations
  set state = 'sealed', sealed_at = clock_timestamp(),
      state_changed_at = clock_timestamp(), row_revision = row_revision + 1
  where id = authorization_row.id returning * into authorization_row;
  perform public.append_document_repair_event(authorization_row.id, 'sealed');
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'operationId', authorization_row.operation_id,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision
  );
end;
$$;

-- Une réparation active ou interrompue garde la priorité sur la reprise
-- ordinaire. Le futur moteur administratif utilisera des RPC spécialisées.
create or replace function public.assert_document_operation_caller(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_allowed_states text[],
  p_require_manage boolean default true
)
returns public.document_operations
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode = 'P4O01',
      message = 'Accès à l’opération documentaire refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id = p_operation_id;
  if not found or operation_row.initiator_kind <> 'user'
     or operation_row.initiator_subject_id <> caller_id then
    raise exception using errcode = 'P4O01',
      message = 'Accès à l’opération documentaire refusé.';
  end if;
  if p_require_manage then
    perform public.assert_document_operation_opening_access(
      operation_row.protected_person_id
    );
  end if;
  select * into operation_row from public.document_operations
  where id = p_operation_id for update;
  if exists (
    select 1 from public.document_repair_authorizations repair_authorization
    where repair_authorization.operation_id = operation_row.id
      and repair_authorization.state = 'active'
  ) or exists (
    select 1
    from public.document_repair_items item
    join public.document_repair_authorizations repair_authorization
      on repair_authorization.id = item.authorization_id
    where repair_authorization.operation_id = operation_row.id
      and item.progress_state in (
        'executing', 'verification_required', 'verified'
      )
  ) then
    raise exception using errcode = 'P4R06',
      message = 'Une réparation administrative bloque la reprise ordinaire.';
  end if;
  if operation_row.row_revision is distinct from p_expected_revision then
    raise exception using errcode = 'P4O06',
      message = 'La révision de l’opération documentaire a changé.';
  end if;
  if not operation_row.state = any(p_allowed_states) then
    raise exception using errcode = 'P4O06',
      message = 'L’état de l’opération documentaire a changé.';
  end if;
  return operation_row;
end;
$$;

revoke all on function public.protect_document_repair_authorization(),
  public.protect_document_repair_item(),
  public.document_repair_plan_hash(jsonb),
  public.append_document_repair_event(uuid,text,text,uuid,text,text),
  public.normalize_administrative_document_repair_plan(uuid,bigint,jsonb),
  public.assert_administrative_document_repair_sql_evidence(uuid,boolean)
from public, anon, authenticated, service_role;

revoke all on function
  public.get_administrative_document_repair_diagnostic(uuid),
  public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb),
  public.get_administrative_document_repair_authorization(uuid,uuid),
  public.cancel_administrative_document_repair_authorization(uuid,bigint),
  public.seal_administrative_document_repair(uuid,bigint,text)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_administrative_document_repair_diagnostic(uuid),
  public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb),
  public.get_administrative_document_repair_authorization(uuid,uuid),
  public.cancel_administrative_document_repair_authorization(uuid,bigint),
  public.seal_administrative_document_repair(uuid,bigint,text)
to authenticated;

comment on table public.document_repair_authorizations is
  'Décision administrative courte, liée à une seule opération et à un plan immuable.';
comment on table public.document_repair_items is
  'Progression durable future par cible ; aucune ligne ne constitue seule une preuve des octets Storage.';
comment on table public.document_repair_events is
  'Journal append-only des décisions de réparation, sans contenu documentaire.';
comment on function public.get_administrative_document_repair_diagnostic(uuid) is
  'Diagnostic de catalogue réservé aux administrateurs ; physicalBytesVerified reste toujours faux.';
comment on function public.seal_administrative_document_repair(uuid,bigint,text) is
  'Clôture impossible avant vérification explicite de chaque cible et traitement documenté des sauvegardes.';
