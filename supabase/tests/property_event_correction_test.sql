begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(48);

select extensions.has_function(
  'public', 'correct_property_event',
  array['uuid','uuid','uuid','bigint','text','date','text','numeric','text','text'],
  'la RPC de correction des événements existe'
);
select extensions.ok(
  (select procedure.prosecdef from pg_proc procedure where procedure.oid = 'public.correct_property_event(uuid,uuid,uuid,bigint,text,date,text,numeric,text,text)'::regprocedure),
  'la RPC utilise un contexte privilégié contrôlé pour garantir l’atomicité de l’audit'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.correct_property_event(uuid,uuid,uuid,bigint,text,date,text,numeric,text,text)', 'EXECUTE'),
  'un utilisateur authentifié peut appeler la RPC contrôlée'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.correct_property_event(uuid,uuid,uuid,bigint,text,date,text,numeric,text,text)', 'EXECUTE'),
  'un utilisateur anonyme ne peut pas appeler la RPC'
);
select extensions.has_column('public', 'management_reports', 'refresh_required_at', 'le signalement d’actualisation existe');
select extensions.has_trigger('public', 'management_reports', 'management_reports_protect_refresh_requirement', 'la finalisation contrôle l’actualisation requise');
select extensions.has_trigger('public', 'real_estate_properties', 'real_estate_properties_protect_entry_consistency', 'la fiche du bien reste alignée sur son événement d’entrée');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '85000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'correction-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '85000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'correction-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '85000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'correction-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '85000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'correction-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '85000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000002',
  '85000000-0000-4000-8000-000000000003',
  '85000000-0000-4000-8000-000000000004'
);
update public.profiles set first_name = 'Odile', last_name = 'Propriétaire' where id = '85000000-0000-4000-8000-000000000001';
update public.profiles set first_name = 'Marc', last_name = 'Gestionnaire' where id = '85000000-0000-4000-8000-000000000002';

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('85000000-0000-4000-8000-000000000101', '85000000-0000-4000-8000-000000000001', 'Dossier', 'Principal'),
  ('85000000-0000-4000-8000-000000000102', '85000000-0000-4000-8000-000000000004', 'Dossier', 'Étranger');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('85000000-0000-4000-8000-000000000201', '85000000-0000-4000-8000-000000000101', '85000000-0000-4000-8000-000000000002', 'manager', '85000000-0000-4000-8000-000000000001'),
  ('85000000-0000-4000-8000-000000000202', '85000000-0000-4000-8000-000000000101', '85000000-0000-4000-8000-000000000003', 'read_only', '85000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties (
  id, protected_person_id, property_type, designation, entry_date, entry_mode, status
)
values
  ('85000000-0000-4000-8000-000000000301', '85000000-0000-4000-8000-000000000101', 'house', 'Entrée cohérente', '2026-01-10', 'acquisition', 'active'),
  ('85000000-0000-4000-8000-000000000302', '85000000-0000-4000-8000-000000000101', 'land', 'Changement significatif', '2024-01-01', 'other', 'active'),
  ('85000000-0000-4000-8000-000000000303', '85000000-0000-4000-8000-000000000101', 'apartment', 'Vente à corriger', '2024-01-01', 'acquisition', 'active'),
  ('85000000-0000-4000-8000-000000000304', '85000000-0000-4000-8000-000000000101', 'commercial', 'Entrées ambiguës', '2026-01-05', 'acquisition', 'active'),
  ('85000000-0000-4000-8000-000000000305', '85000000-0000-4000-8000-000000000101', 'house', 'Événement clôturé', '2024-01-01', 'other', 'active'),
  ('85000000-0000-4000-8000-000000000306', '85000000-0000-4000-8000-000000000102', 'house', 'Bien étranger', '2024-01-01', 'other', 'active');

insert into public.property_events (
  id, property_id, protected_person_id, event_type, event_date, description, amount, document_reference
)
values
  ('85000000-0000-4000-8000-000000000501', '85000000-0000-4000-8000-000000000301', '85000000-0000-4000-8000-000000000101', 'acquisition', '2026-01-10', 'Achat initial', 120000, 'ACTE-1'),
  ('85000000-0000-4000-8000-000000000502', '85000000-0000-4000-8000-000000000302', '85000000-0000-4000-8000-000000000101', 'significant_change', '2026-03-10', 'Travaux initiaux', 5000, null),
  ('85000000-0000-4000-8000-000000000503', '85000000-0000-4000-8000-000000000303', '85000000-0000-4000-8000-000000000101', 'sale', '2026-07-01', 'Vente initiale', 200000, 'VENTE-1'),
  ('85000000-0000-4000-8000-000000000504', '85000000-0000-4000-8000-000000000304', '85000000-0000-4000-8000-000000000101', 'acquisition', '2026-01-05', 'Première entrée', 90000, null),
  ('85000000-0000-4000-8000-000000000505', '85000000-0000-4000-8000-000000000304', '85000000-0000-4000-8000-000000000101', 'donation', '2026-01-06', 'Deuxième entrée', 90000, null),
  ('85000000-0000-4000-8000-000000000506', '85000000-0000-4000-8000-000000000305', '85000000-0000-4000-8000-000000000101', 'significant_change', '2025-05-01', 'Événement passé', 1000, null),
  ('85000000-0000-4000-8000-000000000507', '85000000-0000-4000-8000-000000000306', '85000000-0000-4000-8000-000000000102', 'significant_change', '2026-02-01', 'Événement étranger', 1000, null);

insert into public.management_periods (id, protected_person_id, start_date, end_date, status, closed_at)
values
  ('85000000-0000-4000-8000-000000000601', '85000000-0000-4000-8000-000000000101', '2025-01-01', '2025-12-31', 'closed', now()),
  ('85000000-0000-4000-8000-000000000602', '85000000-0000-4000-8000-000000000101', '2026-01-01', '2026-12-31', 'open', null);

insert into public.management_reports (
  id, protected_person_id, report_year, period_start, period_end, status,
  generated_at, created_by
)
values (
  '85000000-0000-4000-8000-000000000701',
  '85000000-0000-4000-8000-000000000101',
  2026, '2026-01-01', '2026-12-31', 'generated', now(),
  '85000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select extensions.is(
  public.correct_property_event(
    '85000000-0000-4000-8000-000000000101', '85000000-0000-4000-8000-000000000301',
    '85000000-0000-4000-8000-000000000501', 1, 'inheritance', '2026-01-12',
    'Succession corrigée', 125000, 'ACTE-2', 'Qualification et date rectifiées'
  ), 2::bigint,
  'le propriétaire corrige un événement d’entrée avec sa révision attendue'
);
select extensions.is((select event_date from public.property_events where id = '85000000-0000-4000-8000-000000000501'), '2026-01-12'::date, 'la date de l’événement est corrigée');
select extensions.is((select event_type from public.property_events where id = '85000000-0000-4000-8000-000000000501'), 'inheritance', 'une transition compatible entre modes d’entrée est acceptée');
select extensions.is((select revision from public.property_events where id = '85000000-0000-4000-8000-000000000501'), 2::bigint, 'la révision est incrémentée');
select extensions.is((select entry_date from public.real_estate_properties where id = '85000000-0000-4000-8000-000000000301'), '2026-01-12'::date, 'la date d’entrée du bien est synchronisée');
select extensions.is((select entry_mode from public.real_estate_properties where id = '85000000-0000-4000-8000-000000000301'), 'inheritance', 'le mode d’entrée du bien est synchronisé');
select extensions.is((select count(*) from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), 1::bigint, 'une trace générique est créée');
select extensions.is((select reason from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), 'Qualification et date rectifiées', 'le motif est conservé');
select extensions.is((select changed_by from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), '85000000-0000-4000-8000-000000000001'::uuid, 'l’auteur vient du contexte authentifié');
select extensions.is((select old_values->>'event_date' from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), '2026-01-10', 'l’ancienne date figure dans l’audit');
select extensions.is((select new_values->>'property_entry_mode' from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), 'inheritance', 'la nouvelle donnée synchronisée figure dans l’audit');
select extensions.ok((select refresh_required_at is not null from public.management_reports where id = '85000000-0000-4000-8000-000000000701'), 'le projet de compte de gestion est signalé à actualiser');
select extensions.throws_ok(
  $$update public.real_estate_properties set entry_date = '2026-02-01' where id = '85000000-0000-4000-8000-000000000301'$$,
  'P0001', 'La date et le mode d’entrée doivent correspondre à l’événement d’entrée du bien.',
  'la fiche ne peut pas être désynchronisée directement de son événement d’entrée'
);
select extensions.lives_ok(
  $$update public.real_estate_properties set entry_date = '2024-02-01' where id = '85000000-0000-4000-8000-000000000302'$$,
  'un bien sans événement d’entrée historique reste renseignable depuis sa fiche'
);

reset role;
select extensions.throws_ok(
  $$update public.management_reports set status = 'finalized', finalized_at = now() where id = '85000000-0000-4000-8000-000000000701'$$,
  'P0001', 'Le compte de gestion doit être actualisé et son projet régénéré avant finalisation.',
  'un projet obsolète ne peut pas être finalisé'
);
update public.management_reports set status = 'draft', generated_at = null where id = '85000000-0000-4000-8000-000000000701';
select extensions.ok((select refresh_required_at is null from public.management_reports where id = '85000000-0000-4000-8000-000000000701'), 'la reprise en préparation acquitte le signalement');

set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000301','85000000-0000-4000-8000-000000000501',1,'inheritance','2026-01-13','Conflit',125000,'ACTE-2','Ancienne révision')$$,
  '40001', 'L’événement a été corrigé par une autre opération.', 'une révision périmée est refusée'
);
select extensions.is((select count(*) from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000501'), 1::bigint, 'le conflit ne crée aucune trace partielle');
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',1,'significant_change','2026-03-11','Travaux corrigés',6000,null,'   ')$$,
  '23514', 'Les informations de correction sont invalides.', 'un motif vide est refusé'
);
select extensions.throws_ok(
  $$update public.property_events set description = 'Écriture directe' where id = '85000000-0000-4000-8000-000000000502'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'une modification directe sans audit est refusée'
);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',1,'acquisition','2026-03-10','Conversion interdite',5000,null,'Mauvais type')$$,
  '23514', 'Cette transition de type d’événement n’est pas autorisée.', 'une transition entrée hors entrée est refusée'
);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000304','85000000-0000-4000-8000-000000000504',1,'inheritance','2026-01-07','Entrée ambiguë',90000,null,'Tentative ambiguë')$$,
  'P0001', 'Plusieurs événements d’entrée empêchent une correction non ambiguë.', 'plusieurs événements d’entrée bloquent la synchronisation'
);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000305','85000000-0000-4000-8000-000000000506',1,'significant_change','2025-05-02','Événement passé corrigé',1000,null,'Correction clôturée')$$,
  'P0001', 'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.', 'un événement clôturé reste immuable'
);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',1,'significant_change','2025-06-01','Déplacement clôturé',5000,null,'Déplacement interdit')$$,
  'P0001', 'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.', 'un événement ouvert ne peut pas entrer dans une période clôturée'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',1,'significant_change','2026-03-11','Lecteur',6000,null,'Interdit')$$,
  '42501', 'Droits insuffisants.', 'un lecteur ne peut pas corriger un événement'
);
select extensions.is((select count(*) from public.property_event_changes), 1::bigint, 'un lecteur peut consulter l’historique autorisé');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select extensions.is(
  public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',1,'significant_change','2026-03-11','Travaux corrigés',6000,'TRAVAUX-2','Correction gestionnaire'),
  2::bigint, 'un gestionnaire peut corriger un événement ouvert'
);
select extensions.is((select changed_by from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000502'), '85000000-0000-4000-8000-000000000002'::uuid, 'le gestionnaire est enregistré comme auteur');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.lives_ok(
  $$select public.correct_property_sale_price('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000303','85000000-0000-4000-8000-000000000503',200000,205000,'Prix rectifié avant la date')$$,
  'la correction dédiée du prix reste opérationnelle'
);
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '85000000-0000-4000-8000-000000000503'), 1::bigint, 'la correction de prix reste auditée');
select extensions.is(
  public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000303','85000000-0000-4000-8000-000000000503',2,'sale','2026-07-15','Vente datée correctement',205000,'VENTE-2','Date de signature rectifiée'),
  3::bigint, 'la date de vente est corrigée avec la révision courante'
);
select extensions.is((select disposal_date from public.real_estate_properties where id = '85000000-0000-4000-8000-000000000303'), '2026-07-15'::date, 'la date de cession du bien est synchronisée');
select extensions.is((select amount from public.property_events where id = '85000000-0000-4000-8000-000000000503'), 205000::numeric, 'la correction de date conserve le prix effectif');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '85000000-0000-4000-8000-000000000503'), 1::bigint, 'l’historique des corrections de prix est conservé');
select extensions.is((select change_type from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000503'), 'sale_date_correction', 'la correction de date de vente est qualifiée dans l’audit');
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000303','85000000-0000-4000-8000-000000000503',3,'sale','2026-07-16','Tentative prix',210000,'VENTE-2','Contourner le prix')$$,
  '23514', 'Le prix de vente doit être corrigé par le parcours dédié.', 'la correction générique ne contourne pas le prix dédié'
);
select extensions.is((select count(*) from public.property_event_changes where property_event_id = '85000000-0000-4000-8000-000000000503'), 1::bigint, 'l’échec sur le prix ne laisse aucune trace partielle');
select extensions.is((select count(*) from public.transactions), 0::bigint, 'aucune opération bancaire n’est créée');
select extensions.is((select count(*) from public.property_events), 6::bigint, 'tous les événements historiques autorisés restent visibles et préservés');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"85000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select extensions.is((select count(*) from public.property_event_changes), 0::bigint, 'un utilisateur étranger ne voit pas l’historique du dossier');
select extensions.throws_ok(
  $$select public.correct_property_event('85000000-0000-4000-8000-000000000101','85000000-0000-4000-8000-000000000302','85000000-0000-4000-8000-000000000502',2,'significant_change','2026-03-12','Étranger',6000,'TRAVAUX-2','Interdit')$$,
  '42501', 'Droits insuffisants.', 'un utilisateur étranger ne peut pas corriger le dossier'
);

select * from extensions.finish();
rollback;
