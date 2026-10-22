-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2A
-- Contrat SQL de neutralisation documentaire avant suppression Auth.
-- Ce lot n'installe aucun trigger sur storage.objects et ne raccorde pas
-- encore le parcours applicatif.

create table public.account_deletion_document_authorizations (
  id uuid primary key default gen_random_uuid(),
  account_user_id uuid not null,
  attempt_id uuid not null,
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  state text not null default 'active'
    check (state in ('active', 'sealed', 'cancelled')),
  state_changed_at timestamptz not null default clock_timestamp(),
  last_barrier_checked_at timestamptz,
  unique (account_user_id, attempt_id),
  check (expires_at > issued_at and expires_at <= issued_at + interval '10 minutes')
);

create index account_deletion_document_authorizations_expiry_idx
on public.account_deletion_document_authorizations(account_user_id, expires_at desc);

alter table public.account_deletion_document_authorizations enable row level security;
revoke all on table public.account_deletion_document_authorizations
from public, anon, authenticated, service_role;

create trigger account_deletion_document_authorizations_protected
before update or delete on public.account_deletion_document_authorizations
for each row execute function public.protect_document_operation_audit_rows();

create table public.account_storage_neutralizations (
  operation_id uuid primary key
    references public.document_operations(id) on delete restrict,
  target_id uuid not null unique,
  authorization_id uuid not null
    references public.account_deletion_document_authorizations(id) on delete restrict,
  account_user_id uuid not null,
  expected_sha256 text not null check (expected_sha256 ~ '^[0-9a-f]{64}$'),
  expected_byte_size bigint not null check (expected_byte_size between 1 and 20971520),
  mime_type text not null check (
    mime_type in ('application/pdf', 'image/jpeg', 'image/png')
  ),
  phase text not null default 'reserved' check (phase in (
    'reserved', 'backup_verified', 'original_deleted', 'recreated',
    'verified', 'backup_cleanup_authorized', 'backup_cleaned',
    'finalized', 'attention_required'
  )),
  attention_from_phase text check (attention_from_phase in (
    'reserved', 'backup_verified', 'original_deleted', 'recreated',
    'verified', 'backup_cleanup_authorized', 'backup_cleaned'
  )),
  recreated_object_id uuid,
  recreated_object_version text,
  observed_sha256 text check (
    observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'
  ),
  observed_byte_size bigint check (
    observed_byte_size is null or observed_byte_size between 1 and 20971520
  ),
  backup_verified_at timestamptz,
  original_deleted_at timestamptz,
  recreated_at timestamptz,
  content_verified_at timestamptz,
  backup_cleanup_authorized_at timestamptz,
  backup_cleaned_at timestamptz,
  finalized_at timestamptz,
  attention_required_at timestamptz,
  safe_error_code text check (
    safe_error_code is null or safe_error_code ~ '^[A-Z0-9_:-]{1,64}$'
  ),
  row_revision bigint not null default 0 check (row_revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  last_activity_at timestamptz not null default clock_timestamp(),
  foreign key (target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict,
  check ((recreated_object_id is null) = (recreated_object_version is null)),
  check (recreated_object_version is null or btrim(recreated_object_version) <> ''),
  check ((observed_sha256 is null) = (observed_byte_size is null)),
  check ((phase = 'attention_required') = (attention_from_phase is not null)),
  check ((phase = 'finalized') = (finalized_at is not null))
);

create index account_storage_neutralizations_user_phase_idx
on public.account_storage_neutralizations(account_user_id, phase);

alter table public.account_storage_neutralizations enable row level security;
revoke all on table public.account_storage_neutralizations
from public, anon, authenticated, service_role;

create trigger account_storage_neutralizations_protected
before update or delete on public.account_storage_neutralizations
for each row execute function public.protect_document_operation_audit_rows();

alter table public.document_operation_events
  drop constraint document_operation_events_event_type_check;
alter table public.document_operation_events
  add constraint document_operation_events_event_type_check check (event_type in (
    'reserved', 'execution_started', 'compensation_started', 'attention_required',
    'completed', 'compensated', 'cancelled', 'administratively_resolved',
    'object_observed', 'target_applied', 'target_compensation_started',
    'target_compensated', 'backup_verified', 'original_deleted',
    'object_recreated', 'content_verified', 'backup_cleanup_authorized',
    'backup_deleted'
  ));

-- La cible unique d'une neutralisation décrit le verrou et l'identité
-- initiale. Sa progression à deux mutations reste dans la table spécialisée ;
-- elle ne peut donc pas employer honnêtement l'état générique « applied ».
create or replace function public.validate_document_operation_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
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
    and new.initiator_kind = 'account_deletion'
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

create function public.assert_account_storage_neutralization_service()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501',
      message = 'Accès privilégié requis.';
  end if;
end;
$$;

create function public.append_account_storage_neutralization_event(
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
    and operation.initiator_kind = 'account_deletion'
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
    p_outcome, operation_row.initiated_by, 'account_deletion', p_safe_code,
    p_observed_object_id, p_observed_object_version,
    p_observed_size, p_observed_sha256
  );

  return operation_row.row_revision;
end;
$$;

create function public.issue_account_deletion_document_authorization(
  p_account_user_id uuid,
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.account_deletion_document_authorizations%rowtype;
  v_issued_at timestamptz := clock_timestamp();
begin
  perform public.assert_account_storage_neutralization_service();

  if p_account_user_id is null or p_attempt_id is null
     or not exists (select 1 from auth.users where id = p_account_user_id) then
    raise exception using errcode = 'P4N01',
      message = 'Autorisation de suppression de compte refusée.';
  end if;
  if exists (
    select 1 from public.protected_persons
    where owner_id = p_account_user_id
  ) or exists (
    select 1 from public.platform_administrators
    where user_id = p_account_user_id
  ) then
    raise exception using errcode = 'P4N01',
      message = 'Autorisation de suppression de compte refusée.';
  end if;

  insert into public.account_deletion_document_authorizations (
    account_user_id, attempt_id, issued_at, expires_at
  ) values (
    p_account_user_id, p_attempt_id, v_issued_at,
    v_issued_at + interval '10 minutes'
  )
  on conflict (account_user_id, attempt_id) do nothing
  returning * into authorization_row;

  if authorization_row.id is null then
    select * into authorization_row
    from public.account_deletion_document_authorizations
    where account_user_id = p_account_user_id
      and attempt_id = p_attempt_id;
  end if;

  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'accountUserId', authorization_row.account_user_id,
    'attemptId', authorization_row.attempt_id,
    'expiresAt', authorization_row.expires_at,
    'state', authorization_row.state
  );
end;
$$;

create function public.cancel_account_deletion_document_authorization(
  p_authorization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.account_deletion_document_authorizations%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into authorization_row
  from public.account_deletion_document_authorizations
  where id = p_authorization_id
  for update;
  if not found then
    raise exception using errcode = 'P4N01',
      message = 'Autorisation de suppression de compte introuvable.';
  end if;
  if authorization_row.state = 'sealed' then
    raise exception using errcode = 'P4N04',
      message = 'Une autorisation scellée ne peut plus être annulée.';
  end if;
  if authorization_row.state <> 'cancelled' then
    update public.account_deletion_document_authorizations
    set state = 'cancelled', state_changed_at = clock_timestamp()
    where id = p_authorization_id
    returning * into authorization_row;
  end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'accountUserId', authorization_row.account_user_id,
    'attemptId', authorization_row.attempt_id,
    'state', authorization_row.state
  );
end;
$$;

create function public.begin_account_storage_neutralization(
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
  authorization_row public.account_deletion_document_authorizations%rowtype;
  resolution record;
  object_row storage.objects%rowtype;
  existing_operation public.document_operations%rowtype;
  neutralization_row public.account_storage_neutralizations%rowtype;
  v_operation_id uuid;
  v_target_id uuid;
  signature jsonb;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode = 'P4N01',
      message = 'Accès à la neutralisation documentaire refusé.';
  end if;
  if p_authorization_id is null or p_client_request_id is null
     or p_expected_object_id is null
     or p_expected_object_version is null
     or btrim(p_expected_object_version) = ''
     or p_expected_sha256 is null
     or p_expected_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_byte_size not between 1 and 20971520
     or p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception using errcode = 'P4N02',
      message = 'Demande de neutralisation documentaire invalide.';
  end if;

  select * into authorization_row
  from public.account_deletion_document_authorizations
  where id = p_authorization_id
  for update;
  if not found or authorization_row.account_user_id <> caller_id
     or authorization_row.state <> 'active'
     or authorization_row.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P4N01',
      message = 'Autorisation de suppression de compte inactive ou expirée.';
  end if;

  select * into resolution
  from public.resolve_canonical_document_storage_path(p_bucket_id, p_object_path);
  if not resolution.is_canonical
     or not exists (
       select 1 from public.protected_persons
       where id = resolution.protected_person_id
     ) then
    raise exception using errcode = 'P4N02',
      message = 'Objet documentaire non canonique.';
  end if;

  select * into object_row
  from storage.objects object
  where object.bucket_id = p_bucket_id
    and object.name = p_object_path
  for key share;
  if not found
     or object_row.id is distinct from p_expected_object_id
     or object_row.version is distinct from p_expected_object_version then
    raise exception using errcode = 'P4N03',
      message = 'L’objet Storage a changé depuis son inventaire.';
  end if;
  if object_row.owner is distinct from caller_id
     and object_row.owner_id is distinct from caller_id::text then
    raise exception using errcode = 'P4N01',
      message = 'L’objet Storage n’appartient pas au compte courant.';
  end if;

  signature := jsonb_build_array(jsonb_build_object(
    'ordinal', 1,
    'bucket_id', p_bucket_id,
    'object_path', p_object_path,
    'target_role', 'primary',
    'forward_action', 'delete',
    'compensation_action', 'insert',
    'expected_exists', true,
    'expected_object_id', p_expected_object_id,
    'expected_object_version', p_expected_object_version,
    'expected_sha256', p_expected_sha256,
    'expected_byte_size', p_expected_byte_size,
    'mime_type', p_mime_type,
    'authorization_id', p_authorization_id
  ));

  select * into existing_operation
  from public.document_operations
  where initiator_subject_id = caller_id
    and client_request_id = p_client_request_id;
  if found then
    select * into neutralization_row
    from public.account_storage_neutralizations
    where operation_id = existing_operation.id;
    if existing_operation.initiator_kind <> 'account_deletion'
       or existing_operation.workflow <> 'account_storage_neutralization'
       or existing_operation.protected_person_id is distinct from resolution.protected_person_id
       or existing_operation.business_entity_type is distinct from resolution.business_entity_type
       or existing_operation.business_entity_id is distinct from resolution.business_entity_id
       or existing_operation.target_signature is distinct from signature
       or neutralization_row.authorization_id is distinct from p_authorization_id then
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
    resolution.protected_person_id, caller_id, caller_id, 'account_deletion',
    'account_storage_neutralization', resolution.business_entity_type,
    resolution.business_entity_id, p_client_request_id, signature
    ) returning id into v_operation_id;

  insert into public.document_operation_targets (
    operation_id, ordinal, bucket_id, object_path, target_role,
    forward_action, compensation_action, expected_exists,
    expected_object_id, expected_object_version, expected_snapshot_captured_at
  ) values (
    v_operation_id, 1, p_bucket_id, p_object_path, 'primary',
    'delete', 'insert', true, p_expected_object_id,
    p_expected_object_version, clock_timestamp()
  ) returning id into v_target_id;

  begin
    insert into public.document_object_locks (
      bucket_id, object_path, target_id, operation_id
    ) values (p_bucket_id, p_object_path, v_target_id, v_operation_id);
  exception when unique_violation then
    raise exception using errcode = 'P4O05',
      message = 'Ce fichier est déjà réservé par une autre opération.';
  end;

  insert into public.account_storage_neutralizations (
    operation_id, target_id, authorization_id, account_user_id,
    expected_sha256, expected_byte_size, mime_type
  ) values (
    v_operation_id, v_target_id, p_authorization_id, caller_id,
    p_expected_sha256, p_expected_byte_size, p_mime_type
  );

  perform public.append_account_storage_neutralization_event(
    v_operation_id, v_target_id, 'reserved', 'success', null,
    p_expected_object_id, p_expected_object_version,
    p_expected_byte_size, p_expected_sha256
  );

  return jsonb_build_object(
    'operationId', v_operation_id,
    'targetId', v_target_id,
    'state', 'reserved',
    'phase', 'reserved',
    'revision', 0
  );
end;
$$;

create function public.reserve_account_storage_neutralization_backup(
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  neutralization_row public.account_storage_neutralizations%rowtype;
  object_row storage.objects%rowtype;
  backup_row public.document_operation_backups%rowtype;
  recovery_path text;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into operation_row from public.document_operations
  where id = p_operation_id for update;
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if operation_row.id is null or neutralization_row.operation_id is null
     or operation_row.state <> 'reserved'
     or neutralization_row.phase <> 'reserved' then
    raise exception using errcode = 'P4N04',
      message = 'La neutralisation ne peut pas réserver de sauvegarde.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id and operation_id = p_operation_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if not found or object_row.id is distinct from target_row.expected_object_id
     or object_row.version is distinct from target_row.expected_object_version
     or (object_row.owner is distinct from neutralization_row.account_user_id
       and object_row.owner_id is distinct from neutralization_row.account_user_id::text) then
    raise exception using errcode = 'P4N03',
      message = 'L’objet Storage ne correspond plus à la réservation.';
  end if;

  recovery_path := 'operations/' || p_operation_id || '/targets/' ||
    target_row.id || '/backup';
  insert into public.document_operation_backups (
    operation_id, target_id, protected_person_id, initiator_subject_id,
    original_bucket_id, original_object_path, original_object_id,
    original_object_version, recovery_object_path, byte_size, mime_type, sha256
  ) values (
    p_operation_id, target_row.id, operation_row.protected_person_id,
    neutralization_row.account_user_id, target_row.bucket_id,
    target_row.object_path, target_row.expected_object_id,
    target_row.expected_object_version, recovery_path,
    neutralization_row.expected_byte_size, neutralization_row.mime_type,
    neutralization_row.expected_sha256
  )
  on conflict (operation_id, target_id) do nothing
  returning * into backup_row;

  if backup_row.id is null then
    select * into backup_row from public.document_operation_backups
    where operation_id = p_operation_id and target_id = target_row.id;
    if backup_row.recovery_object_path is distinct from recovery_path
       or backup_row.original_object_id is distinct from target_row.expected_object_id
       or backup_row.original_object_version is distinct from target_row.expected_object_version
       or backup_row.byte_size is distinct from neutralization_row.expected_byte_size
       or backup_row.mime_type is distinct from neutralization_row.mime_type
       or backup_row.sha256 is distinct from neutralization_row.expected_sha256 then
      raise exception using errcode = 'P4B05',
        message = 'Une sauvegarde incompatible existe déjà.';
    end if;
  end if;

  return jsonb_build_object(
    'backupId', backup_row.id,
    'bucketId', 'document-operation-backups',
    'objectPath', backup_row.recovery_object_path,
    'state', backup_row.state,
    'revision', backup_row.row_revision,
    'byteSize', backup_row.byte_size,
    'mimeType', backup_row.mime_type,
    'sha256', backup_row.sha256
  );
end;
$$;

create function public.confirm_account_storage_neutralization_backup(
  p_operation_id uuid,
  p_expected_neutralization_revision bigint,
  p_expected_backup_revision bigint,
  p_observed_sha256 text,
  p_observed_byte_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  backup_row public.document_operation_backups%rowtype;
  backup_object storage.objects%rowtype;
  operation_revision bigint;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  select * into backup_row from public.document_operation_backups
  where operation_id = p_operation_id
    and target_id = neutralization_row.target_id for update;
  if neutralization_row.operation_id is null or backup_row.id is null then
    raise exception using errcode = 'P4B03',
      message = 'Sauvegarde documentaire introuvable.';
  end if;
  if neutralization_row.phase <> 'reserved' then
    if neutralization_row.phase in (
      'backup_verified', 'original_deleted', 'recreated', 'verified',
      'backup_cleanup_authorized', 'backup_cleaned', 'finalized'
    ) and backup_row.state in ('verified', 'restored', 'deleted')
      and p_observed_sha256 is not distinct from neutralization_row.expected_sha256
      and p_observed_byte_size is not distinct from neutralization_row.expected_byte_size then
      return jsonb_build_object(
        'operationId', p_operation_id, 'phase', neutralization_row.phase,
        'revision', neutralization_row.row_revision
      );
    end if;
    raise exception using errcode = 'P4N04',
      message = 'La progression de neutralisation a changé.';
  end if;
  if neutralization_row.row_revision <> p_expected_neutralization_revision
     or backup_row.row_revision <> p_expected_backup_revision
     or backup_row.state <> 'upload_pending' then
    raise exception using errcode = 'P4N04',
      message = 'La progression de neutralisation a changé.';
  end if;
  if p_observed_sha256 is distinct from neutralization_row.expected_sha256
     or p_observed_byte_size is distinct from neutralization_row.expected_byte_size then
    raise exception using errcode = 'P4B04',
      message = 'La sauvegarde durable ne correspond pas aux octets attendus.';
  end if;
  select * into backup_object from storage.objects object
  where object.bucket_id = 'document-operation-backups'
    and object.name = backup_row.recovery_object_path
  for key share;
  if not found or backup_object.version is null
     or btrim(backup_object.version) = '' then
    raise exception using errcode = 'P4B04',
      message = 'L’objet de récupération est absent.';
  end if;

  update public.document_operation_backups
  set state = 'verified', recovery_object_id = backup_object.id,
      recovery_object_version = backup_object.version,
      upload_verified_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where id = backup_row.id;
  update public.account_storage_neutralizations
  set phase = 'backup_verified', backup_verified_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id
  returning * into neutralization_row;

  perform public.transition_document_operation(
    p_operation_id, 'reserved', 'executing'
  );
  operation_revision := public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'backup_verified',
    'success', null, backup_object.id, backup_object.version,
    p_observed_byte_size, p_observed_sha256
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision,
    'operationRevision', operation_revision
  );
end;
$$;

create function public.record_account_storage_neutralization_original_deleted(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase in (
    'original_deleted', 'recreated', 'verified',
    'backup_cleanup_authorized', 'backup_cleaned', 'finalized'
  ) then
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'backup_verified'
     or neutralization_row.row_revision <> p_expected_revision
     or not exists (
       select 1 from public.document_operation_backups
       where operation_id = p_operation_id
         and target_id = neutralization_row.target_id
         and state = 'verified'
     ) then
    raise exception using errcode = 'P4N04',
      message = 'La suppression de l’original ne peut pas être confirmée.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  if exists (
    select 1 from storage.objects
    where bucket_id = target_row.bucket_id and name = target_row.object_path
  ) then
    raise exception using errcode = 'P4N03',
      message = 'L’objet Storage original existe encore.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'original_deleted', original_deleted_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'original_deleted'
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.record_account_storage_neutralization_recreated(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_observed_object_id uuid,
  p_observed_object_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase in (
    'recreated', 'verified', 'backup_cleanup_authorized',
    'backup_cleaned', 'finalized'
  ) then
    if neutralization_row.recreated_object_id is distinct from p_observed_object_id
       or neutralization_row.recreated_object_version is distinct from p_observed_object_version then
      raise exception using errcode = 'P4N03',
        message = 'L’identité de l’objet recréé a changé.';
    end if;
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'original_deleted'
     or neutralization_row.row_revision <> p_expected_revision
     or p_observed_object_id is null
     or p_observed_object_version is null
     or btrim(p_observed_object_version) = '' then
    raise exception using errcode = 'P4N04',
      message = 'La recréation ne peut pas être confirmée.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if not found
     or object_row.id is distinct from p_observed_object_id
     or object_row.version is distinct from p_observed_object_version
     or object_row.id is not distinct from target_row.expected_object_id
     or object_row.owner = neutralization_row.account_user_id
     or object_row.owner_id = neutralization_row.account_user_id::text then
    raise exception using errcode = 'P4N03',
      message = 'L’objet recréé n’est pas une neutralisation vérifiable.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'recreated', recreated_object_id = object_row.id,
      recreated_object_version = object_row.version,
      recreated_at = clock_timestamp(), last_activity_at = clock_timestamp(),
      row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'object_recreated',
    'success', null, object_row.id, object_row.version
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.verify_account_storage_neutralization_content(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_observed_sha256 text,
  p_observed_byte_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase in (
    'verified', 'backup_cleanup_authorized', 'backup_cleaned', 'finalized'
  ) then
    if neutralization_row.observed_sha256 is distinct from p_observed_sha256
       or neutralization_row.observed_byte_size is distinct from p_observed_byte_size then
      raise exception using errcode = 'P4N03',
        message = 'La vérification des octets est incompatible.';
    end if;
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'recreated'
     or neutralization_row.row_revision <> p_expected_revision
     or p_observed_sha256 is distinct from neutralization_row.expected_sha256
     or p_observed_byte_size is distinct from neutralization_row.expected_byte_size then
    raise exception using errcode = 'P4N03',
      message = 'Les octets recréés ne correspondent pas à la sauvegarde.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if not found
     or object_row.id is distinct from neutralization_row.recreated_object_id
     or object_row.version is distinct from neutralization_row.recreated_object_version
     or object_row.owner = neutralization_row.account_user_id
     or object_row.owner_id = neutralization_row.account_user_id::text then
    raise exception using errcode = 'P4N03',
      message = 'L’objet recréé a changé avant vérification.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'verified', observed_sha256 = p_observed_sha256,
      observed_byte_size = p_observed_byte_size,
      content_verified_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'content_verified',
    'success', null, object_row.id, object_row.version,
    p_observed_byte_size, p_observed_sha256
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.authorize_account_storage_neutralization_recovery(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select * into backup_row from public.document_operation_backups
  where operation_id = p_operation_id
    and target_id = neutralization_row.target_id for update;
  if neutralization_row.phase not in ('original_deleted', 'recreated')
     or neutralization_row.row_revision <> p_expected_revision
     or backup_row.state not in ('verified', 'restored')
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id = 'document-operation-backups'
         and object.name = backup_row.recovery_object_path
         and object.id = backup_row.recovery_object_id
         and object.version = backup_row.recovery_object_version
     ) then
    raise exception using errcode = 'P4N04',
      message = 'La récupération documentaire n’est pas autorisée.';
  end if;
  return jsonb_build_object(
    'backupId', backup_row.id,
    'sourceBucketId', 'document-operation-backups',
    'sourceObjectPath', backup_row.recovery_object_path,
    'destinationBucketId', target_row.bucket_id,
    'destinationObjectPath', target_row.object_path,
    'expectedSha256', neutralization_row.expected_sha256,
    'expectedByteSize', neutralization_row.expected_byte_size,
    'mimeType', neutralization_row.mime_type,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.confirm_account_storage_neutralization_recovery(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_observed_object_id uuid,
  p_observed_object_version text,
  p_observed_sha256 text,
  p_observed_byte_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
  object_row storage.objects%rowtype;
  previous_phase text;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase in (
    'verified', 'backup_cleanup_authorized', 'backup_cleaned', 'finalized'
  ) then
    if neutralization_row.recreated_object_id is distinct from p_observed_object_id
       or neutralization_row.recreated_object_version is distinct from p_observed_object_version
       or neutralization_row.observed_sha256 is distinct from p_observed_sha256
       or neutralization_row.observed_byte_size is distinct from p_observed_byte_size then
      raise exception using errcode = 'P4N03',
        message = 'La récupération documentaire est incompatible.';
    end if;
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase not in ('original_deleted', 'recreated')
     or neutralization_row.row_revision <> p_expected_revision
     or p_observed_sha256 is distinct from neutralization_row.expected_sha256
     or p_observed_byte_size is distinct from neutralization_row.expected_byte_size
     or p_observed_object_id is null
     or p_observed_object_version is null
     or btrim(p_observed_object_version) = '' then
    raise exception using errcode = 'P4N03',
      message = 'La récupération documentaire n’est pas vérifiable.';
  end if;
  previous_phase := neutralization_row.phase;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select * into backup_row from public.document_operation_backups
  where operation_id = p_operation_id
    and target_id = neutralization_row.target_id for update;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if backup_row.state not in ('verified', 'restored')
     or not found
     or object_row.id is distinct from p_observed_object_id
     or object_row.version is distinct from p_observed_object_version
     or object_row.id is not distinct from target_row.expected_object_id
     or object_row.owner = neutralization_row.account_user_id
     or object_row.owner_id = neutralization_row.account_user_id::text then
    raise exception using errcode = 'P4N03',
      message = 'La récupération documentaire n’est pas vérifiable.';
  end if;
  if previous_phase = 'recreated' and (
    neutralization_row.recreated_object_id is distinct from object_row.id
    or neutralization_row.recreated_object_version is distinct from object_row.version
  ) then
    raise exception using errcode = 'P4N03',
      message = 'L’identité de l’objet recréé a changé.';
  end if;
  if backup_row.state = 'verified' then
    update public.document_operation_backups
    set state = 'restored', restored_at = clock_timestamp(),
        last_activity_at = clock_timestamp(), row_revision = row_revision + 1
    where id = backup_row.id;
  end if;
  update public.account_storage_neutralizations
  set phase = 'verified', recreated_object_id = object_row.id,
      recreated_object_version = object_row.version,
      recreated_at = coalesce(recreated_at, clock_timestamp()),
      observed_sha256 = p_observed_sha256,
      observed_byte_size = p_observed_byte_size,
      content_verified_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  if previous_phase = 'original_deleted' then
    perform public.append_account_storage_neutralization_event(
      p_operation_id, neutralization_row.target_id, 'object_recreated',
      'success', null, object_row.id, object_row.version
    );
  end if;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'content_verified',
    'success', null, object_row.id, object_row.version,
    p_observed_byte_size, p_observed_sha256
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision, 'recovered', true
  );
end;
$$;

create function public.authorize_account_storage_neutralization_backup_cleanup(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  select * into backup_row from public.document_operation_backups
  where operation_id = p_operation_id
    and target_id = neutralization_row.target_id for update;
  if neutralization_row.phase = 'backup_cleanup_authorized' then
    return jsonb_build_object(
      'backupId', backup_row.id, 'bucketId', 'document-operation-backups',
      'objectPath', backup_row.recovery_object_path,
      'state', backup_row.state, 'revision', backup_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'verified'
     or neutralization_row.row_revision <> p_expected_revision
     or backup_row.state not in ('verified', 'restored') then
    raise exception using errcode = 'P4N04',
      message = 'Le nettoyage de la sauvegarde n’est pas autorisé.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'backup_cleanup_authorized',
      backup_cleanup_authorized_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id,
    'backup_cleanup_authorized'
  );
  return jsonb_build_object(
    'backupId', backup_row.id, 'bucketId', 'document-operation-backups',
    'objectPath', backup_row.recovery_object_path,
    'state', backup_row.state, 'revision', backup_row.row_revision
  );
end;
$$;

create function public.confirm_account_storage_neutralization_backup_cleanup(
  p_operation_id uuid,
  p_expected_neutralization_revision bigint,
  p_expected_backup_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  select * into backup_row from public.document_operation_backups
  where operation_id = p_operation_id
    and target_id = neutralization_row.target_id for update;
  if neutralization_row.phase in ('backup_cleaned', 'finalized')
     and backup_row.state = 'deleted' then
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'backup_cleanup_authorized'
     or neutralization_row.row_revision <> p_expected_neutralization_revision
     or backup_row.row_revision <> p_expected_backup_revision
     or backup_row.state not in ('verified', 'restored') then
    raise exception using errcode = 'P4N04',
      message = 'Le nettoyage de la sauvegarde ne peut pas être confirmé.';
  end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id = 'document-operation-backups'
      and object.name = backup_row.recovery_object_path
  ) then
    raise exception using errcode = 'P4B04',
      message = 'L’objet de récupération existe encore.';
  end if;
  update public.document_operation_backups
  set state = 'deleted', deleted_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where id = backup_row.id;
  update public.account_storage_neutralizations
  set phase = 'backup_cleaned', backup_cleaned_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.append_account_storage_neutralization_event(
    p_operation_id, neutralization_row.target_id, 'backup_deleted'
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.finalize_account_storage_neutralization(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  operation_revision bigint;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase = 'finalized' then
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', 'finalized',
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.phase <> 'backup_cleaned'
     or neutralization_row.row_revision <> p_expected_revision
     or not exists (
       select 1 from public.document_operation_backups
       where operation_id = p_operation_id
         and target_id = neutralization_row.target_id
         and state = 'deleted'
     ) then
    raise exception using errcode = 'P4N04',
      message = 'La neutralisation documentaire n’est pas finalisable.';
  end if;
  select * into target_row from public.document_operation_targets
  where id = neutralization_row.target_id;
  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if not found
     or object_row.id is distinct from neutralization_row.recreated_object_id
     or object_row.version is distinct from neutralization_row.recreated_object_version
     or object_row.owner = neutralization_row.account_user_id
     or object_row.owner_id = neutralization_row.account_user_id::text
     or neutralization_row.observed_sha256 is distinct from neutralization_row.expected_sha256
     or neutralization_row.observed_byte_size is distinct from neutralization_row.expected_byte_size then
    raise exception using errcode = 'P4N03',
      message = 'La neutralisation finale n’est pas vérifiable.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'finalized', finalized_at = clock_timestamp(),
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  operation_revision := public.transition_document_operation(
    p_operation_id, 'executing', 'completed'
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'state', 'completed',
    'phase', neutralization_row.phase,
    'revision', neutralization_row.row_revision,
    'operationRevision', operation_revision
  );
end;
$$;

create function public.mark_account_storage_neutralization_attention_required(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_safe_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  neutralization_row public.account_storage_neutralizations%rowtype;
  operation_state text;
begin
  perform public.assert_account_storage_neutralization_service();
  if p_safe_error_code is null
     or p_safe_error_code !~ '^[A-Z0-9_:-]{1,64}$' then
    raise exception using errcode = 'P4N02',
      message = 'Code d’erreur sûr invalide.';
  end if;
  select * into neutralization_row from public.account_storage_neutralizations
  where operation_id = p_operation_id for update;
  if neutralization_row.phase = 'attention_required' then
    if neutralization_row.safe_error_code is distinct from p_safe_error_code then
      raise exception using errcode = 'P4N04',
        message = 'La mise en attention existante est incompatible.';
    end if;
    return jsonb_build_object(
      'operationId', p_operation_id, 'phase', neutralization_row.phase,
      'resumePhase', neutralization_row.attention_from_phase,
      'revision', neutralization_row.row_revision
    );
  end if;
  if neutralization_row.operation_id is null
     or neutralization_row.phase = 'finalized'
     or neutralization_row.row_revision <> p_expected_revision then
    raise exception using errcode = 'P4N04',
      message = 'La neutralisation ne peut pas être placée en attention.';
  end if;
  select state into operation_state from public.document_operations
  where id = p_operation_id for update;
  if operation_state not in ('reserved', 'executing', 'compensating') then
    raise exception using errcode = 'P4N04',
      message = 'La neutralisation ne peut pas être placée en attention.';
  end if;
  update public.account_storage_neutralizations
  set phase = 'attention_required', attention_from_phase = phase,
      attention_required_at = clock_timestamp(),
      safe_error_code = p_safe_error_code,
      last_activity_at = clock_timestamp(), row_revision = row_revision + 1
  where operation_id = p_operation_id returning * into neutralization_row;
  perform public.transition_document_operation(
    p_operation_id, operation_state, 'attention_required', p_safe_error_code
  );
  return jsonb_build_object(
    'operationId', p_operation_id, 'phase', neutralization_row.phase,
    'resumePhase', neutralization_row.attention_from_phase,
    'revision', neutralization_row.row_revision
  );
end;
$$;

create function public.get_account_storage_neutralization_progress(
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
       or (caller_id is not null
         and caller_id = neutralization_row.account_user_id
         and public.is_application_user_active())
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

create function public.assert_account_deletion_document_barrier(
  p_authorization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.account_deletion_document_authorizations%rowtype;
  owned_object_count bigint;
  non_terminal_count bigint;
  uncleared_backup_count bigint;
begin
  perform public.assert_account_storage_neutralization_service();
  select * into authorization_row
  from public.account_deletion_document_authorizations
  where id = p_authorization_id for update;
  if not found or authorization_row.state = 'cancelled'
     or authorization_row.expires_at <= clock_timestamp()
     or not exists (
       select 1 from auth.users where id = authorization_row.account_user_id
     ) then
    raise exception using errcode = 'P4N01',
      message = 'Autorisation de suppression de compte inactive ou expirée.';
  end if;
  if exists (
    select 1 from public.protected_persons
    where owner_id = authorization_row.account_user_id
  ) or exists (
    select 1 from public.platform_administrators
    where user_id = authorization_row.account_user_id
  ) then
    raise exception using errcode = 'P4N05',
      message = 'La suppression Auth reste bloquée par les règles du compte.';
  end if;
  select count(*) into non_terminal_count
  from public.document_operations operation
  where operation.initiator_subject_id = authorization_row.account_user_id
    and operation.state not in (
      'completed', 'compensated', 'cancelled', 'administratively_resolved'
    );
  select count(*) into uncleared_backup_count
  from public.document_operation_backups backup
  where backup.initiator_subject_id = authorization_row.account_user_id
    and backup.state <> 'deleted';
  select count(*) into owned_object_count
  from storage.objects object
  where object.bucket_id in (
    'transaction-proofs', 'bank-statements', 'management-reports'
  ) and (
    object.owner = authorization_row.account_user_id
    or object.owner_id = authorization_row.account_user_id::text
  );
  if non_terminal_count <> 0 or uncleared_backup_count <> 0
     or owned_object_count <> 0 then
    raise exception using errcode = 'P4N05',
      message = 'La suppression Auth reste bloquée par l’état documentaire.';
  end if;
  update public.account_deletion_document_authorizations
  set state = 'sealed', state_changed_at = case
        when state = 'active' then clock_timestamp() else state_changed_at end,
      last_barrier_checked_at = clock_timestamp()
  where id = p_authorization_id;
  return jsonb_build_object(
    'ready', true,
    'accountUserId', authorization_row.account_user_id,
    'attemptId', authorization_row.attempt_id,
    'checkedAt', clock_timestamp()
  );
end;
$$;

revoke all on function
  public.assert_account_storage_neutralization_service(),
  public.append_account_storage_neutralization_event(uuid,uuid,text,text,text,uuid,text,bigint,text),
  public.issue_account_deletion_document_authorization(uuid,uuid),
  public.cancel_account_deletion_document_authorization(uuid),
  public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text),
  public.reserve_account_storage_neutralization_backup(uuid),
  public.confirm_account_storage_neutralization_backup(uuid,bigint,bigint,text,bigint),
  public.record_account_storage_neutralization_original_deleted(uuid,bigint),
  public.record_account_storage_neutralization_recreated(uuid,bigint,uuid,text),
  public.verify_account_storage_neutralization_content(uuid,bigint,text,bigint),
  public.authorize_account_storage_neutralization_recovery(uuid,bigint),
  public.confirm_account_storage_neutralization_recovery(uuid,bigint,uuid,text,text,bigint),
  public.authorize_account_storage_neutralization_backup_cleanup(uuid,bigint),
  public.confirm_account_storage_neutralization_backup_cleanup(uuid,bigint,bigint),
  public.finalize_account_storage_neutralization(uuid,bigint),
  public.mark_account_storage_neutralization_attention_required(uuid,bigint,text),
  public.get_account_storage_neutralization_progress(uuid),
  public.assert_account_deletion_document_barrier(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text),
  public.get_account_storage_neutralization_progress(uuid)
to authenticated;

grant execute on function
  public.issue_account_deletion_document_authorization(uuid,uuid),
  public.cancel_account_deletion_document_authorization(uuid),
  public.reserve_account_storage_neutralization_backup(uuid),
  public.confirm_account_storage_neutralization_backup(uuid,bigint,bigint,text,bigint),
  public.record_account_storage_neutralization_original_deleted(uuid,bigint),
  public.record_account_storage_neutralization_recreated(uuid,bigint,uuid,text),
  public.verify_account_storage_neutralization_content(uuid,bigint,text,bigint),
  public.authorize_account_storage_neutralization_recovery(uuid,bigint),
  public.confirm_account_storage_neutralization_recovery(uuid,bigint,uuid,text,text,bigint),
  public.authorize_account_storage_neutralization_backup_cleanup(uuid,bigint),
  public.confirm_account_storage_neutralization_backup_cleanup(uuid,bigint,bigint),
  public.finalize_account_storage_neutralization(uuid,bigint),
  public.mark_account_storage_neutralization_attention_required(uuid,bigint,text),
  public.get_account_storage_neutralization_progress(uuid),
  public.assert_account_deletion_document_barrier(uuid)
to service_role;

comment on table public.account_deletion_document_authorizations is
  'Autorisations courtes émises par le serveur après réauthentification ; elles ne suppriment jamais le compte Auth.';
comment on table public.account_storage_neutralizations is
  'Progression durable d’une neutralisation de propriété Storage, sans duplication de cible documentaire.';
comment on function public.issue_account_deletion_document_authorization(uuid,uuid) is
  'Crée côté service_role une autorisation de dix minutes liée à un utilisateur et à une tentative de suppression.';
comment on function public.cancel_account_deletion_document_authorization(uuid) is
  'Annule irréversiblement une tentative ; une nouvelle suppression doit employer un nouvel identifiant de tentative.';
comment on function public.assert_account_deletion_document_barrier(uuid) is
  'Barrière privilégiée juste avant suppression Auth ; elle ne constitue pas une transaction distribuée avec Auth ou Storage.';
