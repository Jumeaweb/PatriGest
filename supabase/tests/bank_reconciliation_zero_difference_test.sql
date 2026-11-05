begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(16);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99600000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'balanced-reconciliation-owner@example.test',
  'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id = '99600000-0000-4000-8000-000000000001';

insert into public.protected_persons (id, owner_id, first_name, last_name)
values (
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8000-000000000001',
  'Dossier', 'Rapprochement équilibré'
);

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date, status
) values (
  '99600000-0000-4000-8200-000000000001',
  '99600000-0000-4000-8100-000000000001',
  'checking', 'Banque', 'Compte', 100, '2026-01-01', 'active'
);

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values (
  '99600000-0000-4000-8300-000000000001',
  '99600000-0000-4000-8200-000000000001',
  '2026-01-05', 'income', 'Recette en circulation', 20
);

insert into public.bank_statements (
  id, financial_account_id, statement_start_date, statement_end_date,
  statement_balance, storage_path, created_by
) values
  ('99600000-0000-4000-8400-000000000001', '99600000-0000-4000-8200-000000000001', '2026-01-01', '2026-01-31', 120, 'balanced-simple-zero', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8400-000000000002', '99600000-0000-4000-8200-000000000001', '2026-02-01', '2026-02-28', 125, 'balanced-simple-positive', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8400-000000000003', '99600000-0000-4000-8200-000000000001', '2026-03-01', '2026-03-31', 115, 'balanced-simple-negative', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8400-000000000004', '99600000-0000-4000-8200-000000000001', '2026-04-01', '2026-04-30', 100, 'balanced-complete-zero', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8400-000000000005', '99600000-0000-4000-8200-000000000001', '2026-05-01', '2026-05-31', 105, 'balanced-complete-positive', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8400-000000000006', '99600000-0000-4000-8200-000000000001', '2026-06-01', '2026-06-30', 95, 'balanced-complete-negative', '99600000-0000-4000-8000-000000000001');

insert into public.bank_reconciliations (id, bank_statement_id, created_by) values
  ('99600000-0000-4000-8500-000000000001', '99600000-0000-4000-8400-000000000001', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8500-000000000002', '99600000-0000-4000-8400-000000000002', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8500-000000000003', '99600000-0000-4000-8400-000000000003', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8500-000000000004', '99600000-0000-4000-8400-000000000004', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8500-000000000005', '99600000-0000-4000-8400-000000000005', '99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8500-000000000006', '99600000-0000-4000-8400-000000000006', '99600000-0000-4000-8000-000000000001');

set local "request.jwt.claim.sub" = '99600000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000001') $$,
  'un rapprochement simple avec un écart nul est validé'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000002') $$,
  '55000', 'L''écart simple doit être nul avant la validation.',
  'un écart simple positif est refusé'
);
select extensions.results_eq(
  $$ select status::text, calculated_balance, difference, validated_at
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000002' $$,
  $$ values ('draft'::text, null::numeric, null::numeric, null::timestamptz) $$,
  'le refus positif ne modifie pas le brouillon'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000003') $$,
  '55000', 'L''écart simple doit être nul avant la validation.',
  'un écart simple négatif est refusé'
);
select extensions.results_eq(
  $$ select status::text, calculated_balance, difference, validated_at
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000003' $$,
  $$ values ('draft'::text, null::numeric, null::numeric, null::timestamptz) $$,
  'le refus négatif ne modifie pas le brouillon'
);

select public.activate_complete_bank_reconciliation('99600000-0000-4000-8500-000000000004');
select public.activate_complete_bank_reconciliation('99600000-0000-4000-8500-000000000005');
select public.activate_complete_bank_reconciliation('99600000-0000-4000-8500-000000000006');
select public.add_bank_reconciliation_outstanding_transaction('99600000-0000-4000-8500-000000000004', '99600000-0000-4000-8300-000000000001');
select public.add_bank_reconciliation_outstanding_transaction('99600000-0000-4000-8500-000000000005', '99600000-0000-4000-8300-000000000001');
select public.add_bank_reconciliation_outstanding_transaction('99600000-0000-4000-8500-000000000006', '99600000-0000-4000-8300-000000000001');

select extensions.lives_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000004') $$,
  'un écart initial non nul est accepté lorsque l''écart résiduel est nul'
);
select extensions.results_eq(
  $$ select difference, residual_difference
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000004' $$,
  $$ values (-20::numeric, 0::numeric) $$,
  'la validation détaillée conserve l''écart initial et fige un résiduel nul'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000005') $$,
  '55000', 'L''écart résiduel doit être nul avant la validation.',
  'un écart résiduel positif est refusé'
);
select extensions.results_eq(
  $$ select status::text, calculated_balance, difference, residual_difference, validated_at
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000005' $$,
  $$ values ('draft'::text, null::numeric, null::numeric, null::numeric, null::timestamptz) $$,
  'le refus détaillé positif ne modifie pas le brouillon'
);
select extensions.is(
  (select count(*) from public.bank_reconciliation_outstanding_transactions
   where bank_reconciliation_id = '99600000-0000-4000-8500-000000000005'
     and transaction_date_snapshot is not null),
  0::bigint,
  'le refus ne fige aucun instantané de pointage'
);

select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000006') $$,
  '55000', 'L''écart résiduel doit être nul avant la validation.',
  'un écart résiduel négatif est refusé'
);
select extensions.results_eq(
  $$ select status::text, calculated_balance, difference, residual_difference, validated_at
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000006' $$,
  $$ values ('draft'::text, null::numeric, null::numeric, null::numeric, null::timestamptz) $$,
  'le refus détaillé négatif ne modifie pas le brouillon'
);

select extensions.results_eq(
  $$ select status::text, calculated_balance, difference
     from public.bank_reconciliations
     where id = '99600000-0000-4000-8500-000000000001' $$,
  $$ values ('validated'::text, 120::numeric, 0::numeric) $$,
  'le rapprochement déjà validé conserve son instantané'
);
select extensions.throws_ok(
  $$ select public.validate_bank_reconciliation('99600000-0000-4000-8500-000000000001') $$,
  'P0001', 'Seul un rapprochement en brouillon peut être validé.',
  'un rapprochement déjà validé ne peut pas être recalculé'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.validate_bank_reconciliation(uuid)', 'EXECUTE'),
  'le droit execute authentifié est conservé'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.validate_bank_reconciliation(uuid)', 'EXECUTE'),
  'aucun droit execute anonyme n est ajouté'
);

select * from extensions.finish();
rollback;
