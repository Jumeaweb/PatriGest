begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public','protected_person_archive_runtime_config','le verrou SQL existe');
select extensions.has_table('public','document_operations','les opérations documentaires existent');
select extensions.has_table('public','document_operation_targets','les cibles documentaires existent');
select extensions.has_table('public','document_object_locks','les verrous de chemins existent');
select extensions.has_table('public','document_operation_events','le journal documentaire existe');
select extensions.has_function('public','begin_transaction_proof_document_operation',array['uuid','uuid','text','uuid'],'la RPC des justificatifs existe');
select extensions.has_function('public','begin_bank_statement_document_operation',array['uuid','uuid','uuid','text','uuid'],'la RPC des relevés existe');
select extensions.has_function('public','begin_management_report_document_operation',array['uuid','uuid','text','uuid'],'la RPC des comptes de gestion existe');

select extensions.ok(
  not (select lifecycle_enabled from public.protected_person_archive_runtime_config where singleton),
  'le cycle de vie est désactivé par défaut'
);
select extensions.ok(
  not has_table_privilege('authenticated','public.document_operations','SELECT')
  and not has_table_privilege('authenticated','public.document_operations','INSERT')
  and not has_table_privilege('service_role','public.document_operations','INSERT')
  and not has_table_privilege('authenticated','public.protected_person_archive_runtime_config','UPDATE'),
  'les rôles applicatifs et service_role n’ont aucun accès direct'
);
select extensions.ok(
  has_function_privilege('authenticated','public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)','EXECUTE')
  and not has_function_privilege('anon','public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.create_document_operation(uuid,text,text,uuid,uuid,jsonb)','EXECUTE'),
  'seules les RPC métier dédiées sont publiques pour authenticated'
);
select extensions.ok(
  (select bool_and(p.prosecdef and p.proconfig=array['search_path=""']) from pg_proc p where p.oid in (
    'public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)'::regprocedure,
    'public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid)'::regprocedure,
    'public.begin_management_report_document_operation(uuid,uuid,text,uuid)'::regprocedure)),
  'les RPC dédiées sont SECURITY DEFINER avec search_path vide'
);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select '00000000-0000-0000-0000-000000000000',
 ('99600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'authenticated','authenticated','reservation-'||n||'@example.test','test',now(),'{}','{}',now(),now()
from generate_series(1,3) n;
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id::text like '99600000-0000-4000-8000-%';
update public.application_user_authorizations set account_mode='autonomous'
where user_id='99600000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id,status,started_at)
values('99600000-0000-4000-8000-000000000001','development',now());

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000001','Réservation','Documentaire'),
('99600000-0000-4000-8100-000000000002','99600000-0000-4000-8000-000000000001','Dossier','Vide');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99600000-0000-4000-8900-000000000001','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000002','manager','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8900-000000000002','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000003','read_only','99600000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('99600000-0000-4000-8200-000000000001','99600000-0000-4000-8100-000000000001','checking','Banque test','Compte test',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values('99600000-0000-4000-8300-000000000001','99600000-0000-4000-8200-000000000001','2026-01-02','expense','Test',10);
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,created_by)
values('99600000-0000-4000-8600-000000000001','99600000-0000-4000-8100-000000000001',
 2026,'2026-01-01','2026-12-31','ready','99600000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.throws_ok(
 $$select public.archive_protected_person('99600000-0000-4000-8100-000000000001',1,'Test')$$,
 'P4A07','Le cycle de vie des dossiers n’est pas activé.',
 'l’archivage est bloqué par le verrou SQL'
);
select extensions.throws_ok(
 $$select public.restore_protected_person('99600000-0000-4000-8100-000000000001',1,'Test')$$,
 'P4A07','Le cycle de vie des dossiers n’est pas activé.',
 'la restauration est bloquée par le verrou SQL avant le contrôle d’état'
);
select extensions.throws_ok(
 $$update public.protected_person_archive_runtime_config set lifecycle_enabled=true$$,
 '42501','permission denied for table protected_person_archive_runtime_config',
 'un utilisateur applicatif ne peut pas activer le cycle'
);

select extensions.lives_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','create',
 '99600000-0000-4000-8400-000000000001')$$,
 'une réservation valide est ouverte'
);
select extensions.lives_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','create',
 '99600000-0000-4000-8400-000000000001')$$,
 'une répétition identique est idempotente'
);
reset role;
select extensions.is(
 (select count(*) from public.document_operation_targets where object_path=
 'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000001/proof'),
 1::bigint,'le chemin canonique est dérivé côté PostgreSQL'
);
select extensions.is(
 (select count(*) from public.document_operation_events where event_type='reserved'),
 1::bigint,'l’ouverture est journalisée'
);
select extensions.is((select count(*) from public.document_operations where
 client_request_id='99600000-0000-4000-8400-000000000001'),1::bigint,
 'l’idempotence ne duplique pas l’opération');
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','delete',
 '99600000-0000-4000-8400-000000000001')$$,
 'P4O02','État du justificatif incompatible avec la demande.',
 'un état métier incompatible est refusé avant la réutilisation idempotente'
);
select extensions.throws_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','create',
 '99600000-0000-4000-8400-000000000002')$$,
 'P4O05','Ce fichier est déjà réservé par une autre opération.',
 'deux demandes ne peuvent pas réserver le même chemin'
);
select extensions.throws_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','arbitrary',
 '99600000-0000-4000-8400-000000000003')$$,
 'P4O02','Justificatif ou rattachement invalide.',
 'aucun bucket, chemin ou intent arbitraire n’est accepté'
);

select extensions.lives_ok(
 $$select public.begin_bank_statement_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8200-000000000001',
 '99600000-0000-4000-8700-000000000001','create','99600000-0000-4000-8400-000000000007')$$,
 'un relevé futur peut réserver uniquement son chemin canonique'
);
select extensions.lives_ok(
 $$select public.begin_management_report_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8600-000000000001',
 'generate','99600000-0000-4000-8400-000000000008')$$,
 'un compte prêt peut réserver son PDF projet canonique'
);
reset role;
select extensions.is((select count(*) from public.document_operation_targets where object_path in (
 'protected-persons/99600000-0000-4000-8100-000000000001/accounts/99600000-0000-4000-8200-000000000001/statements/99600000-0000-4000-8700-000000000001/statement',
 'protected-persons/99600000-0000-4000-8100-000000000001/management-reports/99600000-0000-4000-8600-000000000001/management-report-draft.pdf')),
 2::bigint,'les chemins relevé et compte de gestion sont dérivés en SQL');
select public.transition_document_operation((select id from public.document_operations where client_request_id='99600000-0000-4000-8400-000000000007'),'reserved','cancelled');
select public.transition_document_operation((select id from public.document_operations where client_request_id='99600000-0000-4000-8400-000000000008'),'reserved','cancelled');
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
 $$select public.begin_transaction_proof_document_operation(
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8300-000000000001','create',
 '99600000-0000-4000-8400-000000000004')$$,
 'P4O01','Accès à la réservation documentaire refusé.',
 'un lecteur ne peut pas ouvrir de réservation'
);

reset role;
update public.protected_person_archive_runtime_config set lifecycle_enabled=true,updated_at=clock_timestamp() where singleton;
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
 $$select public.archive_protected_person('99600000-0000-4000-8100-000000000001',1,'Réservation active')$$,
 'P4A06','Une opération documentaire en cours bloque l’archivage.',
 'une réservation non terminale bloque l’archivage'
);

reset role;
select public.transition_document_operation(
 (select id from public.document_operations where client_request_id='99600000-0000-4000-8400-000000000001'),
 'reserved','cancelled');
select extensions.is((select count(*) from public.document_object_locks),0::bigint,'un état terminal libère le verrou sans expiration');
select extensions.throws_ok(
 $$select public.transition_document_operation(
 (select id from public.document_operations where client_request_id='99600000-0000-4000-8400-000000000001'),
 'cancelled','executing')$$,
 '23514','Une opération documentaire terminale est immuable.',
 'une opération terminale ne peut pas être réutilisée'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select extensions.is(public.archive_protected_person('99600000-0000-4000-8100-000000000001',1,'Après annulation'),2::bigint,'l’archivage réussit après finalisation');

reset role;
insert into public.document_operations(id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,
 workflow,business_entity_type,business_entity_id,client_request_id,state,target_signature)
values('99600000-0000-4000-8500-000000000001','99600000-0000-4000-8100-000000000001',null,
 '99600000-0000-4000-8000-000000000001','system','administrative_repair','protected_person',
 '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000005','attention_required','[]');
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select extensions.throws_ok(
 $$select public.restore_protected_person('99600000-0000-4000-8100-000000000001',2,'Réparation active')$$,
 'P4A06','Une réparation documentaire en cours bloque la restauration.',
 'une réparation administrative non terminale bloque la restauration'
);

reset role;
select public.transition_document_operation('99600000-0000-4000-8500-000000000001','attention_required','administratively_resolved',null,'Réparation contrôlée');
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select extensions.is(public.restore_protected_person('99600000-0000-4000-8100-000000000001',2,'Réparation terminée'),3::bigint,'la restauration réussit après résolution');

select extensions.throws_ok(
 $$update public.document_operation_events set safe_code='ALTERED'$$,
 '42501','permission denied for table document_operation_events',
 'le journal est immuable pour un utilisateur applicatif'
);

reset role;
insert into public.document_operations(id,protected_person_id,initiated_by,initiator_subject_id,
 workflow,business_entity_type,business_entity_id,client_request_id,state,target_signature,closed_at)
values('99600000-0000-4000-8500-000000000002','99600000-0000-4000-8100-000000000002',
 '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
 'administrative_repair','protected_person','99600000-0000-4000-8100-000000000002',
 '99600000-0000-4000-8400-000000000006','cancelled','[]',clock_timestamp());
set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select extensions.lives_ok($$select public.delete_empty_protected_person('99600000-0000-4000-8100-000000000002')$$,
 'un dossier vide avec seulement un historique terminal reste supprimable');
select extensions.is((select count(*) from public.protected_persons where id='99600000-0000-4000-8100-000000000002'),0::bigint,'la suppression vide nettoie les dépendances terminales');

select * from extensions.finish();
rollback;
