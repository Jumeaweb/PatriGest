begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(38);

select extensions.has_function(
  'public', 'cancel_property_event', array['uuid','uuid','uuid','bigint','text'],
  'la RPC d’annulation logique existe'
);
select extensions.ok(
  (select procedure.prosecdef from pg_proc procedure where procedure.oid = 'public.cancel_property_event(uuid,uuid,uuid,bigint,text)'::regprocedure),
  'la RPC garantit l’atomicité dans un contexte privilégié contrôlé'
);
select extensions.ok(has_function_privilege('authenticated', 'public.cancel_property_event(uuid,uuid,uuid,bigint,text)', 'EXECUTE'), 'authenticated peut appeler la RPC');
select extensions.ok(not has_function_privilege('anon', 'public.cancel_property_event(uuid,uuid,uuid,bigint,text)', 'EXECUTE'), 'anon ne peut pas appeler la RPC');
select extensions.ok(
  not has_function_privilege('authenticated', 'public.correct_property_event_before_cancellation(uuid,uuid,uuid,bigint,text,date,text,numeric,text,text)', 'EXECUTE'),
  'le helper de compatibilité n’est pas directement exécutable par l’application'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.correct_property_event_before_cancellation(uuid,uuid,uuid,bigint,text,date,text,numeric,text,text)', 'EXECUTE'),
  'le helper de compatibilité reste inaccessible aux anonymes'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','86000000-0000-4000-8000-000000000001','authenticated','authenticated','cancel-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','86000000-0000-4000-8000-000000000002','authenticated','authenticated','cancel-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','86000000-0000-4000-8000-000000000003','authenticated','authenticated','cancel-reader@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','86000000-0000-4000-8000-000000000004','authenticated','authenticated','cancel-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active', status_changed_at=now()
where user_id::text like '86000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Olivia',last_name='Propriétaire' where id='86000000-0000-4000-8000-000000000001';
update public.profiles set first_name='Marc',last_name='Gestionnaire' where id='86000000-0000-4000-8000-000000000002';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
  ('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000001','Dossier','Principal'),
  ('86000000-0000-4000-8000-000000000102','86000000-0000-4000-8000-000000000004','Dossier','Étranger');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
  ('86000000-0000-4000-8000-000000000201','86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000002','manager','86000000-0000-4000-8000-000000000001'),
  ('86000000-0000-4000-8000-000000000202','86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000003','read_only','86000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties(id,protected_person_id,property_type,designation,entry_date,entry_mode,status) values
  ('86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000101','house','Vente à annuler','2024-01-01','acquisition','active'),
  ('86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000101','land','Changement propriétaire','2024-01-01','other','active'),
  ('86000000-0000-4000-8000-000000000303','86000000-0000-4000-8000-000000000101','house','Changement gestionnaire','2024-01-01','other','active'),
  ('86000000-0000-4000-8000-000000000304','86000000-0000-4000-8000-000000000101','apartment','Entrée protégée','2024-02-01','donation','active'),
  ('86000000-0000-4000-8000-000000000305','86000000-0000-4000-8000-000000000101','commercial','Exercice clos','2024-01-01','other','active'),
  ('86000000-0000-4000-8000-000000000306','86000000-0000-4000-8000-000000000102','house','Bien étranger','2024-01-01','other','active');

insert into public.property_events(id,property_id,protected_person_id,event_type,event_date,description,amount) values
  ('86000000-0000-4000-8000-000000000501','86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000101','sale','2026-04-10','Vente erronée',200000),
  ('86000000-0000-4000-8000-000000000502','86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000101','significant_change','2026-03-01','Travaux erronés',5000),
  ('86000000-0000-4000-8000-000000000503','86000000-0000-4000-8000-000000000303','86000000-0000-4000-8000-000000000101','significant_change','2026-03-02','Expertise erronée',8000),
  ('86000000-0000-4000-8000-000000000504','86000000-0000-4000-8000-000000000304','86000000-0000-4000-8000-000000000101','donation','2024-02-01','Donation initiale',100000),
  ('86000000-0000-4000-8000-000000000505','86000000-0000-4000-8000-000000000305','86000000-0000-4000-8000-000000000101','significant_change','2025-06-01','Événement clos',1000),
  ('86000000-0000-4000-8000-000000000506','86000000-0000-4000-8000-000000000306','86000000-0000-4000-8000-000000000102','significant_change','2026-02-01','Événement étranger',1000);

insert into public.management_periods(id,protected_person_id,start_date,end_date,status,closed_at) values
  ('86000000-0000-4000-8000-000000000601','86000000-0000-4000-8000-000000000101','2025-01-01','2025-12-31','closed',now()),
  ('86000000-0000-4000-8000-000000000602','86000000-0000-4000-8000-000000000101','2026-01-01','2026-12-31','open',null);
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by)
values('86000000-0000-4000-8000-000000000701','86000000-0000-4000-8000-000000000101',2026,'2026-01-01','2026-12-31','generated',now(),'86000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.lives_ok(
  $$select public.correct_property_sale_price('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000501',200000,205000,'Prix rectifié avant annulation')$$,
  'une correction de prix peut précéder l’annulation'
);
select extensions.is(public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000501',2,'Vente enregistrée par erreur'),3::bigint,'le propriétaire annule la vente à la révision attendue');
select extensions.ok((select cancelled_at is not null from public.property_events where id='86000000-0000-4000-8000-000000000501'),'la vente porte une date d’annulation');
select extensions.is((select cancelled_by from public.property_events where id='86000000-0000-4000-8000-000000000501'),'86000000-0000-4000-8000-000000000001'::uuid,'l’auteur authentifié est conservé');
select extensions.is((select cancellation_reason from public.property_events where id='86000000-0000-4000-8000-000000000501'),'Vente enregistrée par erreur','le motif est conservé');
select extensions.is((select status from public.real_estate_properties where id='86000000-0000-4000-8000-000000000301'),'active','le bien redevient actif');
select extensions.ok((select disposal_date is null from public.real_estate_properties where id='86000000-0000-4000-8000-000000000301'),'la date de cession active est supprimée');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id='86000000-0000-4000-8000-000000000501'),1::bigint,'la correction de prix historique est conservée');
select extensions.is((select change_type from public.property_event_changes where property_event_id='86000000-0000-4000-8000-000000000501'),'cancellation','l’audit qualifie l’annulation');
select extensions.is((select old_values->>'property_status' from public.property_event_changes where property_event_id='86000000-0000-4000-8000-000000000501'),'disposed','l’audit conserve l’ancien statut');
select extensions.is((select new_values->>'property_status' from public.property_event_changes where property_event_id='86000000-0000-4000-8000-000000000501'),'active','l’audit conserve le nouveau statut');
select extensions.ok((select refresh_required_at is not null from public.management_reports where id='86000000-0000-4000-8000-000000000701'),'le compte généré est signalé à actualiser');
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000501',3,'Deuxième annulation')$$,
  '23514','Cet événement est déjà annulé.','une seconde annulation est refusée'
);
select extensions.throws_ok(
  $$update public.property_events set description='Altération' where id='86000000-0000-4000-8000-000000000501'$$,
  '42501','La correction d’un événement immobilier doit utiliser le parcours dédié.','un événement annulé est immuable par les droits applicatifs'
);
select extensions.lives_ok(
  $$insert into public.property_events(property_id,protected_person_id,event_type,event_date,description,amount) values('86000000-0000-4000-8000-000000000301','86000000-0000-4000-8000-000000000101','sale','2026-05-01','Nouvelle vente distincte',210000)$$,
  'une nouvelle vente distincte peut être créée'
);
select extensions.is((select count(*) from public.property_events where property_id='86000000-0000-4000-8000-000000000301' and event_type='sale'),2::bigint,'la vente annulée reste dans l’historique avec la nouvelle vente');
select extensions.is((select count(*) from public.property_events where property_id='86000000-0000-4000-8000-000000000301' and event_type='sale' and cancelled_at is null),1::bigint,'une seule vente reste active');
select extensions.lives_ok(
  $$select public.correct_property_sale_price(
    '86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000301',
    (select id from public.property_events where property_id='86000000-0000-4000-8000-000000000301' and event_type='sale' and cancelled_at is null),
    210000,215000,'Correction de la nouvelle vente'
  )$$,
  'la nouvelle vente conserve le parcours de correction de prix'
);
select extensions.is(
  public.correct_property_event(
    '86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000301',
    (select id from public.property_events where property_id='86000000-0000-4000-8000-000000000301' and event_type='sale' and cancelled_at is null),
    2,'sale','2026-05-02','Nouvelle vente datée correctement',215000,null,'Date de la nouvelle vente rectifiée'
  ),3::bigint,'la nouvelle vente conserve le parcours de correction d’événement'
);
select extensions.is((select disposal_date from public.real_estate_properties where id='86000000-0000-4000-8000-000000000301'),'2026-05-02'::date,'la nouvelle date de cession reste synchronisée');

select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000502',1,'   ')$$,
  '23514','Le motif de l’annulation est obligatoire.','un motif vide est refusé'
);
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000502',2,'Révision périmée')$$,
  '40001','L’événement a été modifié par une autre opération.','une révision périmée est refusée'
);
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000304','86000000-0000-4000-8000-000000000504',1,'Annuler l’entrée')$$,
  '23514','L’annulation d’un événement d’entrée nécessite de définir une origine patrimoniale de remplacement.','un événement d’entrée sans remplacement est refusé'
);
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000305','86000000-0000-4000-8000-000000000505',1,'Annulation clôturée')$$,
  'P0001','Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.','un exercice clôturé reste protégé'
);
select extensions.is((select count(*) from public.property_event_changes where property_event_id='86000000-0000-4000-8000-000000000505'),0::bigint,'un refus ne laisse aucune trace partielle');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000502',1,'Lecteur')$$,
  '42501','Droits insuffisants.','un lecteur ne peut pas annuler'
);
select extensions.is((select count(*) from public.property_event_changes),2::bigint,'le lecteur consulte les traces autorisées');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000303','86000000-0000-4000-8000-000000000503',1,'Expertise sans objet'),2::bigint,'un gestionnaire annule un changement significatif');
select extensions.is((select changed_by from public.property_event_changes where property_event_id='86000000-0000-4000-8000-000000000503'),'86000000-0000-4000-8000-000000000002'::uuid,'le gestionnaire est l’auteur de la trace');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"86000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.cancel_property_event('86000000-0000-4000-8000-000000000101','86000000-0000-4000-8000-000000000302','86000000-0000-4000-8000-000000000502',1,'Dossier étranger')$$,
  '42501','Droits insuffisants.','un utilisateur étranger ne peut pas annuler'
);
select extensions.is((select count(*) from public.property_event_changes),0::bigint,'RLS masque les traces du dossier étranger');
select extensions.is((select count(*) from public.transactions),0::bigint,'aucune opération bancaire n’est créée');

select * from extensions.finish();
rollback;
