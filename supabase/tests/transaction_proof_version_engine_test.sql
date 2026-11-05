begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public','transaction_proof_version_reservations',
  'le registre des réservations versionnées existe');
select extensions.ok(has_function_privilege('authenticated',
  'public.reserve_transaction_proof_version(uuid,uuid,text,uuid)','EXECUTE'),
  'authenticated peut appeler la réservation dédiée');
select extensions.ok(has_function_privilege('authenticated',
  'public.finalize_transaction_proof_version(uuid,bigint,text,text,bigint,text,uuid)','EXECUTE'),
  'authenticated peut appeler la finalisation dédiée');
select extensions.ok(to_regprocedure(
  'public.finalize_transaction_proof_version(uuid,bigint,text,text,bigint,text,uuid,text)') is null,
  'aucune variante ne fait confiance à une version Storage fournie par le client');
select extensions.ok(not has_function_privilege('authenticated',
  'public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)','EXECUTE'),
  'l ancienne RPC expérimentale reste fermée');
select extensions.ok(not has_table_privilege('authenticated',
  'public.transaction_proof_version_reservations','SELECT'),
  'le registre technique n est pas lisible directement');
select extensions.ok(not has_table_privilege('authenticated',
  'public.transaction_proof_version_reservations','INSERT'),
  'le registre technique n est pas inscriptible directement');
select extensions.is((select count(*) from pg_policies where schemaname='storage'
  and tablename='objects' and policyname='transaction_proof_version_upload_reserved'),1::bigint,
  'une politique Storage dédiée est installée');

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000001','authenticated','authenticated','engine-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000002','authenticated','authenticated','engine-manager@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000003','authenticated','authenticated','engine-reader@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99600000-0000-4000-8000-000000000004','authenticated','authenticated','engine-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active',status_changed_at=now(),
  account_mode=case when user_id in ('99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000004')
    then 'autonomous' else 'collaborator' end
where user_id::text like '99600000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Alice',last_name='Moteur'
where id='99600000-0000-4000-8000-000000000001';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000001','Dossier','Actif'),
('99600000-0000-4000-8100-000000000002','99600000-0000-4000-8000-000000000001','Dossier','Archive');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99600000-0000-4000-8200-000000000001','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000002','manager','99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8200-000000000002','99600000-0000-4000-8100-000000000001','99600000-0000-4000-8000-000000000003','read_only','99600000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,
  account_name,initial_balance,initial_balance_date,status) values
('99600000-0000-4000-8300-000000000001','99600000-0000-4000-8100-000000000001','checking','Banque','Actif',0,'2026-01-01','active'),
('99600000-0000-4000-8300-000000000002','99600000-0000-4000-8100-000000000002','checking','Banque','Archive',0,'2026-01-01','active');

insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount,
  cancelled_at,cancelled_by) values
('99600000-0000-4000-8400-000000000001','99600000-0000-4000-8300-000000000001','2026-10-01','expense','Création',10,null,null),
('99600000-0000-4000-8400-000000000002','99600000-0000-4000-8300-000000000001','2026-10-02','income','Recette',20,null,null),
('99600000-0000-4000-8400-000000000003','99600000-0000-4000-8300-000000000001','2026-10-03','expense','Annulée',30,now(),'99600000-0000-4000-8000-000000000001'),
('99600000-0000-4000-8400-000000000004','99600000-0000-4000-8300-000000000001','2026-09-15','expense','Clôturée',40,null,null),
('99600000-0000-4000-8400-000000000005','99600000-0000-4000-8300-000000000002','2026-10-05','expense','Archivée',50,null,null),
('99600000-0000-4000-8400-000000000006','99600000-0000-4000-8300-000000000001','2026-10-06','expense','Legacy',60,null,null);
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values(
  '99600000-0000-4000-8700-000000000009','transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8400-000000000006/proof',
  '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
  '{"size":90,"mimetype":"application/pdf"}','legacy-v1');
insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
values('99600000-0000-4000-8750-000000000009','99600000-0000-4000-8400-000000000006',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8400-000000000006/proof',
  'legacy.pdf','application/pdf',90,'99600000-0000-4000-8000-000000000001');
insert into public.management_periods(id,protected_person_id,start_date,end_date,status,closed_at)
values('99600000-0000-4000-8500-000000000001','99600000-0000-4000-8100-000000000001',
  '2026-09-01','2026-09-30','closed',now());
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
update public.protected_persons set status='archived',archived_at=now()
where id='99600000-0000-4000-8100-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',true);

create temporary table proof_engine_result(payload jsonb) on commit drop;
insert into proof_engine_result values(public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'create','99600000-0000-4000-8600-000000000001'));
select extensions.is((select payload->>'state' from proof_engine_result),'reserved',
  'une dépense autorisée est réservée');
select extensions.ok((select payload->>'storagePath' from proof_engine_result)
  like 'protected-persons/%/proofs/%/versions/%','le chemin réservé est versionné');

insert into proof_engine_result select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'create','99600000-0000-4000-8600-000000000001');
select extensions.is((select count(distinct payload->>'operationId') from proof_engine_result),1::bigint,
  'la même clé rejoue la même réservation');
select extensions.ok((select (payload->>'idempotent')::boolean from proof_engine_result
  order by ctid desc limit 1),'le rejeu est explicitement idempotent');

select extensions.is((select count(*) from public.transaction_proof_documents
  where transaction_id='99600000-0000-4000-8400-000000000001'),0::bigint,
  'la réservation ne crée pas un document faussement disponible');
select extensions.is((select count(*) from public.transaction_proof_versions
  where id=(select (payload->>'versionId')::uuid from proof_engine_result limit 1)),0::bigint,
  'la réservation ne crée pas une version avant upload');

select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'replace','99600000-0000-4000-8600-000000000001')$$,'P4O04',
  'La clé d’idempotence est déjà utilisée pour une autre demande.',
  'une clé idempotente ne peut pas changer d intention');
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'create','99600000-0000-4000-8600-000000000002')$$,'P4O05',
  'Une opération documentaire est déjà en cours pour cette transaction.',
  'une réservation concurrente est refusée');
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000002',
  'create','99600000-0000-4000-8600-000000000003')$$,'P4O02',
  'Seule une dépense active peut recevoir un justificatif.',
  'une recette est refusée');
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000003',
  'create','99600000-0000-4000-8600-000000000004')$$,'P4O02',
  'Seule une dépense active peut recevoir un justificatif.',
  'une transaction annulée est refusée');
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000004',
  'create','99600000-0000-4000-8600-000000000005')$$,'P4O03',
  'Un exercice clôturé ne peut pas être modifié.',
  'un exercice clôturé est refusé');
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000002','99600000-0000-4000-8400-000000000005',
  'create','99600000-0000-4000-8600-000000000006')$$,'P4O03',
  'Le dossier doit être actif.','un dossier archivé est refusé');

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000003',true);
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000002',
  'create','99600000-0000-4000-8600-000000000007')$$,'P4O01',
  'Accès à la réservation documentaire refusé.','un lecteur ne réserve pas');
select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000004',true);
select extensions.throws_ok($$select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000002',
  'create','99600000-0000-4000-8600-000000000008')$$,'P4O01',
  'Accès à la réservation documentaire refusé.','un utilisateur extérieur ne réserve pas');

select set_config('request.jwt.claim.sub','99600000-0000-4000-8000-000000000001',true);
create temporary table legacy_engine_result(payload jsonb) on commit drop;
insert into legacy_engine_result values(public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000006',
  'replace','99600000-0000-4000-8600-000000000010'));
select extensions.is((select version.path_kind from public.transaction_proof_versions version
  join public.transaction_proof_documents document on document.id=version.proof_document_id
  where document.transaction_id='99600000-0000-4000-8400-000000000006'),'legacy',
  'un justificatif /proof existant est adopté comme version legacy');
select extensions.is((select (payload->>'versionNumber')::bigint from legacy_engine_result),2::bigint,
  'le remplacement legacy réserve une deuxième version sans réutiliser le chemin');

select extensions.throws_like($$insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version,user_metadata)
  values(gen_random_uuid(),'transaction-proofs',
    'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8400-000000000001/proofs/99600000-0000-4000-8800-000000000009/versions/99600000-0000-4000-8900-000000000009',
    '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
    '{"size":100,"mimetype":"application/pdf"}','bad-v1','{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}')$$,
  '%row-level security policy%','un chemin versionné sans réservation exacte est refusé');

insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version,user_metadata)
select '99600000-0000-4000-8700-000000000001','transaction-proofs',payload->>'storagePath',
  '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
  '{"size":100,"mimetype":"application/pdf"}','object-v1',
  '{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
from proof_engine_result limit 1;
reset role;
select extensions.is((select count(*) from storage.objects
  where id='99600000-0000-4000-8700-000000000001'),1::bigint,
  'la réservation autorise uniquement son objet exact');
set local role authenticated;

insert into proof_engine_result select public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'create','99600000-0000-4000-8600-000000000001');
select extensions.is((select payload->>'storageObjectId' from proof_engine_result
  order by ctid desc limit 1),'99600000-0000-4000-8700-000000000001',
  'le rejeu récupère l identifiant exact après une réponse d upload perdue');

select extensions.throws_ok($$select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result limit 1),
  (select (payload->>'operationRevision')::bigint from proof_engine_result limit 1)+1,
  'preuve.pdf','application/pdf',100,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '99600000-0000-4000-8700-000000000001')$$,'P4O06',
  'La réservation documentaire a changé.',
  'une révision de réservation obsolète est refusée');
select extensions.throws_ok($$select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result limit 1),
  (select (payload->>'operationRevision')::bigint from proof_engine_result limit 1),
  'preuve.pdf','application/pdf',100,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '99600000-0000-4000-8700-000000000099')$$,'P4S04',
  'Le fichier Storage ne correspond pas à la réservation.',
  'un identifiant Storage différent de l objet réservé est refusé');
select extensions.throws_ok($$select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result limit 1),
  (select (payload->>'operationRevision')::bigint from proof_engine_result limit 1),
  'preuve.pdf','application/pdf',100,
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '99600000-0000-4000-8700-000000000001')$$,'P4S04',
  'Le fichier Storage ne correspond pas à la réservation.',
  'une empreinte incohérente refuse la finalisation');

insert into proof_engine_result select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result limit 1),
  (select (payload->>'operationRevision')::bigint from proof_engine_result limit 1),
  'preuve.pdf','application/pdf',100,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '99600000-0000-4000-8700-000000000001');
select extensions.is((select lifecycle_state from public.transaction_proof_versions
  where storage_object_id='99600000-0000-4000-8700-000000000001'),'current',
  'la finalisation rend la version vérifiée courante');
select extensions.is((select availability_status from public.transaction_proof_versions
  where storage_object_id='99600000-0000-4000-8700-000000000001'),'available',
  'seule la version vérifiée devient disponible');
select extensions.is((select storage_object_version from public.transaction_proof_versions
  where storage_object_id='99600000-0000-4000-8700-000000000001'),'object-v1',
  'la version Storage est résolue depuis le catalogue PostgreSQL');
select extensions.is((select payload->>'storageObjectVersion' from proof_engine_result
  where payload->>'state'='completed' limit 1),'object-v1',
  'la finalisation confirme au client la version autoritative enregistrée');
select extensions.is((select storage_path from public.transaction_documents
  where transaction_id='99600000-0000-4000-8400-000000000001'),
  (select storage_path from public.transaction_proof_versions
    where storage_object_id='99600000-0000-4000-8700-000000000001'),
  'le rattachement historique pointe vers la version courante');

select extensions.ok((public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result
    where payload ? 'storagePath' limit 1),1,
  'preuve.pdf','application/pdf',100,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '99600000-0000-4000-8700-000000000001')->>'idempotent')::boolean,
  'une double finalisation identique est sûre');
select extensions.throws_ok($$select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result
    where payload ? 'storagePath' limit 1),1,
  'autre.pdf','application/pdf',100,
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '99600000-0000-4000-8700-000000000001')$$,'P4O04',
  'La finalisation a déjà été enregistrée avec un autre résultat.',
  'une double finalisation contradictoire est refusée');

truncate proof_engine_result;
insert into proof_engine_result values(public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'replace','99600000-0000-4000-8600-000000000009'));
select extensions.is((select count(*) from public.transaction_proof_versions
  where lifecycle_state='current' and storage_object_id='99600000-0000-4000-8700-000000000001'),1::bigint,
  'l ancienne version reste courante avant confirmation du remplacement');
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version,user_metadata)
select '99600000-0000-4000-8700-000000000002','transaction-proofs',payload->>'storagePath',
  '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
  '{"size":120,"mimetype":"application/pdf"}','object-v2',
  '{"sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'
from proof_engine_result;
select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result),
  (select (payload->>'operationRevision')::bigint from proof_engine_result),
  'preuve-v2.pdf','application/pdf',120,
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  '99600000-0000-4000-8700-000000000002');
select extensions.is((select lifecycle_state from public.transaction_proof_versions
  where storage_object_id='99600000-0000-4000-8700-000000000001'),
  'superseded_pending_deletion','l ancienne version entre en retrait différé');
select extensions.is((select lifecycle_state from public.transaction_proof_versions
  where storage_object_id='99600000-0000-4000-8700-000000000002'),
  'current','la nouvelle version devient courante après confirmation');
select extensions.is((select state from public.transaction_proof_replacement_retirements
  where replacement_version_id=(select id from public.transaction_proof_versions
    where storage_object_id='99600000-0000-4000-8700-000000000002')),
  'pending_secure_deletion','le retrait physique reste différé et traçable');
select extensions.is((select count(*) from storage.objects where id in (
  '99600000-0000-4000-8700-000000000001','99600000-0000-4000-8700-000000000002')),2::bigint,
  'le remplacement SQL ne supprime aucun objet physique');
select extensions.is((select count(distinct storage_path) from public.transaction_proof_versions
  where proof_document_id=(select proof_document_id from public.transaction_documents
    where transaction_id='99600000-0000-4000-8400-000000000001')),2::bigint,
  'chaque version conserve un chemin distinct');

truncate proof_engine_result;
insert into proof_engine_result values(public.reserve_transaction_proof_version(
  '99600000-0000-4000-8100-000000000001','99600000-0000-4000-8400-000000000001',
  'replace','99600000-0000-4000-8600-000000000011'));
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version,user_metadata)
select '99600000-0000-4000-8700-000000000003','transaction-proofs',payload->>'storagePath',
  '99600000-0000-4000-8000-000000000001','99600000-0000-4000-8000-000000000001',
  '{"size":130,"mimetype":"application/pdf"}','object-v3',
  '{"sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'
from proof_engine_result;
select extensions.throws_ok($$select public.finalize_transaction_proof_version(
  (select (payload->>'operationId')::uuid from proof_engine_result),
  (select (payload->>'operationRevision')::bigint from proof_engine_result),
  'preuve-v3.pdf','application/pdf',131,
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  '99600000-0000-4000-8700-000000000003')$$,'P4S04',
  'Le fichier Storage ne correspond pas à la réservation.',
  'un remplacement aux métadonnées divergentes échoue');
select extensions.is((select storage_object_id from public.transaction_proof_versions
  where lifecycle_state='current' and proof_document_id=(select proof_document_id
    from public.transaction_documents where transaction_id='99600000-0000-4000-8400-000000000001')),
  '99600000-0000-4000-8700-000000000002'::uuid,
  'un remplacement échoué laisse intacte la version courante');
select extensions.is((select count(*) from public.transaction_proof_replacement_retirements
  where proof_document_id=(select proof_document_id from public.transaction_documents
    where transaction_id='99600000-0000-4000-8400-000000000001')),1::bigint,
  'un remplacement échoué ne crée aucun retrait supplémentaire');

reset role;
select * from extensions.finish();
rollback;
