begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(47);

select extensions.has_table('public', 'property_sale_price_corrections', 'le journal des corrections de prix existe');
select extensions.has_function(
  'public', 'correct_property_sale_price', array['uuid', 'uuid', 'uuid', 'numeric', 'numeric', 'text'],
  'la fonction dédiée de correction existe'
);
select extensions.has_trigger(
  'public', 'property_events', 'property_events_audit_sale_price_correction',
  'les corrections sont auditées automatiquement'
);
select extensions.has_trigger(
  'public', 'property_sale_price_corrections', 'property_sale_price_corrections_immutable',
  'les traces de correction sont immuables'
);
select extensions.ok(
  (select not routine.prosecdef from pg_proc routine where routine.oid = 'public.correct_property_sale_price(uuid,uuid,uuid,numeric,numeric,text)'::regprocedure),
  'la fonction de correction est SECURITY INVOKER'
);
select extensions.ok(
  (select class.relrowsecurity from pg_class class where class.oid = 'public.property_sale_price_corrections'::regclass),
  'le journal des corrections utilise RLS'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.property_sale_price_corrections', 'UPDATE'),
  'un utilisateur applicatif ne peut pas modifier une trace'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.property_sale_price_corrections', 'DELETE'),
  'un utilisateur applicatif ne peut pas supprimer une trace'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '83000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'correction-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Aline","last_name":"Propriétaire"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '83000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'correction-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Marc","last_name":"Gestionnaire"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '83000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'correction-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Lise","last_name":"Lectrice"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '83000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'correction-foreign@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Autre","last_name":"Propriétaire"}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '83000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000002',
  '83000000-0000-4000-8000-000000000003',
  '83000000-0000-4000-8000-000000000004'
);

update public.profiles set first_name = 'Aline', last_name = 'Propriétaire' where id = '83000000-0000-4000-8000-000000000001';
update public.profiles set first_name = 'Marc', last_name = 'Gestionnaire' where id = '83000000-0000-4000-8000-000000000002';

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000001', 'Dossier', 'Correction'),
  ('83000000-0000-4000-8000-000000000102', '83000000-0000-4000-8000-000000000004', 'Dossier', 'Étranger');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('83000000-0000-4000-8000-000000000201', '83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000002', 'manager', '83000000-0000-4000-8000-000000000001'),
  ('83000000-0000-4000-8000-000000000202', '83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000003', 'read_only', '83000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties (
  id, protected_person_id, property_type, designation, entry_date,
  estimated_value, valuation_date, status
)
values
  ('83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000101', 'house', 'Vente à corriger', '2020-01-01', 180000, '2024-12-31', 'active'),
  ('83000000-0000-4000-8000-000000000302', '83000000-0000-4000-8000-000000000101', 'apartment', 'Vente clôturée', '2020-01-01', 90000, '2024-12-31', 'active'),
  ('83000000-0000-4000-8000-000000000303', '83000000-0000-4000-8000-000000000102', 'land', 'Vente étrangère', '2020-01-01', 50000, '2024-12-31', 'active'),
  ('83000000-0000-4000-8000-000000000304', '83000000-0000-4000-8000-000000000101', 'commercial', 'Ventes historiques multiples', '2020-01-01', 120000, '2024-12-31', 'active'),
  ('83000000-0000-4000-8000-000000000305', '83000000-0000-4000-8000-000000000101', 'house', 'Rollback audit', '2020-01-01', 150000, '2024-12-31', 'active');

insert into public.property_events (id, property_id, protected_person_id, event_type, event_date, description, amount)
values
  ('83000000-0000-4000-8000-000000000507', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000101', 'acquisition', '2020-01-01', 'Acquisition historique conservée', 180000),
  ('83000000-0000-4000-8000-000000000501', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000101', 'sale', '2025-06-15', 'Vente à corriger', 200000),
  ('83000000-0000-4000-8000-000000000502', '83000000-0000-4000-8000-000000000302', '83000000-0000-4000-8000-000000000101', 'sale', '2025-03-15', 'Vente clôturée', 95000),
  ('83000000-0000-4000-8000-000000000503', '83000000-0000-4000-8000-000000000303', '83000000-0000-4000-8000-000000000102', 'sale', '2025-05-10', 'Vente étrangère', 55000),
  ('83000000-0000-4000-8000-000000000506', '83000000-0000-4000-8000-000000000305', '83000000-0000-4000-8000-000000000101', 'sale', '2025-07-01', 'Rollback audit', 155000);

alter table public.property_events disable trigger property_events_validate_sale;
insert into public.property_events (id, property_id, protected_person_id, event_type, event_date, description, amount)
values
  ('83000000-0000-4000-8000-000000000504', '83000000-0000-4000-8000-000000000304', '83000000-0000-4000-8000-000000000101', 'sale', '2025-01-10', 'Première vente historique', 121000),
  ('83000000-0000-4000-8000-000000000505', '83000000-0000-4000-8000-000000000304', '83000000-0000-4000-8000-000000000101', 'sale', '2025-01-11', 'Deuxième vente historique', 122000);
alter table public.property_events enable trigger property_events_validate_sale;

insert into public.management_periods (id, protected_person_id, start_date, end_date, status, closed_at)
values ('83000000-0000-4000-8000-000000000601', '83000000-0000-4000-8000-000000000101', '2025-01-01', '2025-03-31', 'closed', now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select extensions.lives_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 200000, 205000, 'Rectification après contrôle de l’acte')$$,
  'le propriétaire peut corriger le prix de vente'
);
select extensions.is((select amount from public.property_events where id = '83000000-0000-4000-8000-000000000501'), 205000.00::numeric, 'le prix corrigé est enregistré');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 1::bigint, 'une première trace est créée');
select extensions.is((select old_price from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 200000.00::numeric, 'la trace conserve l’ancien prix');
select extensions.is((select new_price from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 205000.00::numeric, 'la trace conserve le nouveau prix');
select extensions.is((select reason from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 'Rectification après contrôle de l’acte', 'la trace conserve le motif');
select extensions.is((select corrected_by from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), '83000000-0000-4000-8000-000000000001'::uuid, 'la trace conserve l’auteur');
select extensions.ok((select char_length(corrected_by_name) > 0 from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 'la trace conserve le nom affichable de l’auteur');
select extensions.is((select status from public.real_estate_properties where id = '83000000-0000-4000-8000-000000000301'), 'disposed', 'le statut cédé est conservé');
select extensions.is((select disposal_date from public.real_estate_properties where id = '83000000-0000-4000-8000-000000000301'), '2025-06-15'::date, 'la date de cession est conservée');
select extensions.is((select estimated_value from public.real_estate_properties where id = '83000000-0000-4000-8000-000000000301'), 180000.00::numeric, 'l’estimation historique est conservée');
select extensions.is((select valuation_date from public.real_estate_properties where id = '83000000-0000-4000-8000-000000000301'), '2024-12-31'::date, 'la date d’estimation est conservée');
select extensions.is((select description from public.property_events where id = '83000000-0000-4000-8000-000000000507'), 'Acquisition historique conservée', 'les autres événements immobiliers sont conservés');
select extensions.is((select count(*) from public.transactions), 0::bigint, 'aucune opération bancaire n’est créée');

select extensions.lives_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 205000, 210000, 'Seconde rectification documentée')$$,
  'une deuxième correction est autorisée'
);
select extensions.is((select amount from public.property_events where id = '83000000-0000-4000-8000-000000000501'), 210000.00::numeric, 'la deuxième correction devient le prix courant');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 2::bigint, 'les deux corrections sont conservées');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501' and old_price = 200000 and new_price = 205000), 1::bigint, 'la première correction reste intacte');

select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 205000, 211000, 'Écrasement concurrent')$$,
  '40001', 'Le prix de vente a été modifié par une autre opération.', 'un prix initial obsolète est refusé'
);
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'), 2::bigint, 'une correction concurrente refusée ne crée pas de trace');
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 210000, 210000, 'Prix identique')$$,
  '23514', 'Le nouveau prix doit être différent du prix actuel.', 'un prix identique est refusé'
);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 210000, -1, 'Prix invalide')$$,
  '23514', 'Le nouveau prix est invalide.', 'un nouveau prix négatif est refusé'
);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 210000, 211000, '   ')$$,
  '23514', 'Le motif de la correction est obligatoire.', 'un motif vide est refusé'
);
select extensions.throws_ok(
  $$update public.property_events set amount = 211000 where id = '83000000-0000-4000-8000-000000000501'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'le prix ne peut pas être modifié directement'
);
select extensions.throws_ok(
  $$update public.property_events set event_type = 'significant_change' where id = '83000000-0000-4000-8000-000000000501'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'la protection du type de vente reste active'
);
select extensions.throws_ok(
  $$update public.property_events set event_date = '2025-06-16' where id = '83000000-0000-4000-8000-000000000501'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'la protection de la date de vente reste active'
);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000302', '83000000-0000-4000-8000-000000000502', 95000, 96000, 'Correction interdite')$$,
  'P0001', 'Cette vente appartient à un exercice clôturé.', 'un exercice clôturé interdit la correction'
);
select set_config('patrigest.sale_price_correction_id', gen_random_uuid()::text, true);
select set_config('patrigest.sale_price_correction_event_id', '83000000-0000-4000-8000-000000000502', true);
select set_config('patrigest.sale_price_correction_expected_price', '95000', true);
select set_config('patrigest.sale_price_correction_reason', 'Tentative de contournement', true);
select extensions.throws_ok(
  $$update public.property_events set amount = 96000 where id = '83000000-0000-4000-8000-000000000502'$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'forger le contexte d’audit ne contourne pas la clôture'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 210000, 211000, 'Lecteur')$$,
  '42501', 'Droits insuffisants.', 'un lecteur ne peut pas corriger le prix'
);
select extensions.is(
  (select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'),
  2::bigint,
  'un lecteur autorisé peut consulter l’historique des corrections'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000102', '83000000-0000-4000-8000-000000000303', '83000000-0000-4000-8000-000000000503', 55000, 56000, 'Dossier étranger')$$,
  '42501', 'Droits insuffisants.', 'un dossier étranger est refusé'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select extensions.lives_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000301', '83000000-0000-4000-8000-000000000501', 210000, 215000, 'Correction par le gestionnaire')$$,
  'un gestionnaire autorisé peut corriger le prix'
);
select extensions.is((select corrected_by from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501' order by corrected_at desc, id desc limit 1), '83000000-0000-4000-8000-000000000002'::uuid, 'la correction du gestionnaire conserve son auteur');
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000304', '83000000-0000-4000-8000-000000000504', 121000, 123000, 'Historique incohérent')$$,
  'P0001', 'La correction exige une unique vente pour ce bien.', 'plusieurs ventes historiques bloquent la correction'
);

reset role;
alter table public.property_events disable trigger property_events_audit_sale_price_correction;
set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.correct_property_sale_price('83000000-0000-4000-8000-000000000101', '83000000-0000-4000-8000-000000000305', '83000000-0000-4000-8000-000000000506', 155000, 156000, 'Audit indisponible')$$,
  'P0001', 'La trace de correction n’a pas été enregistrée.', 'un échec de l’audit annule la correction'
);
reset role;
alter table public.property_events enable trigger property_events_audit_sale_price_correction;
set local role authenticated;
select set_config('request.jwt.claim.sub', '83000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.is((select amount from public.property_events where id = '83000000-0000-4000-8000-000000000506'), 155000.00::numeric, 'le prix reste inchangé après le rollback');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000506'), 0::bigint, 'le rollback ne laisse aucune trace partielle');

reset role;
select extensions.throws_ok(
  $$update public.property_sale_price_corrections set reason = 'Altération' where property_event_id = '83000000-0000-4000-8000-000000000501'$$,
  'P0001', 'Une trace de correction de prix de vente est immuable.', 'même un accès privilégié ne modifie pas une trace sans désactiver la protection'
);
select extensions.throws_ok(
  $$delete from public.property_sale_price_corrections where property_event_id = '83000000-0000-4000-8000-000000000501'$$,
  'P0001', 'Une trace de correction de prix de vente est immuable.', 'même un accès privilégié ne supprime pas une trace sans désactiver la protection'
);

select * from extensions.finish();
rollback;
