begin;
\ir experimental_document_operations_enabled.inc

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public','document_storage_guard_runtime_config',
  'le verrou indépendant de la garde Storage existe'
);
select extensions.ok(
  not (select guard_enabled from public.document_storage_guard_runtime_config where singleton),
  'la garde Storage est désactivée par défaut'
);
select extensions.ok(
  not has_table_privilege('authenticated','public.document_storage_guard_runtime_config','UPDATE')
  and not has_table_privilege('service_role','public.document_storage_guard_runtime_config','UPDATE'),
  'aucun rôle applicatif ou service_role ne peut activer directement la garde'
);
select extensions.ok(
  not has_function_privilege('authenticated','public.resolve_canonical_document_storage_path(text,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.validate_document_storage_mutation(text,text,text,uuid,text)','EXECUTE')
  and not has_function_privilege('service_role','public.validate_document_storage_mutation(text,text,text,uuid,text)','EXECUTE'),
  'les fonctions de garde restent strictement internes'
);
select extensions.ok(
  not exists (
    select 1 from pg_trigger trigger
    join pg_class relation on relation.oid=trigger.tgrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='storage' and relation.relname='objects'
      and not trigger.tgisinternal and trigger.tgname like '%document_storage_guard%'
  ),
  'aucun trigger bloquant de garde Storage n’est encore installé'
);

select extensions.has_column('public','document_operation_targets','expected_object_id','l’identifiant Storage attendu est mémorisé');
select extensions.has_column('public','document_operation_targets','expected_object_version','la version Storage attendue est mémorisée');
select extensions.has_column('public','document_operation_targets','application_state','chaque cible possède son état d’application');
select extensions.has_column('public','document_operation_targets','applied_object_id','le résultat Storage est mémorisé');
select extensions.has_column('public','document_operation_targets','compensation_expected_object_id','la précondition de compensation est mémorisée');
select extensions.has_column('public','document_operation_targets','target_revision','la concurrence des cibles utilise une révision');
select extensions.has_column('public','document_operation_events','observed_object_version','le journal peut conserver la version Storage observée');

select extensions.ok(
  (select is_canonical from public.resolve_canonical_document_storage_path(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof')),
  'le chemin canonique d’un justificatif est accepté'
);
select extensions.is(
  (select business_entity_type from public.resolve_canonical_document_storage_path(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof')),
  'transaction',
  'le justificatif résout son entité métier'
);
select extensions.ok(
  not (select is_canonical from public.resolve_canonical_document_storage_path(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/extra/proof')),
  'un segment supplémentaire de justificatif est refusé'
);
select extensions.ok(
  not (select is_canonical from public.resolve_canonical_document_storage_path(
    'transaction-proofs','protected-persons/not-a-uuid/transactions/not-a-uuid/proof')),
  'les UUID invalides sont refusés sans conversion dangereuse'
);
select extensions.ok(
  (select is_canonical from public.resolve_canonical_document_storage_path(
    'bank-statements',
    'protected-persons/99700000-0000-4000-8100-000000000001/accounts/99700000-0000-4000-8200-000000000001/statements/99700000-0000-4000-8700-000000000001/statement')),
  'le chemin canonique d’un relevé est accepté'
);
select extensions.is(
  (select parent_entity_id from public.resolve_canonical_document_storage_path(
    'bank-statements',
    'protected-persons/99700000-0000-4000-8100-000000000001/accounts/99700000-0000-4000-8200-000000000001/statements/99700000-0000-4000-8700-000000000001/statement')),
  '99700000-0000-4000-8200-000000000001'::uuid,
  'le relevé résout aussi son compte parent'
);
select extensions.is(
  (select document_kind from public.resolve_canonical_document_storage_path(
    'management-reports',
    'protected-persons/99700000-0000-4000-8100-000000000001/management-reports/99700000-0000-4000-8600-000000000001/management-report-draft.pdf')),
  'management_report_draft',
  'le PDF projet est distingué du document définitif'
);
select extensions.is(
  (select document_kind from public.resolve_canonical_document_storage_path(
    'management-reports',
    'protected-persons/99700000-0000-4000-8100-000000000001/management-reports/99700000-0000-4000-8600-000000000001/management-report.pdf')),
  'management_report_final',
  'le PDF définitif est identifié'
);

select extensions.is(
  public.validate_document_storage_mutation(
    'transaction-proofs','chemin/invalide','INSERT',null,null),
  null::uuid,
  'la validation est entièrement neutre lorsque la garde est désactivée'
);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(
 '00000000-0000-0000-0000-000000000000','99700000-0000-4000-8000-000000000001',
 'authenticated','authenticated','storage-guard@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations
set status='active',status_changed_at=now(),account_mode='autonomous'
where user_id='99700000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id,status,started_at)
values('99700000-0000-4000-8000-000000000001','development',now());

insert into public.protected_persons(id,owner_id,first_name,last_name)
values('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8000-000000000001','Garde','Storage');
insert into public.financial_accounts(
  id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values(
 '99700000-0000-4000-8200-000000000001','99700000-0000-4000-8100-000000000001',
 'checking','Banque test','Compte test',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values(
 '99700000-0000-4000-8300-000000000001','99700000-0000-4000-8200-000000000001',
 '2026-01-02','expense','Test garde',10);

set local role authenticated;
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.lives_ok(
  $$select public.begin_transaction_proof_document_operation(
    '99700000-0000-4000-8100-000000000001','99700000-0000-4000-8300-000000000001',
    'create','99700000-0000-4000-8400-000000000001')$$,
  'le contrat de réservation existant reste compatible'
);
reset role;

select extensions.is(
  (select application_state from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000001'),
  'pending',
  'une nouvelle cible commence en attente'
);
select extensions.is(
  (select target_revision from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000001'),
  0::bigint,
  'une nouvelle cible commence à la révision zéro'
);
select extensions.ok(
  (select expected_snapshot_captured_at is not null and expected_object_id is null
   from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000001'),
  'l’absence attendue de l’objet est capturée explicitement'
);

select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000001'),
  'reserved','cancelled');

insert into public.transaction_documents(
  id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
values(
 '99700000-0000-4000-8500-000000000001','99700000-0000-4000-8300-000000000001',
 'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
 'preuve.pdf','application/pdf',12,'99700000-0000-4000-8000-000000000001');
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
values(
 '99700000-0000-4000-8800-000000000001','transaction-proofs',
 'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
 '99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000001',
 '{"size":12,"mimetype":"application/pdf"}'::jsonb,'version-1');

set local role authenticated;
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.lives_ok(
  $$select public.begin_transaction_proof_document_operation(
    '99700000-0000-4000-8100-000000000001','99700000-0000-4000-8300-000000000001',
    'replace','99700000-0000-4000-8400-000000000002')$$,
  'un remplacement capture l’objet Storage existant'
);
reset role;

select extensions.is(
  (select expected_object_id from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
  '99700000-0000-4000-8800-000000000001'::uuid,
  'l’identifiant Storage attendu est capturé'
);
select extensions.is(
  (select expected_object_version from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
  'version-1',
  'la version Storage attendue est capturée'
);

update public.document_storage_guard_runtime_config
set guard_enabled=true,updated_at=clock_timestamp() where singleton;

select extensions.throws_ok(
  $$select public.validate_document_storage_mutation(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
    'UPDATE','99700000-0000-4000-8800-000000000001','version-1')$$,
  'P4S03','La réservation Storage n’est pas en cours d’exécution.',
  'une réservation seulement réservée ne permet aucune mutation'
);
select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000002'),
  'reserved','executing');

select extensions.is(
  public.validate_document_storage_mutation(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
    'INSERT','99700000-0000-4000-8800-000000000001','version-1'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
  'le BEFORE INSERT préalable d’un remplacement est reconnu comme UPDATE'
);
select extensions.throws_ok(
  $$select public.validate_document_storage_mutation(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
    'UPDATE','99700000-0000-4000-8800-000000000001','version-obsolete')$$,
  'P4S04','L’objet Storage a changé depuis la réservation.',
  'une version concurrente est refusée'
);

select extensions.throws_ok(
  format(
    'select public.transition_document_operation_target(%L,0,%L,null,null)',
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id=target.operation_id
     where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
    'compensated'),
  'P4S05','Transition de cible documentaire invalide.',
  'une transition de cible hors séquence est refusée'
);
select extensions.is(
  public.transition_document_operation_target(
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id=target.operation_id
     where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
    0,'applied','99700000-0000-4000-8800-000000000001','version-2'),
  1::bigint,
  'une cible appliquée incrémente sa révision'
);
select extensions.throws_ok(
  format(
    'select public.transition_document_operation_target(%L,0,%L,%L,%L)',
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id=target.operation_id
     where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
    'applied','99700000-0000-4000-8800-000000000001','version-2'),
  'P4S05','La révision de la cible documentaire a changé.',
  'une révision concurrente obsolète est refusée'
);
select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000002'),
  'executing','compensating');
select extensions.is(
  public.transition_document_operation_target(
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id=target.operation_id
     where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
    1,'compensating'),
  2::bigint,
  'une cible appliquée peut entrer en compensation avec l’opération globale'
);
select extensions.is(
  public.validate_document_storage_mutation(
    'transaction-proofs',
    'protected-persons/99700000-0000-4000-8100-000000000001/transactions/99700000-0000-4000-8300-000000000001/proof',
    'UPDATE','99700000-0000-4000-8800-000000000001','version-2'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
  'la compensation vérifie le résultat exact de l’action directe'
);
select extensions.is(
  public.transition_document_operation_target(
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id=target.operation_id
     where operation.client_request_id='99700000-0000-4000-8400-000000000002'),
    2,'compensated','99700000-0000-4000-8800-000000000001','version-3'),
  3::bigint,
  'la compensation mémorise son résultat et incrémente la révision'
);
select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000002'),
  'compensating','compensated');
select extensions.is(
  (select count(*) from public.document_operation_events
   where event_type in ('target_applied','target_compensation_started','target_compensated')),
  3::bigint,
  'les transitions de cible sont journalisées sans mutation du journal'
);

insert into public.bank_statements(
  id,financial_account_id,statement_start_date,statement_end_date,statement_balance,
  storage_path,original_file_name,mime_type,file_size,created_by)
values(
 '99700000-0000-4000-8700-000000000001','99700000-0000-4000-8200-000000000001',
 '2026-01-01','2026-01-31',100,
 'protected-persons/99700000-0000-4000-8100-000000000001/accounts/99700000-0000-4000-8200-000000000001/statements/99700000-0000-4000-8700-000000000001/statement',
 null,null,null,'99700000-0000-4000-8000-000000000001');
select extensions.is(
  (select count(*) from public.bank_statements
   where id='99700000-0000-4000-8700-000000000001' and original_file_name is null),
  1::bigint,
  'un relevé sans PDF reste un état métier valide sans réservation Storage'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.lives_ok(
  $$select public.begin_bank_statement_document_operation(
    '99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000001',
    '99700000-0000-4000-8700-000000000001','attach','99700000-0000-4000-8400-000000000003')$$,
  'l’ajout ultérieur du PDF utilise un intent distinct'
);
select extensions.throws_ok(
  $$select public.begin_bank_statement_document_operation(
    '99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000001',
    '99700000-0000-4000-8700-000000000001','create','99700000-0000-4000-8400-000000000004')$$,
  'P4O02','État du relevé incompatible avec la demande.',
  'la création avec PDF ne se confond pas avec l’ajout sur un relevé existant'
);
select extensions.throws_ok(
  $$select public.begin_bank_statement_document_operation(
    '99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000001',
    '99700000-0000-4000-8700-000000000001','replace','99700000-0000-4000-8400-000000000005')$$,
  'P4O02','État du relevé incompatible avec la demande.',
  'un relevé sans PDF ne peut pas réserver un remplacement'
);
reset role;

select extensions.is(
  (select workflow from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000003'),
  'bank_statement_attach',
  'le workflow distingue explicitement l’ajout ultérieur du PDF'
);
select extensions.throws_ok(
  format(
    'select public.transition_document_operation(%L,%L,%L)',
    (select id from public.document_operations
     where client_request_id='99700000-0000-4000-8400-000000000003'),
    'reserved','completed'),
  '23514','Transition documentaire invalide.',
  'une opération réservée ne peut pas être finalisée directement'
);
select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id='99700000-0000-4000-8400-000000000003'),
  'reserved','executing');
select extensions.throws_ok(
  format(
    'select public.transition_document_operation(%L,%L,%L)',
    (select id from public.document_operations
     where client_request_id='99700000-0000-4000-8400-000000000003'),
    'executing','completed'),
  '23514','Toutes les cibles doivent être appliquées avant la finalisation.',
  'l’opération globale ne peut pas ignorer une cible encore en attente'
);
select public.transition_document_operation_target(
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id=target.operation_id
   where operation.client_request_id='99700000-0000-4000-8400-000000000003'),
  0,'applied','99700000-0000-4000-8800-000000000002','statement-version-1');
select extensions.lives_ok(
  format(
    'select public.transition_document_operation(%L,%L,%L)',
    (select id from public.document_operations
     where client_request_id='99700000-0000-4000-8400-000000000003'),
    'executing','completed'),
  'une opération peut être finalisée quand toutes ses cibles sont appliquées'
);

select extensions.is(
  (select count(*) from pg_policies
   where schemaname='storage' and tablename='objects'
     and policyname in (
       'transaction_proofs_insert_manage','transaction_proofs_update_manage','transaction_proofs_delete_manage',
       'bank_statements_storage_insert_manage','bank_statements_storage_update_manage','bank_statements_storage_delete_manage',
       'management_reports_storage_insert_manage','management_reports_storage_delete_controlled')),
  8::bigint,
  'les politiques Storage applicatives existantes sont conservées dans ce lot'
);

select * from extensions.finish();
rollback;
