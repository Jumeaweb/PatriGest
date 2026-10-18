-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-1
-- Réservations documentaires transactionnelles. Ce lot ne modifie ni les
-- objets Storage ni leurs politiques et laisse le cycle de vie désactivé.

create table public.protected_person_archive_runtime_config (
  singleton boolean primary key default true check (singleton),
  lifecycle_enabled boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.protected_person_archive_runtime_config(singleton, lifecycle_enabled)
values (true, false);

alter table public.protected_person_archive_runtime_config enable row level security;
revoke all on table public.protected_person_archive_runtime_config
from public, anon, authenticated, service_role;

create function public.assert_protected_person_archive_lifecycle_enabled()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce((select lifecycle_enabled
                   from public.protected_person_archive_runtime_config
                   where singleton), false) then
    raise exception using errcode = 'P4A07',
      message = 'Le cycle de vie des dossiers n’est pas activé.';
  end if;
end;
$$;

create table public.document_operations (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  initiated_by uuid references auth.users(id) on delete set null,
  initiator_subject_id uuid not null,
  initiator_kind text not null default 'user'
    check (initiator_kind in ('user','account_deletion','platform_admin','system')),
  workflow text not null check (workflow in (
    'transaction_proof_create','transaction_proof_replace','transaction_proof_delete',
    'bank_statement_create','bank_statement_replace','bank_statement_delete',
    'management_report_generate','management_report_finalize','management_report_resume',
    'account_storage_neutralization','administrative_repair')),
  business_entity_type text not null check (business_entity_type in
    ('transaction','bank_statement','management_report','protected_person')),
  business_entity_id uuid not null,
  client_request_id uuid not null,
  state text not null default 'reserved' check (state in
    ('reserved','executing','compensating','attention_required','completed',
     'compensated','cancelled','administratively_resolved')),
  target_signature jsonb not null check (jsonb_typeof(target_signature) = 'array'),
  created_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  last_activity_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  safe_error_code text check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_:-]{1,64}$'),
  resolution_reason text check (resolution_reason is null or char_length(btrim(resolution_reason)) between 1 and 2000),
  resolution_by uuid references auth.users(id) on delete set null,
  resolution_at timestamptz,
  row_revision bigint not null default 0 check (row_revision >= 0),
  unique (initiator_subject_id, client_request_id),
  check ((state in ('completed','compensated','cancelled','administratively_resolved')) = (closed_at is not null)),
  check ((resolution_reason is null and resolution_by is null and resolution_at is null)
      or (resolution_reason is not null and resolution_at is not null))
);

create index document_operations_person_state_idx
on public.document_operations(protected_person_id, state);
create index document_operations_entity_idx
on public.document_operations(business_entity_type, business_entity_id);

create table public.document_operation_targets (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  ordinal smallint not null check (ordinal between 1 and 16),
  bucket_id text not null check (bucket_id in ('transaction-proofs','bank-statements','management-reports')),
  object_path text not null check (
    object_path = btrim(object_path) and object_path <> '' and
    position(chr(92) in object_path) = 0 and
    object_path !~ '(^/|(^|/)\.\.(/|$)|//)' and
    object_path like 'protected-persons/%'),
  target_role text not null check (target_role in ('primary','source','destination')),
  forward_action text not null check (forward_action in ('insert','update','delete')),
  compensation_action text check (compensation_action in ('insert','update','delete')),
  expected_exists boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(operation_id, ordinal), unique(operation_id, bucket_id, object_path),
  unique(id, operation_id)
);

create table public.document_object_locks (
  bucket_id text not null,
  object_path text not null,
  target_id uuid not null,
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  acquired_at timestamptz not null default clock_timestamp(),
  primary key(bucket_id, object_path), unique(target_id),
  foreign key(target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict
);

create table public.document_operation_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  sequence_number bigint not null check (sequence_number > 0),
  target_id uuid,
  event_type text not null check (event_type in
    ('reserved','execution_started','compensation_started','attention_required',
     'completed','compensated','cancelled','administratively_resolved','object_observed')),
  outcome text not null check (outcome in ('success','failure','information')),
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('user','account_deletion','platform_admin','system')),
  safe_code text check (safe_code is null or safe_code ~ '^[A-Z0-9_:-]{1,64}$'),
  observed_object_id uuid,
  observed_size bigint check (observed_size is null or observed_size >= 0),
  observed_sha256 text check (observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null default clock_timestamp(),
  unique(operation_id, sequence_number),
  foreign key(target_id, operation_id)
    references public.document_operation_targets(id, operation_id) on delete restrict
);

create index document_operation_events_operation_idx
on public.document_operation_events(operation_id, sequence_number);

alter table public.document_operations enable row level security;
alter table public.document_operation_targets enable row level security;
alter table public.document_object_locks enable row level security;
alter table public.document_operation_events enable row level security;
revoke all on table public.document_operations, public.document_operation_targets,
  public.document_object_locks, public.document_operation_events
from public, anon, authenticated, service_role;

create function public.protect_document_operation_audit_rows()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare table_owner name;
begin
  select pg_catalog.pg_get_userbyid(c.relowner) into table_owner
  from pg_catalog.pg_class c where c.oid = tg_relid;
  if current_user <> table_owner then
    raise exception using errcode = '42501', message = 'Le journal documentaire est immuable.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger document_operation_targets_immutable before update or delete
on public.document_operation_targets for each row execute function public.protect_document_operation_audit_rows();
create trigger document_operation_events_append_only before update or delete
on public.document_operation_events for each row execute function public.protect_document_operation_audit_rows();

create function public.validate_document_operation_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (new.id,new.protected_person_id,new.initiator_subject_id,new.initiator_kind,
      new.workflow,new.business_entity_type,new.business_entity_id,new.client_request_id,
      new.target_signature,new.created_at)
     is distinct from
     (old.id,old.protected_person_id,old.initiator_subject_id,old.initiator_kind,
      old.workflow,old.business_entity_type,old.business_entity_id,old.client_request_id,
      old.target_signature,old.created_at) then
    raise exception using errcode = '42501', message = 'L’identité de l’opération documentaire est immuable.';
  end if;
  if old.state in ('completed','compensated','cancelled','administratively_resolved') then
    raise exception using errcode = '23514', message = 'Une opération documentaire terminale est immuable.';
  end if;
  if new.state <> old.state and not (
    (old.state = 'reserved' and new.state in ('executing','compensating','attention_required','cancelled')) or
    (old.state = 'executing' and new.state in ('completed','compensating','attention_required')) or
    (old.state = 'compensating' and new.state in ('compensated','attention_required')) or
    (old.state = 'attention_required' and new.state in ('compensating','administratively_resolved'))
  ) then
    raise exception using errcode = '23514', message = 'Transition documentaire invalide.';
  end if;
  return new;
end;
$$;
create trigger document_operations_validate_update before update on public.document_operations
for each row execute function public.validate_document_operation_update();

create function public.append_document_operation_event(
  p_operation_id uuid, p_target_id uuid, p_event_type text, p_outcome text,
  p_safe_code text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_sequence bigint;
begin
  update public.document_operations set row_revision = row_revision + 1,
    last_activity_at = clock_timestamp()
  where id = p_operation_id returning row_revision into v_sequence;
  if not found then raise exception using errcode='P4O02', message='Opération documentaire introuvable.'; end if;
  insert into public.document_operation_events(
    operation_id,sequence_number,target_id,event_type,outcome,actor_id,actor_kind,safe_code)
  select p_operation_id,v_sequence,p_target_id,p_event_type,p_outcome,auth.uid(),
    case when auth.uid() is null then 'system' else 'user' end,p_safe_code;
end;
$$;

create function public.assert_document_operation_opening_access(p_protected_person_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); dossier_status text;
begin
  if caller_id is null or not public.is_application_user_active() or public.is_platform_admin() then
    raise exception using errcode='P4O01', message='Accès à la réservation documentaire refusé.';
  end if;
  select status into dossier_status from public.protected_persons
  where id=p_protected_person_id for key share;
  if not found or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode='P4O01', message='Accès à la réservation documentaire refusé.';
  end if;
  if dossier_status <> 'active' then
    raise exception using errcode='P4O03', message='Le dossier doit être actif.';
  end if;
end;
$$;

create function public.create_document_operation(
  p_protected_person_id uuid, p_workflow text, p_entity_type text,
  p_entity_id uuid, p_client_request_id uuid, p_targets jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); v_operation_id uuid; existing public.document_operations%rowtype;
  target jsonb; v_target_id uuid;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  if p_client_request_id is null or p_entity_id is null then
    raise exception using errcode='P4O02', message='Demande documentaire invalide.';
  end if;
  if jsonb_typeof(p_targets) <> 'array' or jsonb_array_length(p_targets) not between 1 and 16 then
    raise exception using errcode='P4O02', message='Cibles documentaires invalides.';
  end if;
  insert into public.document_operations(protected_person_id,initiated_by,initiator_subject_id,
    workflow,business_entity_type,business_entity_id,client_request_id,target_signature)
  values(p_protected_person_id,caller_id,caller_id,p_workflow,p_entity_type,p_entity_id,
    p_client_request_id,p_targets)
  on conflict(initiator_subject_id,client_request_id) do nothing returning id into v_operation_id;
  if v_operation_id is null then
    select * into existing from public.document_operations
    where initiator_subject_id=caller_id and client_request_id=p_client_request_id;
    if existing.protected_person_id is distinct from p_protected_person_id
       or existing.workflow is distinct from p_workflow
       or existing.business_entity_type is distinct from p_entity_type
       or existing.business_entity_id is distinct from p_entity_id
       or existing.target_signature is distinct from p_targets then
      raise exception using errcode='P4O04', message='La clé d’idempotence est déjà utilisée pour une autre demande.';
    end if;
    return existing.id;
  end if;
  for target in select value from jsonb_array_elements(p_targets) order by value->>'bucket_id',value->>'object_path' loop
    insert into public.document_operation_targets(operation_id,ordinal,bucket_id,object_path,
      target_role,forward_action,compensation_action,expected_exists)
    values(v_operation_id,(target->>'ordinal')::smallint,target->>'bucket_id',target->>'object_path',
      target->>'target_role',target->>'forward_action',nullif(target->>'compensation_action',''),
      (target->>'expected_exists')::boolean) returning id into v_target_id;
    begin
      insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id)
      values(target->>'bucket_id',target->>'object_path',v_target_id,v_operation_id);
    exception when unique_violation then
      raise exception using errcode='P4O05', message='Ce fichier est déjà réservé par une autre opération.';
    end;
  end loop;
  perform public.append_document_operation_event(v_operation_id,null,'reserved','success',null);
  return v_operation_id;
end;
$$;

create function public.begin_transaction_proof_document_operation(
  p_protected_person_id uuid,p_transaction_id uuid,p_intent text,p_client_request_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare tx record; doc_path text; expected_path text; targets jsonb; workflow text;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  select t.transaction_type,t.transfer_id,a.protected_person_id into tx
  from public.transactions t join public.financial_accounts a on a.id=t.financial_account_id
  where t.id=p_transaction_id for update of t;
  if not found or tx.protected_person_id<>p_protected_person_id or tx.transaction_type<>'expense' or tx.transfer_id is not null
     or p_intent not in ('create','replace','delete') then
    raise exception using errcode='P4O02',message='Justificatif ou rattachement invalide.';
  end if;
  expected_path:='protected-persons/'||p_protected_person_id||'/transactions/'||p_transaction_id||'/proof';
  select storage_path into doc_path from public.transaction_documents where transaction_id=p_transaction_id;
  if (p_intent='create' and doc_path is not null) or (p_intent<>'create' and doc_path is distinct from expected_path) then
    raise exception using errcode='P4O02',message='État du justificatif incompatible avec la demande.';
  end if;
  workflow:='transaction_proof_'||p_intent;
  targets:=jsonb_build_array(jsonb_build_object('ordinal',1,'bucket_id','transaction-proofs',
    'object_path',expected_path,'target_role','primary','forward_action',
    case when p_intent='create' then 'insert' when p_intent='replace' then 'update' else 'delete' end,
    'compensation_action',case when p_intent='create' then 'delete' when p_intent='replace' then 'update' else 'insert' end,
    'expected_exists',p_intent<>'create'));
  return public.create_document_operation(p_protected_person_id,workflow,'transaction',p_transaction_id,p_client_request_id,targets);
end; $$;

create function public.begin_bank_statement_document_operation(
  p_protected_person_id uuid,p_financial_account_id uuid,p_statement_id uuid,
  p_intent text,p_client_request_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare account_person uuid; statement_row public.bank_statements%rowtype; expected_path text; targets jsonb;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  select protected_person_id into account_person from public.financial_accounts
  where id=p_financial_account_id for key share;
  if not found or account_person<>p_protected_person_id or p_statement_id is null
     or p_intent not in ('create','replace','delete') then
    raise exception using errcode='P4O02',message='Relevé ou rattachement invalide.';
  end if;
  expected_path:='protected-persons/'||p_protected_person_id||'/accounts/'||p_financial_account_id||'/statements/'||p_statement_id||'/statement';
  select * into statement_row from public.bank_statements where id=p_statement_id for update;
  if (p_intent='create' and found) or (p_intent<>'create' and
      (not found or statement_row.financial_account_id<>p_financial_account_id or statement_row.storage_path<>expected_path)) then
    raise exception using errcode='P4O02',message='État du relevé incompatible avec la demande.';
  end if;
  targets:=jsonb_build_array(jsonb_build_object('ordinal',1,'bucket_id','bank-statements',
    'object_path',expected_path,'target_role','primary','forward_action',
    case when p_intent='create' then 'insert' when p_intent='replace' then 'update' else 'delete' end,
    'compensation_action',case when p_intent='create' then 'delete' when p_intent='replace' then 'update' else 'insert' end,
    'expected_exists',p_intent<>'create'));
  return public.create_document_operation(p_protected_person_id,'bank_statement_'||p_intent,
    'bank_statement',p_statement_id,p_client_request_id,targets);
end; $$;

create function public.begin_management_report_document_operation(
  p_protected_person_id uuid,p_report_id uuid,p_intent text,p_client_request_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare report_row public.management_reports%rowtype; draft_path text; final_path text; draft_exists boolean; final_exists boolean; targets jsonb;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  select * into report_row from public.management_reports where id=p_report_id for update;
  if not found or report_row.protected_person_id<>p_protected_person_id
     or p_intent not in ('generate','finalize','resume') then
    raise exception using errcode='P4O02',message='Compte de gestion ou rattachement invalide.';
  end if;
  draft_path:='protected-persons/'||p_protected_person_id||'/management-reports/'||p_report_id||'/management-report-draft.pdf';
  final_path:='protected-persons/'||p_protected_person_id||'/management-reports/'||p_report_id||'/management-report.pdf';
  select exists(select 1 from public.management_report_documents where management_report_id=p_report_id and document_type='management_report_draft' and storage_path=draft_path),
         exists(select 1 from public.management_report_documents where management_report_id=p_report_id and document_type='management_report' and storage_path=final_path)
    into draft_exists,final_exists;
  if (p_intent='generate' and (report_row.status::text<>'ready' or draft_exists))
     or (p_intent in ('finalize','resume') and (report_row.status::text<>'generated' or not draft_exists))
     or (p_intent='finalize' and final_exists) then
    raise exception using errcode='P4O02',message='État du compte de gestion incompatible avec la demande.';
  end if;
  if p_intent='finalize' then
    targets:=jsonb_build_array(
      jsonb_build_object('ordinal',1,'bucket_id','management-reports','object_path',final_path,'target_role','destination','forward_action','insert','compensation_action','delete','expected_exists',false),
      jsonb_build_object('ordinal',2,'bucket_id','management-reports','object_path',draft_path,'target_role','source','forward_action','delete','compensation_action','insert','expected_exists',true));
  else
    targets:=jsonb_build_array(jsonb_build_object('ordinal',1,'bucket_id','management-reports','object_path',draft_path,'target_role','primary',
      'forward_action',case when p_intent='generate' then 'insert' else 'delete' end,
      'compensation_action',case when p_intent='generate' then 'delete' else 'insert' end,
      'expected_exists',p_intent='resume'));
  end if;
  return public.create_document_operation(p_protected_person_id,'management_report_'||p_intent,
    'management_report',p_report_id,p_client_request_id,targets);
end; $$;

create function public.transition_document_operation(
  p_operation_id uuid,p_expected_state text,p_new_state text,p_safe_code text default null,
  p_resolution_reason text default null
) returns bigint language plpgsql security definer set search_path='' as $$
declare revision bigint; event_name text;
begin
  update public.document_operations set state=p_new_state,
    started_at=case when p_new_state='executing' then coalesce(started_at,clock_timestamp()) else started_at end,
    closed_at=case when p_new_state in ('completed','compensated','cancelled','administratively_resolved') then clock_timestamp() else null end,
    safe_error_code=p_safe_code,resolution_reason=case when p_new_state='administratively_resolved' then btrim(p_resolution_reason) else resolution_reason end,
    resolution_by=case when p_new_state='administratively_resolved' then auth.uid() else resolution_by end,
    resolution_at=case when p_new_state='administratively_resolved' then clock_timestamp() else resolution_at end,
    row_revision=row_revision+1,last_activity_at=clock_timestamp()
  where id=p_operation_id and state=p_expected_state returning row_revision into revision;
  if not found then raise exception using errcode='P4O06',message='L’état de l’opération documentaire a changé.'; end if;
  if p_new_state in ('completed','compensated','cancelled','administratively_resolved') then
    delete from public.document_object_locks where operation_id=p_operation_id;
  end if;
  event_name:=case p_new_state when 'executing' then 'execution_started' when 'compensating' then 'compensation_started' else p_new_state end;
  insert into public.document_operation_events(
    operation_id,sequence_number,event_type,outcome,actor_id,actor_kind,safe_code)
  values(p_operation_id,revision,event_name,
    case when p_new_state='attention_required' then 'failure' else 'success' end,
    auth.uid(),case when auth.uid() is null then 'system' else 'user' end,p_safe_code);
  return revision;
end; $$;

-- Redéfinition additive des RPC 2A : contrôles historiques préservés.
create or replace function public.archive_protected_person(p_protected_person_id uuid,p_expected_revision bigint,p_reason text)
returns bigint language plpgsql security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); dossier_owner_id uuid; person_row public.protected_persons%rowtype; archived_person public.protected_persons%rowtype; normalized_reason text:=btrim(p_reason);
begin
  if caller_id is null or not public.is_application_user_active() or public.is_platform_admin() then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.assert_protected_person_archive_lifecycle_enabled();
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then raise exception using errcode='P4A03',message='Le motif de l’archivage est invalide.'; end if;
  if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  select owner_id into dossier_owner_id from public.protected_persons where id=p_protected_person_id;
  if not found then raise exception using errcode='P4A02',message='Dossier introuvable.'; end if;
  if dossier_owner_id<>caller_id then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.lock_owner_dossier_capacity(dossier_owner_id);
  select * into person_row from public.protected_persons where id=p_protected_person_id for update;
  if person_row.archive_revision<>p_expected_revision then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  if person_row.status<>'active' or person_row.archived_at is not null then raise exception using errcode='P4A04',message='Le dossier ne peut pas être archivé dans son état actuel.'; end if;
  if exists(select 1 from public.document_operations where protected_person_id=p_protected_person_id and state in ('reserved','executing','compensating','attention_required')) then
    raise exception using errcode='P4A06',message='Une opération documentaire en cours bloque l’archivage.';
  end if;
  update public.protected_persons set status='archived',archived_at=clock_timestamp()
  where id=person_row.id and status='active' and archived_at is null and archive_revision=p_expected_revision returning * into archived_person;
  if not found then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  insert into public.protected_person_archive_changes(protected_person_id,old_status,new_status,changed_by,changed_at,reason)
  values(person_row.id,person_row.status,archived_person.status,caller_id,clock_timestamp(),normalized_reason);
  return archived_person.archive_revision;
end; $$;

create or replace function public.restore_protected_person(p_protected_person_id uuid,p_expected_revision bigint,p_reason text)
returns bigint language plpgsql security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); dossier_owner_id uuid; person_row public.protected_persons%rowtype; restored_person public.protected_persons%rowtype; normalized_reason text:=btrim(p_reason);
begin
  if caller_id is null or not public.is_application_user_active() or public.is_platform_admin() then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.assert_protected_person_archive_lifecycle_enabled();
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then raise exception using errcode='P4A03',message='Le motif de la restauration est invalide.'; end if;
  if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  select owner_id into dossier_owner_id from public.protected_persons where id=p_protected_person_id;
  if not found then raise exception using errcode='P4A02',message='Dossier introuvable.'; end if;
  if dossier_owner_id<>caller_id then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.lock_owner_dossier_capacity(dossier_owner_id);
  select * into person_row from public.protected_persons where id=p_protected_person_id for update;
  if person_row.archive_revision<>p_expected_revision then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  if person_row.status<>'archived' or person_row.archived_at is null then raise exception using errcode='P4A04',message='Le dossier ne peut pas être restauré dans son état actuel.'; end if;
  if exists(select 1 from public.document_operations where protected_person_id=p_protected_person_id and workflow='administrative_repair' and state in ('reserved','executing','compensating','attention_required')) then
    raise exception using errcode='P4A06',message='Une réparation documentaire en cours bloque la restauration.';
  end if;
  update public.protected_persons set status='active',archived_at=null
  where id=person_row.id and status='archived' and archived_at is not null and archive_revision=p_expected_revision returning * into restored_person;
  if not found then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  insert into public.protected_person_archive_changes(protected_person_id,old_status,new_status,changed_by,changed_at,reason)
  values(person_row.id,person_row.status,restored_person.status,caller_id,clock_timestamp(),normalized_reason);
  return restored_person.archive_revision;
end; $$;

-- Audit de la suppression vide : une opération active interdit la suppression ;
-- l’historique technique terminal est retiré dans la même transaction.
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
  delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id=p_protected_person_id);
  delete from public.document_operations where protected_person_id=p_protected_person_id;
  delete from public.protected_person_archive_changes where protected_person_id=p_protected_person_id;
  delete from public.proof_reference_counters where protected_person_id=p_protected_person_id;
  delete from public.protected_persons where id=p_protected_person_id;
end; $$;

revoke all on function public.assert_protected_person_archive_lifecycle_enabled(),
 public.protect_document_operation_audit_rows(),public.validate_document_operation_update(),
 public.append_document_operation_event(uuid,uuid,text,text,text),
 public.assert_document_operation_opening_access(uuid),
 public.create_document_operation(uuid,text,text,uuid,uuid,jsonb),
 public.transition_document_operation(uuid,text,text,text,text)
from public,anon,authenticated,service_role;

revoke all on function public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid),
 public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid),
 public.begin_management_report_document_operation(uuid,uuid,text,uuid)
from public,anon,authenticated,service_role;
grant execute on function public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid),
 public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid),
 public.begin_management_report_document_operation(uuid,uuid,text,uuid)
to authenticated;

comment on table public.document_operations is 'Machine d’état des opérations documentaires réservées, sans transaction Storage longue.';
comment on table public.document_object_locks is 'Verrou exclusif durable par bucket et chemin ; aucune expiration automatique.';
comment on table public.document_operation_events is 'Journal append-only sans jeton, secret ni chemin Storage interne supplémentaire.';
comment on table public.protected_person_archive_runtime_config is 'Verrou SQL interne du cycle de vie ; désactivé par défaut et sans RPC publique d’activation.';
comment on function public.archive_protected_person(uuid,bigint,text) is 'Archive atomiquement un dossier possédé ; P4A06 réservation bloquante, P4A07 cycle désactivé.';
comment on function public.restore_protected_person(uuid,bigint,text) is 'Restaure atomiquement un dossier possédé ; P4A06 réparation bloquante, P4A07 cycle désactivé.';

-- La révocation/rétrogradation d’un collaborateur reste autorisée. Les futurs
-- lots de finalisation devront revalider son droit avant chaque avancée et
-- placer l’opération en attention_required si ce droit a disparu. Tant que ces
-- gardes Storage ne sont pas livrées, le verrou SQL ci-dessus reste désactivé.
