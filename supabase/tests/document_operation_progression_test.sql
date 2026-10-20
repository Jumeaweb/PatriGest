begin;
select extensions.plan(46);

select extensions.has_function('public','start_document_operation',array['uuid','bigint'],
  'la RPC de démarrage existe');
select extensions.has_function('public','record_document_operation_target_applied',
  array['uuid','uuid','bigint','bigint'],'la preuve d’application existe');
select extensions.has_function('public','finalize_transaction_proof_document_operation',
  array['uuid','bigint','text','text','bigint'],'la finalisation des justificatifs existe');
select extensions.has_function('public','finalize_bank_statement_document_operation',
  array['uuid','bigint','date','date','numeric','text','text','text','bigint'],
  'la finalisation des relevés existe');
select extensions.has_function('public','finalize_management_report_document_operation',
  array['uuid','bigint','text','text','bigint','jsonb','integer'],
  'la finalisation des comptes de gestion existe');
select extensions.has_function('public','begin_document_operation_compensation',
  array['uuid','bigint','text'],'le contrat de compensation existe');
select extensions.has_function('public','get_document_operation_progress',array['uuid'],
  'la reprise peut relire une progression interrompue');

select extensions.ok(
  has_function_privilege('authenticated','public.start_document_operation(uuid,bigint)','EXECUTE')
  and not has_function_privilege('anon','public.start_document_operation(uuid,bigint)','EXECUTE')
  and not has_function_privilege('service_role','public.start_document_operation(uuid,bigint)','EXECUTE'),
  'seul authenticated reçoit les RPC publiques'
);
select extensions.ok(
  not has_function_privilege('authenticated',
    'public.assert_document_target_catalog_state(uuid,text)','EXECUTE'),
  'les primitives internes ne sont pas exposées'
);
select extensions.ok(
  (select bool_and(procedure.prosecdef and procedure.proconfig=array['search_path=""'])
   from pg_proc procedure
   where procedure.oid in (
     'public.start_document_operation(uuid,bigint)'::regprocedure,
     'public.record_document_operation_target_applied(uuid,uuid,bigint,bigint)'::regprocedure,
     'public.finalize_transaction_proof_document_operation(uuid,bigint,text,text,bigint)'::regprocedure,
     'public.finalize_bank_statement_document_operation(uuid,bigint,date,date,numeric,text,text,text,bigint)'::regprocedure,
     'public.finalize_management_report_document_operation(uuid,bigint,text,text,bigint,jsonb,integer)'::regprocedure,
     'public.begin_document_operation_compensation(uuid,bigint,text)'::regprocedure,
     'public.get_document_operation_progress(uuid)'::regprocedure
   )),
  'les RPC publiques sont SECURITY DEFINER avec search_path vide'
);
select extensions.is(
  (select guard_enabled from public.document_storage_guard_runtime_config where singleton),
  false,'la garde Storage reste désactivée'
);
select extensions.is(
  (select lifecycle_enabled from public.protected_person_archive_runtime_config where singleton),
  false,'le cycle d’archivage reste désactivé'
);

-- Instrumentation locale du test uniquement, annulée avec la transaction :
-- elle permet aux sous-requêtes pgTAP de retrouver les identifiants opaques.
grant select on public.document_operations,public.document_operation_targets to authenticated;
create policy document_operations_test_select on public.document_operations
  for select to authenticated using (true);
create policy document_operation_targets_test_select on public.document_operation_targets
  for select to authenticated using (true);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','99800000-0000-4000-8000-000000000001',
 'authenticated','authenticated','progress-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99800000-0000-4000-8000-000000000002',
 'authenticated','authenticated','progress-manager@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99800000-0000-4000-8000-000000000003',
 'authenticated','authenticated','progress-reader@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in (
  '99800000-0000-4000-8000-000000000001',
  '99800000-0000-4000-8000-000000000002',
  '99800000-0000-4000-8000-000000000003'
);
update public.application_user_authorizations set account_mode='autonomous'
where user_id='99800000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id,status,started_at) values
('99800000-0000-4000-8000-000000000001','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99800000-0000-4000-8100-000000000001','99800000-0000-4000-8000-000000000001','Progression','Documentaire'),
('99800000-0000-4000-8100-000000000002','99800000-0000-4000-8000-000000000001','Dossier','Secondaire');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99800000-0000-4000-8900-000000000001','99800000-0000-4000-8100-000000000001',
 '99800000-0000-4000-8000-000000000002','manager','99800000-0000-4000-8000-000000000001'),
('99800000-0000-4000-8900-000000000002','99800000-0000-4000-8100-000000000001',
 '99800000-0000-4000-8000-000000000003','read_only','99800000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date) values
('99800000-0000-4000-8200-000000000001','99800000-0000-4000-8100-000000000001','checking','Banque','Compte',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount) values
('99800000-0000-4000-8300-000000000001','99800000-0000-4000-8200-000000000001','2026-01-02','expense','Preuve 1',10),
('99800000-0000-4000-8300-000000000002','99800000-0000-4000-8200-000000000001','2026-01-03','expense','Preuve 2',20),
('99800000-0000-4000-8300-000000000003','99800000-0000-4000-8200-000000000001','2026-01-04','expense','Preuve 3',30);
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,created_by) values
('99800000-0000-4000-8600-000000000001','99800000-0000-4000-8100-000000000001',
 2026,'2026-01-01','2026-12-31','ready','99800000-0000-4000-8000-000000000001');

-- Justificatif : démarrage, preuve catalogue et finalisation atomique.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_transaction_proof_document_operation(
  '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8300-000000000001',
  'create','99800000-0000-4000-8400-000000000001');
select extensions.is((public.start_document_operation(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'),1)->>'state'),
  'executing','le propriétaire démarre la réservation');
select extensions.is((public.get_document_operation_progress(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'))->>'revision'),
  '2','la reprise relit la révision courante de l’opération');
select extensions.throws_ok(
  format('select public.start_document_operation(%L,1)',
    (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001')),
  'P4O06','La révision de l’opération documentaire a changé.','un double démarrage est refusé');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  format('select public.get_document_operation_progress(%L)',
    (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001')),
  'P4O01','Accès à l’opération documentaire refusé.',
  'un lecteur ne peut pas consulter la progression interne');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
  format('select public.record_document_operation_target_applied(%L,%L,2,0)',
    (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'),
    (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000001')),
  'P4S04','Le résultat Storage est introuvable ou sans version.',
  'une cible ne peut pas être appliquée sans objet réel');
reset role;

insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99800000-0000-4000-8800-000000000001','transaction-proofs',
 'protected-persons/99800000-0000-4000-8100-000000000001/transactions/99800000-0000-4000-8300-000000000001/proof',
 '99800000-0000-4000-8000-000000000001','99800000-0000-4000-8000-000000000001',
 '{"size":12,"mimetype":"application/pdf"}','v1');
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is((public.record_document_operation_target_applied(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'),
  (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000001'),2,0)->>'state'),
  'applied','le catalogue Storage fournit la preuve d’application');
select extensions.throws_ok(
  format('select public.finalize_transaction_proof_document_operation(%L,3,%L,%L,13)',
    (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'),
    'preuve.pdf','application/pdf'),
  'P4S04','Les métadonnées du fichier ne correspondent pas au catalogue Storage.',
  'une divergence de taille empêche la finalisation');
select extensions.is((select count(*) from public.transaction_documents where transaction_id='99800000-0000-4000-8300-000000000001'),
  0::bigint,'l’échec de finalisation ne crée aucune métadonnée métier');
select extensions.is(public.finalize_transaction_proof_document_operation(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001'),
  3,'preuve.pdf','application/pdf',12),4::bigint,'la finalisation clôt atomiquement l’opération');
reset role;
select extensions.is((select file_name from public.transaction_documents where transaction_id='99800000-0000-4000-8300-000000000001'),
  'preuve.pdf','les métadonnées métier sont enregistrées');
select extensions.is((select count(*) from public.document_object_locks where operation_id=(select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000001')),
  0::bigint,'la clôture vérifiée libère le verrou');

-- Compensation d'une création après interruption avant finalisation.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_transaction_proof_document_operation(
  '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8300-000000000002',
  'create','99800000-0000-4000-8400-000000000002');
select public.start_document_operation((select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002'),1);
reset role;
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99800000-0000-4000-8800-000000000002','transaction-proofs',
 'protected-persons/99800000-0000-4000-8100-000000000001/transactions/99800000-0000-4000-8300-000000000002/proof',
 '99800000-0000-4000-8000-000000000001','99800000-0000-4000-8000-000000000001',
 '{"size":20,"mimetype":"application/pdf"}','v1');
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000002'),2,0);
select extensions.is((public.begin_document_operation_compensation(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002'),3,'SERVER_INTERRUPTED')->>'state'),
  'compensating','une interruption ouvre la compensation contrôlée');
reset role;
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id='99800000-0000-4000-8800-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is((public.record_document_operation_target_compensated(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000002'),5,2)->>'state'),
 'compensated','la suppression compensatrice est observée');
select extensions.is(public.complete_document_operation_compensation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002'),6),
 7::bigint,'la compensation vérifiée devient terminale');
reset role;
select extensions.is((select count(*) from public.document_object_locks where operation_id=(select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000002')),
 0::bigint,'la compensation terminale libère le verrou');
select extensions.is((select count(*) from public.transaction_documents where transaction_id='99800000-0000-4000-8300-000000000002'),
 0::bigint,'aucune métadonnée métier n’a été créée avant compensation');

-- Perte de droit : démarrage refusé mais mise en attention possible et verrou conservé.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.begin_transaction_proof_document_operation(
  '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8300-000000000003',
  'create','99800000-0000-4000-8400-000000000003');
reset role;
delete from public.protected_person_access where id='99800000-0000-4000-8900-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  format('select public.start_document_operation(%L,1)',
    (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000003')),
  'P4O01','Accès à la réservation documentaire refusé.','la perte du droit bloque le démarrage');
select extensions.is(public.mark_document_operation_attention_required(
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000003'),1,'ACCESS_LOST'),
  2::bigint,'l’initiateur peut signaler l’incertitude après perte de droit');
reset role;
select extensions.is((select state from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000003'),
  'attention_required','l’opération reste non terminale');
select extensions.is((select count(*) from public.document_object_locks where operation_id=(select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000003')),
  1::bigint,'la mise en attention conserve le verrou');

-- Relevé créé avec PDF.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_bank_statement_document_operation(
 '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8200-000000000001',
 '99800000-0000-4000-8700-000000000001','create','99800000-0000-4000-8400-000000000004');
select public.start_document_operation((select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000004'),1);
reset role;
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99800000-0000-4000-8800-000000000003','bank-statements',
 'protected-persons/99800000-0000-4000-8100-000000000001/accounts/99800000-0000-4000-8200-000000000001/statements/99800000-0000-4000-8700-000000000001/statement',
 '99800000-0000-4000-8000-000000000001','99800000-0000-4000-8000-000000000001',
 '{"size":30,"mimetype":"application/pdf"}','v1');
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000004'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000004'),2,0);
select extensions.is(public.finalize_bank_statement_document_operation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000004'),3,
 '2026-01-01','2026-01-31',100,'note','janvier.pdf','application/pdf',30),
 4::bigint,'un relevé et son PDF sont finalisés atomiquement');
reset role;
select extensions.is((select original_file_name from public.bank_statements where id='99800000-0000-4000-8700-000000000001'),
 'janvier.pdf','le relevé créé conserve le nom du PDF');

-- Suppression du seul PDF : le relevé historique reste présent.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_bank_statement_document_operation(
 '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8200-000000000001',
 '99800000-0000-4000-8700-000000000001','delete','99800000-0000-4000-8400-000000000007');
select public.start_document_operation((select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000007'),1);
reset role;
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id='99800000-0000-4000-8800-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000007'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000007'),2,0);
select extensions.is(public.finalize_bank_statement_document_operation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000007'),3,
 null,null,null,null,null,null,null),4::bigint,
 'la suppression vérifiée du PDF se finalise');
reset role;
select extensions.ok((select original_file_name is null and mime_type is null and file_size is null
 from public.bank_statements where id='99800000-0000-4000-8700-000000000001'),
 'le relevé sans PDF est conservé avec des métadonnées cohérentes');

-- Génération puis finalisation à deux cibles d'un compte de gestion.
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_management_report_document_operation(
 '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8600-000000000001',
 'generate','99800000-0000-4000-8400-000000000005');
select public.start_document_operation((select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000005'),1);
reset role;
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99800000-0000-4000-8800-000000000004','management-reports',
 'protected-persons/99800000-0000-4000-8100-000000000001/management-reports/99800000-0000-4000-8600-000000000001/management-report-draft.pdf',
 '99800000-0000-4000-8000-000000000001','99800000-0000-4000-8000-000000000001',
 '{"size":40,"mimetype":"application/pdf"}','v1');
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000005'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000005'),2,0);
select extensions.is(public.finalize_management_report_document_operation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000005'),3,
 'projet.pdf','application/pdf',40,
 '{"report":{"id":"99800000-0000-4000-8600-000000000001","protected_person_id":"99800000-0000-4000-8100-000000000001","report_year":"2026","period_start":"2026-01-01","period_end":"2026-12-31","status":"generated"},"person":{"id":"99800000-0000-4000-8100-000000000001"}}',1),
 4::bigint,'la génération du projet est atomique');
reset role;
select extensions.is((select status::text from public.management_reports where id='99800000-0000-4000-8600-000000000001'),
 'generated','le compte de gestion passe à generated');

set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.begin_management_report_document_operation(
 '99800000-0000-4000-8100-000000000001','99800000-0000-4000-8600-000000000001',
 'finalize','99800000-0000-4000-8400-000000000006');
select extensions.is(jsonb_array_length((public.start_document_operation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000006'),1)->'targets')),
 2,'la finalisation expose exactement deux cibles réservées');
reset role;
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99800000-0000-4000-8800-000000000005','management-reports',
 'protected-persons/99800000-0000-4000-8100-000000000001/management-reports/99800000-0000-4000-8600-000000000001/management-report.pdf',
 '99800000-0000-4000-8000-000000000001','99800000-0000-4000-8000-000000000001',
 '{"size":50,"mimetype":"application/pdf"}','v1');
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id='99800000-0000-4000-8800-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000006'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000006' and target.target_role='destination'),2,0);
select extensions.throws_ok(
 format('select public.finalize_management_report_document_operation(%L,3,%L,%L,50,%L::jsonb,1)',
  (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000006'),
  'final.pdf','application/pdf','{}'),
 'P4S05','Toutes les cibles Storage ne sont pas appliquées.',
 'une opération multi-cible ne se finalise pas partiellement');
select public.record_document_operation_target_applied(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000006'),
 (select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='99800000-0000-4000-8400-000000000006' and target.target_role='source'),3,0);
select extensions.is(public.finalize_management_report_document_operation(
 (select id from public.document_operations where client_request_id='99800000-0000-4000-8400-000000000006'),4,
 'final.pdf','application/pdf',50,
 '{"report":{"id":"99800000-0000-4000-8600-000000000001","protected_person_id":"99800000-0000-4000-8100-000000000001","report_year":"2026","period_start":"2026-01-01","period_end":"2026-12-31","status":"finalized"},"person":{"id":"99800000-0000-4000-8100-000000000001"}}',1),
 5::bigint,'la finalisation multi-cible vérifiée devient atomiquement terminale');
reset role;
select extensions.is((select status::text from public.management_reports where id='99800000-0000-4000-8600-000000000001'),
 'finalized','le compte de gestion passe à finalized');
select extensions.is((select count(*) from public.management_report_documents where management_report_id='99800000-0000-4000-8600-000000000001' and document_type='management_report_draft'),
 0::bigint,'les métadonnées du projet sont supprimées');
select extensions.is((select count(*) from public.management_report_documents where management_report_id='99800000-0000-4000-8600-000000000001' and document_type='management_report'),
 1::bigint,'les métadonnées du PDF final sont conservées');

select extensions.is((select count(*) from pg_trigger trigger join pg_class relation on relation.oid=trigger.tgrelid join pg_namespace namespace on namespace.oid=relation.relnamespace
 where namespace.nspname='storage' and relation.relname='objects' and not trigger.tgisinternal and trigger.tgname like '%document_storage_guard%'),
 0::bigint,'aucun trigger bloquant Storage n’est installé');
select extensions.is((select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname like '%progress%'),
 0::bigint,'aucune politique Storage n’est ajoutée par ce lot');

select * from extensions.finish();
rollback;
