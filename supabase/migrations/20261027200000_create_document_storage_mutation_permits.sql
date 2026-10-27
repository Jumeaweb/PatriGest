-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2D2
-- Registre privé des permis de mutation Storage.
-- Aucun trigger n'est installé sur storage.objects et la garde reste désactivée.

create table public.document_storage_mutation_permits (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  target_id uuid not null,
  permit_scope text not null check (permit_scope in ('document', 'backup')),
  mutation_phase text not null check (mutation_phase in (
    'forward', 'compensation', 'backup_upload', 'backup_cleanup'
  )),
  workflow text not null,
  storage_action text not null check (storage_action in ('insert', 'update', 'delete')),
  bucket_id text not null check (bucket_id in (
    'transaction-proofs', 'bank-statements', 'management-reports',
    'document-operation-backups'
  )),
  object_path text not null check (
    object_path = btrim(object_path)
    and object_path <> ''
    and position(chr(92) in object_path) = 0
    and object_path !~ '(^/|(^|/)\.\.(/|$)|//)'
  ),
  expected_exists boolean not null,
  expected_object_id uuid,
  expected_object_version text,
  operation_revision bigint not null check (operation_revision >= 0),
  target_revision bigint not null check (target_revision >= 0),
  backup_id uuid,
  backup_revision bigint check (backup_revision is null or backup_revision >= 0),
  backup_required boolean not null default false,
  authorizing_subject_id uuid not null,
  authorizer_kind text not null check (authorizer_kind in (
    'user', 'account_deletion', 'platform_admin', 'system'
  )),
  client_request_id uuid not null,
  intention_hash text not null check (intention_hash ~ '^[0-9a-f]{64}$'),
  state text not null default 'issued' check (state in (
    'issued', 'consumed', 'expired', 'cancelled'
  )),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  evidence_required boolean not null default false,
  evidence_recorded_at timestamptz,
  observed_object_id uuid,
  observed_object_version text,
  observed_byte_size bigint check (observed_byte_size is null or observed_byte_size >= 0),
  observed_sha256 text check (
    observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'
  ),
  observed_backup_object_id uuid,
  observed_backup_object_version text,
  observed_backup_byte_size bigint check (
    observed_backup_byte_size is null or observed_backup_byte_size >= 0
  ),
  observed_backup_sha256 text check (
    observed_backup_sha256 is null or observed_backup_sha256 ~ '^[0-9a-f]{64}$'
  ),
  consumed_at timestamptz,
  cancelled_at timestamptz,
  expired_at timestamptz,
  consumed_existing_object_id uuid,
  consumed_existing_object_version text,
  row_revision bigint not null default 0 check (row_revision >= 0),
  unique (operation_id, client_request_id),
  unique (id, operation_id, target_id),
  foreign key (target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict,
  foreign key (backup_id)
    references public.document_operation_backups(id) on delete restrict,
  check ((expected_object_id is null) = (expected_object_version is null)),
  check (expected_object_version is null or btrim(expected_object_version) <> ''),
  check (expected_exists or expected_object_id is null),
  check ((backup_id is null) = (backup_revision is null)),
  check (not backup_required or backup_id is not null),
  check (expires_at > issued_at and expires_at <= issued_at + interval '2 minutes'),
  check ((observed_object_id is null) = (observed_object_version is null)),
  check (observed_object_version is null or btrim(observed_object_version) <> ''),
  check ((observed_backup_object_id is null) = (observed_backup_object_version is null)),
  check (observed_backup_object_version is null or btrim(observed_backup_object_version) <> ''),
  check (
    (evidence_recorded_at is null
      and observed_object_id is null and observed_object_version is null
      and observed_byte_size is null and observed_sha256 is null
      and observed_backup_object_id is null and observed_backup_object_version is null
      and observed_backup_byte_size is null and observed_backup_sha256 is null)
    or evidence_recorded_at is not null
  ),
  check (
    (state = 'issued' and consumed_at is null and cancelled_at is null and expired_at is null)
    or (state = 'consumed' and consumed_at is not null and cancelled_at is null and expired_at is null)
    or (state = 'cancelled' and consumed_at is null and cancelled_at is not null and expired_at is null)
    or (state = 'expired' and consumed_at is null and cancelled_at is null and expired_at is not null)
  )
);

create unique index document_storage_mutation_permits_target_revision_idx
on public.document_storage_mutation_permits(
  target_id, permit_scope, mutation_phase, target_revision
);

create unique index document_storage_mutation_permits_active_path_idx
on public.document_storage_mutation_permits(bucket_id, object_path)
where state = 'issued';

create index document_storage_mutation_permits_state_expiry_idx
on public.document_storage_mutation_permits(state, expires_at);

create table public.document_storage_mutation_permit_events (
  id uuid primary key default gen_random_uuid(),
  permit_id uuid not null references public.document_storage_mutation_permits(id) on delete restrict,
  sequence_number bigint not null check (sequence_number > 0),
  event_type text not null check (event_type in (
    'issued', 'physical_evidence_recorded', 'consumed', 'expired', 'cancelled'
  )),
  actor_subject_id uuid,
  actor_kind text not null check (actor_kind in (
    'user', 'account_deletion', 'platform_admin', 'system'
  )),
  observed_object_id uuid,
  observed_object_version text,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (permit_id, sequence_number)
);

alter table public.document_storage_mutation_permits enable row level security;
alter table public.document_storage_mutation_permit_events enable row level security;

revoke all on table public.document_storage_mutation_permits,
  public.document_storage_mutation_permit_events
from public, anon, authenticated, service_role;

create function public.protect_document_storage_mutation_permit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501',
      message = 'Un permis de mutation Storage ne peut pas être supprimé.';
  end if;

  if (new.id, new.operation_id, new.target_id, new.permit_scope,
      new.mutation_phase, new.workflow, new.storage_action, new.bucket_id,
      new.object_path, new.expected_exists, new.expected_object_id,
      new.expected_object_version, new.operation_revision,
      new.target_revision, new.backup_id, new.backup_revision,
      new.backup_required, new.authorizing_subject_id, new.authorizer_kind,
      new.client_request_id, new.intention_hash, new.issued_at,
      new.expires_at, new.evidence_required)
     is distinct from
     (old.id, old.operation_id, old.target_id, old.permit_scope,
      old.mutation_phase, old.workflow, old.storage_action, old.bucket_id,
      old.object_path, old.expected_exists, old.expected_object_id,
      old.expected_object_version, old.operation_revision,
      old.target_revision, old.backup_id, old.backup_revision,
      old.backup_required, old.authorizing_subject_id, old.authorizer_kind,
      old.client_request_id, old.intention_hash, old.issued_at,
      old.expires_at, old.evidence_required) then
    raise exception using errcode = '42501',
      message = 'Le contexte immuable du permis ne peut pas être modifié.';
  end if;

  if old.state <> 'issued' or new.state not in (
      'issued', 'consumed', 'expired', 'cancelled'
    ) or new.row_revision <> old.row_revision + 1 then
    raise exception using errcode = 'P4G06',
      message = 'Transition de permis invalide.';
  end if;

  if new.state = 'issued' then
    if new.evidence_recorded_at is null
       or new.evidence_recorded_at is not distinct from old.evidence_recorded_at
       or new.consumed_at is not null or new.cancelled_at is not null
       or new.expired_at is not null then
      raise exception using errcode = 'P4G06',
        message = 'Mise à jour de preuve physique invalide.';
    end if;
  elsif new.state = 'consumed' then
    if new.consumed_at is null or new.cancelled_at is not null
       or new.expired_at is not null then
      raise exception using errcode = 'P4G06',
        message = 'Consommation de permis invalide.';
    end if;
  elsif new.state = 'cancelled' then
    if new.cancelled_at is null or new.consumed_at is not null
       or new.expired_at is not null then
      raise exception using errcode = 'P4G06',
        message = 'Annulation de permis invalide.';
    end if;
  elsif new.state = 'expired' and (
      new.expired_at is null or new.consumed_at is not null
      or new.cancelled_at is not null) then
    raise exception using errcode = 'P4G06',
      message = 'Expiration de permis invalide.';
  end if;

  return new;
end;
$$;

create trigger document_storage_mutation_permits_protected
before update or delete on public.document_storage_mutation_permits
for each row execute function public.protect_document_storage_mutation_permit();

create function public.protect_document_storage_mutation_permit_event()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using errcode = '42501',
    message = 'Les lignes d’audit sont immuables.';
end;
$$;

create trigger document_storage_mutation_permit_events_append_only
before update or delete on public.document_storage_mutation_permit_events
for each row execute function public.protect_document_storage_mutation_permit_event();

create function public.append_document_storage_mutation_permit_event(
  p_permit_id uuid,
  p_event_type text,
  p_actor_subject_id uuid,
  p_actor_kind text,
  p_observed_object_id uuid default null,
  p_observed_object_version text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_sequence bigint;
begin
  select coalesce(max(event.sequence_number), 0) + 1
  into next_sequence
  from public.document_storage_mutation_permit_events event
  where event.permit_id = p_permit_id;

  insert into public.document_storage_mutation_permit_events(
    permit_id, sequence_number, event_type, actor_subject_id, actor_kind,
    observed_object_id, observed_object_version
  ) values (
    p_permit_id, next_sequence, p_event_type, p_actor_subject_id, p_actor_kind,
    p_observed_object_id, p_observed_object_version
  );
end;
$$;

create function public.resolve_document_operation_backup_storage_path(
  p_bucket_id text,
  p_object_path text
)
returns table (
  is_canonical boolean,
  operation_id uuid,
  target_id uuid,
  backup_id uuid,
  backup_state text,
  backup_revision bigint,
  recovery_object_id uuid,
  recovery_object_version text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  path_match text[];
  uuid_pattern constant text :=
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  backup_row public.document_operation_backups%rowtype;
begin
  is_canonical := false;
  operation_id := null;
  target_id := null;
  backup_id := null;
  backup_state := null;
  backup_revision := null;
  recovery_object_id := null;
  recovery_object_version := null;

  if p_bucket_id <> 'document-operation-backups' then
    return next;
    return;
  end if;

  path_match := pg_catalog.regexp_match(
    p_object_path,
    '^operations/(' || uuid_pattern || ')/targets/(' || uuid_pattern ||
      ')/backup$'
  );
  if path_match is null then
    return next;
    return;
  end if;

  select * into backup_row
  from public.document_operation_backups backup
  where backup.operation_id = path_match[1]::uuid
    and backup.target_id = path_match[2]::uuid
    and backup.recovery_object_path = p_object_path;

  if not found then
    return next;
    return;
  end if;

  is_canonical := true;
  operation_id := backup_row.operation_id;
  target_id := backup_row.target_id;
  backup_id := backup_row.id;
  backup_state := backup_row.state;
  backup_revision := backup_row.row_revision;
  recovery_object_id := backup_row.recovery_object_id;
  recovery_object_version := backup_row.recovery_object_version;
  return next;
end;
$$;

create function public.document_storage_mutation_permit_intention_hash(
  p_operation_id uuid,
  p_target_id uuid,
  p_permit_scope text,
  p_mutation_phase text,
  p_workflow text,
  p_storage_action text,
  p_bucket_id text,
  p_object_path text,
  p_expected_exists boolean,
  p_expected_object_id uuid,
  p_expected_object_version text,
  p_operation_revision bigint,
  p_target_revision bigint,
  p_backup_id uuid,
  p_backup_revision bigint
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select encode(extensions.digest(
    jsonb_build_object(
      'operationId', p_operation_id,
      'targetId', p_target_id,
      'scope', p_permit_scope,
      'phase', p_mutation_phase,
      'workflow', p_workflow,
      'action', p_storage_action,
      'bucketId', p_bucket_id,
      'objectPath', p_object_path,
      'expectedExists', p_expected_exists,
      'expectedObjectId', p_expected_object_id,
      'expectedObjectVersion', p_expected_object_version,
      'operationRevision', p_operation_revision,
      'targetRevision', p_target_revision,
      'backupId', p_backup_id,
      'backupRevision', p_backup_revision
    )::text,
    'sha256'
  ), 'hex');
$$;

create function public.expire_document_storage_mutation_permits(
  p_bucket_id text,
  p_object_path text,
  p_before timestamptz default clock_timestamp()
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  permit_row public.document_storage_mutation_permits%rowtype;
  expired_count bigint := 0;
begin
  for permit_row in
    select * from public.document_storage_mutation_permits permit
    where permit.state = 'issued'
      and permit.bucket_id = p_bucket_id
      and permit.object_path = p_object_path
      and permit.expires_at <= p_before
    order by permit.id
    for update
  loop
    update public.document_storage_mutation_permits
    set state = 'expired', expired_at = clock_timestamp(),
        row_revision = row_revision + 1
    where id = permit_row.id;
    perform public.append_document_storage_mutation_permit_event(
      permit_row.id, 'expired', null, 'system'
    );
    expired_count := expired_count + 1;
  end loop;
  return expired_count;
end;
$$;

create function public.issue_document_storage_mutation_permit(
  p_operation_id uuid,
  p_target_id uuid,
  p_client_request_id uuid,
  p_expected_operation_revision bigint,
  p_expected_target_revision bigint,
  p_expected_backup_revision bigint default null
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
  permit_row public.document_storage_mutation_permits%rowtype;
  mutation_phase_value text;
  action_value text;
  expected_exists_value boolean;
  expected_object_id_value uuid;
  expected_object_version_value text;
  backup_required_value boolean;
  intention_hash_value text;
  permit_inserted boolean := false;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Accès privilégié requis.';
  end if;
  if p_operation_id is null or p_target_id is null or p_client_request_id is null
     or p_expected_operation_revision is null
     or p_expected_target_revision is null then
    raise exception using errcode = 'P4G01', message = 'Demande de permis invalide.';
  end if;

  select * into operation_row
  from public.document_operations operation
  where operation.id = p_operation_id for update;
  select * into target_row
  from public.document_operation_targets target
  where target.id = p_target_id and target.operation_id = p_operation_id
  for update;
  if operation_row.id is null or target_row.id is null
     or operation_row.row_revision is distinct from p_expected_operation_revision
     or target_row.target_revision is distinct from p_expected_target_revision then
    raise exception using errcode = 'P4G02',
      message = 'Le contexte documentaire ou sa révision a changé.';
  end if;
  if operation_row.initiated_by is null then
    raise exception using errcode = 'P4G03',
      message = 'L’autorité métier du permis est absente.';
  end if;
  if not exists (
    select 1 from public.document_object_locks object_lock
    where object_lock.operation_id = operation_row.id
      and object_lock.target_id = target_row.id
      and object_lock.bucket_id = target_row.bucket_id
      and object_lock.object_path = target_row.object_path
  ) then
    raise exception using errcode = 'P4G02',
      message = 'Le verrou documentaire autoritatif est absent.';
  end if;

  if operation_row.state = 'executing'
     and target_row.application_state = 'pending' then
    mutation_phase_value := 'forward';
    action_value := target_row.forward_action;
    expected_exists_value := target_row.expected_exists;
    expected_object_id_value := target_row.expected_object_id;
    expected_object_version_value := target_row.expected_object_version;
  elsif operation_row.state = 'compensating'
        and target_row.application_state = 'compensating' then
    mutation_phase_value := 'compensation';
    action_value := target_row.compensation_action;
    expected_exists_value := target_row.compensation_expected_exists;
    expected_object_id_value := target_row.compensation_expected_object_id;
    expected_object_version_value := target_row.compensation_expected_object_version;
  else
    raise exception using errcode = 'P4G02',
      message = 'La cible n’autorise aucune mutation Storage.';
  end if;
  if action_value is null or expected_exists_value is null then
    raise exception using errcode = 'P4G02',
      message = 'L’intention Storage autoritative est incomplète.';
  end if;

  select * into object_row from storage.objects object
  where object.bucket_id = target_row.bucket_id
    and object.name = target_row.object_path
  for key share;
  if expected_exists_value then
    if not found or object_row.id is distinct from expected_object_id_value
       or object_row.version is distinct from expected_object_version_value then
      raise exception using errcode = 'P4S04',
        message = 'L’objet Storage a changé depuis la réservation.';
    end if;
  elsif found then
    raise exception using errcode = 'P4S04',
      message = 'Le chemin Storage n’est plus libre.';
  end if;

  backup_required_value := action_value in ('update', 'delete')
    and not (mutation_phase_value = 'compensation'
      and target_row.compensation_action = 'delete');
  if backup_required_value then
    select * into backup_row
    from public.document_operation_backups backup
    where backup.operation_id = operation_row.id
      and backup.target_id = target_row.id
    for update;
    if not found or backup_row.state not in ('verified', 'restored')
       or backup_row.row_revision is distinct from p_expected_backup_revision
       or backup_row.original_bucket_id is distinct from target_row.bucket_id
       or backup_row.original_object_path is distinct from target_row.object_path then
      raise exception using errcode = 'P4G04',
        message = 'La sauvegarde durable vérifiée est absente ou obsolète.';
    end if;
    if not exists (
      select 1 from storage.objects object
      where object.bucket_id = 'document-operation-backups'
        and object.name = backup_row.recovery_object_path
        and object.id = backup_row.recovery_object_id
        and object.version = backup_row.recovery_object_version
    ) then
      raise exception using errcode = 'P4G04',
        message = 'La sauvegarde durable n’est plus présente dans le catalogue.';
    end if;
  elsif p_expected_backup_revision is not null then
    raise exception using errcode = 'P4G01',
      message = 'Une révision de sauvegarde inattendue a été fournie.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_row.bucket_id || chr(31) || target_row.object_path, 0)
  );
  perform public.expire_document_storage_mutation_permits(
    target_row.bucket_id, target_row.object_path, clock_timestamp()
  );

  intention_hash_value := public.document_storage_mutation_permit_intention_hash(
    operation_row.id, target_row.id, 'document', mutation_phase_value,
    operation_row.workflow, action_value, target_row.bucket_id,
    target_row.object_path, expected_exists_value, expected_object_id_value,
    expected_object_version_value, operation_row.row_revision,
    target_row.target_revision, backup_row.id, backup_row.row_revision
  );

  insert into public.document_storage_mutation_permits(
    operation_id, target_id, permit_scope, mutation_phase, workflow,
    storage_action, bucket_id, object_path, expected_exists,
    expected_object_id, expected_object_version, operation_revision,
    target_revision, backup_id, backup_revision, backup_required,
    authorizing_subject_id, authorizer_kind, client_request_id,
    intention_hash, expires_at, evidence_required
  ) values (
    operation_row.id, target_row.id, 'document', mutation_phase_value,
    operation_row.workflow, action_value, target_row.bucket_id,
    target_row.object_path, expected_exists_value, expected_object_id_value,
    expected_object_version_value, operation_row.row_revision,
    target_row.target_revision, backup_row.id, backup_row.row_revision,
    backup_required_value, operation_row.initiated_by,
    operation_row.initiator_kind, p_client_request_id,
    intention_hash_value, clock_timestamp() + interval '2 minutes',
    action_value in ('update', 'delete')
  )
  on conflict (operation_id, client_request_id) do nothing
  returning * into permit_row;

  if permit_row.id is null then
    select * into permit_row
    from public.document_storage_mutation_permits permit
    where permit.operation_id = operation_row.id
      and permit.client_request_id = p_client_request_id;
    if permit_row.intention_hash is distinct from intention_hash_value then
      raise exception using errcode = 'P4G05',
        message = 'La clé d’idempotence est déjà utilisée pour une autre mutation.';
    end if;
  else
    permit_inserted := true;
    perform public.append_document_storage_mutation_permit_event(
      permit_row.id, 'issued', permit_row.authorizing_subject_id,
      permit_row.authorizer_kind
    );
  end if;

  return jsonb_build_object(
    'permitId', permit_row.id,
    'state', permit_row.state,
    'revision', permit_row.row_revision,
    'expiresAt', permit_row.expires_at,
    'idempotent', not permit_inserted
  );
exception
  when unique_violation then
    raise exception using errcode = 'P4G05',
      message = 'Un permis existe déjà pour cette cible ou ce chemin.';
end;
$$;

create function public.issue_document_backup_storage_mutation_permit(
  p_backup_id uuid,
  p_intent text,
  p_client_request_id uuid,
  p_expected_operation_revision bigint,
  p_expected_target_revision bigint,
  p_expected_backup_revision bigint
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
  backup_object storage.objects%rowtype;
  permit_row public.document_storage_mutation_permits%rowtype;
  action_value text;
  expected_exists_value boolean;
  intention_hash_value text;
  permit_inserted boolean := false;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Accès privilégié requis.';
  end if;
  if p_intent not in ('upload', 'cleanup') or p_client_request_id is null then
    raise exception using errcode = 'P4G01', message = 'Demande de permis invalide.';
  end if;

  select * into backup_row from public.document_operation_backups backup
  where backup.id = p_backup_id for update;
  select * into operation_row from public.document_operations operation
  where operation.id = backup_row.operation_id for update;
  select * into target_row from public.document_operation_targets target
  where target.id = backup_row.target_id
    and target.operation_id = backup_row.operation_id for update;
  if backup_row.id is null or operation_row.id is null or target_row.id is null
     or operation_row.initiated_by is null
     or operation_row.row_revision is distinct from p_expected_operation_revision
     or target_row.target_revision is distinct from p_expected_target_revision
     or backup_row.row_revision is distinct from p_expected_backup_revision then
    raise exception using errcode = 'P4G02',
      message = 'Le contexte de sauvegarde ou sa révision a changé.';
  end if;
  if not exists (
    select 1 from public.document_object_locks object_lock
    where object_lock.operation_id = operation_row.id
      and object_lock.target_id = target_row.id
  ) and operation_row.state not in (
    'completed', 'compensated', 'cancelled', 'administratively_resolved'
  ) then
    raise exception using errcode = 'P4G02',
      message = 'Le verrou documentaire autoritatif est absent.';
  end if;

  select * into backup_object from storage.objects object
  where object.bucket_id = 'document-operation-backups'
    and object.name = backup_row.recovery_object_path
  for key share;

  if p_intent = 'upload' then
    if operation_row.state not in ('reserved', 'executing')
       or target_row.application_state <> 'pending'
       or backup_row.state <> 'upload_pending'
       or backup_row.recovery_object_id is not null or found then
      raise exception using errcode = 'P4G02',
        message = 'La sauvegarde n’autorise aucun téléversement.';
    end if;
    action_value := 'insert';
    expected_exists_value := false;
  else
    if operation_row.state not in (
         'completed', 'compensated', 'cancelled', 'administratively_resolved'
       ) or backup_row.state not in ('verified', 'restored')
       or not found
       or backup_object.id is distinct from backup_row.recovery_object_id
       or backup_object.version is distinct from backup_row.recovery_object_version then
      raise exception using errcode = 'P4G07',
        message = 'La sauvegarde constitue encore une copie nécessaire ou a changé.';
    end if;
    if operation_row.state in ('compensated', 'cancelled', 'administratively_resolved') then
      perform 1 from storage.objects object
      where object.bucket_id = backup_row.original_bucket_id
        and object.name = backup_row.original_object_path
      for key share;
      if not found or backup_row.state <> 'restored' then
        raise exception using errcode = 'P4G07',
          message = 'La sauvegarde constitue encore la dernière copie récupérable.';
      end if;
    end if;
    action_value := 'delete';
    expected_exists_value := true;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'document-operation-backups' || chr(31) || backup_row.recovery_object_path,
      0
    )
  );
  perform public.expire_document_storage_mutation_permits(
    'document-operation-backups', backup_row.recovery_object_path,
    clock_timestamp()
  );

  intention_hash_value := public.document_storage_mutation_permit_intention_hash(
    operation_row.id, target_row.id, 'backup',
    case p_intent when 'upload' then 'backup_upload' else 'backup_cleanup' end,
    operation_row.workflow, action_value, 'document-operation-backups',
    backup_row.recovery_object_path, expected_exists_value,
    case when expected_exists_value then backup_object.id end,
    case when expected_exists_value then backup_object.version end,
    operation_row.row_revision, target_row.target_revision,
    backup_row.id, backup_row.row_revision
  );

  insert into public.document_storage_mutation_permits(
    operation_id, target_id, permit_scope, mutation_phase, workflow,
    storage_action, bucket_id, object_path, expected_exists,
    expected_object_id, expected_object_version, operation_revision,
    target_revision, backup_id, backup_revision, backup_required,
    authorizing_subject_id, authorizer_kind, client_request_id,
    intention_hash, expires_at, evidence_required
  ) values (
    operation_row.id, target_row.id, 'backup',
    case p_intent when 'upload' then 'backup_upload' else 'backup_cleanup' end,
    operation_row.workflow, action_value, 'document-operation-backups',
    backup_row.recovery_object_path, expected_exists_value,
    case when expected_exists_value then backup_object.id end,
    case when expected_exists_value then backup_object.version end,
    operation_row.row_revision, target_row.target_revision,
    backup_row.id, backup_row.row_revision, false,
    operation_row.initiated_by, operation_row.initiator_kind,
    p_client_request_id, intention_hash_value,
    clock_timestamp() + interval '2 minutes', action_value = 'delete'
  )
  on conflict (operation_id, client_request_id) do nothing
  returning * into permit_row;

  if permit_row.id is null then
    select * into permit_row from public.document_storage_mutation_permits permit
    where permit.operation_id = operation_row.id
      and permit.client_request_id = p_client_request_id;
    if permit_row.intention_hash is distinct from intention_hash_value then
      raise exception using errcode = 'P4G05',
        message = 'La clé d’idempotence est déjà utilisée pour une autre mutation.';
    end if;
  else
    permit_inserted := true;
    perform public.append_document_storage_mutation_permit_event(
      permit_row.id, 'issued', permit_row.authorizing_subject_id,
      permit_row.authorizer_kind
    );
  end if;

  return jsonb_build_object(
    'permitId', permit_row.id,
    'state', permit_row.state,
    'revision', permit_row.row_revision,
    'expiresAt', permit_row.expires_at,
    'idempotent', not permit_inserted
  );
exception
  when unique_violation then
    raise exception using errcode = 'P4G05',
      message = 'Un permis existe déjà pour cette cible ou ce chemin.';
end;
$$;

create function public.record_document_storage_mutation_permit_evidence(
  p_permit_id uuid,
  p_expected_revision bigint,
  p_observed_object_id uuid,
  p_observed_object_version text,
  p_observed_byte_size bigint,
  p_observed_sha256 text,
  p_observed_backup_object_id uuid default null,
  p_observed_backup_object_version text default null,
  p_observed_backup_byte_size bigint default null,
  p_observed_backup_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  permit_row public.document_storage_mutation_permits%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Accès privilégié requis.';
  end if;
  select * into permit_row from public.document_storage_mutation_permits permit
  where permit.id = p_permit_id for update;
  if not found or permit_row.state <> 'issued'
     or permit_row.row_revision <> p_expected_revision
     or permit_row.expires_at <= clock_timestamp()
     or not permit_row.evidence_required then
    raise exception using errcode = 'P4G06',
      message = 'Le permis ne peut pas recevoir cette preuve physique.';
  end if;
  if p_observed_object_id is distinct from permit_row.expected_object_id
     or p_observed_object_version is distinct from permit_row.expected_object_version
     or p_observed_byte_size is null or p_observed_byte_size < 0
     or p_observed_sha256 is null or p_observed_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P4G08',
      message = 'La preuve physique de la cible est divergente.';
  end if;

  if permit_row.backup_required then
    select * into backup_row from public.document_operation_backups backup
    where backup.id = permit_row.backup_id for update;
    if not found or backup_row.row_revision is distinct from permit_row.backup_revision
       or backup_row.state not in ('verified', 'restored')
       or p_observed_backup_object_id is distinct from backup_row.recovery_object_id
       or p_observed_backup_object_version is distinct from backup_row.recovery_object_version
       or p_observed_backup_byte_size is distinct from backup_row.byte_size
       or p_observed_backup_sha256 is distinct from backup_row.sha256 then
      raise exception using errcode = 'P4G08',
        message = 'La preuve physique de la sauvegarde est divergente.';
    end if;
    if not exists (
      select 1 from storage.objects object
      where object.bucket_id = 'document-operation-backups'
        and object.name = backup_row.recovery_object_path
        and object.id = p_observed_backup_object_id
        and object.version = p_observed_backup_object_version
    ) then
      raise exception using errcode = 'P4G08',
        message = 'La sauvegarde observée n’existe plus dans le catalogue.';
    end if;
    if permit_row.mutation_phase = 'forward'
       and (p_observed_byte_size is distinct from backup_row.byte_size
         or p_observed_sha256 is distinct from backup_row.sha256) then
      raise exception using errcode = 'P4G08',
        message = 'La cible ne correspond plus à la sauvegarde vérifiée.';
    end if;
  elsif permit_row.permit_scope = 'backup' then
    select * into backup_row from public.document_operation_backups backup
    where backup.id = permit_row.backup_id for update;
    if not found or p_observed_byte_size is distinct from backup_row.byte_size
       or p_observed_sha256 is distinct from backup_row.sha256 then
      raise exception using errcode = 'P4G08',
        message = 'La preuve physique de la sauvegarde est divergente.';
    end if;
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = permit_row.bucket_id
      and object.name = permit_row.object_path
      and object.id = p_observed_object_id
      and object.version = p_observed_object_version
  ) then
    raise exception using errcode = 'P4G08',
      message = 'La cible observée n’existe plus dans le catalogue.';
  end if;

  update public.document_storage_mutation_permits
  set evidence_recorded_at = clock_timestamp(),
      observed_object_id = p_observed_object_id,
      observed_object_version = p_observed_object_version,
      observed_byte_size = p_observed_byte_size,
      observed_sha256 = p_observed_sha256,
      observed_backup_object_id = p_observed_backup_object_id,
      observed_backup_object_version = p_observed_backup_object_version,
      observed_backup_byte_size = p_observed_backup_byte_size,
      observed_backup_sha256 = p_observed_backup_sha256,
      row_revision = row_revision + 1
  where id = permit_row.id returning * into permit_row;

  perform public.append_document_storage_mutation_permit_event(
    permit_row.id, 'physical_evidence_recorded',
    permit_row.authorizing_subject_id, permit_row.authorizer_kind,
    p_observed_object_id, p_observed_object_version
  );
  return jsonb_build_object(
    'permitId', permit_row.id, 'state', permit_row.state,
    'revision', permit_row.row_revision,
    'evidenceRecordedAt', permit_row.evidence_recorded_at
  );
end;
$$;

create function public.consume_document_storage_mutation_permit(
  p_permit_id uuid,
  p_expected_revision bigint,
  p_bucket_id text,
  p_object_path text,
  p_sql_operation text,
  p_existing_object_id uuid default null,
  p_existing_object_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  permit_row public.document_storage_mutation_permits%rowtype;
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
  effective_action text;
begin
  select * into permit_row from public.document_storage_mutation_permits permit
  where permit.id = p_permit_id for update;
  if not found then
    raise exception using errcode = 'P4G02', message = 'Permis Storage introuvable.';
  end if;
  if permit_row.state <> 'issued' or permit_row.row_revision <> p_expected_revision then
    raise exception using errcode = 'P4G06',
      message = 'Le permis Storage est déjà consommé ou a changé.';
  end if;
  if permit_row.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P4G06', message = 'Le permis Storage a expiré.';
  end if;

  effective_action := case upper(p_sql_operation)
    when 'INSERT' then case when p_existing_object_id is null then 'insert' else 'update' end
    when 'UPDATE' then 'update'
    when 'DELETE' then 'delete'
    else null
  end;
  if permit_row.bucket_id is distinct from p_bucket_id
     or permit_row.object_path is distinct from p_object_path
     or permit_row.storage_action is distinct from effective_action
     or permit_row.expected_object_id is distinct from p_existing_object_id
     or permit_row.expected_object_version is distinct from p_existing_object_version then
    raise exception using errcode = 'P4G03',
      message = 'La mutation ne correspond pas au permis exact.';
  end if;

  select * into operation_row from public.document_operations operation
  where operation.id = permit_row.operation_id for update;
  select * into target_row from public.document_operation_targets target
  where target.id = permit_row.target_id
    and target.operation_id = permit_row.operation_id for update;
  if operation_row.row_revision is distinct from permit_row.operation_revision
     or target_row.target_revision is distinct from permit_row.target_revision then
    raise exception using errcode = 'P4G02',
      message = 'Le plan documentaire a changé depuis l’émission du permis.';
  end if;
  if not exists (
    select 1 from public.document_object_locks object_lock
    where object_lock.operation_id = permit_row.operation_id
      and object_lock.target_id = permit_row.target_id
  ) and operation_row.state not in (
    'completed', 'compensated', 'cancelled', 'administratively_resolved'
  ) then
    raise exception using errcode = 'P4G02',
      message = 'Le verrou documentaire n’est plus détenu.';
  end if;

  if permit_row.backup_id is not null then
    select * into backup_row from public.document_operation_backups backup
    where backup.id = permit_row.backup_id for update;
    if not found or backup_row.row_revision is distinct from permit_row.backup_revision then
      raise exception using errcode = 'P4G04',
        message = 'La sauvegarde liée au permis a changé.';
    end if;
  end if;
  if permit_row.evidence_required and (
      permit_row.evidence_recorded_at is null
      or permit_row.evidence_recorded_at < clock_timestamp() - interval '30 seconds'
    ) then
    raise exception using errcode = 'P4G08',
      message = 'Une preuve physique récente est requise.';
  end if;

  update public.document_storage_mutation_permits
  set state = 'consumed', consumed_at = clock_timestamp(),
      consumed_existing_object_id = p_existing_object_id,
      consumed_existing_object_version = p_existing_object_version,
      row_revision = row_revision + 1
  where id = permit_row.id returning * into permit_row;
  perform public.append_document_storage_mutation_permit_event(
    permit_row.id, 'consumed', permit_row.authorizing_subject_id,
    permit_row.authorizer_kind, p_existing_object_id,
    p_existing_object_version
  );
  return jsonb_build_object(
    'permitId', permit_row.id, 'state', permit_row.state,
    'revision', permit_row.row_revision,
    'physicalMutationConfirmed', false
  );
end;
$$;

create function public.cancel_document_storage_mutation_permit(
  p_permit_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare permit_row public.document_storage_mutation_permits%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Accès privilégié requis.';
  end if;
  select * into permit_row from public.document_storage_mutation_permits permit
  where permit.id = p_permit_id for update;
  if not found or permit_row.state <> 'issued'
     or permit_row.row_revision <> p_expected_revision then
    raise exception using errcode = 'P4G06',
      message = 'Le permis ne peut pas être annulé.';
  end if;
  update public.document_storage_mutation_permits
  set state = 'cancelled', cancelled_at = clock_timestamp(),
      row_revision = row_revision + 1
  where id = permit_row.id returning * into permit_row;
  perform public.append_document_storage_mutation_permit_event(
    permit_row.id, 'cancelled', permit_row.authorizing_subject_id,
    permit_row.authorizer_kind
  );
  return jsonb_build_object(
    'permitId', permit_row.id, 'state', permit_row.state,
    'revision', permit_row.row_revision
  );
end;
$$;

create function public.get_document_storage_mutation_permit_for_service(
  p_permit_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare permit_row public.document_storage_mutation_permits%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Accès privilégié requis.';
  end if;
  select * into permit_row from public.document_storage_mutation_permits permit
  where permit.id = p_permit_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'permitId', permit_row.id,
    'operationId', permit_row.operation_id,
    'targetId', permit_row.target_id,
    'scope', permit_row.permit_scope,
    'phase', permit_row.mutation_phase,
    'action', permit_row.storage_action,
    'bucketId', permit_row.bucket_id,
    'objectPath', permit_row.object_path,
    'expectedObjectId', permit_row.expected_object_id,
    'expectedObjectVersion', permit_row.expected_object_version,
    'state', case
      when permit_row.state = 'issued' and permit_row.expires_at <= clock_timestamp()
        then 'expired'
      else permit_row.state
    end,
    'revision', permit_row.row_revision,
    'expiresAt', permit_row.expires_at,
    'evidenceRequired', permit_row.evidence_required,
    'evidenceRecordedAt', permit_row.evidence_recorded_at,
    'physicalMutationConfirmed', false
  );
end;
$$;

revoke all on function
  public.protect_document_storage_mutation_permit(),
  public.protect_document_storage_mutation_permit_event(),
  public.append_document_storage_mutation_permit_event(uuid,text,uuid,text,uuid,text),
  public.resolve_document_operation_backup_storage_path(text,text),
  public.document_storage_mutation_permit_intention_hash(uuid,uuid,text,text,text,text,text,text,boolean,uuid,text,bigint,bigint,uuid,bigint),
  public.expire_document_storage_mutation_permits(text,text,timestamptz),
  public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint),
  public.issue_document_backup_storage_mutation_permit(uuid,text,uuid,bigint,bigint,bigint),
  public.record_document_storage_mutation_permit_evidence(uuid,bigint,uuid,text,bigint,text,uuid,text,bigint,text),
  public.consume_document_storage_mutation_permit(uuid,bigint,text,text,text,uuid,text),
  public.cancel_document_storage_mutation_permit(uuid,bigint),
  public.get_document_storage_mutation_permit_for_service(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint),
  public.issue_document_backup_storage_mutation_permit(uuid,text,uuid,bigint,bigint,bigint),
  public.record_document_storage_mutation_permit_evidence(uuid,bigint,uuid,text,bigint,text,uuid,text,bigint,text),
  public.cancel_document_storage_mutation_permit(uuid,bigint),
  public.get_document_storage_mutation_permit_for_service(uuid)
to service_role;

comment on table public.document_storage_mutation_permits is
  'Permis privés et consommables de mutation Storage ; leur consommation ne prouve jamais le résultat physique.';
comment on function public.consume_document_storage_mutation_permit(uuid,bigint,text,text,text,uuid,text) is
  'Primitive interne exigeant un identifiant exact ; aucun trigger Storage ne l’appelle encore.';
comment on function public.resolve_document_operation_backup_storage_path(text,text) is
  'Résout strictement un chemin de sauvegarde déjà enregistré, sans transformer les chemins historiques.';
