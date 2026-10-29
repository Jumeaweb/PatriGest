begin;
\ir experimental_document_operations_enabled.inc
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public','administrative_document_physical_verification_requests','le registre privé des demandes existe');
select extensions.has_table('public','administrative_document_physical_observations','le journal append-only existe');
select extensions.has_function('public','begin_administrative_document_physical_verification',array['text','uuid'],'la session administrateur autorise un constat opaque');
select extensions.has_function('public','get_administrative_document_physical_verification_descriptor',array['uuid'],'le serveur privilégié résout le chemin après autorisation');
select extensions.has_function('public','complete_administrative_document_physical_verification',array['uuid','text','text','text','uuid','text','bigint','text','text'],'le serveur finalise une observation');
select extensions.has_function('public','get_administrative_document_physical_observations',array['text','integer','timestamp with time zone'],'l’historique paginé existe');

select extensions.ok(
  not has_table_privilege('authenticated','public.administrative_document_physical_verification_requests','SELECT')
  and not has_table_privilege('authenticated','public.administrative_document_physical_observations','SELECT')
  and not has_table_privilege('service_role','public.administrative_document_physical_verification_requests','SELECT')
  and not has_table_privilege('service_role','public.administrative_document_physical_observations','SELECT'),
  'les registres techniques ne sont jamais exposés directement'
);
select extensions.ok(
  has_function_privilege('authenticated','public.begin_administrative_document_physical_verification(text,uuid)','EXECUTE')
  and not has_function_privilege('anon','public.begin_administrative_document_physical_verification(text,uuid)','EXECUTE')
  and has_function_privilege('service_role','public.get_administrative_document_physical_verification_descriptor(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.get_administrative_document_physical_verification_descriptor(uuid)','EXECUTE'),
  'la décision métier et la résolution technique restent séparées'
);
select extensions.ok(
  not has_function_privilege('authenticated','public.resolve_administrative_document_physical_finding(text)','EXECUTE')
  and not has_function_privilege('service_role','public.resolve_administrative_document_physical_finding(text)','EXECUTE'),
  'le résolveur de chemins reste privé'
);
select extensions.ok(
  not has_function_privilege('anon','public.get_administrative_document_physical_observations(text,integer,timestamp with time zone)','EXECUTE')
  and not has_function_privilege('authenticated','public.complete_administrative_document_physical_verification(uuid,text,text,text,uuid,text,bigint,text,text)','EXECUTE')
  and not has_function_privilege('service_role','public.begin_administrative_document_physical_verification(text,uuid)','EXECUTE'),
  'aucun rôle API ne peut franchir la séparation session administrative / finalisation technique'
);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
('00000000-0000-0000-0000-000000000000','99750000-0000-4000-8000-000000000001','authenticated','authenticated','physical-admin@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99750000-0000-4000-8000-000000000002','authenticated','authenticated','physical-user@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous'
where user_id in ('99750000-0000-4000-8000-000000000001','99750000-0000-4000-8000-000000000002');
insert into public.platform_administrators(user_id) values ('99750000-0000-4000-8000-000000000001');

insert into storage.objects(id,bucket_id,name,metadata,version,owner_id)
values
('99750000-0000-4000-8100-000000000001','transaction-proofs','legacy/physical-object-one','{"size":16,"mimetype":"application/pdf"}','version-one','99750000-0000-4000-8000-000000000002'),
('99750000-0000-4000-8100-000000000002','transaction-proofs','legacy/physical-object-two','{"size":16,"mimetype":"application/pdf"}','version-one','99750000-0000-4000-8000-000000000002');

set local "request.jwt.claim.sub"='99750000-0000-4000-8000-000000000002';
set local "request.jwt.claims"='{"sub":"99750000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select extensions.throws_ok(
  $$select public.begin_administrative_document_physical_verification('transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001','99750000-0000-4000-8200-000000000001')$$,
  'P4V01','Vérification physique non autorisée.','un utilisateur non administrateur est refusé'
);
reset role;

set local "request.jwt.claim.sub"='99750000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99750000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
create temporary table physical_started as
select public.begin_administrative_document_physical_verification(
  'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
  '99750000-0000-4000-8200-000000000001') result;
grant select on physical_started to service_role;
select extensions.is((select result->>'state' from physical_started),'authorized','un constat autoritatif peut être autorisé');
select extensions.ok(
  position('legacy/' in (select result::text from physical_started))=0
  and position('bucketId' in (select result::text from physical_started))=0,
  'la réponse navigateur ne contient ni bucket ni chemin'
);
select extensions.is(
  public.begin_administrative_document_physical_verification(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
    '99750000-0000-4000-8200-000000000001')->>'verificationRequestId',
  (select result->>'verificationRequestId' from physical_started),
  'une réponse perdue reprend la même demande sans nouvelle observation'
);
select extensions.throws_ok(
  $$select public.begin_administrative_document_physical_verification('transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000002','99750000-0000-4000-8200-000000000001')$$,
  'P4V03','Identifiant de demande déjà utilisé pour une autre intention.','une clé stable ne peut pas changer d’intention'
);
select extensions.throws_ok(
  $$select public.begin_administrative_document_physical_verification('transaction_proof:unresolved_catalog_path:../../secret','99750000-0000-4000-8200-000000000009')$$,
  'P4V02','Demande de vérification invalide.','aucun chemin arbitraire ne peut être injecté'
);
reset role;

set local "request.jwt.claim.sub"='';
set local "request.jwt.claims"='{"role":"service_role"}';
set local role service_role;
create temporary table physical_descriptor as
select public.get_administrative_document_physical_verification_descriptor(
  ((select result->>'verificationRequestId' from physical_started))::uuid) result;
grant select on physical_descriptor to authenticated;
select extensions.is((select result->>'objectPath' from physical_descriptor),'legacy/physical-object-one','le serveur résout le chemin autoritatif exact');
select extensions.is(
  public.complete_administrative_document_physical_verification(
    ((select result->>'verificationRequestId' from physical_started))::uuid,
    (select result->>'serverCapability' from physical_descriptor),
    'verified_readable','physical_readability','99750000-0000-4000-8100-000000000001','version-one',16,repeat('a',64),'NO_RELIABLE_REFERENCE_HASH')->>'outcome',
  'verified_readable','le serveur enregistre une observation bornée'
);
select extensions.throws_ok(
  format($query$select public.get_administrative_document_physical_verification_descriptor(%L::uuid)$query$,
    (select result->>'verificationRequestId' from physical_started)),
  'P4V06','Vérification déjà terminée.','un descripteur terminé ne redonne jamais accès au chemin'
);
select extensions.is(
  public.complete_administrative_document_physical_verification(
    ((select result->>'verificationRequestId' from physical_started))::uuid,
    (select result->>'serverCapability' from physical_descriptor),
    'verified_readable','physical_readability','99750000-0000-4000-8100-000000000001','version-one',16,repeat('a',64),'NO_RELIABLE_REFERENCE_HASH')->>'outcome',
  'verified_readable','la finalisation répétée reste idempotente'
);
reset role;

set local "request.jwt.claim.sub"='99750000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99750000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select extensions.is(
  jsonb_array_length(public.get_administrative_document_physical_observations(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',20,null)->'items'),
  1,'une seule observation est visible après double finalisation'
);
select extensions.is(
  public.begin_administrative_document_physical_verification(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
    '99750000-0000-4000-8200-000000000001')->'observation'->>'outcome',
  'verified_readable','la reprise restitue directement l’observation exacte sans dépendre de la dernière page'
);
select extensions.ok(
  position('legacy/' in public.get_administrative_document_physical_observations(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',20,null)::text)=0
  and position(repeat('a',64) in public.get_administrative_document_physical_observations(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',20,null)::text)=0,
  'l’historique ne divulgue ni chemin ni empreinte'
);
select extensions.is(
  jsonb_array_length(public.get_administrative_document_physical_observations(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000002',1,null)->'items'),
  0,'les constats restent isolés et la pagination est bornée'
);
create temporary table stale_started as
select public.begin_administrative_document_physical_verification(
  'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000002',
  '99750000-0000-4000-8200-000000000002') result;
grant select on stale_started to service_role;
select extensions.throws_ok(
  $$select public.begin_administrative_document_physical_verification(
    'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
    '99750000-0000-4000-8200-000000000008')$$,
  'P4V09','Une autre lecture physique est déjà en cours.','une session ne peut pas ouvrir deux lectures physiques simultanées'
);
reset role;

update storage.objects set version='version-concurrente'
where id='99750000-0000-4000-8100-000000000002';
set local "request.jwt.claim.sub"='';
set local "request.jwt.claims"='{"role":"service_role"}';
set local role service_role;
create temporary table stale_descriptor as
select public.get_administrative_document_physical_verification_descriptor(
  ((select result->>'verificationRequestId' from stale_started))::uuid) result;
select extensions.is((select result->>'state' from stale_descriptor),'stale','le descripteur revérifie le constat avant toute lecture');
select extensions.is((select result->>'objectPath' from stale_descriptor),null,'un constat devenu obsolète ne divulgue plus son ancien chemin');
select extensions.is(
  public.complete_administrative_document_physical_verification(
    ((select result->>'verificationRequestId' from stale_started))::uuid,
    (select result->>'serverCapability' from stale_descriptor),
    'verified_readable','physical_readability','99750000-0000-4000-8100-000000000002','version-one',16,repeat('b',64),null)->>'outcome',
  'stale_inventory_finding','une modification concurrente requalifie le résultat en constat obsolète'
);
reset role;

set local "request.jwt.claim.sub"='99750000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99750000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
create temporary table forged_started as
select public.begin_administrative_document_physical_verification(
  'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
  '99750000-0000-4000-8200-000000000007') result;
grant select on forged_started to service_role;
reset role;
set local "request.jwt.claim.sub"='';
set local "request.jwt.claims"='{"role":"service_role"}';
set local role service_role;
create temporary table forged_descriptor as
select public.get_administrative_document_physical_verification_descriptor(
  ((select result->>'verificationRequestId' from forged_started))::uuid) result;
select extensions.throws_ok(
  format($query$select public.complete_administrative_document_physical_verification(
    %L::uuid,%L,'verified_readable','catalog_only',%L::uuid,'version-one',null,null,null)$query$,
    (select result->>'verificationRequestId' from forged_started),
    (select result->>'serverCapability' from forged_descriptor),
    '99750000-0000-4000-8100-000000000001'),
  'P4V02','Résultat de vérification incohérent.','le contexte technique ne peut pas fabriquer une preuve de lecture sans octets'
);
select extensions.throws_ok(
  format($query$select public.complete_administrative_document_physical_verification(
    %L::uuid,%L,'verification_inconclusive','inconclusive',null,null,null,null,'STORAGE_INFO_FAILED')$query$,
    (select result->>'verificationRequestId' from forged_started),repeat('0',64)),
  'P4V05','Vérification introuvable.','une capacité falsifiée est refusée'
);
select public.complete_administrative_document_physical_verification(
  ((select result->>'verificationRequestId' from forged_started))::uuid,
  (select result->>'serverCapability' from forged_descriptor),
  'verification_inconclusive','inconclusive',null,null,null,null,'STORAGE_INFO_FAILED');
reset role;

set local "request.jwt.claim.sub"='99750000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99750000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
create temporary table expired_started as
select public.begin_administrative_document_physical_verification(
  'transaction_proof:unresolved_catalog_path:99750000-0000-4000-8100-000000000001',
  '99750000-0000-4000-8200-000000000006') result;
grant select on expired_started to service_role;
reset role;
update public.administrative_document_physical_verification_requests
set issued_at=statement_timestamp()-interval '10 minutes',
    expires_at=statement_timestamp()-interval '5 minutes'
where id=((select result->>'verificationRequestId' from expired_started))::uuid;
set local "request.jwt.claim.sub"='';
set local "request.jwt.claims"='{"role":"service_role"}';
set local role service_role;
select extensions.throws_ok(
  format($query$select public.get_administrative_document_physical_verification_descriptor(%L::uuid)$query$,
    (select result->>'verificationRequestId' from expired_started)),
  'P4V07','Autorisation de vérification expirée.','une autorisation expirée ne permet aucune lecture'
);
reset role;

select extensions.throws_ok(
  $$update public.administrative_document_physical_observations set outcome='verification_inconclusive'$$,
  '42501','Les observations physiques sont immuables.','les observations ne peuvent pas être modifiées'
);
select extensions.throws_ok(
  $$delete from public.administrative_document_physical_observations$$,
  '42501','Les observations physiques sont immuables.','les observations ne peuvent pas être supprimées'
);
select extensions.is((select count(*) from storage.objects where id in (
  '99750000-0000-4000-8100-000000000001','99750000-0000-4000-8100-000000000002')),2::bigint,
  'la réconciliation ne supprime ni ne remplace aucun objet Storage');

select * from extensions.finish();
rollback;
