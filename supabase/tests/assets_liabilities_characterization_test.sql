begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(22);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'patrimoine-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'patrimoine-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'patrimoine-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'patrimoine-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '81000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'patrimoine-other-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '81000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000004',
  '81000000-0000-4000-8000-000000000005'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('81000000-0000-4000-8000-000000000101', '81000000-0000-4000-8000-000000000001', 'Dossier', 'Principal'),
  ('81000000-0000-4000-8000-000000000102', '81000000-0000-4000-8000-000000000005', 'Dossier', 'Étranger');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('81000000-0000-4000-8000-000000000201', '81000000-0000-4000-8000-000000000101', '81000000-0000-4000-8000-000000000002', 'manager', '81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-8000-000000000202', '81000000-0000-4000-8000-000000000101', '81000000-0000-4000-8000-000000000003', 'read_only', '81000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties (
  id, protected_person_id, property_type, designation, city,
  estimated_value, valuation_date, status
)
values
  ('81000000-0000-4000-8000-000000000301', '81000000-0000-4000-8000-000000000101', 'house', 'Maison principale', 'Tours', 180000, '2026-01-31', 'active'),
  ('81000000-0000-4000-8000-000000000302', '81000000-0000-4000-8000-000000000102', 'apartment', 'Bien autre dossier', 'Blois', 90000, '2026-01-31', 'active');

insert into public.debts (
  id, protected_person_id, creditor, debt_type, designation,
  start_date, initial_amount, status
)
values
  ('81000000-0000-4000-8000-000000000401', '81000000-0000-4000-8000-000000000101', 'Banque de test', 'bank_loan', 'Prêt principal', '2020-01-01', 120000, 'active'),
  ('81000000-0000-4000-8000-000000000402', '81000000-0000-4000-8000-000000000102', 'Autre banque', 'bank_loan', 'Prêt autre dossier', '2020-01-01', 80000, 'active');

select extensions.has_trigger(
  'public', 'debt_balances', 'debt_balances_sync_current_balance',
  'les situations déclenchent la synchronisation du capital restant dû'
);

select extensions.has_trigger(
  'public', 'property_events', 'property_events_validate_dossier',
  'les événements vérifient leur rattachement au dossier'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select extensions.is(
  (select count(*) from public.real_estate_properties),
  1::bigint,
  'le propriétaire lit seulement les biens de son dossier'
);

insert into public.property_events (
  id, property_id, protected_person_id, event_type, event_date, description, amount
)
values (
  '81000000-0000-4000-8000-000000000501',
  '81000000-0000-4000-8000-000000000301',
  '81000000-0000-4000-8000-000000000101',
  'sale', '2026-02-15', 'Vente caractérisée', 195000
);

select extensions.is(
  (select status from public.real_estate_properties where id = '81000000-0000-4000-8000-000000000301'),
  'active',
  'caractérisation : un événement de vente laisse actuellement le bien actif'
);

select extensions.is(
  (select disposal_date from public.real_estate_properties where id = '81000000-0000-4000-8000-000000000301'),
  null::date,
  'caractérisation : un événement de vente ne renseigne actuellement aucune date de cession'
);

select extensions.throws_ok(
  $$
    insert into public.property_events (
      property_id, protected_person_id, event_type, event_date, description
    ) values (
      '81000000-0000-4000-8000-000000000301',
      '81000000-0000-4000-8000-000000000102',
      'sale', '2026-02-15', 'Mauvais dossier'
    )
  $$,
  'P0001',
  'Le bien immobilier n’appartient pas à ce dossier.',
  'un événement ne peut pas être rattaché au mauvais dossier'
);

select extensions.throws_ok(
  $$
    update public.real_estate_properties
    set protected_person_id = '81000000-0000-4000-8000-000000000102'
    where id = '81000000-0000-4000-8000-000000000301'
  $$,
  'P0001',
  'Le rattachement au dossier ne peut pas être modifié.',
  'le rattachement du bien est immuable'
);

insert into public.debt_balances (
  id, debt_id, balance_date, remaining_balance, remaining_duration_months
)
values (
  '81000000-0000-4000-8000-000000000601',
  '81000000-0000-4000-8000-000000000401',
  '2026-06-30', 75000, 144
);

select extensions.is(
  (select current_balance from public.debts where id = '81000000-0000-4000-8000-000000000401'),
  75000.00::numeric,
  'la première situation synchronise le capital restant dû courant'
);

select extensions.is(
  (select current_balance_date from public.debts where id = '81000000-0000-4000-8000-000000000401'),
  '2026-06-30'::date,
  'la date du capital courant est synchronisée'
);

insert into public.debt_balances (
  id, debt_id, balance_date, remaining_balance, remaining_duration_months
)
values (
  '81000000-0000-4000-8000-000000000602',
  '81000000-0000-4000-8000-000000000401',
  '2025-12-31', 82000, 150
);

select extensions.is(
  (select current_balance from public.debts where id = '81000000-0000-4000-8000-000000000401'),
  75000.00::numeric,
  'une situation plus ancienne ne remplace pas la situation courante'
);

select extensions.throws_ok(
  $$
    insert into public.debt_balances (debt_id, balance_date, remaining_balance)
    values ('81000000-0000-4000-8000-000000000401', '2026-06-30', 74000)
  $$,
  '23505',
  null,
  'une dette ne peut avoir deux situations à la même date'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select extensions.is(
  (select count(*) from public.real_estate_properties),
  1::bigint,
  'le gestionnaire lit les biens du dossier partagé'
);

insert into public.property_events (
  id, property_id, protected_person_id, event_type, event_date, description
)
values (
  '81000000-0000-4000-8000-000000000502',
  '81000000-0000-4000-8000-000000000301',
  '81000000-0000-4000-8000-000000000101',
  'significant_change', '2026-03-01', 'Événement gestionnaire'
);

select extensions.is(
  (select count(*) from public.property_events where id = '81000000-0000-4000-8000-000000000502'),
  1::bigint,
  'le gestionnaire peut ajouter un événement immobilier'
);

insert into public.debt_balances (
  id, debt_id, balance_date, remaining_balance, remaining_duration_months
)
values (
  '81000000-0000-4000-8000-000000000603',
  '81000000-0000-4000-8000-000000000401',
  '2026-09-30', 70000, 141
);

select extensions.is(
  (select current_balance from public.debts where id = '81000000-0000-4000-8000-000000000401'),
  70000.00::numeric,
  'une situation ajoutée par le gestionnaire devient la situation courante'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select extensions.is(
  (select count(*) from public.real_estate_properties),
  1::bigint,
  'le lecteur lit les biens du dossier partagé'
);

select extensions.is(
  (select count(*) from public.debt_balances where debt_id = '81000000-0000-4000-8000-000000000401'),
  3::bigint,
  'le lecteur consulte les situations de dette du dossier partagé'
);

select extensions.throws_ok(
  $$
    insert into public.property_events (
      property_id, protected_person_id, event_type, event_date, description
    ) values (
      '81000000-0000-4000-8000-000000000301',
      '81000000-0000-4000-8000-000000000101',
      'significant_change', '2026-04-01', 'Écriture interdite'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "property_events"',
  'le lecteur ne peut pas ajouter un événement'
);

select extensions.throws_ok(
  $$
    insert into public.debt_balances (debt_id, balance_date, remaining_balance)
    values ('81000000-0000-4000-8000-000000000401', '2026-10-01', 69000)
  $$,
  '42501',
  'new row violates row-level security policy for table "debt_balances"',
  'le lecteur ne peut pas ajouter une situation de dette'
);

select extensions.is(
  (select count(*) from public.real_estate_properties where id = '81000000-0000-4000-8000-000000000302'),
  0::bigint,
  'le lecteur ne voit pas les biens d’un autre dossier'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"81000000-0000-4000-8000-000000000004","role":"authenticated"}', true);

select extensions.is(
  (select count(*) from public.real_estate_properties),
  0::bigint,
  'un utilisateur sans accès ne voit aucun bien'
);

select extensions.is(
  (select count(*) from public.debts),
  0::bigint,
  'un utilisateur sans accès ne voit aucune dette'
);

select extensions.is(
  (select count(*) from public.debt_balances),
  0::bigint,
  'un utilisateur sans accès ne voit aucune situation de dette'
);

select * from extensions.finish();
rollback;
