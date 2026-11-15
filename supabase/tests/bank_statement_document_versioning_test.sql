begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(72);

select extensions.has_table('public', 'bank_statement_document_versions',
  'les versions documentaires des relevés existent');
select extensions.has_table('public', 'bank_statement_active_document_versions',
  'la référence atomique de version active existe');
select extensions.has_table('public', 'bank_statement_document_corrections',
  'les réservations de correction existent');
select extensions.has_table('public', 'management_report_bank_statement_document_versions',
  'les comptes de gestion peuvent figer une version de relevé');
select extensions.has_function('public', 'build_bank_statement_document_version_path',
  array['uuid','uuid','uuid','uuid'], 'le constructeur de chemin versionné existe');
select extensions.has_function('public', 'begin_bank_statement_document_correction',
  array['uuid','uuid','uuid','bigint','uuid','text','text','bigint','text'],
  'la réservation dédiée existe');
select extensions.has_function('public', 'finalize_bank_statement_document_correction',
  array['uuid','bigint','uuid','text'], 'la finalisation atomique existe');
select extensions.has_function('public', 'cancel_bank_statement_document_correction',
  array['uuid','bigint'], 'l annulation sûre existe');
select extensions.has_function('public', 'get_bank_statement_document_history',
  array['uuid'], 'la lecture de l historique existe');
select extensions.ok(
  has_function_privilege('service_role',
    'public.verify_bank_statement_document_version_integrity(uuid,uuid,text,text)','EXECUTE')
  and not has_function_privilege('authenticated',
    'public.verify_bank_statement_document_version_integrity(uuid,uuid,text,text)','EXECUTE')
  and not has_function_privilege('anon',
    'public.verify_bank_statement_document_version_integrity(uuid,uuid,text,text)','EXECUTE'),
  'seul le service serveur peut enregistrer l empreinte calculée du PDF legacy');

select extensions.ok(
  not has_table_privilege('authenticated','public.bank_statement_document_versions','INSERT')
  and not has_table_privilege('authenticated','public.bank_statement_document_versions','UPDATE')
  and not has_table_privilege('authenticated','public.bank_statement_document_versions','DELETE')
  and not has_table_privilege('service_role','public.bank_statement_document_versions','INSERT')
  and not has_table_privilege('service_role','public.bank_statement_document_versions','UPDATE')
  and not has_table_privilege('service_role','public.bank_statement_document_versions','DELETE'),
  'aucun rôle applicatif ne modifie directement les versions');
select extensions.ok(
  has_function_privilege('authenticated',
    'public.begin_bank_statement_document_correction(uuid,uuid,uuid,bigint,uuid,text,text,bigint,text)','EXECUTE')
  and has_function_privilege('authenticated',
    'public.finalize_bank_statement_document_correction(uuid,bigint,uuid,text)','EXECUTE')
  and not has_function_privilege('anon',
    'public.begin_bank_statement_document_correction(uuid,uuid,uuid,bigint,uuid,text,text,bigint,text)','EXECUTE')
  and not has_function_privilege('service_role',
    'public.begin_bank_statement_document_correction(uuid,uuid,uuid,bigint,uuid,text,text,bigint,text)','EXECUTE'),
  'seuls les utilisateurs authentifiés disposent des points d entrée dédiés');
select extensions.ok(
  not has_function_privilege('authenticated',
    'public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid)','EXECUTE'),
  'les RPC documentaires expérimentales restent fermées');
select extensions.ok(
  not has_function_privilege('anon',
    'public.assert_bank_statement_initial_document_mutable(uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated',
    'public.assert_bank_statement_initial_document_mutable(uuid,uuid)','EXECUTE')
  and not has_function_privilege('service_role',
    'public.assert_bank_statement_initial_document_mutable(uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated',
    'public.cleanup_unfrozen_bank_statement_document_versions()','EXECUTE')
  and not has_function_privilege('authenticated',
    'public.protect_bank_statement_document_storage_version()','EXECUTE'),
  'les fonctions de synchronisation restent internes aux triggers');
select extensions.is((
  select count(*) from pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname in (
      'bank_statement_document_versions_storage_select_accessible',
      'bank_statement_document_corrections_storage_insert_manage'
    )
), 2::bigint, 'Storage possède uniquement les nouvelles gardes explicites attendues');

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','9b000000-0000-4000-8000-000000000001','authenticated','authenticated','statement-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','9b000000-0000-4000-8000-000000000002','authenticated','authenticated','statement-reader@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','9b000000-0000-4000-8000-000000000003','authenticated','authenticated','statement-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id::text like '9b000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Propriétaire',last_name='Relevé'
where id='9b000000-0000-4000-8000-000000000001';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8000-000000000001','Dossier','Relevés');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('9b000000-0000-4000-8200-000000000001','9b000000-0000-4000-8100-000000000001',
 '9b000000-0000-4000-8000-000000000002','read_only','9b000000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,
  account_name,initial_balance,initial_balance_date,status) values
('9b000000-0000-4000-8300-000000000001','9b000000-0000-4000-8100-000000000001',
 'checking','Banque test','Compte test',100,'2026-01-01','active');

-- Une version initiale suit le document courant tant que le relevé n'est ni
-- rapproché ni référencé par un compte de gestion définitif.
insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,
  statement_balance,storage_path,original_file_name,mime_type,file_size,note,created_by) values
('9b000000-0000-4000-8400-000000000002','9b000000-0000-4000-8300-000000000001',
 '2026-02-01','2026-02-28',110,
 'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000002/statement',
 'avant-validation.pdf','application/pdf',121,'Cycle pré-validation',
 '9b000000-0000-4000-8000-000000000001');
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
values('9b000000-0000-4000-8700-000000000020','bank-statements',
  'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000002/statement',
  '9b000000-0000-4000-8000-000000000001','9b000000-0000-4000-8000-000000000001',
  '{"size":121,"mimetype":"application/pdf"}'::jsonb,'pre-v1');

select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000002'),1::bigint,
  'l ajout initial crée exactement une version documentaire');

set local role service_role;
select public.verify_bank_statement_document_version_integrity(
  (select id from public.bank_statement_document_versions
    where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  '9b000000-0000-4000-8700-000000000020','pre-v1',repeat('2',64));
reset role;
select extensions.is((select integrity_status from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000002'),'verified',
  'l empreinte initiale peut être vérifiée avant le rapprochement');

update storage.objects
set version='pre-v2', metadata='{"size":130,"mimetype":"application/pdf"}'::jsonb
where id='9b000000-0000-4000-8700-000000000020';
select extensions.ok((select integrity_status='pending_hash' and sha256 is null
    and verified_at is null and verified_by is null
  from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  'le remplacement des octets invalide immédiatement l ancienne empreinte');

update public.bank_statements
set original_file_name='remplacement-avant-validation.pdf',
    mime_type='application/pdf', file_size=130
where id='9b000000-0000-4000-8400-000000000002';
select extensions.ok((select original_file_name='remplacement-avant-validation.pdf'
    and file_size=130 and integrity_status='pending_hash' and sha256 is null
  from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  'les métadonnées de la version initiale suivent le PDF remplacé');
select extensions.ok((select statement_balance=110 and note='Cycle pré-validation'
  from public.bank_statements where id='9b000000-0000-4000-8400-000000000002'),
  'le remplacement documentaire ne modifie aucune donnée financière');

select extensions.ok(exists(
  select 1
  from pg_trigger trigger
  join pg_proc function on function.oid=trigger.tgfoid
  join pg_namespace namespace on namespace.oid=function.pronamespace
  where trigger.tgrelid='storage.objects'::regclass
    and not trigger.tgisinternal
    and namespace.nspname='storage'
    and function.proname='protect_delete'
), 'la suppression physique reste exclusivement confiée à l API Storage native');
-- Le retrait physique a lieu via l API Storage dans l application. Le test SQL
-- exerce uniquement sa finalisation PostgreSQL ; la transaction de test remet
-- ensuite automatiquement la fixture Storage dans son état initial.
update public.bank_statements
set original_file_name=null,mime_type=null,file_size=null
where id='9b000000-0000-4000-8400-000000000002';
select extensions.ok(
  not exists(select 1 from public.bank_statement_document_versions
    where bank_statement_id='9b000000-0000-4000-8400-000000000002')
  and not exists(select 1 from public.bank_statement_active_document_versions
    where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  'le retrait du PDF retire uniquement sa version initiale non figée');

update storage.objects
set version='pre-v3', metadata='{"size":131,"mimetype":"application/pdf"}'::jsonb
where id='9b000000-0000-4000-8700-000000000020';
update public.bank_statements
set original_file_name='nouveau-document.pdf',mime_type='application/pdf',file_size=131
where id='9b000000-0000-4000-8400-000000000002';
select extensions.ok((select version_number=1 and original_file_name='nouveau-document.pdf'
    and file_size=131 and integrity_status='pending_hash'
  from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  'un nouvel ajout après retrait recrée une version initiale cohérente');

update public.bank_statements
set original_file_name=null,mime_type=null,file_size=null
where id='9b000000-0000-4000-8400-000000000002';
delete from public.bank_statements
where id='9b000000-0000-4000-8400-000000000002';
select extensions.ok(
  not exists(select 1 from public.bank_statements
    where id='9b000000-0000-4000-8400-000000000002')
  and not exists(select 1 from public.bank_statement_document_versions
    where bank_statement_id='9b000000-0000-4000-8400-000000000002'),
  'un relevé non validé reste supprimable après retrait de son PDF');

-- L ancien parcours peut supprimer directement un relevé non validé après la
-- compensation Storage ; le trigger nettoie alors la seule version non figée.
insert into public.bank_statements(id,financial_account_id,statement_end_date,statement_balance,
  storage_path,original_file_name,mime_type,file_size,created_by) values
('9b000000-0000-4000-8400-000000000003','9b000000-0000-4000-8300-000000000001',
 '2026-03-31',120,
 'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000003/statement',
 'suppression-directe.pdf','application/pdf',122,
 '9b000000-0000-4000-8000-000000000001');
select extensions.lives_ok($$delete from public.bank_statements
  where id='9b000000-0000-4000-8400-000000000003'$$,
  'un relevé non validé avec version initiale reste supprimable');
select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000003'),0::bigint,
  'la suppression du relevé non validé ne laisse aucune version orpheline');

-- Une liaison de compte de gestion fige la version même sans rapprochement.
insert into public.bank_statements(id,financial_account_id,statement_end_date,statement_balance,
  storage_path,original_file_name,mime_type,file_size,created_by) values
('9b000000-0000-4000-8400-000000000004','9b000000-0000-4000-8300-000000000001',
 '2026-04-30',130,
 'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000004/statement',
 'document-fige.pdf','application/pdf',123,
 '9b000000-0000-4000-8000-000000000001');
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
values('9b000000-0000-4000-8700-000000000040','bank-statements',
  'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000004/statement',
  '9b000000-0000-4000-8000-000000000001','9b000000-0000-4000-8000-000000000001',
  '{"size":123,"mimetype":"application/pdf"}'::jsonb,'frozen-v1');
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,
  status,generated_at,created_by) values
('9b000000-0000-4000-8800-000000000001','9b000000-0000-4000-8100-000000000001',
 2025,'2025-01-01','2025-12-31','generated',now(),'9b000000-0000-4000-8000-000000000001');
insert into public.management_report_documents(id,management_report_id,document_type,storage_path,
  file_name,mime_type,file_size,generated_by) values
('9b000000-0000-4000-8900-000000000001','9b000000-0000-4000-8800-000000000001',
 'management_report_draft',
 'protected-persons/9b000000-0000-4000-8100-000000000001/management-reports/9b000000-0000-4000-8800-000000000001/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,'9b000000-0000-4000-8000-000000000001');
insert into public.management_report_bank_statement_document_versions(
  management_report_document_id,bank_statement_id,document_version_id
) select '9b000000-0000-4000-8900-000000000001',
    '9b000000-0000-4000-8400-000000000004',version.id
  from public.bank_statement_document_versions version
  where version.bank_statement_id='9b000000-0000-4000-8400-000000000004';

select extensions.throws_ok($$update storage.objects set version='frozen-v2'
  where id='9b000000-0000-4000-8700-000000000040'$$,
  '55000','Le document historique du relevé est définitivement figé.',
  'un objet Storage référencé par un compte de gestion ne peut pas être remplacé');
select extensions.ok(exists(select 1 from storage.objects
  where id='9b000000-0000-4000-8700-000000000040'
    and version='frozen-v1'),
  'un échec de remplacement conserve l objet Storage référencé par le compte de gestion');
select extensions.throws_ok($$update public.bank_statements
  set original_file_name='interdit.pdf',file_size=124
  where id='9b000000-0000-4000-8400-000000000004'$$,
  '55000','Le document historique du relevé est définitivement figé.',
  'les métadonnées d une version épinglée ne peuvent pas être modifiées');
select extensions.throws_ok($$delete from public.bank_statements
  where id='9b000000-0000-4000-8400-000000000004'$$,
  '55000','Le document historique du relevé est définitivement figé.',
  'un relevé référencé par un compte de gestion ne peut pas être supprimé');
select extensions.ok(exists(select 1 from public.bank_statement_document_versions version
  join public.management_report_bank_statement_document_versions pinned
    on pinned.document_version_id=version.id
  where version.bank_statement_id='9b000000-0000-4000-8400-000000000004'
    and version.original_file_name='document-fige.pdf'),
  'les refus conservent la version documentaire historique intacte');

insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,
  statement_balance,storage_path,original_file_name,mime_type,file_size,note,created_by) values
('9b000000-0000-4000-8400-000000000001','9b000000-0000-4000-8300-000000000001',
 '2026-01-01','2026-01-31',100,
 'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000001/statement',
 'releve-original.pdf','application/pdf',120,'Métadonnées à préserver',
 '9b000000-0000-4000-8000-000000000001');

select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),1::bigint,
  'le document existant devient une version initiale sans déplacement');
select extensions.is((select count(*) from public.bank_statement_active_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001' and revision=1),1::bigint,
  'la version initiale devient active avec une révision');
select extensions.is((select storage_path from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),
  'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000001/statement',
  'le chemin Storage historique reste strictement inchangé');
select extensions.is((select integrity_status from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),'pending_hash',
  'une version legacy attend une empreinte calculée sans prétendre lire le PDF');

insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
values('9b000000-0000-4000-8700-000000000000','bank-statements',
  'protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000001/statement',
  '9b000000-0000-4000-8000-000000000001','9b000000-0000-4000-8000-000000000001',
  '{"size":120,"mimetype":"application/pdf"}'::jsonb,'storage-v1');
set local role service_role;
select public.verify_bank_statement_document_version_integrity(
  (select id from public.bank_statement_document_versions
    where bank_statement_id='9b000000-0000-4000-8400-000000000001'),
  '9b000000-0000-4000-8700-000000000000','storage-v1',repeat('0',64));
reset role;
select extensions.is((select integrity_status from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),'verified',
  'le service serveur peut compléter une seule fois l intégrité du document legacy');
select extensions.is((select sha256 from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),repeat('0',64),
  'l empreinte calculée du document legacy est conservée');

set local role authenticated;
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000001',true);
insert into public.bank_reconciliations(id,bank_statement_id,created_by)
values('9b000000-0000-4000-8500-000000000001','9b000000-0000-4000-8400-000000000001',
  '9b000000-0000-4000-8000-000000000001');
select public.validate_bank_reconciliation('9b000000-0000-4000-8500-000000000001');

reset role;
select extensions.throws_ok($$update storage.objects set version='storage-v1-interdit'
  where id='9b000000-0000-4000-8700-000000000000'$$,
  '55000','Le document historique du relevé est définitivement figé.',
  'les octets du PDF validé ne peuvent plus être remplacés');
select extensions.ok(exists(select 1 from storage.objects
  where id='9b000000-0000-4000-8700-000000000000'
    and version='storage-v1'),
  'un échec de remplacement conserve l objet Storage du relevé validé');
select extensions.throws_ok($$update public.bank_statements
  set original_file_name='valide-modifie.pdf'
  where id='9b000000-0000-4000-8400-000000000001'$$,
  'P0001','Un relevé rapproché est définitivement figé.',
  'les métadonnées du relevé validé restent figées');
select extensions.throws_ok($$delete from public.bank_statements
  where id='9b000000-0000-4000-8400-000000000001'$$,
  'P0001','Un relevé rapproché est définitivement figé.',
  'le relevé validé reste protégé contre la suppression');

set local role authenticated;
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000002',true);
select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),1::bigint,
  'le lecteur autorisé consulte les versions');
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000003',true);
select extensions.is((select count(*) from public.bank_statement_document_versions),0::bigint,
  'un utilisateur extérieur ne consulte aucune version');
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000002',true);
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000001',
  'Correction interdite au lecteur','nouveau.pdf',140,repeat('a',64))$$,
  '42501','Relevé introuvable ou accès refusé.',
  'un lecteur ne réserve aucune correction');
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000003',true);
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000002',
  'Correction interdite au tiers','nouveau.pdf',140,repeat('a',64))$$,
  '42501','Relevé introuvable ou accès refusé.',
  'un utilisateur extérieur ne réserve aucune correction');

select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000001',true);
select extensions.is((public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000010',
  'Le PDF reçu ne correspond pas au relevé validé','releve-corrige.pdf',140,repeat('b',64)
)->>'state'),'reserved','le propriétaire réserve une correction validée');
select extensions.is((select (public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000010',
  'Le PDF reçu ne correspond pas au relevé validé','releve-corrige.pdf',140,repeat('b',64)
)->>'operationId') = id::text from public.bank_statement_document_corrections
  where client_request_id='9b000000-0000-4000-8600-000000000010'),true,
  'le rejeu identique retourne la même réservation');
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000010',
  'Une intention différente','autre.pdf',141,repeat('c',64))$$,
  'P4R04','La clé d''idempotence est déjà utilisée pour une autre correction.',
  'une même clé ne peut porter une autre intention');
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000011',
  'Correction concurrente','concurrent.pdf',142,repeat('d',64))$$,
  '55000','Une correction documentaire est déjà en cours pour ce relevé.',
  'une seconde correction concurrente est refusée');
select extensions.throws_ok($$select public.finalize_bank_statement_document_correction(
  (select id from public.bank_statement_document_corrections
    where client_request_id='9b000000-0000-4000-8600-000000000010'),
  0,'9b000000-0000-4000-8700-000000000001','storage-v2')$$,
  '55000','Le nouveau PDF n''est pas vérifié dans le stockage privé.',
  'la finalisation refuse un objet Storage absent');
select extensions.is((select state from public.bank_statement_document_corrections
  where client_request_id='9b000000-0000-4000-8600-000000000010'),'reserved',
  'un échec de finalisation conserve une réservation reprenable');

reset role;
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
select '9b000000-0000-4000-8700-000000000001','bank-statements',proposed_storage_path,
  '9b000000-0000-4000-8000-000000000001','9b000000-0000-4000-8000-000000000001',
  '{"size":140,"mimetype":"application/pdf"}'::jsonb,'storage-v2'
from public.bank_statement_document_corrections
where client_request_id='9b000000-0000-4000-8600-000000000010';

set local role authenticated;
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000001',true);
select extensions.lives_ok($$select public.finalize_bank_statement_document_correction(
  (select id from public.bank_statement_document_corrections
    where client_request_id='9b000000-0000-4000-8600-000000000010'),
  0,'9b000000-0000-4000-8700-000000000001','storage-v2')$$,
  'la reprise finalise la correction après vérification de l objet');
reset role;

select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),2::bigint,
  'les deux versions sont conservées');
select extensions.ok(exists(select 1 from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'
    and version_number=1 and path_kind='legacy'),
  'la version originale reste conservée à son chemin historique');
select extensions.is((select version_number from public.bank_statement_document_versions version
  join public.bank_statement_active_document_versions active on active.version_id=version.id
  where active.bank_statement_id='9b000000-0000-4000-8400-000000000001'),2,
  'la nouvelle version devient active atomiquement');
select extensions.is((select revision from public.bank_statement_active_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),2::bigint,
  'le basculement incrémente la révision active');
select extensions.ok((select statement_balance=100
    and statement_start_date='2026-01-01'::date
    and statement_end_date='2026-01-31'::date
    and note='Métadonnées à préserver'
    and storage_path='protected-persons/9b000000-0000-4000-8100-000000000001/accounts/9b000000-0000-4000-8300-000000000001/statements/9b000000-0000-4000-8400-000000000001/statement'
  from public.bank_statements where id='9b000000-0000-4000-8400-000000000001'),
  'aucune donnée du relevé bancaire n est modifiée');
select extensions.is((select status::text from public.bank_reconciliations
  where id='9b000000-0000-4000-8500-000000000001'),'validated',
  'le rapprochement reste validé et intact');

set local role authenticated;
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000001',true);
select extensions.is((public.finalize_bank_statement_document_correction(
  (select id from public.bank_statement_document_corrections
    where client_request_id='9b000000-0000-4000-8600-000000000010'),
  0,'9b000000-0000-4000-8700-000000000001','storage-v2')->>'state'),'completed',
  'un rejeu réseau de la finalisation ne crée aucune version supplémentaire');
select extensions.is((select count(*) from public.get_bank_statement_document_history(
  '9b000000-0000-4000-8400-000000000001')),2::bigint,
  'l historique autorisé expose les deux versions');
select extensions.throws_ok($$update public.bank_statement_document_versions
  set original_file_name='altération.pdf'
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'$$,
  '42501',null,'une version ne peut pas être altérée directement');
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',1,'9b000000-0000-4000-8600-000000000012',
  'Révision périmée','stale.pdf',143,repeat('e',64))$$,
  '40001','Le document actif a changé. Rechargez le relevé avant de recommencer.',
  'une révision obsolète est refusée');
select extensions.lives_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',2,'9b000000-0000-4000-8600-000000000013',
  'Réservation à annuler','cancel.pdf',144,repeat('f',64))$$,
  'une nouvelle intention utilise la révision courante');
select extensions.lives_ok($$select public.cancel_bank_statement_document_correction(
  (select id from public.bank_statement_document_corrections
    where client_request_id='9b000000-0000-4000-8600-000000000013'),0)$$,
  'une réservation sans objet Storage peut être annulée');
select extensions.is((select count(*) from public.bank_statement_document_versions
  where bank_statement_id='9b000000-0000-4000-8400-000000000001'),2::bigint,
  'une annulation de réservation ne crée ni ne supprime de version');

reset role;
update public.protected_persons
set status='archived', archived_at=clock_timestamp()
where id='9b000000-0000-4000-8100-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','9b000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok($$select public.begin_bank_statement_document_correction(
  '9b000000-0000-4000-8100-000000000001','9b000000-0000-4000-8300-000000000001',
  '9b000000-0000-4000-8400-000000000001',2,'9b000000-0000-4000-8600-000000000014',
  'Dossier archivé','archive.pdf',145,repeat('1',64))$$,
  '42501','Relevé introuvable ou accès refusé.',
  'un dossier archivé refuse toute correction');
reset role;

select extensions.ok(position('management_report_bank_statement_document_versions'
  in pg_get_functiondef('public.pin_management_report_bank_statement_document_versions()'::regprocedure))>0,
  'les futurs documents de compte de gestion figent leur version de relevé');
select extensions.ok(exists(select 1 from pg_trigger
  where tgrelid='public.management_report_documents'::regclass
    and tgname='management_report_documents_pin_bank_statement_versions'
    and not tgisinternal),
  'le gel documentaire est automatique à la création du document de compte de gestion');
select extensions.is((select count(*) from pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname like 'bank_statement_document_%'
    and cmd in ('UPDATE','DELETE')),0::bigint,
  'aucune politique Storage n autorise l écrasement ou la suppression des versions');
select extensions.ok(exists(select 1 from pg_trigger
  where tgrelid='public.bank_statements'::regclass
    and tgname='bank_statements_protect_validated_delete'
    and not tgisinternal),
  'la protection de suppression des relevés rapprochés reste installée');
select extensions.ok(position('Un relevé rapproché est définitivement figé.' in pg_get_functiondef(
  'public.protect_bank_statement_identity()'::regprocedure))>0,
  'le verrou historique des rapprochements validés reste inchangé');
select extensions.ok(position('update public.bank_statements' in lower(pg_get_functiondef(
  'public.finalize_bank_statement_document_correction(uuid,bigint,uuid,text)'::regprocedure)))=0,
  'la finalisation documentaire ne contourne jamais le verrou de bank_statements');

select * from extensions.finish();
rollback;
