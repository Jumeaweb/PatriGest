-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-2C
-- Fondations SQL de la garde Storage. Aucun trigger n'est installé sur
-- storage.objects dans ce lot et la garde reste désactivée par défaut.

create table public.document_storage_guard_runtime_config (
  singleton boolean primary key default true check (singleton),
  guard_enabled boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.document_storage_guard_runtime_config(singleton, guard_enabled)
values (true, false);

alter table public.document_storage_guard_runtime_config enable row level security;
revoke all on table public.document_storage_guard_runtime_config
from public, anon, authenticated, service_role;

create function public.is_document_storage_guard_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select config.guard_enabled
    from public.document_storage_guard_runtime_config config
    where config.singleton
  ), false);
$$;

create function public.resolve_canonical_document_storage_path(
  p_bucket_id text,
  p_object_path text
)
returns table (
  is_canonical boolean,
  protected_person_id uuid,
  business_entity_type text,
  business_entity_id uuid,
  parent_entity_id uuid,
  document_kind text
)
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  path_match text[];
  uuid_pattern constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
begin
  is_canonical := false;
  protected_person_id := null;
  business_entity_type := null;
  business_entity_id := null;
  parent_entity_id := null;
  document_kind := null;

  if p_bucket_id = 'transaction-proofs' then
    path_match := pg_catalog.regexp_match(
      p_object_path,
      '^protected-persons/(' || uuid_pattern || ')/transactions/(' || uuid_pattern || ')/proof$'
    );
    if path_match is not null then
      is_canonical := true;
      protected_person_id := path_match[1]::uuid;
      business_entity_type := 'transaction';
      business_entity_id := path_match[2]::uuid;
      document_kind := 'transaction_proof';
    end if;
  elsif p_bucket_id = 'bank-statements' then
    path_match := pg_catalog.regexp_match(
      p_object_path,
      '^protected-persons/(' || uuid_pattern || ')/accounts/(' || uuid_pattern ||
      ')/statements/(' || uuid_pattern || ')/statement$'
    );
    if path_match is not null then
      is_canonical := true;
      protected_person_id := path_match[1]::uuid;
      parent_entity_id := path_match[2]::uuid;
      business_entity_type := 'bank_statement';
      business_entity_id := path_match[3]::uuid;
      document_kind := 'bank_statement';
    end if;
  elsif p_bucket_id = 'management-reports' then
    path_match := pg_catalog.regexp_match(
      p_object_path,
      '^protected-persons/(' || uuid_pattern || ')/management-reports/(' || uuid_pattern ||
      ')/(management-report-draft[.]pdf|management-report[.]pdf)$'
    );
    if path_match is not null then
      is_canonical := true;
      protected_person_id := path_match[1]::uuid;
      business_entity_type := 'management_report';
      business_entity_id := path_match[2]::uuid;
      document_kind := case path_match[3]
        when 'management-report-draft.pdf' then 'management_report_draft'
        else 'management_report_final'
      end;
    end if;
  end if;

  return next;
end;
$$;

alter table public.document_operations
  drop constraint document_operations_workflow_check;
alter table public.document_operations
  add constraint document_operations_workflow_check check (workflow in (
    'transaction_proof_create','transaction_proof_replace','transaction_proof_delete',
    'bank_statement_create','bank_statement_attach','bank_statement_replace','bank_statement_delete',
    'management_report_generate','management_report_finalize','management_report_resume',
    'account_storage_neutralization','administrative_repair'));

alter table public.document_operation_targets
  add column expected_object_id uuid,
  add column expected_object_version text,
  add column expected_snapshot_captured_at timestamptz,
  add column application_state text not null default 'pending',
  add column applied_object_id uuid,
  add column applied_object_version text,
  add column applied_at timestamptz,
  add column compensation_expected_exists boolean,
  add column compensation_expected_object_id uuid,
  add column compensation_expected_object_version text,
  add column compensation_started_at timestamptz,
  add column compensated_object_id uuid,
  add column compensated_object_version text,
  add column compensated_at timestamptz,
  add column target_revision bigint not null default 0;

alter table public.document_operation_targets
  add constraint document_operation_targets_application_state_check
    check (application_state in ('pending','applied','compensating','compensated')),
  add constraint document_operation_targets_target_revision_check
    check (target_revision >= 0),
  add constraint document_operation_targets_expected_identity_check check (
    (expected_object_id is null) = (expected_object_version is null)
    and (expected_object_version is null or btrim(expected_object_version) <> '')
    and (expected_exists or expected_object_id is null)
  ),
  add constraint document_operation_targets_applied_identity_check check (
    (applied_object_id is null) = (applied_object_version is null)
    and (applied_object_version is null or btrim(applied_object_version) <> '')
  ),
  add constraint document_operation_targets_compensation_expected_identity_check check (
    (compensation_expected_object_id is null) = (compensation_expected_object_version is null)
    and (compensation_expected_object_version is null or btrim(compensation_expected_object_version) <> '')
    and (compensation_expected_exists is distinct from false or compensation_expected_object_id is null)
  ),
  add constraint document_operation_targets_compensated_identity_check check (
    (compensated_object_id is null) = (compensated_object_version is null)
    and (compensated_object_version is null or btrim(compensated_object_version) <> '')
  ),
  add constraint document_operation_targets_application_timestamps_check check (
    (application_state = 'pending' and applied_at is null and compensation_started_at is null and compensated_at is null)
    or (application_state = 'applied' and applied_at is not null and compensation_started_at is null and compensated_at is null)
    or (application_state = 'compensating' and applied_at is not null and compensation_started_at is not null and compensated_at is null)
    or (application_state = 'compensated' and applied_at is not null and compensation_started_at is not null and compensated_at is not null)
  );

-- Les éventuelles réservations locales déjà présentes sont enrichies quand
-- leur état Storage est démontrable. Les autres restent volontairement sans
-- snapshot et seront refusées si la garde est activée ultérieurement.
update public.document_operation_targets target
set expected_object_id = object.id,
    expected_object_version = object.version,
    expected_snapshot_captured_at = clock_timestamp()
from storage.objects object
where target.expected_exists
  and object.bucket_id = target.bucket_id
  and object.name = target.object_path
  and object.version is not null
  and btrim(object.version) <> '';

update public.document_operation_targets target
set expected_snapshot_captured_at = clock_timestamp()
where not target.expected_exists
  and not exists (
    select 1 from storage.objects object
    where object.bucket_id = target.bucket_id
      and object.name = target.object_path
  );

alter table public.document_operation_events
  drop constraint document_operation_events_event_type_check;
alter table public.document_operation_events
  add column observed_object_version text,
  add constraint document_operation_events_observed_version_check
    check (observed_object_version is null or btrim(observed_object_version) <> ''),
  add constraint document_operation_events_event_type_check check (event_type in
    ('reserved','execution_started','compensation_started','attention_required',
     'completed','compensated','cancelled','administratively_resolved','object_observed',
     'target_applied','target_compensation_started','target_compensated'));

create or replace function public.create_document_operation(
  p_protected_person_id uuid, p_workflow text, p_entity_type text,
  p_entity_id uuid, p_client_request_id uuid, p_targets jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  v_operation_id uuid;
  existing public.document_operations%rowtype;
  target jsonb;
  v_target_id uuid;
  resolution record;
  v_expected_exists boolean;
  v_object_id uuid;
  v_object_version text;
  v_object_found boolean;
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

  for target in
    select value from jsonb_array_elements(p_targets)
    order by value->>'bucket_id',value->>'object_path'
  loop
    select * into resolution
    from public.resolve_canonical_document_storage_path(
      target->>'bucket_id', target->>'object_path'
    );
    if not resolution.is_canonical
       or resolution.protected_person_id is distinct from p_protected_person_id
       or resolution.business_entity_type is distinct from p_entity_type
       or resolution.business_entity_id is distinct from p_entity_id then
      raise exception using errcode='P4O02', message='Cible documentaire non canonique.';
    end if;

    v_expected_exists := (target->>'expected_exists')::boolean;
    v_object_id := null;
    v_object_version := null;
    select object.id, object.version
    into v_object_id, v_object_version
    from storage.objects object
    where object.bucket_id=target->>'bucket_id'
      and object.name=target->>'object_path'
    for key share;
    v_object_found := found;

    if v_expected_exists and not v_object_found then
      raise exception using errcode='P4O07', message='L’objet Storage attendu est introuvable.';
    elsif not v_expected_exists and v_object_found then
      raise exception using errcode='P4O07', message='Le chemin Storage attendu libre est déjà occupé.';
    elsif v_expected_exists and (v_object_version is null or btrim(v_object_version) = '') then
      raise exception using errcode='P4O07', message='La version de l’objet Storage est indisponible.';
    end if;

    insert into public.document_operation_targets(
      operation_id,ordinal,bucket_id,object_path,target_role,forward_action,
      compensation_action,expected_exists,expected_object_id,
      expected_object_version,expected_snapshot_captured_at)
    values(
      v_operation_id,(target->>'ordinal')::smallint,target->>'bucket_id',
      target->>'object_path',target->>'target_role',target->>'forward_action',
      nullif(target->>'compensation_action',''),v_expected_exists,
      case when v_expected_exists then v_object_id else null end,
      case when v_expected_exists then v_object_version else null end,
      clock_timestamp())
    returning id into v_target_id;

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

create or replace function public.begin_bank_statement_document_operation(
  p_protected_person_id uuid,p_financial_account_id uuid,p_statement_id uuid,
  p_intent text,p_client_request_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  account_person uuid;
  statement_row public.bank_statements%rowtype;
  statement_found boolean;
  expected_path text;
  targets jsonb;
  workflow text;
  forward_action text;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  select protected_person_id into account_person from public.financial_accounts
  where id=p_financial_account_id for key share;
  if not found or account_person<>p_protected_person_id or p_statement_id is null
     or p_intent not in ('create','attach','replace','delete') then
    raise exception using errcode='P4O02',message='Relevé ou rattachement invalide.';
  end if;

  expected_path:='protected-persons/'||p_protected_person_id||'/accounts/'||
    p_financial_account_id||'/statements/'||p_statement_id||'/statement';
  select * into statement_row from public.bank_statements
  where id=p_statement_id for update;
  statement_found := found;

  if p_intent='create' and statement_found then
    raise exception using errcode='P4O02',message='État du relevé incompatible avec la demande.';
  elsif p_intent='attach' and (
      not statement_found
      or statement_row.financial_account_id<>p_financial_account_id
      or statement_row.storage_path<>expected_path
      or statement_row.original_file_name is not null
      or statement_row.mime_type is not null
      or statement_row.file_size is not null) then
    raise exception using errcode='P4O02',message='État du relevé incompatible avec la demande.';
  elsif p_intent in ('replace','delete') and (
      not statement_found
      or statement_row.financial_account_id<>p_financial_account_id
      or statement_row.storage_path<>expected_path
      or statement_row.original_file_name is null
      or statement_row.mime_type is null
      or statement_row.file_size is null) then
    raise exception using errcode='P4O02',message='État du relevé incompatible avec la demande.';
  end if;

  workflow := case when p_intent='attach' then 'bank_statement_attach'
    else 'bank_statement_'||p_intent end;
  forward_action := case when p_intent in ('create','attach') then 'insert'
    when p_intent='replace' then 'update' else 'delete' end;
  targets:=jsonb_build_array(jsonb_build_object(
    'ordinal',1,'bucket_id','bank-statements','object_path',expected_path,
    'target_role','primary','forward_action',forward_action,
    'compensation_action',case when p_intent in ('create','attach') then 'delete'
      when p_intent='replace' then 'update' else 'insert' end,
    'expected_exists',p_intent in ('replace','delete')));

  return public.create_document_operation(p_protected_person_id,workflow,
    'bank_statement',p_statement_id,p_client_request_id,targets);
end;
$$;

create or replace function public.validate_document_storage_mutation(
  p_bucket_id text,
  p_object_path text,
  p_sql_operation text,
  p_existing_object_id uuid default null,
  p_existing_object_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolution record;
  target_row public.document_operation_targets%rowtype;
  operation_row public.document_operations%rowtype;
  effective_action text;
  expected_action text;
  expected_exists boolean;
  expected_object_id uuid;
  expected_object_version text;
  locked_target_id uuid;
  locked_operation_id uuid;
begin
  if not public.is_document_storage_guard_enabled() then
    return null;
  end if;

  select * into resolution
  from public.resolve_canonical_document_storage_path(p_bucket_id,p_object_path);
  if not resolution.is_canonical then
    raise exception using errcode='P4S01',message='Chemin Storage non canonique.';
  end if;

  select target.id, operation.id
  into locked_target_id, locked_operation_id
  from public.document_object_locks object_lock
  join public.document_operation_targets target on target.id=object_lock.target_id
  join public.document_operations operation on operation.id=object_lock.operation_id
  where object_lock.bucket_id=p_bucket_id
    and object_lock.object_path=p_object_path
  for update of target, operation;
  if not found then
    raise exception using errcode='P4S02',message='Aucune réservation Storage active ne correspond à cette cible.';
  end if;
  select * into target_row from public.document_operation_targets
  where id=locked_target_id;
  select * into operation_row from public.document_operations
  where id=locked_operation_id;

  if operation_row.protected_person_id is distinct from resolution.protected_person_id
     or operation_row.business_entity_type is distinct from resolution.business_entity_type
     or operation_row.business_entity_id is distinct from resolution.business_entity_id then
    raise exception using errcode='P4S01',message='Le chemin Storage ne correspond pas à la réservation.';
  end if;

  effective_action := case upper(p_sql_operation)
    when 'INSERT' then case when p_existing_object_id is null then 'insert' else 'update' end
    when 'UPDATE' then 'update'
    when 'DELETE' then 'delete'
    else null
  end;
  if effective_action is null then
    raise exception using errcode='P4S03',message='Mutation Storage non reconnue.';
  end if;

  if operation_row.state='executing' then
    if target_row.application_state<>'pending' then
      raise exception using errcode='P4S03',message='Cette cible Storage a déjà été consommée.';
    end if;
    expected_action:=target_row.forward_action;
    expected_exists:=target_row.expected_exists;
    expected_object_id:=target_row.expected_object_id;
    expected_object_version:=target_row.expected_object_version;
    if target_row.expected_snapshot_captured_at is null then
      raise exception using errcode='P4S04',message='L’état Storage attendu n’a pas été capturé.';
    end if;
  elsif operation_row.state='compensating' then
    if target_row.application_state<>'compensating' then
      raise exception using errcode='P4S03',message='Cette cible n’est pas prête pour une compensation.';
    end if;
    expected_action:=target_row.compensation_action;
    expected_exists:=target_row.compensation_expected_exists;
    expected_object_id:=target_row.compensation_expected_object_id;
    expected_object_version:=target_row.compensation_expected_object_version;
    if expected_exists is null then
      raise exception using errcode='P4S04',message='L’état de compensation attendu n’a pas été capturé.';
    end if;
  else
    raise exception using errcode='P4S03',message='La réservation Storage n’est pas en cours d’exécution.';
  end if;

  if effective_action is distinct from expected_action then
    raise exception using errcode='P4S03',message='La mutation Storage ne correspond pas à l’action réservée.';
  end if;
  if expected_exists and (
      p_existing_object_id is distinct from expected_object_id
      or p_existing_object_version is distinct from expected_object_version) then
    raise exception using errcode='P4S04',message='L’objet Storage a changé depuis la réservation.';
  elsif not expected_exists and p_existing_object_id is not null then
    raise exception using errcode='P4S04',message='Le chemin Storage n’est plus libre.';
  end if;

  return target_row.id;
end;
$$;

create function public.append_document_operation_target_event(
  p_operation_id uuid,
  p_target_id uuid,
  p_event_type text,
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
  operation_actor public.document_operations%rowtype;
begin
  update public.document_operations operation
  set row_revision=operation.row_revision+1,last_activity_at=clock_timestamp()
  where operation.id=p_operation_id
  returning operation.* into operation_actor;
  if not found then
    raise exception using errcode='P4O02',message='Opération documentaire introuvable.';
  end if;
  next_sequence:=operation_actor.row_revision;
  insert into public.document_operation_events(
    operation_id,sequence_number,target_id,event_type,outcome,actor_id,actor_kind,
    observed_object_id,observed_object_version)
  values(
    p_operation_id,next_sequence,p_target_id,p_event_type,'success',
    coalesce(auth.uid(),operation_actor.initiated_by),operation_actor.initiator_kind,
    p_observed_object_id,p_observed_object_version);
end;
$$;

create function public.transition_document_operation_target(
  p_target_id uuid,
  p_expected_revision bigint,
  p_new_state text,
  p_observed_object_id uuid default null,
  p_observed_object_version text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_row public.document_operation_targets%rowtype;
  operation_state text;
  locked_operation_id uuid;
  next_revision bigint;
  event_name text;
begin
  select target.operation_id, operation.state
  into locked_operation_id, operation_state
  from public.document_operation_targets target
  join public.document_operations operation on operation.id=target.operation_id
  where target.id=p_target_id
  for update of target, operation;
  if not found then
    raise exception using errcode='P4S05',message='Cible documentaire introuvable.';
  end if;
  select * into target_row from public.document_operation_targets
  where id=p_target_id and operation_id=locked_operation_id;
  if target_row.target_revision<>p_expected_revision then
    raise exception using errcode='P4S05',message='La révision de la cible documentaire a changé.';
  end if;

  if target_row.application_state='pending' and p_new_state='applied'
     and operation_state='executing' then
    if target_row.forward_action in ('insert','update') and
       (p_observed_object_id is null or p_observed_object_version is null
        or btrim(p_observed_object_version)='') then
      raise exception using errcode='P4S05',message='Le résultat Storage appliqué est incomplet.';
    elsif target_row.forward_action='delete' and
       (p_observed_object_id is not null or p_observed_object_version is not null) then
      raise exception using errcode='P4S05',message='Une suppression Storage ne produit pas d’objet.';
    end if;
    update public.document_operation_targets
    set application_state='applied',applied_object_id=p_observed_object_id,
      applied_object_version=p_observed_object_version,applied_at=clock_timestamp(),
      compensation_expected_exists=forward_action<>'delete',
      compensation_expected_object_id=case when forward_action<>'delete' then p_observed_object_id end,
      compensation_expected_object_version=case when forward_action<>'delete' then p_observed_object_version end,
      target_revision=target_revision+1
    where id=p_target_id returning target_revision into next_revision;
    event_name:='target_applied';
  elsif target_row.application_state='applied' and p_new_state='compensating'
     and operation_state='compensating' and target_row.compensation_action is not null then
    if p_observed_object_id is not null or p_observed_object_version is not null then
      raise exception using errcode='P4S05',message='Le démarrage de compensation n’observe pas encore de résultat.';
    end if;
    update public.document_operation_targets
    set application_state='compensating',compensation_started_at=clock_timestamp(),
      target_revision=target_revision+1
    where id=p_target_id returning target_revision into next_revision;
    event_name:='target_compensation_started';
  elsif target_row.application_state='compensating' and p_new_state='compensated'
     and operation_state='compensating' then
    if target_row.compensation_action in ('insert','update') and
       (p_observed_object_id is null or p_observed_object_version is null
        or btrim(p_observed_object_version)='') then
      raise exception using errcode='P4S05',message='Le résultat de compensation est incomplet.';
    elsif target_row.compensation_action='delete' and
       (p_observed_object_id is not null or p_observed_object_version is not null) then
      raise exception using errcode='P4S05',message='Une compensation par suppression ne produit pas d’objet.';
    end if;
    update public.document_operation_targets
    set application_state='compensated',compensated_object_id=p_observed_object_id,
      compensated_object_version=p_observed_object_version,compensated_at=clock_timestamp(),
      target_revision=target_revision+1
    where id=p_target_id returning target_revision into next_revision;
    event_name:='target_compensated';
  else
    raise exception using errcode='P4S05',message='Transition de cible documentaire invalide.';
  end if;

  perform public.append_document_operation_target_event(
    target_row.operation_id,p_target_id,event_name,p_observed_object_id,p_observed_object_version
  );
  return next_revision;
end;
$$;

create or replace function public.validate_document_operation_update()
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
  if new.state='completed' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id=new.id and target.application_state<>'applied'
  ) then
    raise exception using errcode='23514',message='Toutes les cibles doivent être appliquées avant la finalisation.';
  end if;
  if new.state='compensated' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id=new.id and target.application_state not in ('pending','compensated')
  ) then
    raise exception using errcode='23514',message='Toutes les cibles appliquées doivent être compensées.';
  end if;
  if new.state='cancelled' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id=new.id and target.application_state<>'pending'
  ) then
    raise exception using errcode='23514',message='Une opération déjà appliquée ne peut pas être annulée.';
  end if;
  return new;
end;
$$;

revoke all on function public.is_document_storage_guard_enabled(),
  public.resolve_canonical_document_storage_path(text,text),
  public.validate_document_storage_mutation(text,text,text,uuid,text),
  public.append_document_operation_target_event(uuid,uuid,text,uuid,text),
  public.transition_document_operation_target(uuid,bigint,text,uuid,text)
from public,anon,authenticated,service_role;

-- La signature de la RPC reste identique ; seul le nouvel intent "attach" est
-- ajouté. Les permissions existantes sont réaffirmées explicitement.
revoke all on function public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid)
from public,anon,authenticated,service_role;
grant execute on function public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid)
to authenticated;

comment on table public.document_storage_guard_runtime_config is
  'Verrou interne indépendant de la garde Storage, désactivé par défaut et sans RPC publique d’activation.';
comment on function public.resolve_canonical_document_storage_path(text,text) is
  'Résout uniquement les chemins documentaires canoniques exacts des trois buckets PatriGest.';
comment on function public.validate_document_storage_mutation(text,text,text,uuid,text) is
  'Validation interne neutre tant que la garde est désactivée ; aucun trigger Storage ne l’appelle encore.';
comment on column public.document_operation_targets.expected_object_version is
  'Version du catalogue Storage utilisée pour la concurrence, jamais comme preuve d’intégrité des octets.';
