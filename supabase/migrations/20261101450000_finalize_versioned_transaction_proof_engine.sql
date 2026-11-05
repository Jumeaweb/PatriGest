-- PAT-TRANSACTIONS-01C-DOC2
-- Réservation et finalisation strictes des justificatifs versionnés.
-- Les fichiers remplacés sont conservés ; leur retrait physique est différé.

create table public.transaction_proof_version_reservations (
  operation_id uuid primary key
    references public.document_operations(id) on delete restrict,
  protected_person_id uuid not null
    references public.protected_persons(id) on delete restrict,
  transaction_id uuid not null
    references public.transactions(id) on delete restrict,
  intent text not null check (intent in ('create','replace')),
  proof_document_id uuid not null,
  proof_version_id uuid not null unique,
  expense_reference_assignment_id uuid not null
    references public.proof_reference_assignments(id) on delete restrict,
  proof_reference text not null,
  version_number bigint not null check (version_number > 0),
  storage_path text not null unique,
  expected_current_version_id uuid
    references public.transaction_proof_versions(id) on delete restrict,
  expected_transaction_revision bigint not null check (expected_transaction_revision > 0),
  state text not null default 'reserved'
    check (state in ('reserved','completed','attention_required','cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  finalized_at timestamptz,
  constraint transaction_proof_version_reservations_completion check (
    (state = 'completed' and finalized_at is not null)
    or (state <> 'completed' and finalized_at is null)
  ),
  constraint transaction_proof_version_reservations_intent check (
    (intent = 'create' and expected_current_version_id is null)
    or (intent = 'replace' and expected_current_version_id is not null)
  )
);

create index transaction_proof_version_reservations_entity_idx
  on public.transaction_proof_version_reservations(transaction_id,state);

alter table public.transaction_proof_version_reservations enable row level security;
revoke all on table public.transaction_proof_version_reservations
from public, anon, authenticated, service_role;

create or replace function public.reserve_transaction_proof_version(
  p_protected_person_id uuid,
  p_transaction_id uuid,
  p_intent text,
  p_client_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  transaction_row public.transactions%rowtype;
  account_person_id uuid;
  assignment_row public.proof_reference_assignments%rowtype;
  legacy_row public.transaction_documents%rowtype;
  document_row public.transaction_proof_documents%rowtype;
  current_version public.transaction_proof_versions%rowtype;
  existing_operation public.document_operations%rowtype;
  reservation_row public.transaction_proof_version_reservations%rowtype;
  storage_row storage.objects%rowtype;
  new_document_id uuid;
  new_version_id uuid := gen_random_uuid();
  new_version_number bigint;
  new_path text;
  workflow text;
  targets jsonb;
  operation_id uuid;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  if p_transaction_id is null or p_client_request_id is null
     or p_intent not in ('create','replace') then
    raise exception using errcode='P4O02',
      message='Demande de justificatif invalide.';
  end if;

  -- Une répétition identique est traitée avant la détection des conflits.
  select * into existing_operation
  from public.document_operations
  where initiator_subject_id=caller_id and client_request_id=p_client_request_id;
  if found then
    select * into reservation_row
    from public.transaction_proof_version_reservations reservation
    where reservation.operation_id=existing_operation.id;
    if not found
       or existing_operation.protected_person_id is distinct from p_protected_person_id
       or existing_operation.business_entity_type <> 'transaction'
       or existing_operation.business_entity_id is distinct from p_transaction_id
       or existing_operation.workflow is distinct from 'transaction_proof_'||p_intent
       or reservation_row.intent is distinct from p_intent then
      raise exception using errcode='P4O04',
        message='La clé d’idempotence est déjà utilisée pour une autre demande.';
    end if;
    select * into storage_row
    from storage.objects object
    where object.bucket_id='transaction-proofs'
      and object.name=reservation_row.storage_path
    for key share;
    return jsonb_build_object(
      'operationId',existing_operation.id,
      'operationRevision',existing_operation.row_revision,
      'state',reservation_row.state,
      'intent',reservation_row.intent,
      'documentId',reservation_row.proof_document_id,
      'versionId',reservation_row.proof_version_id,
      'versionNumber',reservation_row.version_number,
      'storagePath',reservation_row.storage_path,
      'transactionRevision',reservation_row.expected_transaction_revision,
      'proofReference',reservation_row.proof_reference,
      'storageObjectId',storage_row.id,
      'idempotent',true
    );
  end if;

  select transaction.* into transaction_row
  from public.transactions transaction
  where transaction.id=p_transaction_id
  for update;
  if not found then
    raise exception using errcode='P4O02',message='Transaction introuvable.';
  end if;
  select account.protected_person_id into account_person_id
  from public.financial_accounts account
  where account.id=transaction_row.financial_account_id;
  if account_person_id is distinct from p_protected_person_id
     or transaction_row.transaction_type <> 'expense'
     or transaction_row.transfer_id is not null
     or transaction_row.cancelled_at is not null
     or transaction_row.proof_reference is null then
    raise exception using errcode='P4O02',
      message='Seule une dépense active peut recevoir un justificatif.';
  end if;
  if exists (
    select 1 from public.management_periods period
    where period.protected_person_id=p_protected_person_id
      and period.status='closed'
      and transaction_row.transaction_date between period.start_date and period.end_date
  ) then
    raise exception using errcode='P4O03',
      message='Un exercice clôturé ne peut pas être modifié.';
  end if;
  if exists (
    select 1 from public.document_operations operation
    where operation.business_entity_type='transaction'
      and operation.business_entity_id=p_transaction_id
      and operation.state in ('reserved','executing','compensating','attention_required')
  ) then
    raise exception using errcode='P4O05',
      message='Une opération documentaire est déjà en cours pour cette transaction.';
  end if;

  select * into assignment_row
  from public.proof_reference_assignments assignment
  where assignment.transaction_id=p_transaction_id and assignment.ended_at is null
  order by assignment.created_at desc limit 1 for update;
  if not found or assignment_row.proof_reference is distinct from transaction_row.proof_reference then
    raise exception using errcode='P4O02',
      message='La référence courante du justificatif est incohérente.';
  end if;

  select * into document_row
  from public.transaction_proof_documents document
  where document.transaction_id=p_transaction_id and document.lifecycle_status='current'
  for update;
  select * into legacy_row from public.transaction_documents
  where transaction_id=p_transaction_id for update;

  -- Adoption contrôlée d'un justificatif historique /proof. Il n'est déclaré
  -- disponible que si le catalogue Storage démontre sa présence et son identité.
  if document_row.id is null and legacy_row.id is not null then
    select * into storage_row from storage.objects object
    where object.bucket_id='transaction-proofs' and object.name=legacy_row.storage_path
      and object.version is not null and btrim(object.version)<>''
    for key share;
    if not found then
      raise exception using errcode='P4S04',
        message='Le justificatif existant est absent du catalogue Storage.';
    end if;
    if coalesce(storage_row.metadata->>'mimetype','')<>legacy_row.mime_type
       or coalesce(storage_row.metadata->>'size','') !~ '^[0-9]+$'
       or (storage_row.metadata->>'size')::bigint<>legacy_row.file_size then
      raise exception using errcode='P4S04',
        message='Le justificatif existant ne correspond pas à ses métadonnées.';
    end if;
    insert into public.transaction_proof_documents(
      protected_person_id,transaction_id,expense_reference_assignment_id,
      proof_reference,lifecycle_status,created_by,created_at
    ) values(p_protected_person_id,p_transaction_id,assignment_row.id,
      assignment_row.proof_reference,'current',legacy_row.created_by,legacy_row.created_at)
    returning * into document_row;
    insert into public.transaction_proof_versions(
      proof_document_id,version_number,storage_path,path_kind,lifecycle_state,
      availability_status,file_name,mime_type,file_size,storage_object_id,
      storage_object_version,created_by,created_at
    ) values(document_row.id,1,legacy_row.storage_path,'legacy','current','available',
      legacy_row.file_name,legacy_row.mime_type,legacy_row.file_size,
      storage_row.id,storage_row.version,legacy_row.created_by,legacy_row.created_at)
    returning * into current_version;
    update public.transaction_documents
      set proof_document_id=document_row.id,proof_version_id=current_version.id
      where id=legacy_row.id;
  elsif document_row.id is not null then
    select * into current_version
    from public.transaction_proof_versions version
    where version.proof_document_id=document_row.id and version.lifecycle_state='current'
    for update;
    if not found then
      raise exception using errcode='P4S04',
        message='La version courante du justificatif est introuvable.';
    end if;
  end if;

  if p_intent='create' then
    if document_row.id is not null or legacy_row.id is not null then
      raise exception using errcode='P4O02',
        message='Un justificatif courant existe déjà.';
    end if;
    new_document_id:=gen_random_uuid();
    new_version_number:=1;
  else
    if document_row.id is null or current_version.id is null then
      raise exception using errcode='P4O02',
        message='Aucun justificatif courant ne peut être remplacé.';
    end if;
    new_document_id:=document_row.id;
    select coalesce(max(version.version_number),0)+1 into new_version_number
    from public.transaction_proof_versions version
    where version.proof_document_id=document_row.id;
  end if;

  new_path:=public.build_transaction_proof_version_path(
    p_protected_person_id,p_transaction_id,new_document_id,new_version_id);
  workflow:='transaction_proof_'||p_intent;
  targets:=jsonb_build_array(jsonb_build_object(
    'ordinal',1,'bucket_id','transaction-proofs','object_path',new_path,
    'target_role','destination','forward_action','insert',
    'compensation_action','delete','expected_exists',false));
  operation_id:=public.create_document_operation(
    p_protected_person_id,workflow,'transaction',p_transaction_id,
    p_client_request_id,targets);

  insert into public.transaction_proof_version_reservations(
    operation_id,protected_person_id,transaction_id,intent,proof_document_id,
    proof_version_id,expense_reference_assignment_id,proof_reference,
    version_number,storage_path,expected_current_version_id,
    expected_transaction_revision,created_by
  ) values(operation_id,p_protected_person_id,p_transaction_id,p_intent,
    new_document_id,new_version_id,assignment_row.id,assignment_row.proof_reference,
    new_version_number,new_path,case when p_intent='replace' then current_version.id end,
    transaction_row.revision,caller_id)
  returning * into reservation_row;

  select * into existing_operation from public.document_operations where id=operation_id;
  return jsonb_build_object(
    'operationId',operation_id,'operationRevision',existing_operation.row_revision,
    'state','reserved','intent',p_intent,'documentId',new_document_id,
    'versionId',new_version_id,'versionNumber',new_version_number,
    'storagePath',new_path,'transactionRevision',transaction_row.revision,
    'proofReference',assignment_row.proof_reference,'idempotent',false
  );
end;
$$;

create function public.can_upload_reserved_transaction_proof_version(
  p_bucket_id text,
  p_object_path text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_bucket_id='transaction-proofs' and exists (
    select 1
    from public.transaction_proof_version_reservations reservation
    join public.document_operations operation on operation.id=reservation.operation_id
    join public.transactions transaction on transaction.id=reservation.transaction_id
    join public.financial_accounts account on account.id=transaction.financial_account_id
    join public.protected_persons person on person.id=reservation.protected_person_id
    join public.proof_reference_assignments assignment
      on assignment.id=reservation.expense_reference_assignment_id
    where reservation.storage_path=p_object_path
      and reservation.state='reserved'
      and operation.state='reserved'
      and operation.initiator_subject_id=auth.uid()
      and operation.initiator_kind='user'
      and transaction.revision=reservation.expected_transaction_revision
      and transaction.transaction_type='expense'
      and transaction.transfer_id is null
      and transaction.cancelled_at is null
      and transaction.proof_reference=reservation.proof_reference
      and account.protected_person_id=reservation.protected_person_id
      and person.status='active'
      and assignment.transaction_id=reservation.transaction_id
      and assignment.ended_at is null
      and assignment.proof_reference=reservation.proof_reference
      and public.can_manage_protected_person(reservation.protected_person_id)
      and not exists (
        select 1 from public.management_periods period
        where period.protected_person_id=reservation.protected_person_id
          and period.status='closed'
          and transaction.transaction_date between period.start_date and period.end_date
      )
  )
$$;

drop policy if exists transaction_proof_version_upload_reserved on storage.objects;
create policy transaction_proof_version_upload_reserved
on storage.objects for insert to authenticated
with check (public.can_upload_reserved_transaction_proof_version(bucket_id,name));

create or replace function public.finalize_transaction_proof_version(
  p_operation_id uuid,
  p_expected_operation_revision bigint,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint,
  p_sha256 text,
  p_storage_object_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_row public.document_operations%rowtype;
  reservation_row public.transaction_proof_version_reservations%rowtype;
  transaction_row public.transactions%rowtype;
  assignment_row public.proof_reference_assignments%rowtype;
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  finalized_version public.transaction_proof_versions%rowtype;
  old_version public.transaction_proof_versions%rowtype;
  legacy_row public.transaction_documents%rowtype;
  final_revision bigint;
begin
  if caller_id is null then
    raise exception using errcode='P4O01',message='Accès à la finalisation refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id=p_operation_id for update;
  select * into reservation_row from public.transaction_proof_version_reservations
  where operation_id=p_operation_id for update;
  if operation_row.id is null or reservation_row.operation_id is null
     or operation_row.initiator_subject_id is distinct from caller_id
     or operation_row.initiator_kind<>'user' then
    raise exception using errcode='P4O01',message='Accès à la finalisation refusé.';
  end if;

  -- Rejeu sûr après perte de réponse : seul un résultat strictement identique est accepté.
  if reservation_row.state='completed' then
    select * into finalized_version
    from public.transaction_proof_versions version
    where version.id=reservation_row.proof_version_id
      and version.storage_object_id is not distinct from p_storage_object_id
      and version.sha256 is not distinct from lower(p_sha256)
      and version.file_name is not distinct from btrim(p_file_name)
      and version.mime_type is not distinct from p_mime_type
      and version.file_size is not distinct from p_file_size;
    if found then
      return jsonb_build_object('operationId',p_operation_id,'state','completed',
        'revision',operation_row.row_revision,'documentId',reservation_row.proof_document_id,
        'versionId',reservation_row.proof_version_id,
        'storageObjectId',finalized_version.storage_object_id,
        'storageObjectVersion',finalized_version.storage_object_version,
        'idempotent',true);
    end if;
    raise exception using errcode='P4O04',
      message='La finalisation a déjà été enregistrée avec un autre résultat.';
  end if;

  if reservation_row.state<>'reserved' or operation_row.state<>'reserved'
     or operation_row.row_revision<>p_expected_operation_revision
     or operation_row.workflow<>'transaction_proof_'||reservation_row.intent then
    raise exception using errcode='P4O06',
      message='La réservation documentaire a changé.';
  end if;
  if nullif(btrim(p_file_name),'') is null
     or p_mime_type not in ('application/pdf','image/jpeg','image/png')
     or p_file_size is null or p_file_size<=0 or p_file_size>10485760
     or p_sha256 is null or lower(p_sha256) !~ '^[0-9a-f]{64}$'
     or p_storage_object_id is null then
    raise exception using errcode='P4O02',message='Métadonnées du justificatif invalides.';
  end if;

  select * into transaction_row from public.transactions
  where id=reservation_row.transaction_id for update;
  select * into assignment_row from public.proof_reference_assignments
  where id=reservation_row.expense_reference_assignment_id for key share;
  if not found
     or transaction_row.revision<>reservation_row.expected_transaction_revision
     or transaction_row.transaction_type<>'expense'
     or transaction_row.transfer_id is not null
     or transaction_row.cancelled_at is not null
     or transaction_row.proof_reference is distinct from reservation_row.proof_reference
     or assignment_row.ended_at is not null
     or assignment_row.proof_reference is distinct from reservation_row.proof_reference then
    raise exception using errcode='P4O06',
      message='La transaction ou sa référence documentaire a changé.';
  end if;
  perform public.assert_document_operation_opening_access(reservation_row.protected_person_id);
  if exists (
    select 1 from public.management_periods period
    where period.protected_person_id=reservation_row.protected_person_id
      and period.status='closed'
      and transaction_row.transaction_date between period.start_date and period.end_date
  ) then
    raise exception using errcode='P4O03',message='Un exercice clôturé ne peut pas être modifié.';
  end if;

  select * into target_row from public.document_operation_targets
  where operation_id=p_operation_id and ordinal=1 for update;
  if not found or target_row.bucket_id<>'transaction-proofs'
     or target_row.object_path<>reservation_row.storage_path
     or target_row.forward_action<>'insert' or target_row.expected_exists
     or target_row.application_state<>'pending' then
    raise exception using errcode='P4S05',message='La cible Storage réservée est incohérente.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id='transaction-proofs'
    and object.name=reservation_row.storage_path for key share;
  if not found
     or object_row.id is distinct from p_storage_object_id
     or nullif(btrim(object_row.version),'') is null
     or coalesce(object_row.metadata->>'mimetype','')<>p_mime_type
     or coalesce(object_row.metadata->>'size','') !~ '^[0-9]+$'
     or (object_row.metadata->>'size')::bigint<>p_file_size
     or lower(coalesce(object_row.user_metadata->>'sha256',''))<>lower(p_sha256) then
    raise exception using errcode='P4S04',
      message='Le fichier Storage ne correspond pas à la réservation.';
  end if;

  if reservation_row.intent='create' then
    if exists(select 1 from public.transaction_proof_documents document
      where document.transaction_id=reservation_row.transaction_id
        and document.lifecycle_status='current')
       or exists(select 1 from public.transaction_documents document
      where document.transaction_id=reservation_row.transaction_id) then
      raise exception using errcode='P4O06',message='Un justificatif courant existe déjà.';
    end if;
    insert into public.transaction_proof_documents(
      id,protected_person_id,transaction_id,expense_reference_assignment_id,
      proof_reference,lifecycle_status,created_by
    ) values(reservation_row.proof_document_id,reservation_row.protected_person_id,
      reservation_row.transaction_id,reservation_row.expense_reference_assignment_id,
      reservation_row.proof_reference,'current',caller_id);
  else
    select * into old_version from public.transaction_proof_versions version
    where version.id=reservation_row.expected_current_version_id
      and version.proof_document_id=reservation_row.proof_document_id
      and version.lifecycle_state='current' for update;
    if not found then
      raise exception using errcode='P4O06',
        message='La version remplacée n’est plus la version courante.';
    end if;
    -- Le fichier neuf est déjà vérifié dans Storage. Le basculement de l'état
    -- courant et l'insertion de sa version sont ensuite atomiques.
    update public.transaction_proof_versions
      set lifecycle_state='superseded_pending_deletion',superseded_at=clock_timestamp(),
        replacement_operation_id=p_operation_id
      where id=old_version.id;
  end if;

  insert into public.transaction_proof_versions(
    id,proof_document_id,version_number,storage_path,path_kind,lifecycle_state,
    availability_status,file_name,mime_type,file_size,sha256,storage_object_id,
    storage_object_version,created_by
  ) values(reservation_row.proof_version_id,reservation_row.proof_document_id,
    reservation_row.version_number,reservation_row.storage_path,'versioned','current',
    'available',btrim(p_file_name),p_mime_type,p_file_size,lower(p_sha256),
    p_storage_object_id,object_row.version,caller_id);

  if reservation_row.intent='replace' then
    insert into public.transaction_proof_replacement_retirements(
      proof_document_id,superseded_version_id,replacement_version_id,operation_id
    ) values(reservation_row.proof_document_id,old_version.id,
      reservation_row.proof_version_id,p_operation_id);
    select * into legacy_row from public.transaction_documents
      where transaction_id=reservation_row.transaction_id for update;
    if legacy_row.id is not null then
      delete from public.transaction_documents where id=legacy_row.id;
    end if;
  end if;

  insert into public.transaction_documents(
    transaction_id,storage_path,file_name,mime_type,file_size,created_by,
    proof_document_id,proof_version_id
  ) values(reservation_row.transaction_id,reservation_row.storage_path,
    btrim(p_file_name),p_mime_type,p_file_size,caller_id,
    reservation_row.proof_document_id,reservation_row.proof_version_id);

  perform public.transition_document_operation(p_operation_id,'reserved','executing');
  perform public.transition_document_operation_target(
    target_row.id,target_row.target_revision,'applied',object_row.id,object_row.version);
  final_revision:=public.transition_document_operation(p_operation_id,'executing','completed');
  update public.transaction_proof_version_reservations
    set state='completed',finalized_at=clock_timestamp()
    where operation_id=p_operation_id;

  return jsonb_build_object('operationId',p_operation_id,'state','completed',
    'revision',final_revision,'documentId',reservation_row.proof_document_id,
    'versionId',reservation_row.proof_version_id,
    'storageObjectId',object_row.id,
    'storageObjectVersion',object_row.version,
    'idempotent',false);
end;
$$;

revoke all on function public.reserve_transaction_proof_version(uuid,uuid,text,uuid),
  public.can_upload_reserved_transaction_proof_version(text,text),
  public.finalize_transaction_proof_version(uuid,bigint,text,text,bigint,text,uuid)
from public, anon, authenticated, service_role;

grant execute on function public.reserve_transaction_proof_version(uuid,uuid,text,uuid),
  public.can_upload_reserved_transaction_proof_version(text,text),
  public.finalize_transaction_proof_version(uuid,bigint,text,text,bigint,text,uuid)
to authenticated;

comment on table public.transaction_proof_version_reservations is
  'Réservations exactes et non réutilisables des justificatifs versionnés.';
comment on function public.reserve_transaction_proof_version(uuid,uuid,text,uuid) is
  'Réserve idempotemment une identité documentaire, une version et un chemin Storage libre.';
comment on function public.finalize_transaction_proof_version(uuid,bigint,text,text,bigint,text,uuid) is
  'Résout la version Storage autoritairement puis finalise atomiquement l objet réservé.';
