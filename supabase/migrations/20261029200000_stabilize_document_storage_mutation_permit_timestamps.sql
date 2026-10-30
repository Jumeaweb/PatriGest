-- PAT-PRODUCTION-03
-- Utilise une référence temporelle unique pour l'émission d'un permis.
-- La durée reste exactement égale à deux minutes.

create or replace function public.issue_document_storage_mutation_permit(
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
  permit_issued_at timestamptz;
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
  permit_issued_at := clock_timestamp();

  insert into public.document_storage_mutation_permits(
    operation_id, target_id, permit_scope, mutation_phase, workflow,
    storage_action, bucket_id, object_path, expected_exists,
    expected_object_id, expected_object_version, operation_revision,
    target_revision, backup_id, backup_revision, backup_required,
    authorizing_subject_id, authorizer_kind, client_request_id,
    intention_hash, issued_at, expires_at, evidence_required
  ) values (
    operation_row.id, target_row.id, 'document', mutation_phase_value,
    operation_row.workflow, action_value, target_row.bucket_id,
    target_row.object_path, expected_exists_value, expected_object_id_value,
    expected_object_version_value, operation_row.row_revision,
    target_row.target_revision, backup_row.id, backup_row.row_revision,
    backup_required_value, operation_row.initiated_by,
    operation_row.initiator_kind, p_client_request_id,
    intention_hash_value, permit_issued_at,
    permit_issued_at + interval '2 minutes',
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

create or replace function public.issue_document_backup_storage_mutation_permit(
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
  permit_issued_at timestamptz;
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
  permit_issued_at := clock_timestamp();

  insert into public.document_storage_mutation_permits(
    operation_id, target_id, permit_scope, mutation_phase, workflow,
    storage_action, bucket_id, object_path, expected_exists,
    expected_object_id, expected_object_version, operation_revision,
    target_revision, backup_id, backup_revision, backup_required,
    authorizing_subject_id, authorizer_kind, client_request_id,
    intention_hash, issued_at, expires_at, evidence_required
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
    p_client_request_id, intention_hash_value, permit_issued_at,
    permit_issued_at + interval '2 minutes', action_value = 'delete'
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

-- CREATE OR REPLACE conserve normalement l'ACL. La révocation est répétée ici
-- pour rendre la fermeture de production explicite après cette correction.
revoke all on function
  public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint),
  public.issue_document_backup_storage_mutation_permit(uuid,text,uuid,bigint,bigint,bigint)
from public, anon, authenticated, service_role;

comment on function
  public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint)
is 'Émet un permis Storage à durée exacte de deux minutes depuis une référence temporelle unique ; fermé aux rôles Data API.';

comment on function
  public.issue_document_backup_storage_mutation_permit(uuid,text,uuid,bigint,bigint,bigint)
is 'Émet un permis Storage de sauvegarde à durée exacte de deux minutes depuis une référence temporelle unique ; fermé aux rôles Data API.';
