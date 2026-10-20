-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3A
-- Progression vérifiée des opérations documentaires. La garde Storage et le
-- cycle d'archivage restent désactivés ; cette migration n'installe aucun
-- trigger ni aucune politique sur storage.objects.

create function public.assert_document_operation_caller(
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
    raise exception using errcode='P4O01',
      message='Accès à l’opération documentaire refusé.';
  end if;

  select * into operation_row
  from public.document_operations
  where id=p_operation_id;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id then
    raise exception using errcode='P4O01',
      message='Accès à l’opération documentaire refusé.';
  end if;

  -- Verrouiller le dossier avant l'opération : l'archivage suit le même ordre.
  if p_require_manage then
    perform public.assert_document_operation_opening_access(
      operation_row.protected_person_id
    );
  end if;

  select * into operation_row
  from public.document_operations
  where id=p_operation_id
  for update;
  if operation_row.row_revision is distinct from p_expected_revision then
    raise exception using errcode='P4O06',
      message='La révision de l’opération documentaire a changé.';
  end if;
  if not operation_row.state=any(p_allowed_states) then
    raise exception using errcode='P4O06',
      message='L’état de l’opération documentaire a changé.';
  end if;
  return operation_row;
end;
$$;

create function public.assert_document_operation_business_state(
  p_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  operation_row public.document_operations%rowtype;
  resolution record;
  transaction_row record;
  statement_row public.bank_statements%rowtype;
  statement_found boolean;
  report_row public.management_reports%rowtype;
  draft_path text;
  final_path text;
  draft_exists boolean;
  final_exists boolean;
begin
  select * into operation_row from public.document_operations
  where id=p_operation_id;
  if not found then
    raise exception using errcode='P4O02',
      message='Opération documentaire introuvable.';
  end if;

  select * into resolution
  from public.resolve_canonical_document_storage_path(
    (select bucket_id from public.document_operation_targets
     where operation_id=p_operation_id order by ordinal limit 1),
    (select object_path from public.document_operation_targets
     where operation_id=p_operation_id order by ordinal limit 1)
  );
  if not resolution.is_canonical
     or resolution.protected_person_id is distinct from operation_row.protected_person_id
     or resolution.business_entity_type is distinct from operation_row.business_entity_type
     or resolution.business_entity_id is distinct from operation_row.business_entity_id then
    raise exception using errcode='P4O02',
      message='Le rattachement documentaire a changé.';
  end if;

  if operation_row.business_entity_type='transaction' then
    select transaction.id,transaction.transaction_date,transaction.transaction_type,
      transaction.transfer_id,account.protected_person_id
    into transaction_row
    from public.transactions transaction
    join public.financial_accounts account
      on account.id=transaction.financial_account_id
    where transaction.id=operation_row.business_entity_id
    for update of transaction;
    if not found
       or transaction_row.protected_person_id<>operation_row.protected_person_id
       or transaction_row.transaction_type<>'expense'
       or transaction_row.transfer_id is not null then
      raise exception using errcode='P4O02',
        message='Le rattachement du justificatif est invalide.';
    end if;
    if exists (
      select 1 from public.management_periods period
      where period.protected_person_id=operation_row.protected_person_id
        and period.status='closed'
        and transaction_row.transaction_date between period.start_date and period.end_date
    ) then
      raise exception using errcode='P4O08',
        message='L’exercice correspondant est clôturé.';
    end if;
    if operation_row.workflow='transaction_proof_create' and exists (
      select 1 from public.transaction_documents
      where transaction_id=operation_row.business_entity_id
    ) then
      raise exception using errcode='P4O02',message='Le justificatif existe déjà.';
    elsif operation_row.workflow in ('transaction_proof_replace','transaction_proof_delete')
      and not exists (
        select 1 from public.transaction_documents document
        join public.document_operation_targets target
          on target.operation_id=p_operation_id and target.ordinal=1
        where document.transaction_id=operation_row.business_entity_id
          and document.storage_path=target.object_path
      ) then
      raise exception using errcode='P4O02',
        message='Le justificatif attendu est introuvable.';
    end if;

  elsif operation_row.business_entity_type='bank_statement' then
    select * into statement_row from public.bank_statements
    where id=operation_row.business_entity_id for update;
    statement_found:=found;
    if not exists (
      select 1 from public.document_operation_targets target
      cross join lateral public.resolve_canonical_document_storage_path(
        target.bucket_id,target.object_path) path
      join public.financial_accounts account on account.id=path.parent_entity_id
      where target.operation_id=p_operation_id
        and account.protected_person_id=operation_row.protected_person_id
    ) then
      raise exception using errcode='P4O02',message='Le rattachement du relevé est invalide.';
    end if;
    if operation_row.workflow='bank_statement_create' and statement_found then
      raise exception using errcode='P4O02',message='Le relevé existe déjà.';
    elsif operation_row.workflow='bank_statement_attach' and (
      not statement_found or statement_row.original_file_name is not null
      or statement_row.mime_type is not null or statement_row.file_size is not null
    ) then
      raise exception using errcode='P4O02',
        message='Le relevé ne peut pas recevoir ce PDF.';
    elsif operation_row.workflow in ('bank_statement_replace','bank_statement_delete')
      and (not statement_found or statement_row.original_file_name is null
        or statement_row.mime_type is null or statement_row.file_size is null) then
      raise exception using errcode='P4O02',
        message='Le PDF du relevé attendu est introuvable.';
    end if;

  elsif operation_row.business_entity_type='management_report' then
    select * into report_row from public.management_reports
    where id=operation_row.business_entity_id for update;
    if not found or report_row.protected_person_id<>operation_row.protected_person_id then
      raise exception using errcode='P4O02',message='Compte de gestion introuvable.';
    end if;
    draft_path:='protected-persons/'||operation_row.protected_person_id||
      '/management-reports/'||report_row.id||'/management-report-draft.pdf';
    final_path:='protected-persons/'||operation_row.protected_person_id||
      '/management-reports/'||report_row.id||'/management-report.pdf';
    select exists(select 1 from public.management_report_documents
      where management_report_id=report_row.id
        and document_type='management_report_draft' and storage_path=draft_path),
      exists(select 1 from public.management_report_documents
      where management_report_id=report_row.id
        and document_type='management_report' and storage_path=final_path)
    into draft_exists,final_exists;
    if operation_row.workflow='management_report_generate'
       and (report_row.status::text<>'ready' or draft_exists)
       or operation_row.workflow in ('management_report_finalize','management_report_resume')
       and (report_row.status::text<>'generated' or not draft_exists)
       or operation_row.workflow='management_report_finalize' and final_exists then
      raise exception using errcode='P4O02',
        message='L’état du compte de gestion a changé.';
    end if;
  else
    raise exception using errcode='P4O02',
      message='Type d’opération documentaire non pris en charge.';
  end if;
end;
$$;

create function public.assert_document_target_catalog_state(
  p_target_id uuid,
  p_phase text
)
returns storage.objects
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  object_found boolean;
  expected_action text;
  expected_id uuid;
  expected_version text;
begin
  select * into target_row from public.document_operation_targets
  where id=p_target_id;
  if not found or p_phase not in ('expected','applied','compensated') then
    raise exception using errcode='P4S05',message='Cible documentaire invalide.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id=target_row.bucket_id and object.name=target_row.object_path
  for key share;
  object_found:=found;

  if p_phase='expected' then
    if target_row.expected_exists<>object_found
       or target_row.expected_exists and (
         object_row.id is distinct from target_row.expected_object_id
         or object_row.version is distinct from target_row.expected_object_version) then
      raise exception using errcode='P4S04',
        message='L’objet Storage a changé depuis la réservation.';
    end if;
  else
    expected_action:=case when p_phase='applied' then target_row.forward_action
      else target_row.compensation_action end;
    expected_id:=case when p_phase='applied' then target_row.applied_object_id
      else target_row.compensated_object_id end;
    expected_version:=case when p_phase='applied' then target_row.applied_object_version
      else target_row.compensated_object_version end;
    if expected_action='delete' and object_found then
      raise exception using errcode='P4S04',
        message='L’objet Storage supprimé est encore présent.';
    elsif expected_action in ('insert','update') and (
      not object_found or object_row.id is distinct from expected_id
      or object_row.version is distinct from expected_version) then
      raise exception using errcode='P4S04',
        message='Le résultat Storage ne correspond plus au résultat enregistré.';
    end if;
  end if;
  return object_row;
end;
$$;

create function public.start_document_operation(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  next_revision bigint;
  targets jsonb;
begin
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['reserved'],true
  );
  perform public.assert_document_operation_business_state(p_operation_id);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id order by ordinal for update
  loop
    if target_row.application_state<>'pending' then
      raise exception using errcode='P4S05',
        message='Une cible documentaire n’est plus en attente.';
    end if;
    perform public.assert_document_target_catalog_state(target_row.id,'expected');
    if not exists(select 1 from public.document_object_locks
      where target_id=target_row.id and operation_id=p_operation_id
        and bucket_id=target_row.bucket_id and object_path=target_row.object_path) then
      raise exception using errcode='P4O05',message='Le verrou documentaire est absent.';
    end if;
  end loop;
  next_revision:=public.transition_document_operation(
    p_operation_id,'reserved','executing'
  );
  select jsonb_agg(jsonb_build_object(
    'id',target.id,'ordinal',target.ordinal,'bucketId',target.bucket_id,
    'objectPath',target.object_path,'role',target.target_role,
    'action',target.forward_action,'revision',target.target_revision,
    'expectedObjectId',target.expected_object_id,
    'expectedObjectVersion',target.expected_object_version
  ) order by target.ordinal) into targets
  from public.document_operation_targets target
  where target.operation_id=p_operation_id;
  return jsonb_build_object('operationId',p_operation_id,'state','executing',
    'revision',next_revision,'workflow',operation_row.workflow,'targets',targets);
end;
$$;

create function public.record_document_operation_target_applied(
  p_operation_id uuid,
  p_target_id uuid,
  p_expected_operation_revision bigint,
  p_expected_target_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype;
  object_found boolean;
  target_revision bigint;
  operation_revision bigint;
begin
  perform public.assert_document_operation_caller(
    p_operation_id,p_expected_operation_revision,array['executing'],true);
  select * into target_row from public.document_operation_targets
  where id=p_target_id and operation_id=p_operation_id for update;
  if not found or target_row.application_state<>'pending'
     or target_row.target_revision<>p_expected_target_revision then
    raise exception using errcode='P4S05',
      message='La cible documentaire ou sa révision a changé.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id=target_row.bucket_id and object.name=target_row.object_path
  for key share;
  object_found:=found;
  if target_row.forward_action='delete' then
    if object_found then raise exception using errcode='P4S04',
      message='La suppression Storage n’est pas effective.'; end if;
  elsif not object_found or object_row.version is null or btrim(object_row.version)='' then
    raise exception using errcode='P4S04',
      message='Le résultat Storage est introuvable ou sans version.';
  elsif target_row.forward_action='insert' and target_row.expected_exists then
    raise exception using errcode='P4S04',message='Insertion Storage incohérente.';
  elsif target_row.forward_action='update' and (
    object_row.id is distinct from target_row.expected_object_id
    or object_row.version is not distinct from target_row.expected_object_version) then
    raise exception using errcode='P4S04',
      message='Le remplacement Storage n’a pas produit une nouvelle version.';
  end if;
  target_revision:=public.transition_document_operation_target(
    p_target_id,p_expected_target_revision,'applied',
    case when object_found then object_row.id end,
    case when object_found then object_row.version end
  );
  select row_revision into operation_revision from public.document_operations
  where id=p_operation_id;
  return jsonb_build_object('operationId',p_operation_id,
    'revision',operation_revision,'targetId',p_target_id,
    'targetRevision',target_revision,'state','applied');
end;
$$;

create function public.assert_document_operation_ready_to_finalize(
  p_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare target_row public.document_operation_targets%rowtype;
begin
  perform public.assert_document_operation_business_state(p_operation_id);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id order by ordinal for update
  loop
    if target_row.application_state<>'applied' then
      raise exception using errcode='P4S05',
        message='Toutes les cibles Storage ne sont pas appliquées.';
    end if;
    perform public.assert_document_target_catalog_state(target_row.id,'applied');
  end loop;
end;
$$;

create function public.assert_document_object_metadata(
  p_target_id uuid,
  p_mime_type text,
  p_file_size bigint,
  p_max_size bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare object_row storage.objects%rowtype;
begin
  object_row:=public.assert_document_target_catalog_state(p_target_id,'applied');
  if p_file_size is null or p_file_size<=0 or p_file_size>p_max_size
     or coalesce(object_row.metadata->>'mimetype','')<>p_mime_type
     or coalesce(object_row.metadata->>'size','') !~ '^[0-9]+$'
     or (object_row.metadata->>'size')::bigint<>p_file_size then
    raise exception using errcode='P4S04',
      message='Les métadonnées du fichier ne correspondent pas au catalogue Storage.';
  end if;
end;
$$;

create function public.finalize_transaction_proof_document_operation(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
begin
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['executing'],true);
  if operation_row.workflow not in (
    'transaction_proof_create','transaction_proof_replace','transaction_proof_delete') then
    raise exception using errcode='P4O02',message='Workflow documentaire incompatible.';
  end if;
  perform public.assert_document_operation_ready_to_finalize(p_operation_id);
  select * into target_row from public.document_operation_targets
  where operation_id=p_operation_id and ordinal=1;
  if operation_row.workflow<>'transaction_proof_delete' then
    if nullif(btrim(p_file_name),'') is null
       or p_mime_type not in ('application/pdf','image/jpeg','image/png') then
      raise exception using errcode='P4O02',message='Métadonnées du justificatif invalides.';
    end if;
    perform public.assert_document_object_metadata(
      target_row.id,p_mime_type,p_file_size,10485760);
  end if;
  if operation_row.workflow='transaction_proof_create' then
    insert into public.transaction_documents(
      transaction_id,storage_path,file_name,mime_type,file_size,created_by)
    values(operation_row.business_entity_id,target_row.object_path,btrim(p_file_name),
      p_mime_type,p_file_size,auth.uid());
  elsif operation_row.workflow='transaction_proof_replace' then
    update public.transaction_documents set file_name=btrim(p_file_name),
      mime_type=p_mime_type,file_size=p_file_size
    where transaction_id=operation_row.business_entity_id
      and storage_path=target_row.object_path;
    if not found then raise exception using errcode='P4O02',message='Justificatif introuvable.'; end if;
  else
    delete from public.transaction_documents
    where transaction_id=operation_row.business_entity_id
      and storage_path=target_row.object_path;
    if not found then raise exception using errcode='P4O02',message='Justificatif introuvable.'; end if;
  end if;
  return public.transition_document_operation(p_operation_id,'executing','completed');
end;
$$;

create function public.finalize_bank_statement_document_operation(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_statement_start_date date,
  p_statement_end_date date,
  p_statement_balance numeric,
  p_note text,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  resolution record;
begin
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['executing'],true);
  if operation_row.workflow not in ('bank_statement_create','bank_statement_attach',
      'bank_statement_replace','bank_statement_delete') then
    raise exception using errcode='P4O02',message='Workflow documentaire incompatible.';
  end if;
  perform public.assert_document_operation_ready_to_finalize(p_operation_id);
  select * into target_row from public.document_operation_targets
  where operation_id=p_operation_id and ordinal=1;
  select * into resolution from public.resolve_canonical_document_storage_path(
    target_row.bucket_id,target_row.object_path);
  if operation_row.workflow<>'bank_statement_delete' then
    if p_statement_end_date is null
       or p_statement_start_date>p_statement_end_date
       or nullif(btrim(p_file_name),'') is null or p_mime_type<>'application/pdf' then
      raise exception using errcode='P4O02',message='Métadonnées du relevé invalides.';
    end if;
    perform public.assert_document_object_metadata(
      target_row.id,p_mime_type,p_file_size,10485760);
  end if;
  if operation_row.workflow='bank_statement_create' then
    insert into public.bank_statements(
      id,financial_account_id,statement_start_date,statement_end_date,
      statement_balance,storage_path,original_file_name,mime_type,file_size,note,created_by)
    values(operation_row.business_entity_id,resolution.parent_entity_id,
      p_statement_start_date,p_statement_end_date,p_statement_balance,
      target_row.object_path,btrim(p_file_name),p_mime_type,p_file_size,p_note,auth.uid());
  elsif operation_row.workflow='bank_statement_delete' then
    update public.bank_statements set original_file_name=null,mime_type=null,file_size=null
    where id=operation_row.business_entity_id and storage_path=target_row.object_path;
    if not found then raise exception using errcode='P4O02',message='Relevé introuvable.'; end if;
  else
    update public.bank_statements set
      statement_start_date=coalesce(p_statement_start_date,statement_start_date),
      statement_end_date=coalesce(p_statement_end_date,statement_end_date),
      statement_balance=p_statement_balance,note=p_note,
      original_file_name=btrim(p_file_name),mime_type=p_mime_type,file_size=p_file_size
    where id=operation_row.business_entity_id and storage_path=target_row.object_path;
    if not found then raise exception using errcode='P4O02',message='Relevé introuvable.'; end if;
  end if;
  return public.transition_document_operation(p_operation_id,'executing','completed');
end;
$$;

create function public.finalize_management_report_document_operation(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint,
  p_preview_snapshot jsonb,
  p_snapshot_schema_version integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare operation_row public.document_operations%rowtype;
  report_row public.management_reports%rowtype;
  target_row public.document_operation_targets%rowtype;
  draft_target public.document_operation_targets%rowtype;
  expected_snapshot_status text;
begin
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['executing'],true);
  if operation_row.workflow not in ('management_report_generate',
      'management_report_finalize','management_report_resume') then
    raise exception using errcode='P4O02',message='Workflow documentaire incompatible.';
  end if;
  perform public.assert_document_operation_ready_to_finalize(p_operation_id);
  select * into report_row from public.management_reports
  where id=operation_row.business_entity_id for update;

  if operation_row.workflow='management_report_resume' then
    select * into target_row from public.document_operation_targets
    where operation_id=p_operation_id and ordinal=1;
    delete from public.management_report_documents
    where management_report_id=report_row.id
      and document_type='management_report_draft'
      and storage_path=target_row.object_path;
    if not found then raise exception using errcode='P4O02',message='PDF projet introuvable.'; end if;
    update public.management_reports set status='draft',generated_at=null,finalized_at=null
    where id=report_row.id and status::text='generated';
    if not found then raise exception using errcode='P4O02',message='Le statut du compte a changé.'; end if;
  else
    select * into target_row from public.document_operation_targets
    where operation_id=p_operation_id and target_role in ('primary','destination')
    order by ordinal limit 1;
    if nullif(btrim(p_file_name),'') is null or p_mime_type<>'application/pdf'
       or p_preview_snapshot is null or jsonb_typeof(p_preview_snapshot)<>'object'
       or p_snapshot_schema_version is null or p_snapshot_schema_version<=0 then
      raise exception using errcode='P4O02',message='Métadonnées du compte de gestion invalides.';
    end if;
    perform public.assert_document_object_metadata(
      target_row.id,p_mime_type,p_file_size,20971520);
    expected_snapshot_status:=case when operation_row.workflow='management_report_generate'
      then 'generated' else 'finalized' end;
    if p_preview_snapshot #>> '{report,id}' is distinct from report_row.id::text
       or p_preview_snapshot #>> '{report,protected_person_id}' is distinct from report_row.protected_person_id::text
       or p_preview_snapshot #>> '{person,id}' is distinct from report_row.protected_person_id::text
       or p_preview_snapshot #>> '{report,report_year}' is distinct from report_row.report_year::text
       or p_preview_snapshot #>> '{report,period_start}' is distinct from report_row.period_start::text
       or p_preview_snapshot #>> '{report,period_end}' is distinct from report_row.period_end::text
       or p_preview_snapshot #>> '{report,status}' is distinct from expected_snapshot_status then
      raise exception using errcode='P4O02',
        message='Le snapshot ne correspond pas au compte de gestion.';
    end if;
    insert into public.management_report_documents(
      management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      preview_snapshot,snapshot_schema_version,generated_by)
    values(report_row.id,
      case when operation_row.workflow='management_report_generate'
        then 'management_report_draft'::public.management_report_document_type
        else 'management_report'::public.management_report_document_type end,
      target_row.object_path,btrim(p_file_name),p_mime_type,p_file_size,
      p_preview_snapshot,p_snapshot_schema_version,auth.uid());
    if operation_row.workflow='management_report_generate' then
      update public.management_reports set status='generated',generated_at=now(),finalized_at=null
      where id=report_row.id and status::text='ready';
    else
      select * into draft_target from public.document_operation_targets
      where operation_id=p_operation_id and target_role='source';
      delete from public.management_report_documents
      where management_report_id=report_row.id
        and document_type='management_report_draft'
        and storage_path=draft_target.object_path;
      if not found then raise exception using errcode='P4O02',message='PDF projet introuvable.'; end if;
      update public.management_reports set status='finalized',finalized_at=now()
      where id=report_row.id and status::text='generated';
    end if;
    if not found then raise exception using errcode='P4O02',message='Le statut du compte a changé.'; end if;
  end if;
  return public.transition_document_operation(p_operation_id,'executing','completed');
end;
$$;

create function public.begin_document_operation_compensation(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_safe_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare operation_row public.document_operations%rowtype;
  target_row public.document_operation_targets%rowtype;
  next_revision bigint; targets jsonb;
begin
  if p_safe_code is null or p_safe_code !~ '^[A-Z0-9_:-]{1,64}$' then
    raise exception using errcode='P4O02',message='Code de compensation invalide.';
  end if;
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['executing','attention_required'],true);
  perform public.assert_document_operation_business_state(p_operation_id);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id order by ordinal for update
  loop
    if target_row.application_state='applied' then
      perform public.assert_document_target_catalog_state(target_row.id,'applied');
    elsif target_row.application_state<>'pending' then
      raise exception using errcode='P4S05',message='État de cible incompatible avec la compensation.';
    end if;
  end loop;
  next_revision:=public.transition_document_operation(
    p_operation_id,operation_row.state,'compensating',p_safe_code);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id and application_state='applied'
    order by ordinal for update
  loop
    perform public.transition_document_operation_target(
      target_row.id,target_row.target_revision,'compensating');
  end loop;
  select row_revision into next_revision from public.document_operations where id=p_operation_id;
  select jsonb_agg(jsonb_build_object('id',target.id,'ordinal',target.ordinal,
    'bucketId',target.bucket_id,'objectPath',target.object_path,
    'action',target.compensation_action,'revision',target.target_revision,
    'expectedObjectId',target.compensation_expected_object_id,
    'expectedObjectVersion',target.compensation_expected_object_version)
    order by target.ordinal) into targets
  from public.document_operation_targets target
  where target.operation_id=p_operation_id and target.application_state='compensating';
  return jsonb_build_object('operationId',p_operation_id,'state','compensating',
    'revision',next_revision,'targets',coalesce(targets,'[]'::jsonb));
end;
$$;

create function public.record_document_operation_target_compensated(
  p_operation_id uuid,
  p_target_id uuid,
  p_expected_operation_revision bigint,
  p_expected_target_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare target_row public.document_operation_targets%rowtype;
  object_row storage.objects%rowtype; object_found boolean;
  target_revision bigint; operation_revision bigint;
begin
  perform public.assert_document_operation_caller(
    p_operation_id,p_expected_operation_revision,array['compensating'],true);
  select * into target_row from public.document_operation_targets
  where id=p_target_id and operation_id=p_operation_id for update;
  if not found or target_row.application_state<>'compensating'
     or target_row.target_revision<>p_expected_target_revision then
    raise exception using errcode='P4S05',message='La cible de compensation a changé.';
  end if;
  select * into object_row from storage.objects object
  where object.bucket_id=target_row.bucket_id and object.name=target_row.object_path
  for key share;
  object_found:=found;
  if target_row.compensation_action='delete' and object_found then
    raise exception using errcode='P4S04',message='La suppression de compensation n’est pas effective.';
  elsif target_row.compensation_action in ('insert','update') and (
    not object_found or object_row.version is null or btrim(object_row.version)='') then
    raise exception using errcode='P4S04',message='La restauration Storage est introuvable.';
  elsif target_row.compensation_action='update' and (
    object_row.id is distinct from target_row.compensation_expected_object_id
    or object_row.version is not distinct from target_row.compensation_expected_object_version) then
    raise exception using errcode='P4S04',message='La restauration Storage n’a pas produit une nouvelle version.';
  end if;
  target_revision:=public.transition_document_operation_target(
    p_target_id,p_expected_target_revision,'compensated',
    case when object_found then object_row.id end,
    case when object_found then object_row.version end);
  select row_revision into operation_revision from public.document_operations where id=p_operation_id;
  return jsonb_build_object('operationId',p_operation_id,'revision',operation_revision,
    'targetId',p_target_id,'targetRevision',target_revision,'state','compensated');
end;
$$;

create function public.complete_document_operation_compensation(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare target_row public.document_operation_targets%rowtype;
begin
  perform public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['compensating'],true);
  perform public.assert_document_operation_business_state(p_operation_id);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id order by ordinal for update
  loop
    if target_row.application_state='compensated' then
      perform public.assert_document_target_catalog_state(target_row.id,'compensated');
    elsif target_row.application_state<>'pending' then
      raise exception using errcode='P4S05',message='La compensation est incomplète.';
    end if;
  end loop;
  return public.transition_document_operation(p_operation_id,'compensating','compensated');
end;
$$;

create function public.mark_document_operation_attention_required(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_safe_code text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare operation_row public.document_operations%rowtype;
begin
  if p_safe_code is null or p_safe_code !~ '^[A-Z0-9_:-]{1,64}$' then
    raise exception using errcode='P4O02',message='Code d’erreur sûr invalide.';
  end if;
  -- Cette issue reste disponible à l'initiateur après perte de droit ou
  -- archivage afin de ne jamais abandonner silencieusement un état incertain.
  operation_row:=public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,
    array['reserved','executing','compensating'],false);
  return public.transition_document_operation(
    p_operation_id,operation_row.state,'attention_required',p_safe_code);
end;
$$;

create function public.cancel_reserved_document_operation(
  p_operation_id uuid,
  p_expected_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare target_row public.document_operation_targets%rowtype;
begin
  perform public.assert_document_operation_caller(
    p_operation_id,p_expected_revision,array['reserved'],true);
  for target_row in select * from public.document_operation_targets
    where operation_id=p_operation_id order by ordinal for update
  loop
    perform public.assert_document_target_catalog_state(target_row.id,'expected');
  end loop;
  return public.transition_document_operation(p_operation_id,'reserved','cancelled');
end;
$$;

create function public.get_document_operation_progress(
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid:=auth.uid();
  operation_row public.document_operations%rowtype;
  targets jsonb;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode='P4O01',
      message='Accès à l’opération documentaire refusé.';
  end if;
  select * into operation_row from public.document_operations
  where id=p_operation_id;
  if not found or operation_row.initiator_kind<>'user'
     or operation_row.initiator_subject_id<>caller_id
     or not public.can_manage_protected_person(operation_row.protected_person_id) then
    raise exception using errcode='P4O01',
      message='Accès à l’opération documentaire refusé.';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id',target.id,'ordinal',target.ordinal,'bucketId',target.bucket_id,
    'objectPath',target.object_path,'role',target.target_role,
    'forwardAction',target.forward_action,
    'compensationAction',target.compensation_action,
    'state',target.application_state,'revision',target.target_revision,
    'expectedObjectId',target.expected_object_id,
    'expectedObjectVersion',target.expected_object_version,
    'appliedObjectId',target.applied_object_id,
    'appliedObjectVersion',target.applied_object_version,
    'compensatedObjectId',target.compensated_object_id,
    'compensatedObjectVersion',target.compensated_object_version
  ) order by target.ordinal) into targets
  from public.document_operation_targets target
  where target.operation_id=p_operation_id;
  return jsonb_build_object('operationId',operation_row.id,
    'workflow',operation_row.workflow,'state',operation_row.state,
    'revision',operation_row.row_revision,'safeErrorCode',operation_row.safe_error_code,
    'targets',coalesce(targets,'[]'::jsonb));
end;
$$;

revoke all on function public.assert_document_operation_caller(uuid,bigint,text[],boolean),
  public.assert_document_operation_business_state(uuid),
  public.assert_document_target_catalog_state(uuid,text),
  public.assert_document_operation_ready_to_finalize(uuid),
  public.assert_document_object_metadata(uuid,text,bigint,bigint)
from public,anon,authenticated,service_role;

revoke all on function public.start_document_operation(uuid,bigint),
  public.record_document_operation_target_applied(uuid,uuid,bigint,bigint),
  public.finalize_transaction_proof_document_operation(uuid,bigint,text,text,bigint),
  public.finalize_bank_statement_document_operation(uuid,bigint,date,date,numeric,text,text,text,bigint),
  public.finalize_management_report_document_operation(uuid,bigint,text,text,bigint,jsonb,integer),
  public.begin_document_operation_compensation(uuid,bigint,text),
  public.record_document_operation_target_compensated(uuid,uuid,bigint,bigint),
  public.complete_document_operation_compensation(uuid,bigint),
  public.mark_document_operation_attention_required(uuid,bigint,text),
  public.cancel_reserved_document_operation(uuid,bigint),
  public.get_document_operation_progress(uuid)
from public,anon,authenticated,service_role;

grant execute on function public.start_document_operation(uuid,bigint),
  public.record_document_operation_target_applied(uuid,uuid,bigint,bigint),
  public.finalize_transaction_proof_document_operation(uuid,bigint,text,text,bigint),
  public.finalize_bank_statement_document_operation(uuid,bigint,date,date,numeric,text,text,text,bigint),
  public.finalize_management_report_document_operation(uuid,bigint,text,text,bigint,jsonb,integer),
  public.begin_document_operation_compensation(uuid,bigint,text),
  public.record_document_operation_target_compensated(uuid,uuid,bigint,bigint),
  public.complete_document_operation_compensation(uuid,bigint),
  public.mark_document_operation_attention_required(uuid,bigint,text),
  public.cancel_reserved_document_operation(uuid,bigint),
  public.get_document_operation_progress(uuid)
to authenticated;

comment on function public.start_document_operation(uuid,bigint) is
  'Démarre une réservation après contrôle optimiste, métier et du catalogue Storage.';
comment on function public.record_document_operation_target_applied(uuid,uuid,bigint,bigint) is
  'Enregistre une mutation uniquement après observation directe de storage.objects.';
comment on function public.begin_document_operation_compensation(uuid,bigint,text) is
  'Prépare une compensation ; les octets supprimés ou remplacés doivent être fournis par l’orchestrateur.';
comment on function public.get_document_operation_progress(uuid) is
  'Relit une opération interrompue et ses révisions sans autoriser de mutation ni de nouveau chemin.';
