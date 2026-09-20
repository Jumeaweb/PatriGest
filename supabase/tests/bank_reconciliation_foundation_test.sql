begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(51);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rapp-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rapp-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rapp-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'rapp-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'rapp-other-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'rapp-admin@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000004',
  '30000000-0000-4000-8000-000000000005'
);

insert into public.platform_administrators (user_id, appointed_by)
values ('30000000-0000-4000-8000-000000000006', null);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('30000000-0000-4000-8000-000000000101', '30000000-0000-4000-8000-000000000001', 'Dossier', 'RAPP'),
  ('30000000-0000-4000-8000-000000000102', '30000000-0000-4000-8000-000000000005', 'Autre', 'Dossier');

insert into public.protected_person_access (
  id, protected_person_id, user_id, role, invited_by
)
values
  ('30000000-0000-4000-8000-000000000201', '30000000-0000-4000-8000-000000000101', '30000000-0000-4000-8000-000000000002', 'manager', '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000202', '30000000-0000-4000-8000-000000000101', '30000000-0000-4000-8000-000000000003', 'read_only', '30000000-0000-4000-8000-000000000001');

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date, opening_date, status, closing_date
)
values
  ('30000000-0000-4000-8000-000000000301', '30000000-0000-4000-8000-000000000101', 'checking', 'Banque RAPP', 'Compte ouvert', 100, '2026-01-01', '2026-02-01', 'active', null),
  ('30000000-0000-4000-8000-000000000302', '30000000-0000-4000-8000-000000000101', 'checking', 'Banque RAPP', 'Compte clôturé', 200, '2025-01-01', '2025-02-01', 'closed', '2025-12-31'),
  ('30000000-0000-4000-8000-000000000303', '30000000-0000-4000-8000-000000000102', 'checking', 'Autre banque', 'Compte autre dossier', 300, '2026-01-01', null, 'active', null),
  ('30000000-0000-4000-8000-000000000304', '30000000-0000-4000-8000-000000000101', 'checking', 'Banque RAPP', 'Compte sans ouverture', 400, '2026-01-01', null, 'active', null);

insert into public.bank_statements (
  id, financial_account_id, statement_start_date, statement_end_date,
  statement_balance, storage_path, original_file_name, mime_type, file_size,
  created_by
)
values
  ('30000000-0000-4000-8000-000000000501', '30000000-0000-4000-8000-000000000301', '2026-03-01', '2026-03-31', 110, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000501/statement', 'mars.pdf', 'application/pdf', 1024, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000503', '30000000-0000-4000-8000-000000000301', null, '2026-05-31', 130, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000503/statement', null, null, null, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000504', '30000000-0000-4000-8000-000000000301', null, '2026-06-30', 140, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000504/statement', null, null, null, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000505', '30000000-0000-4000-8000-000000000301', null, '2026-07-31', 150, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000505/statement', null, null, null, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000506', '30000000-0000-4000-8000-000000000303', null, '2026-03-31', 310, 'protected-persons/30000000-0000-4000-8000-000000000102/accounts/30000000-0000-4000-8000-000000000303/statements/30000000-0000-4000-8000-000000000506/statement', null, null, null, '30000000-0000-4000-8000-000000000005'),
  ('30000000-0000-4000-8000-000000000508', '30000000-0000-4000-8000-000000000301', null, '2026-08-31', 160, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000508/statement', 'aout.pdf', 'application/pdf', 10, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000509', '30000000-0000-4000-8000-000000000301', null, '2026-09-30', 170, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000509/statement', 'septembre.pdf', 'application/pdf', 10, '30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000510', '30000000-0000-4000-8000-000000000301', null, '2026-10-31', 180, 'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000510/statement', null, null, null, '30000000-0000-4000-8000-000000000001');

select extensions.is(
  (select count(*) from public.bank_statements where id = '30000000-0000-4000-8000-000000000501' and original_file_name = 'mars.pdf' and mime_type = 'application/pdf' and file_size = 1024),
  1::bigint,
  'an existing statement with a complete PDF remains valid'
);

set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, statement_balance,
    storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000502',
    '30000000-0000-4000-8000-000000000301', '2026-04-30', 120,
    'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000502/statement',
    '30000000-0000-4000-8000-000000000001'
  ) $$,
  'owner creates a bank statement without a PDF'
);

reset role;

select extensions.is(
  (select num_nulls(original_file_name, mime_type, file_size) from public.bank_statements where id = '30000000-0000-4000-8000-000000000502'),
  3,
  'a statement without a PDF has all document metadata null'
);

select extensions.is(
  (select num_nonnulls(original_file_name, mime_type, file_size) from public.bank_statements where id = '30000000-0000-4000-8000-000000000501'),
  3,
  'a statement with a PDF has all document metadata set'
);

select extensions.throws_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, statement_balance,
    storage_path, original_file_name, created_by
  ) values (
    '30000000-0000-4000-8000-000000000511',
    '30000000-0000-4000-8000-000000000301', '2026-11-30', 190,
    'partial-document', 'partial.pdf', '30000000-0000-4000-8000-000000000001'
  ) $$,
  '23514', null,
  'partial PDF metadata is rejected'
);

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, statement_balance,
    storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000512',
    '30000000-0000-4000-8000-000000000301', '2026-02-01', 100,
    'minimum-date', '30000000-0000-4000-8000-000000000001'
  ) $$,
  'a statement exactly at the minimum reconcilable date is archived'
);

select extensions.lives_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000612',
       '30000000-0000-4000-8000-000000000512',
       '30000000-0000-4000-8000-000000000001'
     );
     delete from public.bank_reconciliations
     where id = '30000000-0000-4000-8000-000000000612' $$,
  'a statement exactly at the minimum date can be reconciled'
);

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_start_date, statement_end_date,
    storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000513',
    '30000000-0000-4000-8000-000000000304', '2019-12-31', '2020-12-31',
    'before-initial-balance', '30000000-0000-4000-8000-000000000001'
  ) $$,
  'a historical statement before initial_balance_date remains a valid archive'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations
   where bank_statement_id = '30000000-0000-4000-8000-000000000513'),
  0::bigint,
  'a historical archive does not require a reconciliation'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000611',
       '30000000-0000-4000-8000-000000000513',
       '30000000-0000-4000-8000-000000000001'
     ) $$,
  'P0001', 'Le relevé est antérieur à la première date rapprochable du compte.',
  'a historical archive before initial_balance_date cannot be reconciled'
);

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000514',
    '30000000-0000-4000-8000-000000000301', '2026-01-31',
    'before-opening', '30000000-0000-4000-8000-000000000001'
  ) $$,
  'a statement before opening_date remains a valid archive'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000613',
       '30000000-0000-4000-8000-000000000514',
       '30000000-0000-4000-8000-000000000001'
     ) $$,
  'P0001', 'Le relevé est antérieur à la première date rapprochable du compte.',
  'a statement before opening_date cannot be reconciled'
);

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000507',
    '30000000-0000-4000-8000-000000000302', '2025-12-31',
    'closed-account-date', '30000000-0000-4000-8000-000000000001'
  ) $$,
  'closing_date is accepted for a closed account'
);

select extensions.lives_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000614',
       '30000000-0000-4000-8000-000000000507',
       '30000000-0000-4000-8000-000000000001'
     );
     delete from public.bank_reconciliations
     where id = '30000000-0000-4000-8000-000000000614' $$,
  'a statement exactly at closing_date can be reconciled'
);

select extensions.lives_ok(
  $$ insert into public.bank_statements (
    id, financial_account_id, statement_end_date, storage_path, created_by
  ) values (
    '30000000-0000-4000-8000-000000000515',
    '30000000-0000-4000-8000-000000000302', '2026-01-01',
    'after-closing', '30000000-0000-4000-8000-000000000001'
  ) $$,
  'a statement after closing_date remains a valid archive'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000615',
       '30000000-0000-4000-8000-000000000515',
       '30000000-0000-4000-8000-000000000001'
     ) $$,
  'P0001', 'Le relevé est postérieur à la clôture du compte.',
  'a statement after closing_date cannot be reconciled'
);

insert into public.bank_statements (
  id, financial_account_id, statement_end_date, storage_path, created_by
) values (
  '30000000-0000-4000-8000-000000000516',
  '30000000-0000-4000-8000-000000000301', '2026-11-30',
  'draft-date-guard', '30000000-0000-4000-8000-000000000001'
);
insert into public.bank_reconciliations (id, bank_statement_id, created_by)
values (
  '30000000-0000-4000-8000-000000000616',
  '30000000-0000-4000-8000-000000000516',
  '30000000-0000-4000-8000-000000000001'
);

select extensions.throws_ok(
  $$ update public.bank_statements
     set statement_end_date = '2026-01-31'
     where id = '30000000-0000-4000-8000-000000000516' $$,
  'P0001', 'Le relevé est antérieur à la première date rapprochable du compte.',
  'a statement linked to a draft cannot be moved outside account bounds'
);

delete from public.bank_reconciliations where id = '30000000-0000-4000-8000-000000000616';
delete from public.bank_statements where id = '30000000-0000-4000-8000-000000000516';

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date, status
) values (
  '30000000-0000-4000-8000-000000000305',
  '30000000-0000-4000-8000-000000000101', 'checking', 'Banque RAPP',
  'Compte dérive temporelle', 0, '2026-01-01', 'active'
);
insert into public.bank_statements (
  id, financial_account_id, statement_end_date, storage_path, created_by
) values (
  '30000000-0000-4000-8000-000000000517',
  '30000000-0000-4000-8000-000000000305', '2026-02-28',
  'validation-date-guard', '30000000-0000-4000-8000-000000000001'
);
insert into public.bank_reconciliations (id, bank_statement_id, created_by)
values (
  '30000000-0000-4000-8000-000000000617',
  '30000000-0000-4000-8000-000000000517',
  '30000000-0000-4000-8000-000000000001'
);
update public.financial_accounts
set initial_balance_date = '2026-03-01'
where id = '30000000-0000-4000-8000-000000000305';

select extensions.throws_ok(
  $$ update public.bank_reconciliations
     set status = 'validated', calculated_balance = 0, difference = 0,
         validated_at = now(), validated_by = '30000000-0000-4000-8000-000000000001'
     where id = '30000000-0000-4000-8000-000000000617' $$,
  'P0001', 'Le relevé est antérieur à la première date rapprochable du compte.',
  'draft to validated rechecks current account bounds'
);

delete from public.bank_reconciliations where id = '30000000-0000-4000-8000-000000000617';
delete from public.bank_statements where id = '30000000-0000-4000-8000-000000000517';
delete from public.financial_accounts where id = '30000000-0000-4000-8000-000000000305';

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, calculated_balance, created_by
  ) values (
    '30000000-0000-4000-8000-000000000699',
    '30000000-0000-4000-8000-000000000510', 180,
    '30000000-0000-4000-8000-000000000001'
  ) $$,
  '23514', null,
  'a draft cannot contain snapshots'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, status, calculated_balance, difference,
    created_by, validated_at, validated_by
  ) values (
    '30000000-0000-4000-8000-000000000698',
    '30000000-0000-4000-8000-000000000510', 'validated', 180, 0,
    '30000000-0000-4000-8000-000000000001', now(),
    '30000000-0000-4000-8000-000000000001'
  ) $$,
  'P0001', 'Un rapprochement doit être créé en brouillon.',
  'a reconciliation cannot be inserted directly as validated'
);

set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000601',
    '30000000-0000-4000-8000-000000000501',
    '30000000-0000-4000-8000-000000000001'
  ) $$,
  'owner creates a draft reconciliation'
);

select extensions.results_eq(
  $$ select status::text, calculated_balance, difference, validated_at, validated_by
     from public.bank_reconciliations
     where id = '30000000-0000-4000-8000-000000000601' $$,
  $$ values ('draft'::text, null::numeric, null::numeric, null::timestamptz, null::uuid) $$,
  'draft snapshots and validation metadata are null'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000602',
    '30000000-0000-4000-8000-000000000501',
    '30000000-0000-4000-8000-000000000001'
  ) $$,
  '23505', null,
  'one bank statement can have only one reconciliation'
);

select extensions.lives_ok(
  $$ update public.bank_reconciliations
     set status = 'validated', calculated_balance = 108, difference = 2,
         validated_at = now(), validated_by = '30000000-0000-4000-8000-000000000001'
     where id = '30000000-0000-4000-8000-000000000601' $$,
  'owner validates a draft reconciliation'
);

select extensions.results_eq(
  $$ select status::text, calculated_balance, difference,
            validated_at is not null, validated_by
     from public.bank_reconciliations
     where id = '30000000-0000-4000-8000-000000000601' $$,
  $$ values ('validated'::text, 108.00::numeric, 2.00::numeric, true, '30000000-0000-4000-8000-000000000001'::uuid) $$,
  'validated reconciliation stores both snapshots and audit metadata'
);

select extensions.throws_ok(
  $$ update public.bank_reconciliations
     set status = 'draft', calculated_balance = null, difference = null,
         validated_at = null, validated_by = null
     where id = '30000000-0000-4000-8000-000000000601' $$,
  'P0001', 'Un rapprochement validé est définitivement figé.',
  'validated reconciliation cannot return to draft'
);

select extensions.throws_ok(
  $$ update public.bank_reconciliations set difference = 3
     where id = '30000000-0000-4000-8000-000000000601' $$,
  'P0001', 'Un rapprochement validé est définitivement figé.',
  'validated reconciliation snapshots cannot change'
);

select extensions.throws_ok(
  $$ delete from public.bank_reconciliations
     where id = '30000000-0000-4000-8000-000000000601' $$,
  'P0001', 'Un rapprochement validé est définitivement figé.',
  'validated reconciliation cannot be deleted'
);

select extensions.throws_ok(
  $$ update public.bank_statements set note = 'Modification interdite'
     where id = '30000000-0000-4000-8000-000000000501' $$,
  'P0001', 'Un relevé rapproché est définitivement figé.',
  'statement linked to a validated reconciliation cannot change'
);

select extensions.throws_ok(
  $$ delete from public.bank_statements
     where id = '30000000-0000-4000-8000-000000000501' $$,
  'P0001', 'Un relevé rapproché est définitivement figé.',
  'statement linked to a validated reconciliation cannot be deleted'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  1::bigint,
  'owner reads the accessible reconciliation'
);

reset role;
set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000603',
    '30000000-0000-4000-8000-000000000503',
    '30000000-0000-4000-8000-000000000002'
  ) $$,
  'manager creates a draft reconciliation'
);

select extensions.lives_ok(
  $$ update public.bank_reconciliations
     set status = 'validated', calculated_balance = 125, difference = 5,
         validated_at = now(), validated_by = '30000000-0000-4000-8000-000000000002'
     where id = '30000000-0000-4000-8000-000000000603' $$,
  'manager validates a draft reconciliation'
);

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  2::bigint,
  'manager reads accessible reconciliations'
);

reset role;
set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  2::bigint,
  'read_only reads accessible reconciliations'
);

select extensions.results_eq(
  $$ with changed as (
       update public.bank_reconciliations set updated_at = now()
       where id = '30000000-0000-4000-8000-000000000601'
       returning 1
     ) select count(*)::bigint from changed $$,
  $$ values (0::bigint) $$,
  'read_only cannot update a reconciliation'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000604',
    '30000000-0000-4000-8000-000000000504',
    '30000000-0000-4000-8000-000000000003'
  ) $$,
  '42501', null,
  'read_only cannot create a reconciliation'
);

reset role;
set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  0::bigint,
  'user without dossier access cannot read reconciliations'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000605',
    '30000000-0000-4000-8000-000000000505',
    '30000000-0000-4000-8000-000000000004'
  ) $$,
  '42501', null,
  'user without dossier access cannot create a reconciliation'
);

reset role;
set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000006';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000006","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from public.bank_reconciliations),
  0::bigint,
  'platform administrator has no implicit reconciliation read access'
);

select extensions.throws_ok(
  $$ insert into public.bank_reconciliations (
    id, bank_statement_id, created_by
  ) values (
    '30000000-0000-4000-8000-000000000606',
    '30000000-0000-4000-8000-000000000505',
    '30000000-0000-4000-8000-000000000006'
  ) $$,
  '42501', null,
  'platform administrator has no implicit reconciliation write access'
);

reset role;
set local "request.jwt.claim.sub" = '30000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"30000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$ insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata)
     values (
       '30000000-0000-4000-8000-000000000701', 'bank-statements',
       'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000508/statement',
       '30000000-0000-4000-8000-000000000001',
       '30000000-0000-4000-8000-000000000001', '{"size":10}'::jsonb
     ) $$,
  'owner adds a PDF before reconciliation validation'
);

select extensions.results_eq(
  $$ with changed as (
       update storage.objects set metadata = '{"size":11}'::jsonb
       where id = '30000000-0000-4000-8000-000000000701'
       returning 1
     ) select count(*)::bigint from changed $$,
  $$ values (1::bigint) $$,
  'owner replaces PDF metadata before validation'
);

select extensions.ok(
  position('can_manage_protected_person' in (
    select qual from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'bank_statements_storage_delete_manage'
  )) > 0,
  'storage delete policy preserves owner and manager authorization'
);

select extensions.lives_ok(
  $$ insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata)
     values (
       '30000000-0000-4000-8000-000000000702', 'bank-statements',
       'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000509/statement',
       '30000000-0000-4000-8000-000000000001',
       '30000000-0000-4000-8000-000000000001', '{"size":10}'::jsonb
     );
     insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000609',
       '30000000-0000-4000-8000-000000000509',
       '30000000-0000-4000-8000-000000000001'
     );
     update public.bank_reconciliations
     set status = 'validated', calculated_balance = 168, difference = 2,
         validated_at = now(), validated_by = '30000000-0000-4000-8000-000000000001'
     where id = '30000000-0000-4000-8000-000000000609' $$,
  'owner adds a PDF and validates its reconciliation'
);

select extensions.results_eq(
  $$ with changed as (
       update storage.objects set metadata = '{"size":12}'::jsonb
       where id = '30000000-0000-4000-8000-000000000702'
       returning 1
     ) select count(*)::bigint from changed $$,
  $$ values (0::bigint) $$,
  'validated statement PDF cannot be replaced'
);

select extensions.ok(
  position('bank_reconciliations' in (
    select qual from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'bank_statements_storage_delete_manage'
  )) > 0,
  'storage delete policy protects validated statement PDFs'
);

select extensions.is(
  (select count(*) from storage.objects where id = '30000000-0000-4000-8000-000000000702'),
  1::bigint,
  'validated statement PDF remains stored'
);

select extensions.throws_ok(
  $$ insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata)
     values (
       '30000000-0000-4000-8000-000000000703', 'bank-statements',
       'protected-persons/30000000-0000-4000-8000-000000000101/accounts/30000000-0000-4000-8000-000000000301/statements/30000000-0000-4000-8000-000000000501/statement',
       '30000000-0000-4000-8000-000000000001',
       '30000000-0000-4000-8000-000000000001', '{"size":10}'::jsonb
     ) $$,
  '42501', null,
  'validated statement cannot receive a PDF'
);

select extensions.lives_ok(
  $$ insert into public.bank_reconciliations (id, bank_statement_id, created_by)
     values (
       '30000000-0000-4000-8000-000000000610',
       '30000000-0000-4000-8000-000000000510',
       '30000000-0000-4000-8000-000000000001'
     ) $$,
  'owner can create another draft for deletion testing'
);

select extensions.results_eq(
  $$ with removed as (
       delete from public.bank_reconciliations
       where id = '30000000-0000-4000-8000-000000000610'
       returning 1
     ) select count(*)::bigint from removed $$,
  $$ values (1::bigint) $$,
  'owner can delete a draft reconciliation'
);

select * from extensions.finish();

rollback;
