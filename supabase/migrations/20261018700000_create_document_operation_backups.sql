-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3C
-- Sauvegardes privées et durables pour les compensations documentaires.
-- La garde Storage et le cycle d'archivage restent désactivés.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'document-operation-backups',
  'document-operation-backups',
  false,
  20971520,
  array['application/pdf', 'image/jpeg', 'image/png']
);

create table public.document_operation_backups (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  target_id uuid not null,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  initiator_subject_id uuid not null,
  original_bucket_id text not null check (original_bucket_id in (
    'transaction-proofs', 'bank-statements', 'management-reports'
  )),
  original_object_path text not null check (
    original_object_path = btrim(original_object_path)
    and original_object_path <> ''
    and position(chr(92) in original_object_path) = 0
    and original_object_path !~ '(^/|(^|/)\.\.(/|$)|//)'
  ),
  original_object_id uuid not null,
  original_object_version text not null check (btrim(original_object_version) <> ''),
  recovery_object_path text not null unique check (
    recovery_object_path ~ '^operations/[0-9a-f-]{36}/targets/[0-9a-f-]{36}/backup$'
  ),
  byte_size bigint not null check (byte_size between 1 and 20971520),
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'upload_pending' check (state in (
    'upload_pending', 'verified', 'restored', 'deleted', 'attention_required'
  )),
  recovery_object_id uuid,
  recovery_object_version text,
  created_at timestamptz not null default clock_timestamp(),
  upload_verified_at timestamptz,
  restored_at timestamptz,
  deleted_at timestamptz,
  last_activity_at timestamptz not null default clock_timestamp(),
  row_revision bigint not null default 0 check (row_revision >= 0),
  safe_error_code text check (
    safe_error_code is null or safe_error_code ~ '^[A-Z0-9_:-]{1,64}$'
  ),
  unique (operation_id, target_id),
  foreign key (target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict,
  check ((recovery_object_id is null) = (recovery_object_version is null)),
  check (recovery_object_version is null or btrim(recovery_object_version) <> ''),
  check ((state = 'upload_pending') = (upload_verified_at is null)),
  check (state <> 'restored' or restored_at is not null),
  check (restored_at is null or state in ('restored','deleted')),
  check ((state = 'deleted') = (deleted_at is not null))
);

create index document_operation_backups_operation_idx
on public.document_operation_backups(operation_id, state);

create index document_operation_backups_reconciliation_idx
on public.document_operation_backups(state, last_activity_at)
where state <> 'deleted';

alter table public.document_operation_backups enable row level security;
revoke all on table public.document_operation_backups
from public, anon, authenticated, service_role;

create trigger document_operation_backups_protected
before update or delete on public.document_operation_backups
for each row execute function public.protect_document_operation_audit_rows();

create function public.reserve_document_operation_backup(
  p_operation_id uuid,
  p_target_id uuid,
  p_byte_size bigint,
  p_mime_type text,
  p_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  backup_row public.document_operation_backups%rowtype;
  expected_path text;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  if p_byte_size not between 1 and 20971520
     or p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png')
     or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P4B02', message='Métadonnées de sauvegarde invalides.';
  end if;

  select * into operation_row from public.document_operations
  where id=p_operation_id for update;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id
     or operation_row.state<>'reserved' then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  perform public.assert_document_operation_opening_access(operation_row.protected_person_id);

  select * into target_row from public.document_operation_targets
  where id=p_target_id and operation_id=p_operation_id for update;
  if not found or target_row.forward_action not in ('update','delete')
     or not target_row.expected_exists
     or target_row.expected_object_id is null
     or target_row.expected_object_version is null then
    raise exception using errcode='P4B03', message='Cible de sauvegarde invalide.';
  end if;
  if not exists (
    select 1 from public.document_object_locks
    where target_id=p_target_id and operation_id=p_operation_id
      and bucket_id=target_row.bucket_id and object_path=target_row.object_path
  ) then
    raise exception using errcode='P4O05', message='Le verrou documentaire est absent.';
  end if;

  select * into object_row from storage.objects object
  where object.bucket_id=target_row.bucket_id and object.name=target_row.object_path
  for key share;
  if not found or object_row.id is distinct from target_row.expected_object_id
     or object_row.version is distinct from target_row.expected_object_version then
    raise exception using errcode='P4S04', message='L’objet Storage a changé depuis la réservation.';
  end if;

  expected_path := 'operations/' || p_operation_id || '/targets/' || p_target_id || '/backup';
  insert into public.document_operation_backups(
    operation_id, target_id, protected_person_id, initiator_subject_id,
    original_bucket_id, original_object_path, original_object_id,
    original_object_version, recovery_object_path, byte_size, mime_type, sha256
  ) values (
    p_operation_id, p_target_id, operation_row.protected_person_id,
    operation_row.initiator_subject_id, target_row.bucket_id, target_row.object_path,
    target_row.expected_object_id, target_row.expected_object_version,
    expected_path, p_byte_size, p_mime_type, p_sha256
  )
  on conflict (operation_id, target_id) do nothing
  returning * into backup_row;

  if backup_row.id is null then
    select * into backup_row from public.document_operation_backups
    where operation_id=p_operation_id and target_id=p_target_id for update;
    if backup_row.protected_person_id is distinct from operation_row.protected_person_id
       or backup_row.original_bucket_id is distinct from target_row.bucket_id
       or backup_row.original_object_path is distinct from target_row.object_path
       or backup_row.original_object_id is distinct from target_row.expected_object_id
       or backup_row.original_object_version is distinct from target_row.expected_object_version
       or backup_row.recovery_object_path is distinct from expected_path
       or backup_row.byte_size is distinct from p_byte_size
       or backup_row.mime_type is distinct from p_mime_type
       or backup_row.sha256 is distinct from p_sha256 then
      raise exception using errcode='P4B05', message='Une sauvegarde incompatible existe déjà.';
    end if;
  end if;

  return jsonb_build_object(
    'backupId', backup_row.id,
    'state', backup_row.state,
    'revision', backup_row.row_revision
  );
end;
$$;

create function public.get_document_operation_backup(
  p_operation_id uuid,
  p_target_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id=p_operation_id;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id
     or not public.can_manage_protected_person(operation_row.protected_person_id) then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into backup_row from public.document_operation_backups
  where operation_id=p_operation_id and target_id=p_target_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'backupId', backup_row.id,
    'state', backup_row.state,
    'revision', backup_row.row_revision,
    'byteSize', backup_row.byte_size,
    'mimeType', backup_row.mime_type,
    'sha256', backup_row.sha256
  );
end;
$$;

create function public.confirm_document_operation_backup(
  p_operation_id uuid,
  p_target_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  backup_row public.document_operation_backups%rowtype;
  object_row storage.objects%rowtype;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id=p_operation_id;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id
     or operation_row.state<>'reserved'
     or not public.can_manage_protected_person(operation_row.protected_person_id) then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into backup_row from public.document_operation_backups
  where operation_id=p_operation_id and target_id=p_target_id for update;
  if not found then
    raise exception using errcode='P4B03', message='Sauvegarde documentaire introuvable.';
  end if;
  if backup_row.state='verified' then
    return jsonb_build_object('backupId',backup_row.id,'state',backup_row.state,
      'revision',backup_row.row_revision);
  end if;
  if backup_row.state<>'upload_pending'
     or backup_row.row_revision<>p_expected_revision then
    raise exception using errcode='P4B06', message='La sauvegarde documentaire a changé.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id='document-operation-backups'
    and object.name=backup_row.recovery_object_path for key share;
  if not found or object_row.version is null or btrim(object_row.version)='' then
    raise exception using errcode='P4B04', message='L’objet de récupération est absent.';
  end if;
  update public.document_operation_backups set
    state='verified', recovery_object_id=object_row.id,
    recovery_object_version=object_row.version,
    upload_verified_at=clock_timestamp(), last_activity_at=clock_timestamp(),
    row_revision=row_revision+1
  where id=backup_row.id
  returning * into backup_row;
  return jsonb_build_object('backupId',backup_row.id,'state',backup_row.state,
    'revision',backup_row.row_revision);
end;
$$;

create function public.mark_document_operation_backup_restored(
  p_operation_id uuid,
  p_target_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  backup_row public.document_operation_backups%rowtype;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id=p_operation_id;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id
     or operation_row.state<>'compensating'
     or not public.can_manage_protected_person(operation_row.protected_person_id) then
    raise exception using errcode='P4O01', message='Accès à la sauvegarde documentaire refusé.';
  end if;
  select * into target_row from public.document_operation_targets
  where id=p_target_id and operation_id=p_operation_id;
  select * into backup_row from public.document_operation_backups
  where operation_id=p_operation_id and target_id=p_target_id for update;
  if target_row.id is null or backup_row.id is null
     or target_row.application_state<>'compensating' then
    raise exception using errcode='P4B03', message='Cible de restauration invalide.';
  end if;
  if backup_row.state='restored' then
    return jsonb_build_object('backupId',backup_row.id,'state',backup_row.state,
      'revision',backup_row.row_revision);
  end if;
  if backup_row.state<>'verified' or backup_row.row_revision<>p_expected_revision
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id=backup_row.original_bucket_id
         and object.name=backup_row.original_object_path
         and object.version is not null and btrim(object.version)<>''
     ) then
    raise exception using errcode='P4B06', message='La restauration documentaire n’est pas vérifiable.';
  end if;
  update public.document_operation_backups set
    state='restored', restored_at=clock_timestamp(),
    last_activity_at=clock_timestamp(), row_revision=row_revision+1
  where id=backup_row.id returning * into backup_row;
  return jsonb_build_object('backupId',backup_row.id,'state',backup_row.state,
    'revision',backup_row.row_revision);
end;
$$;

create function public.get_document_operation_backup_storage_descriptor(
  p_backup_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare backup_row public.document_operation_backups%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Accès privilégié requis.';
  end if;
  select * into backup_row from public.document_operation_backups
  where id=p_backup_id;
  if not found then
    raise exception using errcode='P4B03', message='Sauvegarde documentaire introuvable.';
  end if;
  return jsonb_build_object(
    'backupId', backup_row.id,
    'operationId', backup_row.operation_id,
    'targetId', backup_row.target_id,
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

create function public.complete_document_operation_backup_cleanup(
  p_backup_id uuid,
  p_expected_revision bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  backup_row public.document_operation_backups%rowtype;
  operation_state text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Accès privilégié requis.';
  end if;
  select * into backup_row from public.document_operation_backups
  where id=p_backup_id for update;
  if not found then
    raise exception using errcode='P4B03', message='Sauvegarde documentaire introuvable.';
  end if;
  if backup_row.state='deleted' then return; end if;
  select state into operation_state from public.document_operations
  where id=backup_row.operation_id;
  if operation_state not in ('completed','compensated','cancelled','administratively_resolved')
     or backup_row.row_revision<>p_expected_revision then
    raise exception using errcode='P4B06', message='La sauvegarde ne peut pas être supprimée.';
  end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id='document-operation-backups'
      and object.name=backup_row.recovery_object_path
  ) then
    raise exception using errcode='P4B04', message='L’objet de récupération existe encore.';
  end if;
  update public.document_operation_backups set
    state='deleted', deleted_at=clock_timestamp(),
    last_activity_at=clock_timestamp(), row_revision=row_revision+1
  where id=backup_row.id;
end;
$$;

create function public.authorize_document_operation_backup_cleanup(
  p_backup_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  backup_row public.document_operation_backups%rowtype;
  operation_state text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Accès privilégié requis.';
  end if;
  select * into backup_row from public.document_operation_backups
  where id=p_backup_id for update;
  if not found then
    raise exception using errcode='P4B03', message='Sauvegarde documentaire introuvable.';
  end if;
  select state into operation_state from public.document_operations
  where id=backup_row.operation_id;
  if operation_state not in ('completed','compensated','cancelled','administratively_resolved')
     or backup_row.state not in ('verified','restored','deleted')
     or backup_row.row_revision<>p_expected_revision then
    raise exception using errcode='P4B06', message='La sauvegarde ne peut pas être supprimée.';
  end if;
  return jsonb_build_object(
    'backupId',backup_row.id,'bucketId','document-operation-backups',
    'objectPath',backup_row.recovery_object_path,'state',backup_row.state,
    'revision',backup_row.row_revision
  );
end;
$$;

create function public.list_document_operation_backups_requiring_reconciliation()
returns table (
  backup_id uuid,
  operation_id uuid,
  target_id uuid,
  backup_state text,
  operation_state text,
  initiator_missing boolean,
  last_activity_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501', message='Accès privilégié requis.';
  end if;
  return query
  select backup.id, backup.operation_id, backup.target_id, backup.state,
    operation.state,
    not exists(select 1 from auth.users account where account.id=backup.initiator_subject_id),
    backup.last_activity_at
  from public.document_operation_backups backup
  join public.document_operations operation on operation.id=backup.operation_id
  where backup.state<>'deleted'
    and (operation.state in ('completed','compensated','cancelled','administratively_resolved','attention_required')
      or not exists(select 1 from auth.users account where account.id=backup.initiator_subject_id))
  order by backup.last_activity_at;
end;
$$;

-- La suppression d'un dossier vide ne doit ni perdre ni masquer une sauvegarde
-- encore utile. Les seules lignes techniques retirables sont déjà purgées.
create or replace function public.delete_empty_protected_person(p_protected_person_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_owner_id uuid;
begin
  select owner_id into v_owner_id from public.protected_persons
  where id=p_protected_person_id and owner_id=auth.uid() for update;
  if v_owner_id is null then raise exception 'Dossier introuvable ou suppression non autorisée.'; end if;
  if exists(select 1 from public.financial_accounts where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.protection_measures where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.management_periods where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.protected_person_access where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.protected_person_invitations where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.transfers where protected_person_id=p_protected_person_id)
     or exists(select 1 from public.proof_reference_assignments where protected_person_id=p_protected_person_id) then
    raise exception 'Ce dossier ne peut pas être supprimé tant qu''il contient des comptes ou d''autres données associées.';
  end if;
  if exists(select 1 from public.document_operations where protected_person_id=p_protected_person_id and state in ('reserved','executing','compensating','attention_required')) then
    raise exception using errcode='P4A06',message='Une opération documentaire en cours bloque la suppression.';
  end if;
  if exists(select 1 from public.document_operation_backups where protected_person_id=p_protected_person_id and state<>'deleted') then
    raise exception using errcode='P4A06',message='Une sauvegarde documentaire bloque la suppression.';
  end if;
  delete from public.document_operation_backups where protected_person_id=p_protected_person_id;
  delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operations where protected_person_id=p_protected_person_id;
  delete from public.protected_person_archive_changes where protected_person_id=p_protected_person_id;
  delete from public.proof_reference_counters where protected_person_id=p_protected_person_id;
  delete from public.protected_persons where id=p_protected_person_id;
end;
$$;

revoke all on function public.reserve_document_operation_backup(uuid,uuid,bigint,text,text),
  public.get_document_operation_backup(uuid,uuid),
  public.confirm_document_operation_backup(uuid,uuid,bigint),
  public.mark_document_operation_backup_restored(uuid,uuid,bigint),
  public.get_document_operation_backup_storage_descriptor(uuid),
  public.authorize_document_operation_backup_cleanup(uuid,bigint),
  public.complete_document_operation_backup_cleanup(uuid,bigint),
  public.list_document_operation_backups_requiring_reconciliation()
from public, anon, authenticated, service_role;

grant execute on function public.reserve_document_operation_backup(uuid,uuid,bigint,text,text),
  public.get_document_operation_backup(uuid,uuid),
  public.confirm_document_operation_backup(uuid,uuid,bigint),
  public.mark_document_operation_backup_restored(uuid,uuid,bigint)
to authenticated;

grant execute on function public.get_document_operation_backup_storage_descriptor(uuid),
  public.authorize_document_operation_backup_cleanup(uuid,bigint),
  public.complete_document_operation_backup_cleanup(uuid,bigint),
  public.list_document_operation_backups_requiring_reconciliation()
to service_role;

comment on table public.document_operation_backups is
  'Registre privé des sauvegardes de compensation ; aucun octet, secret ou jeton n’y est stocké.';
comment on function public.get_document_operation_backup_storage_descriptor(uuid) is
  'Descripteur réservé au serveur privilégié ; la clé service_role constitue le périmètre de confiance.';
comment on function public.list_document_operation_backups_requiring_reconciliation() is
  'Inventaire technique sans contenu ni chemin destiné au traitement administratif des opérations orphelines.';
