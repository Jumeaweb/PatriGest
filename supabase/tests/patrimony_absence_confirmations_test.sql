begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(87);

select extensions.has_table('public', 'patrimony_absence_confirmations', 'la table des confirmations d’absence existe');
select extensions.has_column('public', 'patrimony_absence_confirmations', 'protected_person_id', 'le dossier est conservé');
select extensions.has_column('public', 'patrimony_absence_confirmations', 'category', 'la catégorie est conservée');
select extensions.has_column('public', 'patrimony_absence_confirmations', 'confirmed_at', 'la date est conservée');
select extensions.has_column('public', 'patrimony_absence_confirmations', 'confirmed_by', 'l’auteur est conservé');
select extensions.has_column('public', 'patrimony_absence_confirmations', 'confirmed_by_name', 'le nom de l’auteur est conservé');
select extensions.has_pk('public', 'patrimony_absence_confirmations', 'une confirmation est unique par dossier et catégorie');
select extensions.has_function(
  'public', 'set_patrimony_absence_confirmation', array['uuid','text','boolean'],
  'la RPC de confirmation et de retrait existe'
);
select extensions.ok(
  not (select procedure.prosecdef from pg_proc procedure where procedure.oid = 'public.set_patrimony_absence_confirmation(uuid,text,boolean)'::regprocedure),
  'la RPC est SECURITY INVOKER'
);
select extensions.ok(has_function_privilege('authenticated', 'public.set_patrimony_absence_confirmation(uuid,text,boolean)', 'EXECUTE'), 'authenticated peut appeler la RPC');
select extensions.ok(not has_function_privilege('anon', 'public.set_patrimony_absence_confirmation(uuid,text,boolean)', 'EXECUTE'), 'anon ne peut pas appeler la RPC');
select extensions.ok((select class.relrowsecurity from pg_class class where class.oid = 'public.patrimony_absence_confirmations'::regclass), 'RLS est activée');
select extensions.ok(has_table_privilege('authenticated', 'public.patrimony_absence_confirmations', 'SELECT'), 'authenticated peut lire les confirmations autorisées');
select extensions.ok(has_column_privilege('authenticated', 'public.patrimony_absence_confirmations', 'protected_person_id', 'INSERT'), 'authenticated peut fournir le dossier');
select extensions.ok(has_column_privilege('authenticated', 'public.patrimony_absence_confirmations', 'category', 'INSERT'), 'authenticated peut fournir la catégorie');
select extensions.ok(not has_column_privilege('authenticated', 'public.patrimony_absence_confirmations', 'confirmed_at', 'INSERT'), 'le client ne peut pas fournir la date');
select extensions.ok(not has_column_privilege('authenticated', 'public.patrimony_absence_confirmations', 'confirmed_by', 'INSERT'), 'le client ne peut pas fournir l’auteur');
select extensions.ok(not has_column_privilege('authenticated', 'public.patrimony_absence_confirmations', 'confirmed_by_name', 'INSERT'), 'le client ne peut pas fournir le nom de l’auteur');
select extensions.ok(not has_table_privilege('authenticated', 'public.patrimony_absence_confirmations', 'UPDATE'), 'authenticated ne peut pas modifier une confirmation');
select extensions.ok(not has_table_privilege('anon', 'public.patrimony_absence_confirmations', 'SELECT'), 'anon ne peut pas lire les confirmations');
select extensions.has_trigger('public', 'real_estate_properties', 'real_estate_properties_invalidate_absence_confirmation', 'les biens invalident leur confirmation');
select extensions.has_trigger('public', 'debts', 'debts_invalidate_absence_confirmation', 'les dettes invalident leur confirmation');
select extensions.ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.validate_patrimony_absence_confirmation()'::regprocedure)) > 0, 'la validation prend un verrou transactionnel');
select extensions.ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.invalidate_patrimony_absence_confirmation()'::regprocedure)) > 0, 'l’invalidation prend le même type de verrou');
select extensions.ok(position('pg_advisory_xact_lock' in pg_get_functiondef('public.set_patrimony_absence_confirmation(uuid,text,boolean)'::regprocedure)) > 0, 'la RPC sérialise aussi les opérations concurrentes');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','88000000-0000-4000-8000-000000000001','authenticated','authenticated','absence-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','88000000-0000-4000-8000-000000000002','authenticated','authenticated','absence-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','88000000-0000-4000-8000-000000000003','authenticated','authenticated','absence-reader@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','88000000-0000-4000-8000-000000000004','authenticated','authenticated','absence-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active', status_changed_at=now()
where user_id::text like '88000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Olivia', last_name='Propriétaire' where id='88000000-0000-4000-8000-000000000001';
update public.profiles set first_name='Marc', last_name='Gestionnaire' where id='88000000-0000-4000-8000-000000000002';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
  ('88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000001','Dossier','Principal'),
  ('88000000-0000-4000-8000-000000000102','88000000-0000-4000-8000-000000000004','Dossier','Étranger'),
  ('88000000-0000-4000-8000-000000000103','88000000-0000-4000-8000-000000000001','Dossier','À supprimer');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
  ('88000000-0000-4000-8000-000000000201','88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000002','manager','88000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000202','88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000003','read_only','88000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"88000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'le propriétaire confirme l’absence de bien');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),1::bigint,'la confirmation immobilière est enregistrée');
select extensions.is((select confirmed_by from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),'88000000-0000-4000-8000-000000000001'::uuid,'l’auteur authentifié est imposé');
select extensions.is((select confirmed_by_name from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),'Olivia Propriétaire','le nom de l’auteur vient du profil');
select extensions.ok((select confirmed_at between transaction_timestamp() and clock_timestamp() from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),'la date est déterminée par PostgreSQL');
select extensions.ok(not public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'une confirmation déjà présente reste inchangée');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','active_debt',true), 'l’absence de dette est confirmée indépendamment');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101'),2::bigint,'les deux catégories coexistent');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',false), 'le retrait volontaire est accepté');
select extensions.is((select string_agg(category,',' order by category) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101'),'active_debt','le retrait immobilier ne touche pas la dette');
select extensions.ok(not public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',false), 'retirer une confirmation absente est sans effet');
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','bank_account',true)$$,
  '23514','La catégorie de confirmation est invalide.','une catégorie inconnue est refusée'
);
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',null)$$,
  '23514','L’état de confirmation est obligatoire.','un état nul est refusé'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"88000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.lives_ok(
  $$insert into public.patrimony_absence_confirmations(protected_person_id,category) values('88000000-0000-4000-8000-000000000101','real_estate')$$,
  'un gestionnaire peut confirmer directement sous le contrôle de PostgreSQL'
);
select extensions.is((select confirmed_by from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),'88000000-0000-4000-8000-000000000002'::uuid,'l’écriture directe ne choisit pas l’auteur');
select extensions.is((select confirmed_by_name from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),'Marc Gestionnaire','l’écriture directe ne choisit pas le nom');
select extensions.throws_ok(
  $$update public.patrimony_absence_confirmations set confirmed_at=now() where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'$$,
  '42501','permission denied for table patrimony_absence_confirmations','une confirmation ne peut pas être modifiée'
);
select extensions.lives_ok(
  $$delete from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'$$,
  'un gestionnaire peut retirer directement la confirmation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"88000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true)$$,
  '42501','Droits insuffisants.','un lecteur ne peut pas confirmer'
);
select extensions.throws_ok(
  $$insert into public.patrimony_absence_confirmations(protected_person_id,category) values('88000000-0000-4000-8000-000000000101','real_estate')$$,
  '42501','Droits insuffisants.','le trigger refuse aussi l’écriture directe du lecteur'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations),1::bigint,'le lecteur voit la confirmation de dette du dossier autorisé');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"88000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true)$$,
  '42501','Droits insuffisants.','un utilisateur étranger ne peut pas confirmer'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations),0::bigint,'RLS masque les confirmations du dossier étranger');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"88000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'une absence immobilière est confirmée avant création');
select extensions.lives_ok(
  $$insert into public.real_estate_properties(id,protected_person_id,property_type,designation,entry_date,entry_mode,status) values('88000000-0000-4000-8000-000000000301','88000000-0000-4000-8000-000000000101','house','Bien actif','2025-01-01','acquisition','active')$$,
  'un bien actif peut être créé sans régression'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'la création active invalide la confirmation immobilière');
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true)$$,
  '23514','L’absence de bien immobilier ne peut pas être confirmée tant qu’un bien actif existe.','un bien actif interdit la confirmation'
);
select extensions.lives_ok(
  $$insert into public.property_events(id,property_id,protected_person_id,event_type,event_date,description,amount) values('88000000-0000-4000-8000-000000000501','88000000-0000-4000-8000-000000000301','88000000-0000-4000-8000-000000000101','sale','2026-01-15','Vente du bien',150000)$$,
  'la vente immobilière reste compatible avec les triggers existants'
);
select extensions.is((select status from public.real_estate_properties where id='88000000-0000-4000-8000-000000000301'),'disposed','la vente synchronise toujours le statut');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'la vente du dernier bien ne crée aucune confirmation');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'l’absence peut être confirmée après la vente');
select extensions.lives_ok(
  $$insert into public.real_estate_properties(id,protected_person_id,property_type,designation,entry_date,entry_mode,status) values('88000000-0000-4000-8000-000000000302','88000000-0000-4000-8000-000000000101','apartment','Bien à archiver','2025-02-01','donation','active')$$,
  'un second bien actif peut être créé'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'la nouvelle création invalide la confirmation');
select extensions.is(public.archive_real_estate_property('88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000302',1,'Archivage de test'),2::bigint,'un bien actif peut toujours être archivé');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'l’archivage du dernier bien actif ne crée aucune confirmation');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'l’absence peut être confirmée après archivage');
select extensions.is(public.restore_real_estate_property('88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000302',2,'Restauration de test'),3::bigint,'un bien actif peut toujours être restauré');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'la restauration active invalide la confirmation');
select extensions.is(public.archive_real_estate_property('88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000302',3,'Nouvel archivage avant annulation'),4::bigint,'le bien restauré peut être archivé de nouveau');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'le nouvel archivage ne crée pas de confirmation');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','real_estate',true), 'l’absence est confirmée avant annulation de vente');
select extensions.is(public.cancel_property_event('88000000-0000-4000-8000-000000000101','88000000-0000-4000-8000-000000000301','88000000-0000-4000-8000-000000000501',1,'Vente saisie par erreur'),2::bigint,'l’annulation de vente reste fonctionnelle');
select extensions.is((select status from public.real_estate_properties where id='88000000-0000-4000-8000-000000000301'),'active','l’annulation réactive le bien');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='real_estate'),0::bigint,'l’annulation de vente invalide la confirmation');

select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','active_debt',false), 'la confirmation de dette initiale est retirée');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','active_debt',true), 'l’absence de dette est confirmée avant création');
select extensions.lives_ok(
  $$insert into public.debts(id,protected_person_id,creditor,debt_type,designation,status) values('88000000-0000-4000-8000-000000000401','88000000-0000-4000-8000-000000000101','Banque test','bank_loan','Dette active','active')$$,
  'une dette active peut être créée sans régression'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='active_debt'),0::bigint,'la création d’une dette active invalide la confirmation');
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','active_debt',true)$$,
  '23514','L’absence de dette ne peut pas être confirmée tant qu’une dette active existe.','une dette active interdit la confirmation'
);
select extensions.lives_ok(
  $$update public.debts set status='settled',settled_at='2026-02-01' where id='88000000-0000-4000-8000-000000000401'$$,
  'une dette peut toujours être soldée'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='active_debt'),0::bigint,'le règlement de la dernière dette ne crée aucune confirmation');
select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000101','active_debt',true), 'l’absence de dette peut être confirmée après règlement');
select extensions.lives_ok(
  $$update public.debts set status='active',settled_at=null where id='88000000-0000-4000-8000-000000000401'$$,
  'une dette soldée peut être réactivée'
);
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000101' and category='active_debt'),0::bigint,'la réactivation invalide la confirmation de dette');

select extensions.ok(public.set_patrimony_absence_confirmation('88000000-0000-4000-8000-000000000103','real_estate',true), 'un dossier vide peut porter une confirmation');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000103'),1::bigint,'la confirmation du dossier vide existe avant suppression');
select extensions.lives_ok(
  $$select public.delete_empty_protected_person('88000000-0000-4000-8000-000000000103')$$,
  'la confirmation ne bloque pas la suppression autorisée du dossier'
);
select extensions.is((select count(*) from public.protected_persons where id='88000000-0000-4000-8000-000000000103'),0::bigint,'le dossier vide est supprimé');
select extensions.is((select count(*) from public.patrimony_absence_confirmations where protected_person_id='88000000-0000-4000-8000-000000000103'),0::bigint,'la confirmation est supprimée en cascade');
select extensions.is((select count(*) from public.transactions),0::bigint,'les confirmations ne créent aucune opération bancaire');
select extensions.is((select count(*) from public.property_events where id='88000000-0000-4000-8000-000000000501' and cancelled_at is not null),1::bigint,'l’historique immobilier demeure cohérent');
select extensions.is((select status from public.debts where id='88000000-0000-4000-8000-000000000401'),'active','la dette réactivée demeure cohérente');

select * from extensions.finish();
rollback;
