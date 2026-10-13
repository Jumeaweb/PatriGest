begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(44);

select extensions.has_function(
  'public', 'synchronize_property_sale', array[]::text[],
  'la fonction de synchronisation des ventes existe'
);

select extensions.has_trigger(
  'public', 'property_events', 'property_events_validate_sale',
  'les ventes sont contrôlées avant leur insertion'
);

select extensions.has_trigger(
  'public', 'property_events', 'property_events_protect_sale',
  'les ventes sont protégées contre les modifications incohérentes'
);

select extensions.has_trigger(
  'public', 'real_estate_properties', 'real_estate_properties_protect_sale',
  'les biens vendus sont protégés contre les modifications incohérentes'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '82000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sale-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '82000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'sale-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '82000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'sale-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '82000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000002',
  '82000000-0000-4000-8000-000000000003'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('82000000-0000-4000-8000-000000000101', '82000000-0000-4000-8000-000000000001', 'Dossier', 'Vente');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('82000000-0000-4000-8000-000000000201', '82000000-0000-4000-8000-000000000101', '82000000-0000-4000-8000-000000000002', 'manager', '82000000-0000-4000-8000-000000000001'),
  ('82000000-0000-4000-8000-000000000202', '82000000-0000-4000-8000-000000000101', '82000000-0000-4000-8000-000000000003', 'read_only', '82000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties (
  id, protected_person_id, property_type, designation, entry_date,
  estimated_value, valuation_date, status, disposal_date
)
values
  ('82000000-0000-4000-8000-000000000301', '82000000-0000-4000-8000-000000000101', 'house', 'Vente normale', '2020-01-01', 180000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000302', '82000000-0000-4000-8000-000000000101', 'apartment', 'Cédé sans vente', '2020-01-01', 90000, '2025-12-31', 'disposed', '2026-01-15'),
  ('82000000-0000-4000-8000-000000000303', '82000000-0000-4000-8000-000000000101', 'land', 'Date invalide', '2024-01-01', 50000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000304', '82000000-0000-4000-8000-000000000101', 'commercial', 'Atomicité', '2020-01-01', 120000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000305', '82000000-0000-4000-8000-000000000101', 'house', 'Autre événement', '2020-01-01', 140000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000306', '82000000-0000-4000-8000-000000000101', 'house', 'Lecture seule', '2020-01-01', 160000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000307', '82000000-0000-4000-8000-000000000101', 'house', 'Vente historique active', '2020-01-01', 170000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000308', '82000000-0000-4000-8000-000000000101', 'house', 'Vente historique cédée', '2020-01-01', 175000, '2026-01-31', 'disposed', '2025-06-15'),
  ('82000000-0000-4000-8000-000000000309', '82000000-0000-4000-8000-000000000101', 'house', 'Vente gestionnaire', '2020-01-01', 185000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000310', '82000000-0000-4000-8000-000000000101', 'house', 'Prix absent', '2020-01-01', 190000, '2026-01-31', 'active', null),
  ('82000000-0000-4000-8000-000000000311', '82000000-0000-4000-8000-000000000101', 'house', 'Vente future', '2020-01-01', 200000, '2026-01-31', 'active', null);

alter table public.property_events disable trigger property_events_validate_sale;
insert into public.property_events (
  id, property_id, protected_person_id, event_type, event_date, description, amount
)
values
  ('82000000-0000-4000-8000-000000000501', '82000000-0000-4000-8000-000000000307', '82000000-0000-4000-8000-000000000101', 'sale', '2025-05-15', 'Vente historique incohérente', 171000),
  ('82000000-0000-4000-8000-000000000502', '82000000-0000-4000-8000-000000000308', '82000000-0000-4000-8000-000000000101', 'sale', '2025-06-15', 'Vente historique cohérente', 176000);
alter table public.property_events enable trigger property_events_validate_sale;

set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

insert into public.property_events (
  property_id, protected_person_id, event_type, event_date, description, amount
)
values (
  '82000000-0000-4000-8000-000000000301',
  '82000000-0000-4000-8000-000000000101',
  'sale', '2026-02-15', 'Vente normale', 195000
);

select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000301'), 'disposed', 'la vente cède le bien actif');
select extensions.is((select disposal_date from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000301'), '2026-02-15'::date, 'la vente renseigne la date de cession');
select extensions.is((select estimated_value from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000301'), 180000.00::numeric, 'la dernière estimation reste inchangée');
select extensions.is((select valuation_date from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000301'), '2026-01-31'::date, 'la date de la dernière estimation reste inchangée');
select extensions.is((select amount from public.property_events where property_id = '82000000-0000-4000-8000-000000000301' and event_type = 'sale'), 195000.00::numeric, 'le prix de vente reste porté par l’événement');
select extensions.is((
  select count(*)
  from public.transactions transaction
  join public.financial_accounts account on account.id = transaction.financial_account_id
  where account.protected_person_id = '82000000-0000-4000-8000-000000000101'
), 0::bigint, 'la vente ne crée aucune transaction bancaire');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000301', '82000000-0000-4000-8000-000000000101', 'sale', '2026-02-16', 'Doublon', 196000)$$,
  '23505', 'Une vente est déjà enregistrée pour ce bien.', 'une deuxième vente est refusée'
);
select extensions.is((select count(*) from public.property_events where property_id = '82000000-0000-4000-8000-000000000301' and event_type = 'sale'), 1::bigint, 'la vente existante n’est pas dupliquée');

select extensions.throws_ok(
  $$update public.property_events set event_type = 'significant_change' where property_id = '82000000-0000-4000-8000-000000000301' and event_type = 'sale'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'une vente ne peut pas devenir un autre événement par écriture directe'
);
select extensions.throws_ok(
  $$update public.property_events set event_date = '2026-02-16' where property_id = '82000000-0000-4000-8000-000000000301' and event_type = 'sale'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'la date d’une vente ne peut pas être modifiée directement'
);
select extensions.throws_ok(
  $$update public.property_events set amount = null where property_id = '82000000-0000-4000-8000-000000000301' and event_type = 'sale'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'une vente ne peut pas perdre son prix par écriture directe'
);
select extensions.throws_ok(
  $$update public.real_estate_properties set status = 'active', disposal_date = null where id = '82000000-0000-4000-8000-000000000301'$$,
  'P0001', 'Le statut et la date de cession doivent correspondre à l’événement de vente.', 'un bien vendu ne peut pas redevenir actif'
);
select extensions.throws_ok(
  $$update public.real_estate_properties set disposal_date = '2026-02-16' where id = '82000000-0000-4000-8000-000000000301'$$,
  'P0001', 'Le statut et la date de cession doivent correspondre à l’événement de vente.', 'la date de cession ne peut pas diverger de la vente'
);
update public.real_estate_properties
set designation = 'Vente normale renommée'
where id = '82000000-0000-4000-8000-000000000301';
select extensions.is((select designation from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000301'), 'Vente normale renommée', 'une modification descriptive reste autorisée après la vente');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000302', '82000000-0000-4000-8000-000000000101', 'sale', '2026-02-20', 'Régularisation implicite', 95000)$$,
  'P0001', 'Seul un bien actif peut être vendu.', 'un bien historiquement cédé sans vente n’est pas corrigé automatiquement'
);
select extensions.is((select count(*) from public.property_events where property_id = '82000000-0000-4000-8000-000000000302' and event_type = 'sale'), 0::bigint, 'aucune vente n’est ajoutée au bien cédé incohérent');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000307', '82000000-0000-4000-8000-000000000101', 'sale', '2026-02-20', 'Doublon historique', 180000)$$,
  '23505', 'Une vente est déjà enregistrée pour ce bien.', 'un bien actif avec vente historique ne reçoit pas de seconde vente'
);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000307'), 'active', 'le bien actif incohérent n’est pas corrigé automatiquement');
select extensions.throws_ok(
  $$update public.real_estate_properties set status = 'disposed', disposal_date = '2025-05-16' where id = '82000000-0000-4000-8000-000000000307'$$,
  'P0001', 'Le statut et la date de cession doivent correspondre à l’événement de vente.', 'une réparation historique avec une mauvaise date est refusée'
);
update public.real_estate_properties
set status = 'disposed', disposal_date = '2025-05-15'
where id = '82000000-0000-4000-8000-000000000307';
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000307'), 'disposed', 'une incohérence historique peut être réparée vers le statut cédé');
select extensions.is((select disposal_date from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000307'), '2025-05-15'::date, 'la réparation historique reprend exactement la date de vente');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000308', '82000000-0000-4000-8000-000000000101', 'sale', '2026-02-20', 'Doublon historique', 180000)$$,
  '23505', 'Une vente est déjà enregistrée pour ce bien.', 'un bien déjà cédé avec vente reste protégé contre les doublons'
);
select extensions.is((select disposal_date from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000308'), '2025-06-15'::date, 'le bien déjà cédé conserve sa date historique');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000303', '82000000-0000-4000-8000-000000000101', 'sale', '2023-12-31', 'Vente antérieure', 55000)$$,
  'P0001', 'La date de vente ne peut pas précéder l’entrée du bien dans le patrimoine.', 'une vente antérieure à l’entrée dans le patrimoine est refusée'
);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000303'), 'active', 'l’échec de date laisse le bien actif');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000310', '82000000-0000-4000-8000-000000000101', 'sale', '2026-02-20', 'Prix absent', null)$$,
  '23514', 'Le prix de vente doit être renseigné.', 'une vente sans prix est refusée'
);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000310'), 'active', 'l’échec de prix laisse le bien actif');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000304', '82000000-0000-4000-8000-000000000101', 'sale', '2026-03-01', '', 125000)$$,
  '23514', null, 'un échec de validation de l’événement annule toute la vente'
);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000304'), 'active', 'la mise à jour du bien est annulée avec l’événement invalide');

insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount)
values ('82000000-0000-4000-8000-000000000305', '82000000-0000-4000-8000-000000000101', 'significant_change', '2026-03-01', 'Travaux', 10000);
select extensions.is((select count(*) from public.property_events where property_id = '82000000-0000-4000-8000-000000000305'), 1::bigint, 'les autres types d’événements restent enregistrables');
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000305'), 'active', 'un autre événement ne modifie pas le statut du bien');
select extensions.throws_ok(
  $$update public.property_events set event_type = 'sale', amount = 15000 where property_id = '82000000-0000-4000-8000-000000000305'$$,
  '42501', 'La correction d’un événement immobilier doit utiliser le parcours dédié.', 'un autre événement ne peut pas être transformé directement en vente'
);
select public.correct_property_event(
  '82000000-0000-4000-8000-000000000101',
  '82000000-0000-4000-8000-000000000305',
  (select id from public.property_events where property_id = '82000000-0000-4000-8000-000000000305'),
  1, 'significant_change', '2026-03-02', 'Travaux actualisés', 10000, null,
  'Actualisation des travaux'
);
select extensions.is((select event_date from public.property_events where property_id = '82000000-0000-4000-8000-000000000305'), '2026-03-02'::date, 'les autres événements restent modifiables');

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000311', '82000000-0000-4000-8000-000000000101', 'sale', (current_date + 1), 'Vente future', 205000)$$,
  'P0001', 'La date de vente ne peut pas être future.', 'une vente future est refusée'
);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000311'), 'active', 'l’échec de vente future laisse le bien actif');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount)
values ('82000000-0000-4000-8000-000000000309', '82000000-0000-4000-8000-000000000101', 'sale', '2026-04-01', 'Vente gestionnaire', 200000);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000309'), 'disposed', 'un gestionnaire peut enregistrer une vente cohérente');
select extensions.is((select disposal_date from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000309'), '2026-04-01'::date, 'la vente du gestionnaire synchronise sa date');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select extensions.throws_ok(
  $$insert into public.property_events (property_id, protected_person_id, event_type, event_date, description, amount) values ('82000000-0000-4000-8000-000000000306', '82000000-0000-4000-8000-000000000101', 'sale', '2026-05-01', 'Vente interdite', 165000)$$,
  '42501', null, 'un lecteur ne peut pas enregistrer une vente'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '82000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.is((select status from public.real_estate_properties where id = '82000000-0000-4000-8000-000000000306'), 'active', 'l’échec en lecture seule laisse le bien actif');
select extensions.is((select count(*) from public.property_events where property_id = '82000000-0000-4000-8000-000000000306'), 0::bigint, 'l’échec en lecture seule ne crée aucun événement');

select * from extensions.finish();
rollback;
