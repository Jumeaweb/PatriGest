-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C4B2
-- Transitions de sauvegarde strictement nécessaires au moteur physique de
-- réparation administrative. Aucune mutation Storage n'est effectuée ici.

create or replace function public.get_administrative_document_repair_authorization(
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
      message = 'Consultation de la réparation non autorisée.';
  end if;
  select * into authorization_row
  from public.document_repair_authorizations repair_authorization
  where repair_authorization.operation_id = p_operation_id
    and repair_authorization.attempt_id = p_attempt_id
    and repair_authorization.administrator_subject_id = caller_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'operationId', authorization_row.operation_id,
    'administratorSubjectId', authorization_row.administrator_subject_id,
    'attemptId', authorization_row.attempt_id,
    'reason', authorization_row.reason,
    'repairPlan', authorization_row.repair_plan,
    'planHash', authorization_row.repair_plan_hash,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision,
    'expiresAt', public.document_repair_effective_expires_at(authorization_row),
    'renewalCount', authorization_row.renewal_count
  );
end;
$$;

create function public.mark_administrative_document_repair_backup_restored(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_execution_id uuid,
  p_expected_item_revision bigint,
  p_expected_backup_revision bigint
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
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  select * into item_row from public.document_repair_items item
  where item.id = p_item_id and item.authorization_id = authorization_row.id
  for update;
  if not found or item_row.action not in ('restore_original', 'resume_compensation')
     or item_row.progress_state <> 'executing'
     or item_row.execution_id is distinct from p_execution_id
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R05',
      message = 'La restauration ne correspond pas au plan de réparation.';
  end if;
  select * into target_row from public.document_operation_targets target
  where target.id = item_row.target_id
    and target.operation_id = authorization_row.operation_id for update;
  select * into backup_row from public.document_operation_backups backup
  where backup.id = item_row.backup_id
    and backup.operation_id = authorization_row.operation_id
    and backup.target_id = item_row.target_id for update;
  if target_row.id is null or backup_row.id is null
     or backup_row.row_revision is distinct from p_expected_backup_revision
     or backup_row.state not in ('verified', 'restored')
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id = target_row.bucket_id
         and object.name = target_row.object_path
         and object.version is not null and btrim(object.version) <> ''
     )
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id = 'document-operation-backups'
         and object.name = backup_row.recovery_object_path
         and object.id = backup_row.recovery_object_id
         and object.version = backup_row.recovery_object_version
     ) then
    raise exception using errcode = 'P4R07',
      message = 'La restauration physique ne peut pas être confirmée.';
  end if;
  if backup_row.state = 'verified' then
    update public.document_operation_backups
    set state = 'restored', restored_at = clock_timestamp(),
        last_activity_at = clock_timestamp(), row_revision = row_revision + 1
    where id = backup_row.id returning * into backup_row;
  end if;
  return jsonb_build_object(
    'backupId', backup_row.id, 'state', backup_row.state,
    'revision', backup_row.row_revision
  );
end;
$$;

create function public.authorize_administrative_document_repair_backup_cleanup(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_execution_id uuid,
  p_expected_item_revision bigint,
  p_expected_backup_revision bigint
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
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  select * into item_row from public.document_repair_items item
  where item.id = p_item_id and item.authorization_id = authorization_row.id
  for update;
  if not found or item_row.action <> 'complete_backup_cleanup'
     or item_row.progress_state <> 'executing'
     or item_row.execution_id is distinct from p_execution_id
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R05',
      message = 'Le nettoyage ne correspond pas au plan de réparation.';
  end if;
  select * into target_row from public.document_operation_targets target
  where target.id = item_row.target_id
    and target.operation_id = authorization_row.operation_id for update;
  select * into backup_row from public.document_operation_backups backup
  where backup.id = item_row.backup_id
    and backup.operation_id = authorization_row.operation_id
    and backup.target_id = item_row.target_id for update;
  if target_row.id is null or backup_row.id is null
     or backup_row.row_revision is distinct from p_expected_backup_revision
     or backup_row.state not in ('verified', 'restored', 'deleted')
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id = target_row.bucket_id
         and object.name = target_row.object_path
         and object.version is not null and btrim(object.version) <> ''
     ) then
    raise exception using errcode = 'P4R07',
      message = 'Le nettoyage de sauvegarde n’est pas sûr.';
  end if;
  return jsonb_build_object(
    'backupId', backup_row.id,
    'bucketId', 'document-operation-backups',
    'objectPath', backup_row.recovery_object_path,
    'objectId', backup_row.recovery_object_id,
    'objectVersion', backup_row.recovery_object_version,
    'byteSize', backup_row.byte_size,
    'mimeType', backup_row.mime_type,
    'sha256', backup_row.sha256,
    'state', backup_row.state,
    'revision', backup_row.row_revision
  );
end;
$$;

create function public.complete_administrative_document_repair_backup_cleanup(
  p_authorization_id uuid,
  p_item_id uuid,
  p_administrator_subject_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_execution_id uuid,
  p_expected_item_revision bigint,
  p_expected_backup_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  item_row public.document_repair_items%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  authorization_row := public.assert_document_repair_runtime_context(
    p_authorization_id, p_administrator_subject_id, p_attempt_id,
    p_expected_plan_hash, true
  );
  select * into item_row from public.document_repair_items item
  where item.id = p_item_id and item.authorization_id = authorization_row.id
  for update;
  if not found or item_row.action <> 'complete_backup_cleanup'
     or item_row.progress_state <> 'executing'
     or item_row.execution_id is distinct from p_execution_id
     or item_row.row_revision is distinct from p_expected_item_revision then
    raise exception using errcode = 'P4R05',
      message = 'Le nettoyage ne correspond pas au plan de réparation.';
  end if;
  select * into backup_row from public.document_operation_backups backup
  where backup.id = item_row.backup_id
    and backup.operation_id = authorization_row.operation_id
    and backup.target_id = item_row.target_id for update;
  if backup_row.id is null
     or backup_row.row_revision is distinct from p_expected_backup_revision
     or backup_row.state not in ('verified', 'restored', 'deleted') then
    raise exception using errcode = 'P4R07',
      message = 'Le nettoyage de sauvegarde a divergé.';
  end if;
  if backup_row.state <> 'deleted' then
    if exists (
      select 1 from storage.objects object
      where object.bucket_id = 'document-operation-backups'
        and object.name = backup_row.recovery_object_path
    ) then
      raise exception using errcode = 'P4R07',
        message = 'La sauvegarde physique existe encore.';
    end if;
    update public.document_operation_backups
    set state = 'deleted', deleted_at = clock_timestamp(),
        last_activity_at = clock_timestamp(), row_revision = row_revision + 1
    where id = backup_row.id returning * into backup_row;
  end if;
  return jsonb_build_object(
    'backupId', backup_row.id, 'state', backup_row.state,
    'revision', backup_row.row_revision
  );
end;
$$;

revoke all on function
  public.get_administrative_document_repair_authorization(uuid,uuid),
  public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint),
  public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint),
  public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_administrative_document_repair_authorization(uuid,uuid)
to authenticated;

grant execute on function
  public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint),
  public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint),
  public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)
to service_role;

comment on function public.get_administrative_document_repair_authorization(uuid,uuid) is
  'Relit uniquement la tentative de réparation de l’administrateur appelant.';
comment on function public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint) is
  'Confirme la transition SQL d’une sauvegarde restaurée sous autorisation de réparation active.';
comment on function public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint) is
  'Délivre le descripteur exact de la seule sauvegarde dont le nettoyage a été approuvé.';
comment on function public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint) is
  'Finalise le registre après disparition vérifiée de la sauvegarde autorisée.';
