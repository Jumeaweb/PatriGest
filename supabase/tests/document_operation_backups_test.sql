begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public','document_operation_backups',
  'le registre durable des sauvegardes existe');
select extensions.ok(
  exists(select 1 from storage.buckets where id='document-operation-backups'
    and not public and file_size_limit=20971520),
  'le bucket de récupération est privé et borné'
);
select extensions.ok(
  not has_table_privilege('anon','public.document_operation_backups','SELECT')
  and not has_table_privilege('authenticated','public.document_operation_backups','SELECT')
  and not has_table_privilege('service_role','public.document_operation_backups','SELECT'),
  'aucun rôle applicatif ne lit ou ne modifie directement le registre'
);
select extensions.ok(
  has_function_privilege('authenticated',
    'public.reserve_document_operation_backup(uuid,uuid,bigint,text,text)','EXECUTE')
  and not has_function_privilege('anon',
    'public.reserve_document_operation_backup(uuid,uuid,bigint,text,text)','EXECUTE')
  and not has_function_privilege('authenticated',
    'public.get_document_operation_backup_storage_descriptor(uuid)','EXECUTE')
  and has_function_privilege('service_role',
    'public.get_document_operation_backup_storage_descriptor(uuid)','EXECUTE'),
  'les RPC utilisateur et privilégiées sont séparées'
);
select extensions.ok(
  not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and (qual ilike '%document-operation-backups%'
        or with_check ilike '%document-operation-backups%')
  ),
  'aucune politique Storage directe n’expose le bucket de récupération'
);
select extensions.is(
  (select guard_enabled from public.document_storage_guard_runtime_config where singleton),
  false,'la garde Storage reste désactivée'
);
select extensions.is(
  (select lifecycle_enabled from public.protected_person_archive_runtime_config where singleton),
  false,'le cycle d’archivage reste désactivé'
);

-- Instrumentation locale, annulée en fin de test. Elle ne change pas les
-- privilèges livrés par la migration.
grant select on public.document_operation_backups to authenticated, service_role;
create policy document_operation_backups_test_select
on public.document_operation_backups for select
to authenticated, service_role using (true);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','99900000-0000-4000-8000-000000000001',
 'authenticated','authenticated','backup-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99900000-0000-4000-8000-000000000002',
 'authenticated','authenticated','backup-other@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in ('99900000-0000-4000-8000-000000000001','99900000-0000-4000-8000-000000000002');
update public.application_user_authorizations set account_mode='autonomous'
where user_id='99900000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id,status,started_at)
values('99900000-0000-4000-8000-000000000001','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99900000-0000-4000-8100-000000000001','99900000-0000-4000-8000-000000000001','Sauvegarde','Durable');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99900000-0000-4000-8900-000000000001','99900000-0000-4000-8100-000000000001',
 '99900000-0000-4000-8000-000000000002','manager','99900000-0000-4000-8000-000000000001');

insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99900000-0000-4000-8800-000000000001','transaction-proofs',
 'protected-persons/99900000-0000-4000-8100-000000000001/transactions/99900000-0000-4000-8300-000000000001/proof',
 '99900000-0000-4000-8000-000000000001','99900000-0000-4000-8000-000000000001',
 '{"size":12,"mimetype":"application/pdf"}','original-v1');

insert into public.document_operations(
 id,protected_person_id,initiated_by,initiator_subject_id,workflow,business_entity_type,
 business_entity_id,client_request_id,state,target_signature,row_revision
) values
('99900000-0000-4000-8400-000000000001','99900000-0000-4000-8100-000000000001',
 '99900000-0000-4000-8000-000000000001','99900000-0000-4000-8000-000000000001',
 'transaction_proof_replace','transaction','99900000-0000-4000-8300-000000000001',
 '99900000-0000-4000-8500-000000000001','reserved','[]',0),
('99900000-0000-4000-8400-000000000002','99900000-0000-4000-8100-000000000001',
 '99900000-0000-4000-8000-000000000002','99900000-0000-4000-8000-000000000002',
 'transaction_proof_replace','transaction','99900000-0000-4000-8300-000000000002',
 '99900000-0000-4000-8500-000000000002','reserved','[]',0);
insert into public.document_operation_targets(
 id,operation_id,ordinal,bucket_id,object_path,target_role,forward_action,
 compensation_action,expected_exists,expected_object_id,expected_object_version,
 expected_snapshot_captured_at
) values
('99900000-0000-4000-8600-000000000001','99900000-0000-4000-8400-000000000001',1,
 'transaction-proofs','protected-persons/99900000-0000-4000-8100-000000000001/transactions/99900000-0000-4000-8300-000000000001/proof',
 'primary','update','update',true,'99900000-0000-4000-8800-000000000001','original-v1',now()),
('99900000-0000-4000-8600-000000000002','99900000-0000-4000-8400-000000000002',1,
 'transaction-proofs','protected-persons/99900000-0000-4000-8100-000000000001/transactions/99900000-0000-4000-8300-000000000001/proof',
 'primary','update','update',true,'99900000-0000-4000-8800-000000000001','original-v1',now());
insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id) values
('transaction-proofs','protected-persons/99900000-0000-4000-8100-000000000001/transactions/99900000-0000-4000-8300-000000000001/proof',
 '99900000-0000-4000-8600-000000000001','99900000-0000-4000-8400-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001',
    12,'application/pdf',repeat('a',64))->>'state'),
  'upload_pending','une sauvegarde exacte est réservée'
);
select extensions.is(
  (select recovery_object_path from public.document_operation_backups
   where operation_id='99900000-0000-4000-8400-000000000001'),
  'operations/99900000-0000-4000-8400-000000000001/targets/99900000-0000-4000-8600-000000000001/backup',
  'le chemin est dérivé exclusivement de l’opération et de la cible'
);
select extensions.is(
  (select count(*) from public.document_operation_backups),1::bigint,
  'une double réservation identique est idempotente'
) from public.reserve_document_operation_backup(
  '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001',
  12,'application/pdf',repeat('a',64));
select extensions.throws_ok(
  $$select public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001',
    12,'application/pdf',repeat('b',64))$$,
  'P4B05','Une sauvegarde incompatible existe déjà.',
  'une empreinte concurrente incompatible est refusée'
);
select extensions.throws_ok(
  $$select public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000002',
    12,'application/pdf',repeat('a',64))$$,
  'P4B03','Cible de sauvegarde invalide.',
  'une cible d’une autre opération ne peut pas être associée'
);

select extensions.throws_ok(
  format($sql$select public.confirm_document_operation_backup(%L,%L,0)$sql$,
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001'),
  'P4B04','L’objet de récupération est absent.',
  'la confirmation refuse un objet absent'
);
reset role;

insert into storage.objects(id,bucket_id,name,metadata,version) values
('99900000-0000-4000-8800-000000000002','document-operation-backups',
 'operations/99900000-0000-4000-8400-000000000001/targets/99900000-0000-4000-8600-000000000001/backup',
 '{"size":12,"mimetype":"application/pdf"}','backup-v1');

set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  (public.confirm_document_operation_backup(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001',0)->>'state'),
  'verified','la présence Storage permet de confirmer la sauvegarde vérifiée'
);
select extensions.is(
  (public.get_document_operation_backup(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001')->>'sha256'),
  repeat('a',64),'la reprise retrouve les métadonnées après interruption'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.is(
  (public.get_document_operation_backup_storage_descriptor(
    (select id from public.document_operation_backups
     where operation_id='99900000-0000-4000-8400-000000000001'))->>'bucketId'),
  'document-operation-backups','le serveur privilégié reçoit le seul bucket de récupération'
);
select extensions.throws_ok(
  format($sql$select public.authorize_document_operation_backup_cleanup(%L,1)$sql$,
    (select id from public.document_operation_backups
     where operation_id='99900000-0000-4000-8400-000000000001')),
  'P4B06','La sauvegarde ne peut pas être supprimée.',
  'une opération non terminale interdit le nettoyage'
);
reset role;

-- La restauration est enregistrée uniquement pendant la compensation.
update public.document_operations set state='compensating'
where id='99900000-0000-4000-8400-000000000001';
update public.document_operation_targets set application_state='compensating',
  applied_at=now(),compensation_started_at=now()
where id='99900000-0000-4000-8600-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  (public.mark_document_operation_backup_restored(
    '99900000-0000-4000-8400-000000000001','99900000-0000-4000-8600-000000000001',1)->>'state'),
  'restored','une restauration contrôlée est tracée'
);
reset role;

update public.document_operation_targets set application_state='compensated',
  compensated_at=now()
where id='99900000-0000-4000-8600-000000000001';
update public.document_operations set state='compensated',closed_at=now()
where id='99900000-0000-4000-8400-000000000001';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.is(
  (public.authorize_document_operation_backup_cleanup(
    (select id from public.document_operation_backups
     where operation_id='99900000-0000-4000-8400-000000000001'),2)->>'state'),
  'restored','une opération terminale autorise le nettoyage contrôlé'
);
reset role;
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where bucket_id='document-operation-backups';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.complete_document_operation_backup_cleanup(
  (select id from public.document_operation_backups
   where operation_id='99900000-0000-4000-8400-000000000001'),2);
select extensions.is(
  (select state from public.document_operation_backups
   where operation_id='99900000-0000-4000-8400-000000000001'),
  'deleted','la purge physique vérifiée clôt le registre sans effacer sa trace'
);
reset role;

-- Une version initiale modifiée est détectée avant toute nouvelle sauvegarde.
delete from public.document_object_locks where operation_id='99900000-0000-4000-8400-000000000001';
insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id) values
('transaction-proofs','protected-persons/99900000-0000-4000-8100-000000000001/transactions/99900000-0000-4000-8300-000000000001/proof',
 '99900000-0000-4000-8600-000000000002','99900000-0000-4000-8400-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000002','99900000-0000-4000-8600-000000000002',
    12,'application/pdf',repeat('c',64))$$,
  'P4O01','Accès à la sauvegarde documentaire refusé.',
  'un autre gestionnaire ne peut pas reprendre l’opération d’un initiateur'
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(
  (public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000002','99900000-0000-4000-8600-000000000002',
    12,'application/pdf',repeat('c',64))->>'state'),
  'upload_pending','le gestionnaire autorisé peut réserver la cible exacte'
);
reset role;
update storage.objects set version='original-v2'
where id='99900000-0000-4000-8800-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000002','99900000-0000-4000-8600-000000000002',
    12,'application/pdf',repeat('c',64))$$,
  'P4S04','L’objet Storage a changé depuis la réservation.',
  'une version initiale modifiée est refusée'
);
reset role;
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id='99900000-0000-4000-8800-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','99900000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99900000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.reserve_document_operation_backup(
    '99900000-0000-4000-8400-000000000002','99900000-0000-4000-8600-000000000002',
    12,'application/pdf',repeat('c',64))$$,
  'P4S04','L’objet Storage a changé depuis la réservation.',
  'un objet original absent est refusé'
);
reset role;

-- La disparition du compte initiateur conserve la trace et la rend réconciliable.
update public.document_operations set initiated_by=null
where id='99900000-0000-4000-8400-000000000002';
delete from public.protected_person_access
where user_id='99900000-0000-4000-8000-000000000002';
delete from auth.users where id='99900000-0000-4000-8000-000000000002';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select extensions.ok(
  exists(select 1 from public.list_document_operation_backups_requiring_reconciliation()
    where initiator_missing),
  'la réconciliation signale un initiateur supprimé sans exposer de chemin'
);
select extensions.ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='document_operation_backups'
      and column_name in ('content','bytes','token','secret')
  ),
  'le registre ne contient ni octets, ni jeton, ni secret'
);

select * from extensions.finish();
rollback;
