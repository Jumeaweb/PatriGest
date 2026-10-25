-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C4B1
-- Progression et reprise SQL des réparations documentaires administratives.
-- Cette migration ne modifie aucun octet Storage et n'installe aucun trigger Storage.

alter table public.document_repair_authorizations
  add column recovery_expires_at timestamptz,
  add column renewal_count smallint not null default 0
    check (renewal_count between 0 and 6),
  add column last_renewal_id uuid,
  add column last_renewed_at timestamptz,
  add constraint document_repair_authorizations_recovery_window_check check (
    (recovery_expires_at is null and renewal_count = 0
      and last_renewal_id is null and last_renewed_at is null)
    or
    (recovery_expires_at is not null and renewal_count > 0
      and last_renewal_id is not null and last_renewed_at is not null
      and recovery_expires_at > last_renewed_at
      and recovery_expires_at <= last_renewed_at + interval '10 minutes')
  );

alter table public.document_repair_items
  add column execution_id uuid,
  add column execution_started_at timestamptz,
  add column last_observation_kind text check (
    last_observation_kind is null or last_observation_kind in (
      'physical_verified', 'catalog_absent', 'physical_read_impossible',
      'version_divergent', 'content_divergent', 'backup_missing',
      'original_missing', 'unqualifiable'
    )
  ),
  add column last_observation_id uuid,
  add column last_observation_at timestamptz,
  add constraint document_repair_items_execution_identity_check check (
    (progress_state = 'authorized' and execution_id is null
      and execution_started_at is null)
    or
    (progress_state <> 'authorized' and execution_id is not null
      and execution_started_at is not null)
  ),
  add constraint document_repair_items_last_observation_check check (
    (last_observation_kind is null and last_observation_id is null
      and last_observation_at is null)
    or
    (last_observation_kind is not null and last_observation_id is not null
      and last_observation_at is not null)
  );

create unique index document_repair_one_execution_per_item_idx
on public.document_repair_items(id, execution_id)
where execution_id is not null;

create table public.document_repair_observations (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null,
  operation_id uuid not null,
  item_id uuid not null,
  execution_id uuid not null,
  observation_kind text not null check (observation_kind in (
    'physical_verified', 'catalog_absent', 'physical_read_impossible',
    'version_divergent', 'content_divergent', 'backup_missing',
    'original_missing', 'unqualifiable'
  )),
  object_exists boolean,
  object_id uuid,
  object_version text,
  byte_size bigint check (byte_size is null or byte_size >= 0),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  physical_bytes_verified boolean not null default false,
  backup_present boolean,
  backup_id uuid,
  backup_revision bigint,
  backup_state text,
  backup_object_id uuid,
  backup_object_version text,
  observation_fingerprint text not null
    check (observation_fingerprint ~ '^[0-9a-f]{64}$'),
  recorded_at timestamptz not null default clock_timestamp(),
  unique (item_id, execution_id, observation_fingerprint),
  foreign key (authorization_id, operation_id)
    references public.document_repair_authorizations(id, operation_id)
    on delete restrict,
  foreign key (item_id, authorization_id)
    references public.document_repair_items(id, authorization_id)
    on delete restrict,
  check ((object_id is null) = (object_version is null)),
  check ((byte_size is null) = (sha256 is null)),
  check (object_version is null or btrim(object_version) <> ''),
  check ((backup_object_id is null) = (backup_object_version is null)),
  check (backup_object_version is null or btrim(backup_object_version) <> ''),
  check (backup_present is distinct from false or backup_object_id is null),
  check (
    not physical_bytes_verified
    or (object_exists and object_id is not null
      and byte_size is not null and sha256 is not null)
  )
);

create index document_repair_observations_item_idx
on public.document_repair_observations(item_id, recorded_at, id);

alter table public.document_repair_observations enable row level security;
revoke all on table public.document_repair_observations
from public, anon, authenticated, service_role;

create trigger document_repair_observations_append_only
before update or delete on public.document_repair_observations
for each row execute function public.protect_document_operation_audit_rows();

alter table public.document_repair_events
  drop constraint document_repair_events_event_type_check;
alter table public.document_repair_events
  add constraint document_repair_events_event_type_check check (event_type in (
    'authorized', 'cancelled', 'authorization_renewed', 'execution_started',
    'observation_recorded', 'observation_blocked', 'verification_required',
    'target_verified', 'sealed'
  ));

create or replace function public.protect_document_repair_authorization()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  renewal_changed boolean;
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

  renewal_changed := (
    new.recovery_expires_at, new.renewal_count, new.last_renewal_id,
    new.last_renewed_at
  ) is distinct from (
    old.recovery_expires_at, old.renewal_count, old.last_renewal_id,
    old.last_renewed_at
  );

  if new.state = old.state and renewal_changed then
    if old.state <> 'active'
       or new.row_revision <> old.row_revision + 1
       or new.renewal_count <> old.renewal_count + 1
       or new.last_renewal_id is null
       or new.last_renewal_id is not distinct from old.last_renewal_id
       or new.last_renewed_at < coalesce(old.last_renewed_at, old.issued_at)
       or new.recovery_expires_at <= new.last_renewed_at
       or new.recovery_expires_at > new.last_renewed_at + interval '10 minutes'
       or (new.state_changed_at, new.sealed_at, new.cancelled_at)
          is distinct from
          (old.state_changed_at, old.sealed_at, old.cancelled_at) then
      raise exception using errcode = '23514',
        message = 'Prolongation de réparation invalide.';
    end if;
    return new;
  end if;

  if renewal_changed then
    raise exception using errcode = '42501',
      message = 'La reprise de réparation est immuable hors prolongation contrôlée.';
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

create or replace function public.protect_document_repair_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  anomaly_changed boolean;
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
  if old.execution_id is not null and (
    new.execution_id, new.execution_started_at
  ) is distinct from (
    old.execution_id, old.execution_started_at
  ) then
    raise exception using errcode = '42501',
      message = 'L’identité d’exécution de la réparation est immuable.';
  end if;
  if old.progress_state in ('verification_required', 'verified') and (
    new.last_observation_kind, new.last_observation_id, new.last_observation_at
  ) is distinct from (
    old.last_observation_kind, old.last_observation_id, old.last_observation_at
  ) then
    raise exception using errcode = '42501',
      message = 'Le dernier constat probant de la réparation est immuable.';
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

  anomaly_changed := (
    new.last_observation_kind, new.last_observation_id, new.last_observation_at
  ) is distinct from (
    old.last_observation_kind, old.last_observation_id, old.last_observation_at
  );

  if new.progress_state = old.progress_state and anomaly_changed then
    if old.progress_state <> 'executing'
       or new.row_revision <> old.row_revision + 1
       or new.last_observation_kind in ('physical_verified', 'catalog_absent')
       or new.last_observation_id is null
       or new.last_observation_id is not distinct from old.last_observation_id
       or new.last_observation_at < coalesce(
         old.last_observation_at, old.execution_started_at
       )
       or (
         new.result_kind, new.backup_disposition,
         new.observed_object_exists, new.observed_object_id,
         new.observed_object_version, new.observed_byte_size,
         new.observed_sha256, new.observation_source,
         new.observation_recorded_at, new.verified_at
       ) is distinct from (
         old.result_kind, old.backup_disposition,
         old.observed_object_exists, old.observed_object_id,
         old.observed_object_version, old.observed_byte_size,
         old.observed_sha256, old.observation_source,
         old.observation_recorded_at, old.verified_at
       ) then
      raise exception using errcode = '23514',
        message = 'Observation bloquante de réparation invalide.';
    end if;
    return new;
  end if;

  if new.progress_state = old.progress_state and (
    new.result_kind, new.backup_disposition, new.observed_object_exists,
    new.observed_object_id, new.observed_object_version,
    new.observed_byte_size, new.observed_sha256, new.observation_source,
    new.observation_recorded_at, new.verified_at, new.row_revision,
    new.execution_id, new.execution_started_at,
    new.last_observation_kind, new.last_observation_id, new.last_observation_at
  ) is distinct from (
    old.result_kind, old.backup_disposition, old.observed_object_exists,
    old.observed_object_id, old.observed_object_version,
    old.observed_byte_size, old.observed_sha256, old.observation_source,
    old.observation_recorded_at, old.verified_at, old.row_revision,
    old.execution_id, old.execution_started_at,
    old.last_observation_kind, old.last_observation_id, old.last_observation_at
  ) then
    raise exception using errcode = '42501',
      message = 'Une preuve exige une transition de progression.';
  end if;
  if new.progress_state <> old.progress_state
     and new.row_revision <> old.row_revision + 1 then
    raise exception using errcode = '23514',
      message = 'Révision de progression de réparation invalide.';
  end if;
  if new.progress_state = 'executing' and (
    new.execution_id is null or new.execution_started_at is null
    or new.result_kind is not null or new.backup_disposition is not null
    or new.observed_object_exists is not null
    or new.observation_recorded_at is not null
    or new.verified_at is not null
  ) then
    raise exception using errcode = 'P4R07',
      message = 'L’identité d’exécution de la réparation est absente.';
  end if;
  if new.progress_state = 'verification_required' and (
    new.observed_object_exists is null
    or new.last_observation_kind not in ('physical_verified', 'catalog_absent')
    or (
      new.observed_object_exists
      and (
        new.observed_object_id is null
        or new.observed_byte_size is null
        or new.observed_sha256 is null
        or new.observation_source <> 'storage_bytes'
        or new.last_observation_kind <> 'physical_verified'
      )
    )
    or (
      not new.observed_object_exists
      and (
        new.observed_object_id is not null
        or new.observed_byte_size is not null
        or new.observed_sha256 is not null
        or new.observation_source <> 'storage_catalog'
        or new.last_observation_kind <> 'catalog_absent'
      )
    )
    or new.observation_recorded_at is null
    or new.last_observation_id is null
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

create function public.assert_document_repair_service()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = 'P4R01',
      message = 'Progression technique de réparation non autorisée.';
  end if;
end;
$$;

create function public.document_repair_effective_expires_at(
  p_authorization public.document_repair_authorizations
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_authorization.recovery_expires_at, p_authorization.expires_at);
$$;

create function public.assert_document_repair_runtime_context(
  p_authorization_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_require_unexpired boolean default true
)
returns public.document_repair_authorizations
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  operation_row public.document_operations%rowtype;
begin
  perform public.assert_document_repair_service();
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.administrator_subject_id
        is distinct from p_administrator_subject_id
     or authorization_row.attempt_id is distinct from p_attempt_id then
    raise exception using errcode = 'P4R01',
      message = 'Contexte technique de réparation non autorisé.';
  end if;
  if authorization_row.repair_plan_hash is distinct from p_expected_plan_hash
     or public.document_repair_plan_hash(authorization_row.repair_plan)
        is distinct from authorization_row.repair_plan_hash then
    raise exception using errcode = 'P4R05',
      message = 'Le plan de réparation a divergé.';
  end if;
  if p_require_unexpired and authorization_row.state <> 'active' then
    raise exception using errcode = 'P4R05',
      message = 'Autorisation de réparation inactive ou scellée.';
  end if;
  if p_require_unexpired and public.document_repair_effective_expires_at(
    authorization_row
  ) <= clock_timestamp() then
    raise exception using errcode = 'P4R05',
      message = 'Autorisation de réparation expirée.';
  end if;
  if not exists (
    select 1 from public.platform_administrators administrator
    where administrator.user_id = authorization_row.administrator_subject_id
  ) then
    raise exception using errcode = 'P4R01',
      message = 'L’administrateur initiateur n’est plus autorisé.';
  end if;
  select * into operation_row from public.document_operations
  where id = authorization_row.operation_id for update;
  if not found or (p_require_unexpired and (
    operation_row.state <> 'attention_required'
    or operation_row.row_revision
       is distinct from authorization_row.observed_operation_revision
  )) then
    raise exception using errcode = 'P4R04',
      message = 'L’opération documentaire a changé pendant la réparation.';
  end if;
  return authorization_row;
end;
$$;

create function public.assert_document_repair_target_context(
  p_authorization_id uuid,
  p_item_id uuid,
  p_expected_action text
)
returns public.document_repair_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  item_row public.document_repair_items%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  object_found boolean;
begin
  select * into item_row from public.document_repair_items
  where id = p_item_id and authorization_id = p_authorization_id for update;
  if not found or item_row.action is distinct from p_expected_action then
    raise exception using errcode = 'P4R05',
      message = 'La cible ou l’action de réparation a divergé.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = item_row.target_id and operation_id = item_row.operation_id
  for update;
  if not found
     or target_row.target_revision is distinct from item_row.expected_target_revision
     or target_row.application_state
        is distinct from item_row.expected_application_state then
    raise exception using errcode = 'P4R04',
      message = 'La cible documentaire a changé.';
  end if;
  if not exists (
    select 1 from public.document_object_locks object_lock
    where object_lock.target_id = target_row.id
      and object_lock.operation_id = target_row.operation_id
      and object_lock.bucket_id = target_row.bucket_id
      and object_lock.object_path = target_row.object_path
  ) or exists (
    select 1 from public.document_object_locks object_lock
    where object_lock.bucket_id = target_row.bucket_id
      and object_lock.object_path = target_row.object_path
      and object_lock.operation_id <> target_row.operation_id
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
      and other_target.operation_id <> target_row.operation_id
      and neutralization.phase <> 'finalized'
  ) then
    raise exception using errcode = 'P4R06',
      message = 'Une neutralisation de compte est en conflit avec la réparation.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path for update;
  object_found := found;
  if item_row.progress_state = 'authorized' and (
    object_found is distinct from item_row.expected_object_exists
    or (object_found and (
      object_row.id is distinct from item_row.expected_object_id
      or object_row.version is distinct from item_row.expected_object_version
    ))
  ) then
    raise exception using errcode = 'P4R04',
      message = 'L’identité catalogue de la cible a changé avant exécution.';
  end if;
  return item_row;
end;
$$;

create function public.start_administrative_document_repair_item(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_expected_action text,
  p_execution_id uuid,
  p_expected_authorization_revision bigint,
  p_expected_item_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  item_row public.document_repair_items%rowtype;
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  item_row := public.assert_document_repair_target_context(
    authorization_row.id, p_item_id, p_expected_action
  );
  if p_execution_id is null then
    raise exception using errcode = 'P4R02',
      message = 'Identité d’exécution invalide.';
  end if;
  if item_row.progress_state <> 'authorized' then
    if item_row.execution_id is distinct from p_execution_id then
      raise exception using errcode = 'P4R05',
        message = 'Une autre exécution a déjà commencé cette cible.';
    end if;
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'itemId', item_row.id,
      'executionId', item_row.execution_id,
      'progressState', item_row.progress_state,
      'revision', item_row.row_revision,
      'idempotent', true
    );
  end if;
  if authorization_row.row_revision
       is distinct from p_expected_authorization_revision
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R04',
      message = 'La révision de la réparation a changé.';
  end if;
  update public.document_repair_items
  set progress_state = 'executing', execution_id = p_execution_id,
      execution_started_at = clock_timestamp(), row_revision = row_revision + 1
  where id = item_row.id returning * into item_row;
  perform public.append_document_repair_event(
    authorization_row.id, 'execution_started', 'success', item_row.id,
    'EXECUTION_STARTED'
  );
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'itemId', item_row.id,
    'executionId', item_row.execution_id,
    'progressState', item_row.progress_state,
    'revision', item_row.row_revision,
    'idempotent', false
  );
end;
$$;

create function public.document_repair_observation_fingerprint(
  p_observation jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(convert_to(p_observation::text, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

create function public.record_administrative_document_repair_observation(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_expected_action text,
  p_execution_id uuid,
  p_expected_item_revision bigint,
  p_observation_kind text,
  p_object_exists boolean,
  p_object_id uuid,
  p_object_version text,
  p_byte_size bigint,
  p_sha256 text,
  p_backup_present boolean,
  p_backup_id uuid,
  p_backup_revision bigint,
  p_backup_state text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  item_row public.document_repair_items%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
  object_row storage.objects%rowtype;
  object_found boolean;
  backup_found boolean;
  backup_object_found boolean;
  backup_object_id_value uuid;
  backup_object_version_value text;
  normalized_observation jsonb;
  fingerprint_value text;
  observation_row public.document_repair_observations%rowtype;
  is_conclusive boolean;
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  item_row := public.assert_document_repair_target_context(
    authorization_row.id, p_item_id, p_expected_action
  );
  if item_row.progress_state not in ('executing', 'verification_required')
     or item_row.execution_id is distinct from p_execution_id then
    raise exception using errcode = 'P4R05',
      message = 'L’exécution de réparation ne correspond pas à la cible.';
  end if;
  if p_observation_kind not in (
    'physical_verified', 'catalog_absent', 'physical_read_impossible',
    'version_divergent', 'content_divergent', 'backup_missing',
    'original_missing', 'unqualifiable'
  ) then
    raise exception using errcode = 'P4R02',
      message = 'Type d’observation de réparation invalide.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = item_row.target_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path for update;
  object_found := found;
  if p_object_exists is distinct from object_found
     or (object_found and (
       p_object_id is distinct from object_row.id
       or p_object_version is distinct from object_row.version
     ))
     or (not object_found and (
       p_object_id is not null or p_object_version is not null
     )) then
    raise exception using errcode = 'P4R04',
      message = 'L’observation ne correspond pas au catalogue Storage.';
  end if;

  select * into backup_row from public.document_operation_backups backup
  where backup.id = item_row.backup_id
    and backup.operation_id = item_row.operation_id
    and backup.target_id = item_row.target_id for update;
  backup_found := found;
  if backup_found then
    select object.id, object.version
    into backup_object_id_value, backup_object_version_value
    from storage.objects object
    where object.bucket_id = 'document-operation-backups'
      and object.name = backup_row.recovery_object_path
      and object.id = backup_row.recovery_object_id
      and object.version = backup_row.recovery_object_version
    for update;
    backup_object_found := found;
  else
    backup_object_found := false;
  end if;
  if p_backup_present is distinct from backup_object_found
     or p_backup_id is distinct from (
       case when backup_found then backup_row.id else null end
     )
     or p_backup_revision is distinct from (
       case when backup_found then backup_row.row_revision else null end
     )
     or p_backup_state is distinct from (
       case when backup_found then backup_row.state else null end
     ) then
    raise exception using errcode = 'P4R04',
      message = 'L’observation de sauvegarde a divergé.';
  end if;

  is_conclusive := p_observation_kind in ('physical_verified', 'catalog_absent');
  if p_observation_kind = 'physical_verified' and (
    not object_found or p_byte_size is null or p_byte_size < 0
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
    or not coalesce(object_row.metadata->>'size', '') ~ '^[0-9]+$'
    or (object_row.metadata->>'size')::bigint is distinct from p_byte_size
  ) then
    raise exception using errcode = 'P4R07',
      message = 'La preuve physique de l’objet est absente ou incohérente.';
  elsif p_observation_kind = 'catalog_absent' and (
    object_found or p_byte_size is not null or p_sha256 is not null
  ) then
    raise exception using errcode = 'P4R07',
      message = 'La preuve d’absence catalogue est incohérente.';
  elsif p_observation_kind = 'content_divergent' and (
    not object_found or p_byte_size is null
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
  ) then
    raise exception using errcode = 'P4R07',
      message = 'La divergence de contenu n’est pas qualifiée.';
  elsif not is_conclusive and p_observation_kind <> 'content_divergent'
        and (p_byte_size is not null or p_sha256 is not null) then
    raise exception using errcode = 'P4R07',
      message = 'Une anomalie non lue ne peut pas porter une preuve physique.';
  end if;

  normalized_observation := jsonb_build_object(
    'kind', p_observation_kind,
    'objectExists', p_object_exists,
    'objectId', p_object_id,
    'objectVersion', p_object_version,
    'byteSize', p_byte_size,
    'sha256', p_sha256,
    'backupPresent', p_backup_present,
    'backupId', p_backup_id,
    'backupRevision', p_backup_revision,
    'backupState', p_backup_state,
    'backupObjectId', backup_object_id_value,
    'backupObjectVersion', backup_object_version_value
  );
  fingerprint_value := public.document_repair_observation_fingerprint(
    normalized_observation
  );
  select * into observation_row
  from public.document_repair_observations observation
  where observation.item_id = item_row.id
    and observation.execution_id = p_execution_id
    and observation.observation_fingerprint = fingerprint_value;
  if found then
    return jsonb_build_object(
      'observationId', observation_row.id,
      'itemId', item_row.id,
      'progressState', item_row.progress_state,
      'revision', item_row.row_revision,
      'conclusive', is_conclusive,
      'idempotent', true
    );
  end if;
  if item_row.progress_state <> 'executing'
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R04',
      message = 'La révision de la cible de réparation a changé.';
  end if;
  insert into public.document_repair_observations (
    authorization_id, operation_id, item_id, execution_id,
    observation_kind, object_exists, object_id, object_version,
    byte_size, sha256, physical_bytes_verified, backup_present,
    backup_id, backup_revision, backup_state, backup_object_id,
    backup_object_version, observation_fingerprint
  ) values (
    authorization_row.id, authorization_row.operation_id, item_row.id,
    p_execution_id, p_observation_kind, p_object_exists, p_object_id,
    p_object_version, p_byte_size, p_sha256,
    p_observation_kind in ('physical_verified', 'content_divergent'),
    p_backup_present, p_backup_id, p_backup_revision, p_backup_state,
    backup_object_id_value, backup_object_version_value, fingerprint_value
  ) returning * into observation_row;

  if is_conclusive then
    update public.document_repair_items
    set progress_state = 'verification_required',
        observed_object_exists = p_object_exists,
        observed_object_id = p_object_id,
        observed_object_version = p_object_version,
        observed_byte_size = p_byte_size,
        observed_sha256 = p_sha256,
        observation_source = case when p_object_exists
          then 'storage_bytes' else 'storage_catalog' end,
        observation_recorded_at = observation_row.recorded_at,
        last_observation_kind = p_observation_kind,
        last_observation_id = observation_row.id,
        last_observation_at = observation_row.recorded_at,
        row_revision = row_revision + 1
    where id = item_row.id returning * into item_row;
    perform public.append_document_repair_event(
      authorization_row.id, 'observation_recorded', 'success', item_row.id,
      upper(p_observation_kind)
    );
    perform public.append_document_repair_event(
      authorization_row.id, 'verification_required', 'information', item_row.id,
      'VERIFICATION_REQUIRED'
    );
  else
    update public.document_repair_items
    set last_observation_kind = p_observation_kind,
        last_observation_id = observation_row.id,
        last_observation_at = observation_row.recorded_at,
        row_revision = row_revision + 1
    where id = item_row.id returning * into item_row;
    perform public.append_document_repair_event(
      authorization_row.id, 'observation_blocked', 'failure', item_row.id,
      upper(p_observation_kind)
    );
  end if;
  return jsonb_build_object(
    'observationId', observation_row.id,
    'itemId', item_row.id,
    'progressState', item_row.progress_state,
    'revision', item_row.row_revision,
    'conclusive', is_conclusive,
    'idempotent', false
  );
end;
$$;

create function public.verify_administrative_document_repair_item(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_expected_action text,
  p_execution_id uuid,
  p_expected_item_revision bigint,
  p_result_kind text,
  p_backup_disposition text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  item_row public.document_repair_items%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  backup_row public.document_operation_backups%rowtype;
  observation_row public.document_repair_observations%rowtype;
  backup_object_row storage.objects%rowtype;
  object_found boolean;
  backup_found boolean;
  backup_object_found boolean;
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  item_row := public.assert_document_repair_target_context(
    authorization_row.id, p_item_id, p_expected_action
  );
  if item_row.execution_id is distinct from p_execution_id then
    raise exception using errcode = 'P4R05',
      message = 'L’exécution de réparation a divergé.';
  end if;
  if item_row.progress_state = 'verified' then
    if item_row.result_kind is distinct from p_result_kind
       or item_row.backup_disposition is distinct from p_backup_disposition then
      raise exception using errcode = 'P4R05',
        message = 'La vérification répétée a divergé.';
    end if;
    return jsonb_build_object(
      'itemId', item_row.id, 'progressState', item_row.progress_state,
      'resultKind', item_row.result_kind, 'revision', item_row.row_revision,
      'idempotent', true
    );
  end if;
  if item_row.progress_state <> 'verification_required'
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R04',
      message = 'La cible n’est pas prête pour vérification.';
  end if;
  if p_result_kind is null or p_backup_disposition is null then
    raise exception using errcode = 'P4R02',
      message = 'Résultat de vérification invalide.';
  end if;
  if (item_row.action = 'resume_compensation'
        and p_result_kind <> 'compensation_completed')
     or (item_row.action = 'restore_original'
        and p_result_kind <> 'restoration_completed')
     or (item_row.action = 'complete_backup_cleanup'
        and p_result_kind <> 'backup_cleanup_completed')
     or (item_row.action = 'confirm_already_conform'
        and p_result_kind <> 'already_conform')
     or (item_row.action = 'accept_residual_state'
        and p_result_kind <> 'residual_accepted') then
    raise exception using errcode = 'P4R07',
      message = 'Le résultat ne correspond pas à l’action approuvée.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = item_row.target_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path for update;
  object_found := found;
  if object_found is distinct from item_row.observed_object_exists
     or (object_found and (
       object_row.id is distinct from item_row.observed_object_id
       or object_row.version is distinct from item_row.observed_object_version
       or not coalesce(object_row.metadata->>'size', '') ~ '^[0-9]+$'
       or (object_row.metadata->>'size')::bigint
          is distinct from item_row.observed_byte_size
     )) then
    raise exception using errcode = 'P4R04',
      message = 'Le catalogue Storage a changé après l’observation.';
  end if;

  select * into backup_row from public.document_operation_backups backup
  where backup.id = item_row.backup_id
    and backup.operation_id = item_row.operation_id
    and backup.target_id = item_row.target_id for update;
  backup_found := found;
  if backup_found then
    select * into backup_object_row from storage.objects object
    where object.bucket_id = 'document-operation-backups'
      and object.name = backup_row.recovery_object_path
      and object.id = backup_row.recovery_object_id
      and object.version = backup_row.recovery_object_version
    for update;
    backup_object_found := found;
  else
    backup_object_found := false;
  end if;
  select * into observation_row
  from public.document_repair_observations observation
  where observation.id = item_row.last_observation_id
    and observation.item_id = item_row.id
    and observation.execution_id = item_row.execution_id;
  if not found or observation_row.observation_kind not in (
    'physical_verified', 'catalog_absent'
  ) or observation_row.object_exists
       is distinct from item_row.observed_object_exists
     or observation_row.object_id is distinct from item_row.observed_object_id
     or observation_row.object_version
        is distinct from item_row.observed_object_version
     or observation_row.byte_size is distinct from item_row.observed_byte_size
     or observation_row.sha256 is distinct from item_row.observed_sha256 then
    raise exception using errcode = 'P4R07',
      message = 'L’observation probante de la cible est absente ou divergente.';
  end if;
  if item_row.backup_id is null then
    if p_backup_disposition <> 'none'
       or observation_row.backup_id is not null
       or observation_row.backup_present is distinct from false then
      raise exception using errcode = 'P4R07',
        message = 'La disposition de sauvegarde est incompatible.';
    end if;
  elsif not backup_found
     or observation_row.backup_id is distinct from backup_row.id
     or observation_row.backup_revision is distinct from backup_row.row_revision
     or observation_row.backup_state is distinct from backup_row.state
     or observation_row.backup_present is distinct from backup_object_found
     or observation_row.backup_object_id is distinct from (
       case when backup_object_found then backup_object_row.id else null end
     )
     or observation_row.backup_object_version is distinct from (
       case when backup_object_found then backup_object_row.version else null end
     )
     or (p_backup_disposition = 'deleted' and backup_row.state <> 'deleted')
     or (p_backup_disposition = 'restored' and (
       backup_row.state <> 'restored'
       or not item_row.observed_object_exists
       or item_row.observed_byte_size is distinct from backup_row.byte_size
       or item_row.observed_sha256 is distinct from backup_row.sha256
     ))
     or (p_backup_disposition = 'retained_for_review' and (
       p_result_kind <> 'residual_accepted'
       or backup_row.state not in ('verified', 'restored', 'attention_required')
     ))
     or p_backup_disposition not in ('deleted', 'restored', 'retained_for_review') then
    raise exception using errcode = 'P4R07',
      message = 'La sauvegarde ne correspond pas au résultat annoncé.';
  end if;
  if item_row.action = 'restore_original' and (
    p_backup_disposition <> 'restored' or not item_row.observed_object_exists
  ) then
    raise exception using errcode = 'P4R07',
      message = 'La restauration approuvée n’est pas démontrée.';
  elsif item_row.action = 'complete_backup_cleanup'
        and p_backup_disposition <> 'deleted' then
    raise exception using errcode = 'P4R07',
      message = 'Le nettoyage approuvé n’est pas démontré.';
  elsif item_row.action = 'confirm_already_conform' and (
    item_row.observed_object_exists is distinct from item_row.expected_object_exists
    or (item_row.observed_object_exists and (
      item_row.observed_object_id is distinct from item_row.expected_object_id
      or item_row.observed_object_version
         is distinct from item_row.expected_object_version
    ))
  ) then
    raise exception using errcode = 'P4R07',
      message = 'L’état déclaré conforme diffère du plan approuvé.';
  elsif item_row.action = 'resume_compensation' and (
    (target_row.compensation_action = 'delete'
      and item_row.observed_object_exists)
    or (target_row.compensation_action in ('insert', 'update')
      and not item_row.observed_object_exists)
  ) then
    raise exception using errcode = 'P4R07',
      message = 'Le résultat de compensation ne correspond pas à l’action prévue.';
  end if;

  update public.document_repair_items
  set progress_state = 'verified', result_kind = p_result_kind,
      backup_disposition = p_backup_disposition,
      verified_at = clock_timestamp(), row_revision = row_revision + 1
  where id = item_row.id returning * into item_row;
  perform public.append_document_repair_event(
    authorization_row.id, 'target_verified', 'success', item_row.id,
    'TARGET_VERIFIED', item_row.result_kind
  );
  return jsonb_build_object(
    'itemId', item_row.id, 'progressState', item_row.progress_state,
    'resultKind', item_row.result_kind, 'revision', item_row.row_revision,
    'idempotent', false
  );
end;
$$;

create function public.renew_administrative_document_repair_authorization(
  p_authorization_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_renewal_id uuid,
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
  renewed_at_value timestamptz := clock_timestamp();
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Prolongation de réparation non autorisée.';
  end if;
  select * into authorization_row from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.administrator_subject_id <> caller_id
     or authorization_row.attempt_id is distinct from p_attempt_id then
    raise exception using errcode = 'P4R01',
      message = 'Prolongation de réparation non autorisée.';
  end if;
  if authorization_row.repair_plan_hash is distinct from p_expected_plan_hash
     or public.document_repair_plan_hash(authorization_row.repair_plan)
        is distinct from authorization_row.repair_plan_hash then
    raise exception using errcode = 'P4R05',
      message = 'Le plan de réparation a divergé.';
  end if;
  if authorization_row.last_renewal_id is not distinct from p_renewal_id then
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'state', authorization_row.state,
      'expiresAt', authorization_row.recovery_expires_at,
      'revision', authorization_row.row_revision,
      'idempotent', true
    );
  end if;
  if authorization_row.state <> 'active'
     or p_renewal_id is null
     or authorization_row.row_revision is distinct from p_expected_revision
     or authorization_row.renewal_count >= 6 then
    raise exception using errcode = 'P4R05',
      message = 'La reprise de réparation ne peut pas être prolongée.';
  end if;
  if not exists (
    select 1 from public.document_repair_items item
    where item.authorization_id = authorization_row.id
      and item.progress_state <> 'authorized'
  ) then
    raise exception using errcode = 'P4R05',
      message = 'Une autorisation non commencée ne peut pas être prolongée.';
  end if;
  update public.document_repair_authorizations
  set recovery_expires_at = renewed_at_value + interval '10 minutes',
      renewal_count = renewal_count + 1,
      last_renewal_id = p_renewal_id,
      last_renewed_at = renewed_at_value,
      row_revision = row_revision + 1
  where id = authorization_row.id returning * into authorization_row;
  perform public.append_document_repair_event(
    authorization_row.id, 'authorization_renewed', 'information', null,
    'RECOVERY_WINDOW_RENEWED'
  );
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'state', authorization_row.state,
    'expiresAt', authorization_row.recovery_expires_at,
    'revision', authorization_row.row_revision,
    'idempotent', false
  );
end;
$$;

create function public.get_administrative_document_repair_progress_for_service(
  p_authorization_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  items_value jsonb;
  events_value jsonb;
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, false
  );
  select jsonb_agg(jsonb_build_object(
    'itemId', item.id,
    'targetId', item.target_id,
    'ordinal', item.ordinal,
    'action', item.action,
    'progressState', item.progress_state,
    'revision', item.row_revision,
    'executionId', item.execution_id,
    'bucketId', target.bucket_id,
    'objectPath', target.object_path,
    'targetRevision', target.target_revision,
    'applicationState', target.application_state,
    'lastObservationKind', item.last_observation_kind,
    'lastObservationId', item.last_observation_id,
    'observedObjectExists', item.observed_object_exists,
    'observedObjectId', item.observed_object_id,
    'observedObjectVersion', item.observed_object_version,
    'observedByteSize', item.observed_byte_size,
    'observedSha256', item.observed_sha256,
    'backup', case when backup.id is null then null else jsonb_build_object(
      'backupId', backup.id,
      'state', backup.state,
      'revision', backup.row_revision,
      'byteSize', backup.byte_size,
      'sha256', backup.sha256,
      'recoveryObjectPath', backup.recovery_object_path,
      'recoveryObjectId', backup.recovery_object_id,
      'recoveryObjectVersion', backup.recovery_object_version
    ) end,
    'observations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'observationId', observation.id,
        'kind', observation.observation_kind,
        'objectExists', observation.object_exists,
        'objectId', observation.object_id,
        'objectVersion', observation.object_version,
        'byteSize', observation.byte_size,
        'sha256', observation.sha256,
        'physicalBytesVerified', observation.physical_bytes_verified,
        'backupPresent', observation.backup_present,
        'recordedAt', observation.recorded_at
      ) order by observation.recorded_at, observation.id)
      from public.document_repair_observations observation
      where observation.item_id = item.id
    ), '[]'::jsonb)
  ) order by item.ordinal) into items_value
  from public.document_repair_items item
  join public.document_operation_targets target on target.id = item.target_id
  left join public.document_operation_backups backup on backup.id = item.backup_id
  where item.authorization_id = authorization_row.id;

  select jsonb_agg(jsonb_build_object(
    'sequence', event.sequence_number,
    'itemId', event.item_id,
    'eventType', event.event_type,
    'outcome', event.outcome,
    'safeCode', event.safe_code,
    'resultKind', event.result_kind,
    'occurredAt', event.occurred_at
  ) order by event.sequence_number) into events_value
  from public.document_repair_events event
  where event.authorization_id = authorization_row.id;

  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'operationId', authorization_row.operation_id,
    'administratorSubjectId', authorization_row.administrator_subject_id,
    'attemptId', authorization_row.attempt_id,
    'planHash', authorization_row.repair_plan_hash,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision,
    'expiresAt', public.document_repair_effective_expires_at(authorization_row),
    'expired', public.document_repair_effective_expires_at(authorization_row)
      <= clock_timestamp(),
    'items', coalesce(items_value, '[]'::jsonb),
    'events', coalesce(events_value, '[]'::jsonb)
  );
end;
$$;

create function public.assert_administrative_document_repair_progression_evidence(
  p_authorization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.document_repair_items item
    left join public.document_repair_observations observation
      on observation.id = item.last_observation_id
     and observation.item_id = item.id
     and observation.authorization_id = item.authorization_id
     and observation.execution_id = item.execution_id
    left join public.document_operation_backups backup
      on backup.id = item.backup_id
     and backup.operation_id = item.operation_id
     and backup.target_id = item.target_id
    left join storage.objects backup_object
      on backup_object.bucket_id = 'document-operation-backups'
     and backup_object.name = backup.recovery_object_path
     and backup_object.id = backup.recovery_object_id
     and backup_object.version = backup.recovery_object_version
    where item.authorization_id = p_authorization_id
      and (
        item.progress_state <> 'verified'
        or item.execution_id is null
        or observation.id is null
        or observation.observation_kind not in (
          'physical_verified', 'catalog_absent'
        )
        or observation.object_exists
          is distinct from item.observed_object_exists
        or observation.object_id is distinct from item.observed_object_id
        or observation.object_version
          is distinct from item.observed_object_version
        or observation.byte_size is distinct from item.observed_byte_size
        or observation.sha256 is distinct from item.observed_sha256
        or (item.observed_object_exists
          and not observation.physical_bytes_verified)
        or observation.backup_id is distinct from item.backup_id
        or (item.backup_id is null
          and observation.backup_present is distinct from false)
        or (item.backup_id is not null and (
          backup.id is null
          or observation.backup_revision is distinct from backup.row_revision
          or observation.backup_state is distinct from backup.state
          or observation.backup_present
            is distinct from (backup_object.id is not null)
          or observation.backup_object_id is distinct from backup_object.id
          or observation.backup_object_version
            is distinct from backup_object.version
        ))
      )
  ) then
    raise exception using errcode = 'P4R07',
      message = 'Le journal probant de la réparation est absent ou divergent.';
  end if;
end;
$$;

-- Le scellement utilise la fenêtre de reprise contrôlée lorsqu'elle existe.
create or replace function public.seal_administrative_document_repair(
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
    perform public.assert_administrative_document_repair_progression_evidence(
      authorization_row.id
    );
    return jsonb_build_object(
      'authorizationId', authorization_row.id,
      'operationId', authorization_row.operation_id,
      'state', authorization_row.state,
      'revision', authorization_row.row_revision
    );
  end if;
  if authorization_row.state <> 'active'
     or public.document_repair_effective_expires_at(authorization_row)
        <= clock_timestamp()
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
  perform public.assert_administrative_document_repair_progression_evidence(
    authorization_row.id
  );
  if exists (
    select 1 from public.document_operation_backups backup
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

revoke all on function
  public.assert_document_repair_service(),
  public.document_repair_effective_expires_at(public.document_repair_authorizations),
  public.assert_document_repair_runtime_context(uuid,uuid,uuid,text,boolean),
  public.assert_document_repair_target_context(uuid,uuid,text),
  public.document_repair_observation_fingerprint(jsonb),
  public.assert_administrative_document_repair_progression_evidence(uuid)
from public, anon, authenticated, service_role;

revoke all on function
  public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint),
  public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text),
  public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text),
  public.get_administrative_document_repair_progress_for_service(uuid,uuid,uuid,text),
  public.renew_administrative_document_repair_authorization(uuid,uuid,text,uuid,bigint)
from public, anon, authenticated, service_role;

grant execute on function
  public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint),
  public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text),
  public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text),
  public.get_administrative_document_repair_progress_for_service(uuid,uuid,uuid,text)
to service_role;

grant execute on function
  public.renew_administrative_document_repair_authorization(uuid,uuid,text,uuid,bigint)
to authenticated;

comment on table public.document_repair_observations is
  'Journal append-only des observations catalogue et physiques fournies par l’orchestrateur ; PostgreSQL ne lit pas lui-même les octets.';
comment on function public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint) is
  'Démarre exactement une cible autorisée avec une identité d’exécution stable, sans mutation Storage.';
comment on function public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text) is
  'Enregistre une observation fournie par le service ; physical_bytes_verified atteste seulement la déclaration de lecture du service.';
comment on function public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text) is
  'Vérifie la cohérence SQL d’une preuve déjà collectée avant de marquer la cible vérifiée.';
