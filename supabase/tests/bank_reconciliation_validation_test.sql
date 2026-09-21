begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(28);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '31000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rapp5-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '31000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rapp5-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '31000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rapp5-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '31000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'rapp5-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '31000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'rapp5-admin@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '31000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000002',
  '31000000-0000-4000-8000-000000000003',
  '31000000-0000-4000-8000-000000000004'
);

insert into public.platform_administrators (user_id, appointed_by)
values ('31000000-0000-4000-8000-000000000005', null);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('31000000-0000-4000-8000-000000000101', '31000000-0000-4000-8000-000000000001', 'Dossier', 'RAPP5');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('31000000-0000-4000-8000-000000000201', '31000000-0000-4000-8000-000000000101', '31000000-0000-4000-8000-000000000002', 'manager', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000202', '31000000-0000-4000-8000-000000000101', '31000000-0000-4000-8000-000000000003', 'read_only', '31000000-0000-4000-8000-000000000001');

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date, opening_date, status, closing_date
)
values
  ('31000000-0000-4000-8000-000000000301', '31000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Compte courant', 100.10, '2026-01-01', '2026-01-01', 'active', null),
  ('31000000-0000-4000-8000-000000000302', '31000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Sans opération', 42.50, '2026-01-01', null, 'active', null),
  ('31000000-0000-4000-8000-000000000303', '31000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Compte clôturé', 50, '2026-01-01', '2026-01-15', 'closed', '2026-12-31'),
  ('31000000-0000-4000-8000-000000000304', '31000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Bornes mouvantes', 10, '2026-01-01', null, 'active', null);

insert into public.transfers (
  id, protected_person_id, source_account_id, destination_account_id,
  transfer_date, amount, label
)
values
  ('31000000-0000-4000-8000-000000000701', '31000000-0000-4000-8000-000000000101', '31000000-0000-4000-8000-000000000302', '31000000-0000-4000-8000-000000000301', '2026-01-07', 20.03, 'Virement entrant'),
  ('31000000-0000-4000-8000-000000000702', '31000000-0000-4000-8000-000000000101', '31000000-0000-4000-8000-000000000301', '31000000-0000-4000-8000-000000000302', '2026-01-08', 4.04, 'Virement sortant');

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount, transfer_id
)
values
  ('31000000-0000-4000-8000-000000000401', '31000000-0000-4000-8000-000000000301', '2026-01-05', 'income', 'Recette', 10.01, null),
  ('31000000-0000-4000-8000-000000000402', '31000000-0000-4000-8000-000000000301', '2026-01-06', 'expense', 'Dépense', 3.02, null),
  ('31000000-0000-4000-8000-000000000403', '31000000-0000-4000-8000-000000000301', '2026-01-07', 'transfer_in', 'Virement entrant', 20.03, '31000000-0000-4000-8000-000000000701'),
  ('31000000-0000-4000-8000-000000000404', '31000000-0000-4000-8000-000000000301', '2026-01-08', 'transfer_out', 'Virement sortant', 4.04, '31000000-0000-4000-8000-000000000702'),
  ('31000000-0000-4000-8000-000000000405', '31000000-0000-4000-8000-000000000301', '2026-01-31', 'income', 'Même jour plus', 0.05, null),
  ('31000000-0000-4000-8000-000000000406', '31000000-0000-4000-8000-000000000301', '2026-01-31', 'expense', 'Même jour moins', 0.06, null),
  ('31000000-0000-4000-8000-000000000407', '31000000-0000-4000-8000-000000000301', '2026-02-01', 'income', 'Après relevé', 99.00, null);

insert into public.bank_statements (
  id, financial_account_id, statement_end_date, statement_balance, storage_path, created_by
)
values
  ('31000000-0000-4000-8000-000000000501', '31000000-0000-4000-8000-000000000301', '2026-01-31', 123.07, 'rapp5-zero', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000502', '31000000-0000-4000-8000-000000000301', '2026-02-28', 229.00, 'rapp5-positive', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000503', '31000000-0000-4000-8000-000000000302', '2026-01-31', 40.00, 'rapp5-negative', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000504', '31000000-0000-4000-8000-000000000302', '2026-02-28', null, 'rapp5-no-balance', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000505', '31000000-0000-4000-8000-000000000303', '2026-01-15', 50, 'rapp5-minimum', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000506', '31000000-0000-4000-8000-000000000303', '2026-12-31', 50, 'rapp5-closing', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000507', '31000000-0000-4000-8000-000000000304', '2026-06-30', 10, 'rapp5-moving-min', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000508', '31000000-0000-4000-8000-000000000304', '2026-07-31', 10, 'rapp5-moving-close', '31000000-0000-4000-8000-000000000001');

insert into public.bank_reconciliations (id, bank_statement_id, created_by)
values
  ('31000000-0000-4000-8000-000000000601', '31000000-0000-4000-8000-000000000501', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000602', '31000000-0000-4000-8000-000000000502', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000603', '31000000-0000-4000-8000-000000000503', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000604', '31000000-0000-4000-8000-000000000504', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000605', '31000000-0000-4000-8000-000000000505', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000606', '31000000-0000-4000-8000-000000000506', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000607', '31000000-0000-4000-8000-000000000507', '31000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000608', '31000000-0000-4000-8000-000000000508', '31000000-0000-4000-8000-000000000001');

update public.financial_accounts set initial_balance_date = '2026-07-01'
where id = '31000000-0000-4000-8000-000000000304';
update public.financial_accounts set closing_date = '2026-07-01', status = 'closed'
where id = '31000000-0000-4000-8000-000000000304';

select extensions.is(
  (select pronargs from pg_proc where oid = 'public.validate_bank_reconciliation(uuid)'::regprocedure),
  1::smallint,
  'validation accepts only the reconciliation identifier'
);

select extensions.ok(
  position('lock table public.transactions in share mode' in lower(pg_get_functiondef('public.validate_bank_reconciliation(uuid)'::regprocedure))) > 0,
  'validation locks transaction writers before calculating the snapshot'
);

select extensions.ok(
  position('for update' in lower(pg_get_functiondef('public.validate_bank_reconciliation(uuid)'::regprocedure))) > 0,
  'validation locks reconciliation and statement rows'
);

set local "request.jwt.claim.sub" = '31000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"31000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  has_table_privilege('public.bank_reconciliations', 'UPDATE'),
  false,
  'authenticated cannot update reconciliation snapshots directly'
);

select extensions.throws_ok(
  $$ update public.bank_reconciliations
     set status = 'validated', calculated_balance = 999, difference = 999,
         validated_at = now(), validated_by = auth.uid()
     where id = '31000000-0000-4000-8000-000000000601' $$,
  '42501', null,
  'owner cannot forge validated snapshots with direct update'
);

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000601') $$,
  'owner validates a draft through the RPC'
);

select extensions.results_eq(
  $$ select status::text, calculated_balance, difference,
            validated_at is not null, validated_by
     from public.bank_reconciliations
     where id = '31000000-0000-4000-8000-000000000601' $$,
  $$ values ('validated'::text, 123.07::numeric, 0.00::numeric, true,
             '31000000-0000-4000-8000-000000000001'::uuid) $$,
  'income expense transfers same-day entries and inclusive end date match the balance service'
);

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000603') $$,
  'an account with no transaction can be validated'
);

select extensions.results_eq(
  $$ select calculated_balance, difference
     from public.bank_reconciliations
     where id = '31000000-0000-4000-8000-000000000603' $$,
  $$ values (42.50::numeric, -2.50::numeric) $$,
  'initial balance only and a negative difference are exact'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000601') $$,
  'P0001', 'Seul un rapprochement en brouillon peut être validé.',
  'a validated reconciliation cannot be validated again'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000604') $$,
  'P0001', 'Le solde du relevé doit être renseigné avant le contrôle.',
  'a statement without balance cannot be validated'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000607') $$,
  'P0001', 'Le relevé est antérieur à la première date rapprochable du compte.',
  'current minimum date is rechecked by the RPC'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000608') $$,
  'P0001', 'Le relevé est postérieur à la clôture du compte.',
  'current closing date is rechecked by the RPC'
);

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000605') $$,
  'minimum reconcilable date is inclusive'
);

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000606') $$,
  'closing date is inclusive'
);

reset role;
set local "request.jwt.claim.sub" = '31000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"31000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000602') $$,
  'manager validates a draft through the RPC'
);

select extensions.results_eq(
  $$ select calculated_balance, difference, validated_by
     from public.bank_reconciliations
     where id = '31000000-0000-4000-8000-000000000602' $$,
  $$ values (222.07::numeric, 6.93::numeric, '31000000-0000-4000-8000-000000000002'::uuid) $$,
  'future exclusion and positive difference match the balance service'
);

reset role;
set local "request.jwt.claim.sub" = '31000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"31000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000607') $$,
  'P0001', 'Rapprochement introuvable.',
  'read_only cannot validate'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  8::bigint,
  'read_only can still read accessible reconciliations'
);

reset role;
set local "request.jwt.claim.sub" = '31000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"31000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000607') $$,
  'P0001', 'Rapprochement introuvable.',
  'user without dossier access cannot validate'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  0::bigint,
  'user without dossier access cannot read reconciliations'
);

reset role;
set local "request.jwt.claim.sub" = '31000000-0000-4000-8000-000000000005';
set local "request.jwt.claims" = '{"sub":"31000000-0000-4000-8000-000000000005","role":"authenticated"}';
set local role authenticated;

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('31000000-0000-4000-8000-000000000607') $$,
  'P0001', 'Rapprochement introuvable.',
  'platform administrator has no implicit validation access'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  0::bigint,
  'platform administrator has no implicit reconciliation read access'
);

reset role;

select extensions.is(
  (select calculated_balance from public.bank_reconciliations where id = '31000000-0000-4000-8000-000000000601'),
  123.07::numeric,
  'validated calculated balance remains stored as an immutable snapshot'
);

select extensions.is(
  (select difference from public.bank_reconciliations where id = '31000000-0000-4000-8000-000000000602'),
  6.93::numeric,
  'validated positive difference remains stored as an immutable snapshot'
);

select extensions.ok(
  (select calculated_balance is null and difference is null
   from public.bank_reconciliations where id = '31000000-0000-4000-8000-000000000604'),
  'a refused draft keeps both snapshot columns null'
);

select extensions.ok(
  (select status = 'draft' and calculated_balance is null and difference is null
   from public.bank_reconciliations where id = '31000000-0000-4000-8000-000000000607'),
  'a draft remains dynamic after a failed bounds check'
);

select extensions.is(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'bank_reconciliations'
     and cmd = 'UPDATE'),
  0::bigint,
  'no direct authenticated update policy remains'
);

select * from extensions.finish();

rollback;
