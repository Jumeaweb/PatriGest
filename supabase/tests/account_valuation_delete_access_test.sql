begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(7);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'valuation-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'valuation-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'valuation-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'valuation-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'valuation-other-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000001', 'Dossier', 'Principal'),
  ('10000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000005', 'Dossier', 'Autre');

update public.application_user_authorizations
set registration_intent = 'collaborator',
    account_mode = 'collaborator'
where user_id in (
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003'
);

insert into public.protected_person_access (
  id, protected_person_id, user_id, role, invited_by
)
values
  ('10000000-0000-4000-8000-000000000201', '10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000002', 'manager', '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000202', '10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000003', 'read_only', '10000000-0000-4000-8000-000000000001');

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
)
values
  ('10000000-0000-4000-8000-000000000301', '10000000-0000-4000-8000-000000000101', 'life_insurance', 'Banque locale', 'Placement principal', 100, '2025-01-01'),
  ('10000000-0000-4000-8000-000000000302', '10000000-0000-4000-8000-000000000102', 'life_insurance', 'Autre banque', 'Placement autre dossier', 200, '2025-01-01');

insert into public.account_valuations (
  id, financial_account_id, valuation_date, value
)
values
  ('10000000-0000-4000-8000-000000000401', '10000000-0000-4000-8000-000000000301', '2025-01-31', 101),
  ('10000000-0000-4000-8000-000000000402', '10000000-0000-4000-8000-000000000301', '2025-02-28', 102),
  ('10000000-0000-4000-8000-000000000403', '10000000-0000-4000-8000-000000000301', '2025-03-31', 103),
  ('10000000-0000-4000-8000-000000000404', '10000000-0000-4000-8000-000000000301', '2025-04-30', 104),
  ('10000000-0000-4000-8000-000000000405', '10000000-0000-4000-8000-000000000302', '2025-01-31', 201);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.results_eq(
  $$ with deleted as (
    delete from public.account_valuations
    where id = '10000000-0000-4000-8000-000000000401'
    returning 1
  ) select count(*)::bigint from deleted $$,
  $$ values (1::bigint) $$,
  'owner deletes a valuation'
);

select extensions.results_eq(
  $$ with deleted as (
    delete from public.account_valuations
    where id = '10000000-0000-4000-8000-000000000405'
    returning 1
  ) select count(*)::bigint from deleted $$,
  $$ values (0::bigint) $$,
  'owner cannot delete a valuation from another dossier'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select extensions.results_eq(
  $$ with deleted as (
    delete from public.account_valuations
    where id = '10000000-0000-4000-8000-000000000402'
    returning 1
  ) select count(*)::bigint from deleted $$,
  $$ values (1::bigint) $$,
  'manager deletes a valuation'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select extensions.results_eq(
  $$ with deleted as (
    delete from public.account_valuations
    where id = '10000000-0000-4000-8000-000000000403'
    returning 1
  ) select count(*)::bigint from deleted $$,
  $$ values (0::bigint) $$,
  'read_only cannot delete a valuation'
);

reset role;
select extensions.is(
  (select count(*) from public.account_valuations where id = '10000000-0000-4000-8000-000000000403'),
  1::bigint,
  'read_only leaves the valuation unchanged'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select extensions.results_eq(
  $$ with deleted as (
    delete from public.account_valuations
    where id = '10000000-0000-4000-8000-000000000404'
    returning 1
  ) select count(*)::bigint from deleted $$,
  $$ values (0::bigint) $$,
  'user without access cannot delete a valuation'
);

reset role;
select extensions.is(
  (select count(*) from public.account_valuations where id in (
    '10000000-0000-4000-8000-000000000404',
    '10000000-0000-4000-8000-000000000405'
  )),
  2::bigint,
  'forbidden cross-dossier valuations remain unchanged'
);

select * from extensions.finish();

rollback;
