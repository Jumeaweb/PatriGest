begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(50);

select extensions.has_column('public','real_estate_properties','archive_revision','la révision d’archivage existe');
select extensions.has_column('public','real_estate_properties','archived_at','la date d’archivage existe');
select extensions.has_column('public','real_estate_properties','archived_by','l’auteur courant existe');
select extensions.has_column('public','real_estate_properties','archive_reason','le motif courant existe');
select extensions.has_table('public','property_archive_changes','le journal d’archivage existe');
select extensions.has_function('public','archive_real_estate_property',array['uuid','uuid','bigint','text'],'la RPC d’archivage existe');
select extensions.has_function('public','restore_real_estate_property',array['uuid','uuid','bigint','text'],'la RPC de restauration existe');
select extensions.ok((select prosecdef from pg_proc where oid='public.archive_real_estate_property(uuid,uuid,bigint,text)'::regprocedure),'l’archivage est transactionnel et privilégié');
select extensions.ok((select prosecdef from pg_proc where oid='public.restore_real_estate_property(uuid,uuid,bigint,text)'::regprocedure),'la restauration est transactionnelle et privilégiée');
select extensions.ok(has_function_privilege('authenticated','public.archive_real_estate_property(uuid,uuid,bigint,text)','EXECUTE'),'authenticated peut appeler l’archivage contrôlé');
select extensions.ok(not has_function_privilege('anon','public.archive_real_estate_property(uuid,uuid,bigint,text)','EXECUTE'),'anon ne peut pas archiver');
select extensions.has_trigger('public','property_archive_changes','property_archive_changes_immutable','le journal est append-only');
select extensions.has_trigger('public','real_estate_properties','real_estate_properties_protect_archive_state','l’état d’archive est protégé');
select extensions.has_trigger('public','property_events','property_events_protect_archived_property','les événements des biens archivés sont gelés');

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','87000000-0000-4000-8000-000000000001','authenticated','authenticated','archive-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','87000000-0000-4000-8000-000000000002','authenticated','authenticated','archive-manager@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','87000000-0000-4000-8000-000000000003','authenticated','authenticated','archive-reader@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','87000000-0000-4000-8000-000000000004','authenticated','authenticated','archive-outsider@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now() where user_id::text like '87000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Alice',last_name='Propriétaire' where id='87000000-0000-4000-8000-000000000001';
update public.profiles set first_name='Marc',last_name='Gestionnaire' where id='87000000-0000-4000-8000-000000000002';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000001','Dossier','Principal'),
('87000000-0000-4000-8000-000000000102','87000000-0000-4000-8000-000000000004','Dossier','Étranger');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('87000000-0000-4000-8000-000000000201','87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000002','manager','87000000-0000-4000-8000-000000000001'),
('87000000-0000-4000-8000-000000000202','87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000003','read_only','87000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties(id,protected_person_id,property_type,designation,entry_date,entry_mode,status,estimated_value) values
('87000000-0000-4000-8000-000000000301','87000000-0000-4000-8000-000000000101','house','Bien actif','2024-01-01','acquisition','active',150000),
('87000000-0000-4000-8000-000000000302','87000000-0000-4000-8000-000000000101','apartment','Bien à vendre','2024-01-01','acquisition','active',90000),
('87000000-0000-4000-8000-000000000303','87000000-0000-4000-8000-000000000101','land','Bien incohérent','2024-01-01','other','active',50000),
('87000000-0000-4000-8000-000000000304','87000000-0000-4000-8000-000000000102','house','Bien étranger','2024-01-01','other','active',100000),
('87000000-0000-4000-8000-000000000305','87000000-0000-4000-8000-000000000101','commercial','Bien gestionnaire','2024-01-01','other','active',80000),
('87000000-0000-4000-8000-000000000306','87000000-0000-4000-8000-000000000101','house','Historique clôturé','2024-01-01','other','active',110000);
insert into public.property_events(id,property_id,protected_person_id,event_type,event_date,description,amount) values
('87000000-0000-4000-8000-000000000501','87000000-0000-4000-8000-000000000301','87000000-0000-4000-8000-000000000101','significant_change','2026-02-01','Travaux',5000),
('87000000-0000-4000-8000-000000000502','87000000-0000-4000-8000-000000000302','87000000-0000-4000-8000-000000000101','sale','2026-03-01','Vente',120000),
('87000000-0000-4000-8000-000000000506','87000000-0000-4000-8000-000000000306','87000000-0000-4000-8000-000000000101','significant_change','2025-06-01','Travaux clôturés',3000);
update public.real_estate_properties set disposal_date='2026-01-15' where id='87000000-0000-4000-8000-000000000303';
insert into public.management_periods(id,protected_person_id,start_date,end_date,status,closed_at) values
('87000000-0000-4000-8000-000000000601','87000000-0000-4000-8000-000000000101','2025-01-01','2025-12-31','closed',now()),
('87000000-0000-4000-8000-000000000602','87000000-0000-4000-8000-000000000101','2026-01-01','2026-12-31','open',null);
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by) values
('87000000-0000-4000-8000-000000000701','87000000-0000-4000-8000-000000000101',2026,'2026-01-01','2026-12-31','generated',now(),'87000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','87000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"87000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select public.correct_property_event('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000306','87000000-0000-4000-8000-000000000506',1,'significant_change','2025-06-02','Correction',3000,null,'Correction clôturée')$$,
  'P0001','Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.','les données historiques clôturées restent protégées'
);
select extensions.lives_ok(
  $$select public.correct_property_sale_price('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000302','87000000-0000-4000-8000-000000000502',120000,125000,'Prix corrigé avant archivage')$$,
  'une correction de prix peut précéder l’archivage'
);
select extensions.is(public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000301',1,'Bien saisi en double'),2::bigint,'le propriétaire archive un bien');
select extensions.ok((select archived_at is not null from public.real_estate_properties where id='87000000-0000-4000-8000-000000000301'),'la date d’archivage est renseignée');
select extensions.is((select archived_by from public.real_estate_properties where id='87000000-0000-4000-8000-000000000301'),'87000000-0000-4000-8000-000000000001'::uuid,'l’auteur authentifié est renseigné');
select extensions.is((select status from public.real_estate_properties where id='87000000-0000-4000-8000-000000000301'),'active','l’archivage conserve le statut métier');
select extensions.is((select count(*) from public.property_events where property_id='87000000-0000-4000-8000-000000000301'),1::bigint,'les événements sont conservés');
select extensions.is((select operation from public.property_archive_changes where property_id='87000000-0000-4000-8000-000000000301'),'archive','l’archivage est audité');
select extensions.is((select changed_by_name from public.property_archive_changes where property_id='87000000-0000-4000-8000-000000000301'),'Alice Propriétaire','le nom de l’auteur vient du profil');
select extensions.ok((select refresh_required_at is not null from public.management_reports where id='87000000-0000-4000-8000-000000000701'),'le compte généré est à actualiser');
select extensions.throws_ok(
  $$update public.real_estate_properties set designation='Altération' where id='87000000-0000-4000-8000-000000000301'$$,
  '23514','Un bien archivé ne peut pas être modifié avant sa restauration.','un bien archivé est gelé'
);
select extensions.throws_ok(
  $$insert into public.property_events(property_id,protected_person_id,event_type,event_date,description) values('87000000-0000-4000-8000-000000000301','87000000-0000-4000-8000-000000000101','significant_change','2026-04-01','Interdit')$$,
  '23514','Les événements d’un bien archivé ne peuvent pas être modifiés.','aucun événement ne peut être ajouté au bien archivé'
);
select extensions.throws_ok(
  $$update public.real_estate_properties set archived_at=now(),archived_by='87000000-0000-4000-8000-000000000001',archive_reason='Direct' where id='87000000-0000-4000-8000-000000000305'$$,
  '42501','permission denied for table real_estate_properties','les colonnes d’archive ne sont pas modifiables directement'
);
select extensions.throws_ok(
  $$select public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000305',1,'   ')$$,
  '23514','Le motif de l’archivage est obligatoire.','le motif d’archivage est obligatoire'
);
select extensions.throws_ok(
  $$select public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000305',2,'Révision périmée')$$,
  '40001','Le bien immobilier a été modifié par une autre opération.','une révision périmée est refusée'
);
select extensions.is(public.restore_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000301',2,'Doublon vérifié et conservé'),3::bigint,'le propriétaire restaure un bien cohérent');
select extensions.ok((select archived_at is null from public.real_estate_properties where id='87000000-0000-4000-8000-000000000301'),'le bien restauré redevient courant');
select extensions.is((select count(*) from public.property_archive_changes where property_id='87000000-0000-4000-8000-000000000301'),2::bigint,'les deux opérations restent dans l’audit');
select extensions.is((select string_agg(operation,',' order by changed_at,id) from public.property_archive_changes where property_id='87000000-0000-4000-8000-000000000301'),'archive,restore','l’historique d’archive n’est pas effacé');
select extensions.throws_ok(
  $$select public.restore_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000301',3,'Restauration silencieuse')$$,
  '23514','Ce bien immobilier n’est pas archivé.','un bien non archivé ne peut pas être restauré'
);

select extensions.is(public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000302',1,'Cession historique à masquer des vues courantes'),2::bigint,'un bien cédé peut être archivé');
select extensions.is((select status from public.real_estate_properties where id='87000000-0000-4000-8000-000000000302'),'disposed','le statut cédé est conservé');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_id='87000000-0000-4000-8000-000000000302'),1::bigint,'les corrections de prix sont conservées');
select extensions.is(public.restore_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000302',2,'Restauration du bien cédé'),3::bigint,'un bien cédé cohérent peut être restauré');
select extensions.is((select disposal_date from public.real_estate_properties where id='87000000-0000-4000-8000-000000000302'),'2026-03-01'::date,'la date de cession est conservée');

select extensions.is(public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000303',1,'Mettre à l’écart la fiche incohérente'),2::bigint,'une fiche incohérente peut être retirée des vues courantes');
select extensions.throws_ok(
  $$select public.restore_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000303',2,'Tentative de restauration')$$,
  'P0001','Le statut actif du bien est incohérent avec son historique de cession.','la restauration incohérente est refusée'
);
select extensions.ok((select archived_at is not null from public.real_estate_properties where id='87000000-0000-4000-8000-000000000303'),'le refus est atomique et conserve l’archive');

select extensions.is(public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000306',1,'Archivage courant avec historique clôturé'),2::bigint,'un archivage préserve un historique clôturé sans le réécrire');
select extensions.is((select description from public.property_events where id='87000000-0000-4000-8000-000000000506'),'Travaux clôturés','la donnée clôturée reste inchangée');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','87000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"87000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000305',1,'Lecteur')$$,
  '42501','Droits insuffisants.','un lecteur ne peut pas archiver'
);
select extensions.is((select count(*) from public.property_archive_changes),6::bigint,'le lecteur peut consulter l’audit autorisé');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','87000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"87000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000305',1,'Archivage par le gestionnaire'),2::bigint,'un gestionnaire peut archiver');
select extensions.is((select changed_by from public.property_archive_changes where property_id='87000000-0000-4000-8000-000000000305'),'87000000-0000-4000-8000-000000000002'::uuid,'le gestionnaire est audité');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','87000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"87000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.archive_real_estate_property('87000000-0000-4000-8000-000000000101','87000000-0000-4000-8000-000000000305',2,'Dossier étranger')$$,
  '42501','Droits insuffisants.','un dossier étranger est refusé'
);
select extensions.is((select count(*) from public.property_archive_changes),0::bigint,'RLS masque l’audit étranger');

select * from extensions.finish();
rollback;
