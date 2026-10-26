begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'document_repair_exceptional_recoveries',
  'le registre privé des récupérations exceptionnelles existe'
);
select extensions.has_table(
  'public', 'document_repair_exceptional_activations',
  'les fenêtres exceptionnelles sont conservées séparément'
);
select extensions.has_table(
  'public', 'document_repair_exceptional_events',
  'le journal append-only exceptionnel existe'
);
select extensions.has_trigger(
  'public', 'document_repair_authorizations',
  'document_repair_exceptional_recovery_consumed',
  'le scellement existant consomme la récupération sans second moteur'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.document_repair_exceptional_recoveries', 'SELECT')
  and not has_table_privilege('service_role', 'public.document_repair_exceptional_recoveries', 'SELECT')
  and not has_table_privilege('authenticated', 'public.document_repair_exceptional_activations', 'INSERT')
  and not has_table_privilege('service_role', 'public.document_repair_exceptional_events', 'INSERT'),
  'aucun rôle API ne dispose d’un accès direct aux registres privés'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.request_administrative_document_exceptional_recovery(uuid,uuid,text,uuid,text,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.decide_administrative_document_exceptional_recovery(uuid,uuid,boolean,text,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.decide_administrative_document_exceptional_recovery(uuid,uuid,boolean,text,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.request_administrative_document_exceptional_recovery(uuid,uuid,text,uuid,text,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.activate_administrative_document_exceptional_recovery(uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'les trois RPC métier sont réservées à authenticated et jamais à service_role'
);
select extensions.ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'append_document_repair_exceptional_event',
        'document_repair_exceptional_context_fingerprint',
        'assert_document_repair_exceptional_eligibility',
        'document_repair_effective_expires_at',
        'request_administrative_document_exceptional_recovery',
        'decide_administrative_document_exceptional_recovery',
        'activate_administrative_document_exceptional_recovery',
        'get_administrative_document_exceptional_recovery',
        'consume_document_repair_exceptional_recovery'
      )
      and (
        (procedure.proname <> 'protect_document_repair_exceptional_recovery'
          and not procedure.prosecdef)
        or (procedure.proname = 'protect_document_repair_exceptional_recovery'
          and procedure.prosecdef)
        or not (procedure.proconfig @> array['search_path=""'])
      )
  ),
  'toutes les fonctions privilégiées utilisent SECURITY DEFINER et un search_path vide'
);

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000001','authenticated','authenticated','recovery-admin-1@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000002','authenticated','authenticated','recovery-admin-2@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000003','authenticated','authenticated','recovery-admin-3@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000004','authenticated','authenticated','recovery-user@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status='active',status_changed_at=now(),account_mode='autonomous'
where user_id in (
  '99600000-0000-4000-8000-000000000001',
  '99600000-0000-4000-8000-000000000002',
  '99600000-0000-4000-8000-000000000003',
  '99600000-0000-4000-8000-000000000004'
);
insert into public.platform_administrators(user_id) values
  ('99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000002'),
  ('99600000-0000-4000-8000-000000000003');
insert into public.account_subscriptions(owner_id,status,started_at)
values ('99600000-0000-4000-8000-000000000004','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name)
values (
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8000-000000000004','Récupération','Test'
);

insert into public.document_operations(
  id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,
  workflow,business_entity_type,business_entity_id,client_request_id,
  state,target_signature,row_revision
) values
  ('99600000-0000-4000-8200-000000000001','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_replace','transaction','99600000-0000-4000-8300-000000000001','99600000-0000-4000-8400-000000000001','attention_required','[]',5),
  ('99600000-0000-4000-8200-000000000002','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_delete','transaction','99600000-0000-4000-8300-000000000002','99600000-0000-4000-8400-000000000002','attention_required','[]',0),
  ('99600000-0000-4000-8200-000000000003','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_delete','transaction','99600000-0000-4000-8300-000000000003','99600000-0000-4000-8400-000000000003','attention_required','[]',0),
  ('99600000-0000-4000-8200-000000000004','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_delete','transaction','99600000-0000-4000-8300-000000000004','99600000-0000-4000-8400-000000000004','attention_required','[]',0),
  ('99600000-0000-4000-8200-000000000005','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_delete','transaction','99600000-0000-4000-8300-000000000005','99600000-0000-4000-8400-000000000005','attention_required','[]',0),
  ('99600000-0000-4000-8200-000000000006','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000004','99600000-0000-4000-8000-000000000004','user','transaction_proof_delete','transaction','99600000-0000-4000-8300-000000000006','99600000-0000-4000-8400-000000000006','attention_required','[]',0);

insert into public.document_operation_targets(
  id,operation_id,ordinal,bucket_id,object_path,target_role,
  forward_action,compensation_action,expected_exists
) values
  ('99600000-0000-4000-8500-000000000001','99600000-0000-4000-8200-000000000001',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000001/proof','primary','update','update',false),
  ('99600000-0000-4000-8500-000000000002','99600000-0000-4000-8200-000000000001',2,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000002/proof','primary','delete','insert',false),
  ('99600000-0000-4000-8500-000000000003','99600000-0000-4000-8200-000000000002',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000003/proof','primary','delete','insert',false),
  ('99600000-0000-4000-8500-000000000004','99600000-0000-4000-8200-000000000003',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000004/proof','primary','delete','insert',false),
  ('99600000-0000-4000-8500-000000000005','99600000-0000-4000-8200-000000000004',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000005/proof','primary','delete','insert',false),
  ('99600000-0000-4000-8500-000000000006','99600000-0000-4000-8200-000000000005',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000006/proof','primary','delete','insert',false),
  ('99600000-0000-4000-8500-000000000007','99600000-0000-4000-8200-000000000006',1,'transaction-proofs','protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000007/proof','primary','delete','insert',false);

insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id)
select target.bucket_id,target.object_path,target.id,target.operation_id
from public.document_operation_targets target
where target.id::text like '99600000-0000-4000-8500-%';

create temporary table recovery_fixture_plans(
  authorization_id uuid primary key,
  operation_id uuid not null,
  attempt_id uuid not null,
  plan jsonb not null,
  plan_hash text
);

insert into recovery_fixture_plans(authorization_id,operation_id,attempt_id,plan)
values
  ('99600000-0000-4000-8600-000000000001','99600000-0000-4000-8200-000000000001','99600000-0000-4000-8700-000000000001',jsonb_build_array(
    jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000001','action','confirm_already_conform','expectedOperationRevision',5,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null),
    jsonb_build_object('ordinal',2,'targetId','99600000-0000-4000-8500-000000000002','action','confirm_already_conform','expectedOperationRevision',5,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null)
  )),
  ('99600000-0000-4000-8600-000000000002','99600000-0000-4000-8200-000000000002','99600000-0000-4000-8700-000000000002',jsonb_build_array(jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000003','action','confirm_already_conform','expectedOperationRevision',0,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null))),
  ('99600000-0000-4000-8600-000000000003','99600000-0000-4000-8200-000000000003','99600000-0000-4000-8700-000000000003',jsonb_build_array(jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000004','action','confirm_already_conform','expectedOperationRevision',0,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null))),
  ('99600000-0000-4000-8600-000000000004','99600000-0000-4000-8200-000000000004','99600000-0000-4000-8700-000000000004',jsonb_build_array(jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000005','action','confirm_already_conform','expectedOperationRevision',0,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null))),
  ('99600000-0000-4000-8600-000000000005','99600000-0000-4000-8200-000000000005','99600000-0000-4000-8700-000000000005',jsonb_build_array(jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000006','action','confirm_already_conform','expectedOperationRevision',0,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null))),
  ('99600000-0000-4000-8600-000000000006','99600000-0000-4000-8200-000000000006','99600000-0000-4000-8700-000000000006',jsonb_build_array(jsonb_build_object('ordinal',1,'targetId','99600000-0000-4000-8500-000000000007','action','confirm_already_conform','expectedOperationRevision',0,'expectedTargetRevision',0,'expectedApplicationState','pending','expectedObjectExists',false,'expectedObjectId',null,'expectedObjectVersion',null,'backupId',null,'expectedBackupRevision',null,'expectedBackupState',null,'residualReason',null)));
update recovery_fixture_plans set plan_hash=public.document_repair_plan_hash(plan);
grant select on recovery_fixture_plans to service_role;

insert into public.document_repair_authorizations(
  id,administrator_subject_id,operation_id,attempt_id,reason,repair_plan,
  repair_plan_hash,target_count,observed_operation_revision,issued_at,expires_at,
  recovery_expires_at,renewal_count,last_renewal_id,last_renewed_at,row_revision
)
select plan.authorization_id,'99600000-0000-4000-8000-000000000001',
  plan.operation_id,plan.attempt_id,'Réparation bloquée',plan.plan,plan.plan_hash,
  jsonb_array_length(plan.plan),case when plan.operation_id='99600000-0000-4000-8200-000000000001' then 5 else 0 end,
  now()-interval '2 hours',now()-interval '110 minutes',
  case when plan.authorization_id='99600000-0000-4000-8600-000000000004' then now()+interval '5 minutes' else now()-interval '10 minutes' end,
  case when plan.authorization_id='99600000-0000-4000-8600-000000000003' then 5 else 6 end,
  gen_random_uuid(),
  case when plan.authorization_id='99600000-0000-4000-8600-000000000004' then now()-interval '1 minute' else now()-interval '20 minutes' end,
  case when plan.authorization_id='99600000-0000-4000-8600-000000000003' then 5 else 6 end
from recovery_fixture_plans plan;

insert into public.document_repair_items(
  id,authorization_id,operation_id,target_id,ordinal,action,
  expected_operation_revision,expected_target_revision,
  expected_application_state,expected_object_exists,progress_state,
  execution_id,execution_started_at
) values
  ('99600000-0000-4000-8800-000000000001','99600000-0000-4000-8600-000000000001','99600000-0000-4000-8200-000000000001','99600000-0000-4000-8500-000000000001',1,'confirm_already_conform',5,0,'pending',false,'executing','99600000-0000-4000-8900-000000000001',now()-interval '30 minutes'),
  ('99600000-0000-4000-8800-000000000002','99600000-0000-4000-8600-000000000001','99600000-0000-4000-8200-000000000001','99600000-0000-4000-8500-000000000002',2,'confirm_already_conform',5,0,'pending',false,'authorized',null,null),
  ('99600000-0000-4000-8800-000000000003','99600000-0000-4000-8600-000000000002','99600000-0000-4000-8200-000000000002','99600000-0000-4000-8500-000000000003',1,'confirm_already_conform',0,0,'pending',false,'authorized',null,null),
  ('99600000-0000-4000-8800-000000000004','99600000-0000-4000-8600-000000000003','99600000-0000-4000-8200-000000000003','99600000-0000-4000-8500-000000000004',1,'confirm_already_conform',0,0,'pending',false,'executing','99600000-0000-4000-8900-000000000004',now()-interval '30 minutes'),
  ('99600000-0000-4000-8800-000000000005','99600000-0000-4000-8600-000000000004','99600000-0000-4000-8200-000000000004','99600000-0000-4000-8500-000000000005',1,'confirm_already_conform',0,0,'pending',false,'executing','99600000-0000-4000-8900-000000000005',now()-interval '30 minutes'),
  ('99600000-0000-4000-8800-000000000006','99600000-0000-4000-8600-000000000005','99600000-0000-4000-8200-000000000005','99600000-0000-4000-8500-000000000006',1,'confirm_already_conform',0,0,'pending',false,'executing','99600000-0000-4000-8900-000000000006',now()-interval '30 minutes'),
  ('99600000-0000-4000-8800-000000000007','99600000-0000-4000-8600-000000000006','99600000-0000-4000-8200-000000000006','99600000-0000-4000-8500-000000000007',1,'confirm_already_conform',0,0,'pending',false,'executing','99600000-0000-4000-8900-000000000007',now()-interval '30 minutes');

insert into public.document_repair_observations(
  id,authorization_id,operation_id,item_id,execution_id,observation_kind,
  object_exists,physical_bytes_verified,backup_present,observation_fingerprint
) values (
  '99600000-0000-4000-8a00-000000000001','99600000-0000-4000-8600-000000000001',
  '99600000-0000-4000-8200-000000000001','99600000-0000-4000-8800-000000000001',
  '99600000-0000-4000-8900-000000000001','unqualifiable',null,false,false,repeat('a',64)
);

insert into public.document_repair_authorizations(
  id,administrator_subject_id,operation_id,attempt_id,reason,repair_plan,
  repair_plan_hash,target_count,observed_operation_revision,state,
  issued_at,expires_at,cancelled_at,state_changed_at,recovery_expires_at,
  renewal_count,last_renewal_id,last_renewed_at,row_revision
)
select '99600000-0000-4000-8600-000000000007',
  '99600000-0000-4000-8000-000000000001',plan.operation_id,
  '99600000-0000-4000-8700-000000000007','Réparation annulée',plan.plan,
  plan.plan_hash,jsonb_array_length(plan.plan),5,'cancelled',
  now()-interval '2 hours',now()-interval '110 minutes',now()-interval '5 minutes',
  now()-interval '5 minutes',now()-interval '10 minutes',6,
  gen_random_uuid(),now()-interval '20 minutes',7
from recovery_fixture_plans plan
where plan.authorization_id='99600000-0000-4000-8600-000000000001';

create temporary table exceptional_storage_snapshot as
select count(*) as object_count from storage.objects;

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8700-000000000001',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8b00-000000000001','Motif exceptionnel',6)$$,
  'P4X01','Demande de récupération exceptionnelle non autorisée.',
  'un utilisateur ordinaire est refusé'
);
select extensions.throws_ok(
  $$select public.decide_administrative_document_exceptional_recovery(
    gen_random_uuid(),gen_random_uuid(),true,'Décision interdite',0)$$,
  'P4X01','Décision de récupération exceptionnelle non autorisée.',
  'un utilisateur ordinaire ne peut pas approuver une récupération'
);
select extensions.throws_ok(
  $$select public.activate_administrative_document_exceptional_recovery(
    gen_random_uuid(),gen_random_uuid(),0)$$,
  'P4X01','Activation de récupération exceptionnelle non autorisée.',
  'un utilisateur ordinaire ne peut pas activer une fenêtre'
);

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.lives_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8700-000000000001',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8b00-000000000001','Motif exceptionnel',6)$$,
  'l’administrateur initiateur peut demander la récupération'
);
select extensions.ok(
  (select (public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8700-000000000001',plan_hash,
    '99600000-0000-4000-8b00-000000000001','Motif exceptionnel',6)->>'idempotent')::boolean
   from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
  'une réponse de demande perdue peut être rejouée idempotemment'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8700-000000000001',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8b00-000000000001','Motif exceptionnel',5)$$,
  'P4X05','La clé de demande est déjà liée à une autre récupération.',
  'la clé de demande ne peut pas être rejouée avec une autre révision attendue'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000002','99600000-0000-4000-8700-000000000002',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000002'),
    '99600000-0000-4000-8b00-000000000002','Non commencée',6)$$,
  'P4X03','Une réparation non commencée ne peut pas être récupérée.',
  'une réparation jamais commencée est refusée'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000003','99600000-0000-4000-8700-000000000003',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000003'),
    '99600000-0000-4000-8b00-000000000003','Seulement cinq',5)$$,
  'P4X03','La réparation n’est pas éligible à une récupération exceptionnelle.',
  'moins de six renouvellements est refusé'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000004','99600000-0000-4000-8700-000000000004',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000004'),
    '99600000-0000-4000-8b00-000000000004','Encore active',6)$$,
  'P4X03','La réparation n’est pas éligible à une récupération exceptionnelle.',
  'une autorisation ordinaire non expirée est refusée'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8700-000000000099',repeat('f',64),
    '99600000-0000-4000-8b00-000000000099','Contexte divergent',6)$$,
  'P4X01','Demande de récupération exceptionnelle non autorisée.',
  'une autre tentative ne peut pas reprendre la réparation'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000007','99600000-0000-4000-8700-000000000007',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8b00-000000000007','Autorisation annulée',7)$$,
  'P4X03','La réparation n’est pas éligible à une récupération exceptionnelle.',
  'une autorisation annulée ne peut pas être récupérée'
);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000005','99600000-0000-4000-8700-000000000005',repeat('f',64),
    '99600000-0000-4000-8b00-000000000005','Plan divergent',6)$$,
  'P4X04','Le contexte initial de réparation a divergé.',
  'une empreinte de plan divergente est refusée'
);
select extensions.lives_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8600-000000000005','99600000-0000-4000-8700-000000000005',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000005'),
    '99600000-0000-4000-8b00-000000000005','Demande à refuser',6)$$,
  'une seconde récupération éligible peut être soumise à décision'
);

insert into public.account_deletion_document_authorizations(
  id,account_user_id,attempt_id,issued_at,expires_at
) values (
  '99600000-0000-4000-9100-000000000001',
  '99600000-0000-4000-8000-000000000004',
  '99600000-0000-4000-9100-000000000002',now(),now()+interval '10 minutes'
);
insert into public.document_operations(
  id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,
  workflow,business_entity_type,business_entity_id,client_request_id,
  state,target_signature
) values (
  '99600000-0000-4000-9200-000000000001',
  '99600000-0000-4000-8100-000000000001',null,
  '99600000-0000-4000-8000-000000000004','account_deletion',
  'account_storage_neutralization','protected_person',
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-9200-000000000002','executing','[]'
);
insert into public.document_operation_targets(
  id,operation_id,ordinal,bucket_id,object_path,target_role,
  forward_action,compensation_action,expected_exists
) select
  '99600000-0000-4000-9300-000000000001',
  '99600000-0000-4000-9200-000000000001',1,bucket_id,object_path,
  'primary','delete','insert',false
from public.document_operation_targets
where id='99600000-0000-4000-8500-000000000006';
insert into public.account_storage_neutralizations(
  operation_id,target_id,authorization_id,account_user_id,
  expected_sha256,expected_byte_size,mime_type
) values (
  '99600000-0000-4000-9200-000000000001',
  '99600000-0000-4000-9300-000000000001',
  '99600000-0000-4000-9100-000000000001',
  '99600000-0000-4000-8000-000000000004',repeat('e',64),10,'application/pdf'
);

select extensions.throws_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,0)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8c00-000000000001','Auto-approbation'
  ),
  'P4X01','Une validation administrative indépendante est requise.',
  'l’auto-approbation est refusée'
);

delete from public.document_object_locks where target_id='99600000-0000-4000-8500-000000000002';
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,0)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8c00-000000000002','Approbation indépendante'
  ),
  'P4X06','Une cible ou son verrou a divergé.',
  'un verrou divergent bloque l’approbation'
);
select extensions.throws_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,0)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000005'),
    '99600000-0000-4000-8c00-000000000005','Conflit de neutralisation'
  ),
  'P4X06','Une neutralisation de compte est en conflit avec la récupération.',
  'une neutralisation concurrente bloque l’approbation'
);
select extensions.lives_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,false,%L,0)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000005'),
    '99600000-0000-4000-8c00-000000000006','Refus motivé après diagnostic'
  ),
  'le second administrateur peut refuser explicitement et sans mutation documentaire'
);
select extensions.is(
  (select state from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000005'),
  'rejected',
  'une récupération refusée conserve son état terminal audité'
);
insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id)
select bucket_id,object_path,id,operation_id from public.document_operation_targets
where id='99600000-0000-4000-8500-000000000002';
select extensions.lives_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,0)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8c00-000000000002','Approbation indépendante'
  ),
  'un second administrateur distinct approuve le contexte inchangé'
);
select extensions.ok(
  (select (public.decide_administrative_document_exceptional_recovery(
    id,'99600000-0000-4000-8c00-000000000002',true,'Approbation indépendante',0
  )->>'idempotent')::boolean
  from public.document_repair_exceptional_recoveries
  where authorization_id='99600000-0000-4000-8600-000000000001'),
  'une réponse d’approbation perdue peut être rejouée'
);
select extensions.throws_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,1)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8c00-000000000002','Approbation indépendante'
  ),
  'P4X05','La clé de décision est déjà liée à une autre décision.',
  'la clé de décision ne peut pas être rejouée avec une autre révision attendue'
);

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.throws_ok(
  $$select public.request_administrative_document_exceptional_recovery(
    gen_random_uuid(),gen_random_uuid(),repeat('a',64),gen_random_uuid(),'Interdit',0)$$,
  '42501','permission denied for function request_administrative_document_exceptional_recovery',
  'service_role ne peut jamais demander la récupération métier'
);
select extensions.throws_ok(
  $$select public.decide_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8d00-000000000099','99600000-0000-4000-8c00-000000000099',true,'Interdit',0)$$,
  '42501','permission denied for function decide_administrative_document_exceptional_recovery',
  'service_role ne peut jamais prendre la décision métier'
);
select extensions.throws_ok(
  $$select public.activate_administrative_document_exceptional_recovery(
    gen_random_uuid(),gen_random_uuid(),0)$$,
  '42501','permission denied for function activate_administrative_document_exceptional_recovery',
  'service_role ne peut jamais activer la récupération métier'
);
reset role;

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  format(
    'select public.decide_administrative_document_exceptional_recovery(%L,%L,true,%L,1)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8c00-000000000003','Seconde décision concurrente'
  ),
  'P4X05','La récupération a déjà reçu une décision ou a divergé.',
  'une seconde approbation concurrente ne remplace pas la première'
);

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.lives_ok(
  format(
    'select public.activate_administrative_document_exceptional_recovery(%L,%L,1)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8e00-000000000001'
  ),
  'l’initiateur active la première fenêtre de cinq minutes'
);
select extensions.ok(
  (select (public.activate_administrative_document_exceptional_recovery(
    id,'99600000-0000-4000-8e00-000000000001',1
  )->>'idempotent')::boolean
  from public.document_repair_exceptional_recoveries
  where authorization_id='99600000-0000-4000-8600-000000000001'),
  'une réponse d’activation perdue peut être rejouée'
);
select extensions.throws_ok(
  format(
    'select public.activate_administrative_document_exceptional_recovery(%L,%L,2)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8e00-000000000001'
  ),
  'P4X05','La clé d’activation est déjà liée à une autre intention.',
  'la clé d’activation ne peut pas être rejouée avec une autre révision attendue'
);
select extensions.throws_ok(
  format(
    'select public.activate_administrative_document_exceptional_recovery(%L,%L,2)',
    (select id from public.document_repair_exceptional_recoveries where authorization_id='99600000-0000-4000-8600-000000000001'),
    '99600000-0000-4000-8e00-000000000002'
  ),
  'P4X06','Une fenêtre exceptionnelle est déjà active.',
  'une activation concurrente distincte est refusée'
);
select extensions.is(
  (select renewal_count from public.document_repair_authorizations where id='99600000-0000-4000-8600-000000000001'),
  6::smallint,
  'la récupération ne remet jamais à zéro les six renouvellements'
);
select extensions.is(
  (select repair_plan from public.document_repair_authorizations where id='99600000-0000-4000-8600-000000000001'),
  (select plan from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
  'le plan initial est conservé exactement'
);
select extensions.is(
  (select count(*) from public.document_repair_observations where authorization_id='99600000-0000-4000-8600-000000000001'),
  1::bigint,
  'les observations antérieures sont conservées'
);

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.lives_ok(
  $$select public.start_administrative_document_repair_item(
    '99600000-0000-4000-8600-000000000001','99600000-0000-4000-8800-000000000002',
    '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8700-000000000001',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'),
    'confirm_already_conform','99600000-0000-4000-8900-000000000002',6,0)$$,
  'les RPC de progression existantes reconnaissent la fenêtre active'
);
reset role;

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.seal_administrative_document_repair(
    '99600000-0000-4000-8600-000000000001',6,
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000001'))$$,
  'P4R07','La réparation ne dispose pas de toutes les preuves requises.',
  'la fenêtre exceptionnelle ne permet pas de sceller sans preuves complètes'
);
select extensions.is(
  (select object_count from exceptional_storage_snapshot),
  (select count(*) from storage.objects),
  'le contrat exceptionnel ne provoque aucune mutation Storage'
);

-- Une récupération déjà approuvée et deux activations expirées démontre le
-- refus après expiration ainsi que le plafond strict, sans attente réelle.
insert into public.document_repair_exceptional_recoveries(
  id,authorization_id,operation_id,original_attempt_id,requester_subject_id,
  approver_subject_id,request_id,decision_id,reason,decision_reason,
  repair_plan_hash,requested_authorization_revision,request_context_hash,state,
  activation_count,last_activation_id,requested_at,decided_at,last_activated_at,
  active_expires_at,row_revision
) select
  '99600000-0000-4000-8f00-000000000001',plan.authorization_id,plan.operation_id,
  plan.attempt_id,'99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000002',
  '99600000-0000-4000-9000-000000000001','99600000-0000-4000-9000-000000000002',
  'Récupération épuisée','Validation épuisée',plan.plan_hash,6,
  public.document_repair_exceptional_context_fingerprint(plan.authorization_id),
  'approved',2,'99600000-0000-4000-9000-000000000004',
  now()-interval '30 minutes',now()-interval '29 minutes',
  now()-interval '10 minutes',now()-interval '5 minutes',3
from recovery_fixture_plans plan
where plan.authorization_id='99600000-0000-4000-8600-000000000006';
insert into public.document_repair_exceptional_activations(
  recovery_id,authorization_id,ordinal,activation_id,activated_by,
  context_hash,activated_at,expires_at
) values
  ('99600000-0000-4000-8f00-000000000001','99600000-0000-4000-8600-000000000006',1,'99600000-0000-4000-9000-000000000003','99600000-0000-4000-8000-000000000001',repeat('b',64),now()-interval '20 minutes',now()-interval '15 minutes'),
  ('99600000-0000-4000-8f00-000000000001','99600000-0000-4000-8600-000000000006',2,'99600000-0000-4000-9000-000000000004','99600000-0000-4000-8000-000000000001',repeat('c',64),now()-interval '10 minutes',now()-interval '5 minutes');

select extensions.throws_ok(
  $$select public.activate_administrative_document_exceptional_recovery(
    '99600000-0000-4000-8f00-000000000001','99600000-0000-4000-9000-000000000005',3)$$,
  'P4X07','Le plafond des activations exceptionnelles est atteint.',
  'une troisième activation est refusée'
);
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.throws_ok(
  $$select public.start_administrative_document_repair_item(
    '99600000-0000-4000-8600-000000000006','99600000-0000-4000-8800-000000000007',
    '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8700-000000000006',
    (select plan_hash from recovery_fixture_plans where authorization_id='99600000-0000-4000-8600-000000000006'),
    'confirm_already_conform','99600000-0000-4000-8900-000000000007',6,0)$$,
  'P4R05','Autorisation de réparation expirée.',
  'la progression est refusée après expiration de la dernière fenêtre'
);
reset role;

-- Le trigger de consommation constitue la dernière barrière temporelle : si
-- une fenêtre expire après les contrôles initiaux du scellement, toute la
-- transaction doit être annulée. Une erreur ultérieure doit également annuler
-- atomiquement la consommation et son événement append-only.
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create temporary table exceptional_seal_probe(id uuid primary key, state text not null);
insert into exceptional_seal_probe(id,state) values
  ('99600000-0000-4000-8600-000000000006','active'),
  ('99600000-0000-4000-8600-000000000001','active');
create trigger a_consume_exceptional_recovery
after update of state on exceptional_seal_probe
for each row execute function public.consume_document_repair_exceptional_recovery();

select extensions.throws_ok(
  $$update exceptional_seal_probe set state='sealed'
    where id='99600000-0000-4000-8600-000000000006'$$,
  'P4X03','La fenêtre exceptionnelle n’est plus active au scellement.',
  'une fenêtre expirée à la frontière du scellement ne peut pas être consommée'
);
select extensions.is(
  (select state from public.document_repair_exceptional_recoveries
   where authorization_id='99600000-0000-4000-8600-000000000006'),
  'approved',
  'le refus temporel conserve la récupération approuvée sans faux scellement'
);

create function pg_temp.fail_after_exceptional_consumption()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = 'P4X99', message = 'Échec simulé après consommation.';
end;
$$;
create trigger z_fail_after_exceptional_consumption
after update of state on exceptional_seal_probe
for each row execute function pg_temp.fail_after_exceptional_consumption();
select extensions.throws_ok(
  $$update exceptional_seal_probe set state='sealed'
    where id='99600000-0000-4000-8600-000000000001'$$,
  'P4X99','Échec simulé après consommation.',
  'un échec après le trigger annule la consommation dans la même transaction'
);
select extensions.is(
  (select state from public.document_repair_exceptional_recoveries
   where authorization_id='99600000-0000-4000-8600-000000000001'),
  'approved',
  'la récupération reste approuvée après annulation de la transaction de scellement'
);
select extensions.is(
  (select count(*) from public.document_repair_exceptional_events event
   join public.document_repair_exceptional_recoveries recovery
     on recovery.id = event.recovery_id
   where recovery.authorization_id='99600000-0000-4000-8600-000000000001'
     and event.event_type='consumed'),
  0::bigint,
  'aucun événement de consommation ne survit à la transaction annulée'
);
drop trigger z_fail_after_exceptional_consumption on exceptional_seal_probe;
select extensions.lives_ok(
  $$update exceptional_seal_probe set state='sealed'
    where id='99600000-0000-4000-8600-000000000001'$$,
  'le scellement dans une fenêtre active consomme atomiquement la récupération'
);
select extensions.is(
  (select state from public.document_repair_exceptional_recoveries
   where authorization_id='99600000-0000-4000-8600-000000000001'),
  'consumed',
  'la récupération est terminale après consommation réussie'
);
select extensions.is(
  (select count(*) from public.document_repair_exceptional_events event
   join public.document_repair_exceptional_recoveries recovery
     on recovery.id = event.recovery_id
   where recovery.authorization_id='99600000-0000-4000-8600-000000000001'
     and event.event_type='consumed'),
  1::bigint,
  'la consommation réussie produit exactement un événement append-only'
);
update exceptional_seal_probe set state='sealed'
where id='99600000-0000-4000-8600-000000000001';
select extensions.is(
  (select count(*) from public.document_repair_exceptional_events event
   join public.document_repair_exceptional_recoveries recovery
     on recovery.id = event.recovery_id
   where recovery.authorization_id='99600000-0000-4000-8600-000000000001'
     and event.event_type='consumed'),
  1::bigint,
  'la répétition du scellement ne duplique pas la consommation'
);

select * from extensions.finish();
rollback;
