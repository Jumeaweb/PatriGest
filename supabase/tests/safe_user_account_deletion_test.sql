begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(28);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sec02-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'sec02-admin@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'sec02-history@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'sec02-appointed@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'sec02-storage@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'sec02-other-storage@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '20000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000005',
  '20000000-0000-4000-8000-000000000006'
);

insert into public.platform_administrators (user_id, appointed_by)
values
  ('20000000-0000-4000-8000-000000000002', null),
  ('20000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000003');

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('20000000-0000-4000-8000-000000000101', '20000000-0000-4000-8000-000000000001', 'Histoire', 'SEC02');

insert into public.protected_person_access (
  id, protected_person_id, user_id, role, invited_by
)
values (
  '20000000-0000-4000-8000-000000000111',
  '20000000-0000-4000-8000-000000000101',
  '20000000-0000-4000-8000-000000000003',
  'manager',
  '20000000-0000-4000-8000-000000000001'
);

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
)
values (
  '20000000-0000-4000-8000-000000000201',
  '20000000-0000-4000-8000-000000000101',
  'checking', 'Banque locale', 'Compte SEC02', 1000, '2025-01-01'
);

insert into public.categories (
  id, owner_id, name, usage, is_system, official_category_id
)
values (
  '20000000-0000-4000-8000-000000000301',
  '20000000-0000-4000-8000-000000000003',
  'Preset historique SEC02', 'expense', false,
  (select id from public.categories where official_code = 'DEP-1-08')
);

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount,
  category_id, accounting_nature, official_category_id,
  classification_precision, updated_at
)
values (
  '20000000-0000-4000-8000-000000000401',
  '20000000-0000-4000-8000-000000000201',
  '2025-06-15', 'expense', 'Transaction historique SEC02', 42,
  '20000000-0000-4000-8000-000000000301', 'ordinary',
  (select id from public.categories where official_code = 'DEP-1-08'),
  'Précision historique SEC02', '2025-06-16 10:00:00+00'
);

insert into public.transaction_documents (
  id, transaction_id, storage_path, file_name, mime_type, file_size,
  created_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000501',
  '20000000-0000-4000-8000-000000000401',
  'sec02/transaction-proof.pdf', 'transaction-proof.pdf', 'application/pdf', 1,
  '20000000-0000-4000-8000-000000000003', '2025-06-16 10:00:00+00'
);

insert into public.bank_statements (
  id, financial_account_id, statement_start_date, statement_end_date,
  statement_balance, storage_path, original_file_name, mime_type, file_size,
  created_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000502',
  '20000000-0000-4000-8000-000000000201', '2025-06-01', '2025-06-30', 1042,
  'sec02/bank-statement.pdf', 'bank-statement.pdf', 'application/pdf', 1,
  '20000000-0000-4000-8000-000000000003', '2025-07-01 10:00:00+00'
);

insert into public.management_periods (
  id, protected_person_id, start_date, end_date, status, closed_at
)
values (
  '20000000-0000-4000-8000-000000000601',
  '20000000-0000-4000-8000-000000000101',
  '2025-01-01', '2025-12-31', 'closed', '2026-01-01 10:00:00+00'
);

insert into public.management_reports (
  id, protected_person_id, management_period_id, report_year,
  period_start, period_end, status, created_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000701',
  '20000000-0000-4000-8000-000000000101',
  '20000000-0000-4000-8000-000000000601', 2025,
  '2025-01-01', '2025-12-31', 'draft',
  '20000000-0000-4000-8000-000000000003', '2026-01-01 10:00:00+00'
);

insert into public.management_report_account_selections (
  id, management_report_id, financial_account_id, selection_mode, reason,
  created_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000711',
  '20000000-0000-4000-8000-000000000701',
  '20000000-0000-4000-8000-000000000201', 'included_manual', 'Fixture SEC02',
  '20000000-0000-4000-8000-000000000003', '2026-01-01 10:00:00+00'
);

alter table public.management_reports disable trigger management_reports_protect_identity;
update public.management_reports
set status = 'approved',
    generated_at = '2026-01-02 10:00:00+00',
    finalized_at = '2026-01-03 10:00:00+00',
    transmitted_at = '2026-01-04 10:00:00+00',
    approved_at = '2026-01-05 10:00:00+00',
    updated_at = '2026-01-05 10:00:00+00'
where id = '20000000-0000-4000-8000-000000000701';
alter table public.management_reports enable trigger management_reports_protect_identity;

insert into public.management_report_documents (
  id, management_report_id, document_type, storage_path, file_name,
  mime_type, file_size, generated_by
)
values (
  '20000000-0000-4000-8000-000000000721',
  '20000000-0000-4000-8000-000000000701', 'management_report',
  'sec02/management-report.pdf', 'management-report.pdf', 'application/pdf', 1,
  '20000000-0000-4000-8000-000000000003'
);

insert into public.management_report_transmissions (
  id, management_report_id, transmission_date, transmission_method,
  recipient, declared_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000731',
  '20000000-0000-4000-8000-000000000701', '2026-01-04', 'postal_mail',
  'Destinataire SEC02', '20000000-0000-4000-8000-000000000003',
  '2026-01-04 10:00:00+00'
);

insert into public.management_report_approvals (
  id, management_report_id, approval_date, reviewer_name, declared_by,
  updated_at
)
values (
  '20000000-0000-4000-8000-000000000741',
  '20000000-0000-4000-8000-000000000701', '2026-01-05', 'Juge SEC02',
  '20000000-0000-4000-8000-000000000003', '2026-01-05 10:00:00+00'
);

insert into public.management_report_difficulties (
  id, management_report_id, difficulty_date, reason, declared_by, updated_at
)
values (
  '20000000-0000-4000-8000-000000000751',
  '20000000-0000-4000-8000-000000000701', '2026-01-05', 'Fixture SEC02',
  '20000000-0000-4000-8000-000000000003', '2026-01-05 10:00:00+00'
);

insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, user_metadata)
values
  ('20000000-0000-4000-8000-000000000801', 'transaction-proofs', 'sec02/current-user.pdf', '20000000-0000-4000-8000-000000000005', '20000000-0000-4000-8000-000000000005', '{"size":1}'::jsonb, '{"fixture":true}'::jsonb),
  ('20000000-0000-4000-8000-000000000802', 'transaction-proofs', 'sec02/other-user.pdf', '20000000-0000-4000-8000-000000000006', '20000000-0000-4000-8000-000000000006', '{"size":2}'::jsonb, '{"fixture":true}'::jsonb);

select extensions.throws_ok(
  $$ delete from auth.users where id = '20000000-0000-4000-8000-000000000001' $$,
  '23503', null,
  'protected person owner deletion remains restricted'
);

select extensions.throws_ok(
  $$ delete from auth.users where id = '20000000-0000-4000-8000-000000000002' $$,
  '23503', null,
  'platform administrator self deletion remains restricted'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000005';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000005","role":"authenticated"}';
set local role authenticated;

select extensions.results_eq(
  $$ select bucket_id, name from public.list_current_user_owned_storage_objects() $$,
  $$ values ('transaction-proofs'::text, 'sec02/current-user.pdf'::text) $$,
  'storage enumeration is scoped to the current authenticated session'
);

select extensions.is(
  (select count(*) from public.list_current_user_owned_storage_objects()
   where name = 'sec02/other-user.pdf'),
  0::bigint,
  'storage enumeration does not expose another user objects'
);

reset role;

select extensions.throws_ok(
  $$ update public.transactions set category_id = null where id = '20000000-0000-4000-8000-000000000401' $$,
  'P0001', 'Cette opération appartient à un exercice clôturé.',
  'an ordinary category clear cannot impersonate referential cleanup in a closed period'
);

select extensions.throws_ok(
  $$ update public.transaction_documents set created_by = null where id = '20000000-0000-4000-8000-000000000501' $$,
  'P0001', 'Le rattachement du justificatif ne peut pas être modifié.',
  'application cannot clear transaction document audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.bank_statements set created_by = null where id = '20000000-0000-4000-8000-000000000502' $$,
  'P0001', 'Le rattachement du relevé ne peut pas être modifié.',
  'application cannot clear bank statement audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_reports set created_by = null where id = '20000000-0000-4000-8000-000000000701' $$,
  'P0001', 'Ce compte de gestion est définitivement figé.',
  'application cannot clear frozen report audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_report_documents set generated_by = null where id = '20000000-0000-4000-8000-000000000721' $$,
  'P0001', 'Un document de compte de gestion ne peut pas être modifié.',
  'application cannot clear report document audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_report_transmissions set declared_by = null where id = '20000000-0000-4000-8000-000000000731' $$,
  'P0001', 'Le rattachement de la transmission ne peut pas être modifié.',
  'application cannot clear report transmission audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_report_approvals set declared_by = null where id = '20000000-0000-4000-8000-000000000741' $$,
  'P0001', 'Le rattachement du retour ne peut pas être modifié.',
  'application cannot clear report approval audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_report_difficulties set declared_by = null where id = '20000000-0000-4000-8000-000000000751' $$,
  'P0001', 'Le rattachement du retour ne peut pas être modifié.',
  'application cannot clear report difficulty audit identity while user exists'
);
select extensions.throws_ok(
  $$ update public.management_report_account_selections set created_by = null where id = '20000000-0000-4000-8000-000000000711' $$,
  'P0001', 'La sélection des comptes est modifiable uniquement pendant la préparation.',
  'application cannot clear frozen report selection audit identity while user exists'
);

select extensions.lives_ok(
  $$ delete from auth.users where id = '20000000-0000-4000-8000-000000000003' $$,
  'eligible user deletion performs all referential cleanups atomically'
);

select extensions.is((select count(*) from public.profiles where id = '20000000-0000-4000-8000-000000000003'), 0::bigint, 'profile cascades');
select extensions.is((select count(*) from public.protected_person_access where user_id = '20000000-0000-4000-8000-000000000003'), 0::bigint, 'shared access cascades');
select extensions.is((select count(*) from public.application_user_authorizations where user_id = '20000000-0000-4000-8000-000000000003'), 0::bigint, 'application authorization cascades');
select extensions.is((select count(*) from public.categories where id = '20000000-0000-4000-8000-000000000301'), 0::bigint, 'personal category cascades');
select extensions.is((select category_id from public.transactions where id = '20000000-0000-4000-8000-000000000401'), null::uuid, 'transaction category reference becomes null');
select extensions.is((select accounting_nature from public.transactions where id = '20000000-0000-4000-8000-000000000401'), 'ordinary', 'stable accounting nature survives');
select extensions.is(
  (select official_code from public.categories where id = (
    select official_category_id from public.transactions where id = '20000000-0000-4000-8000-000000000401'
  )),
  'DEP-1-08',
  'stable official category survives'
);
select extensions.is((select classification_precision from public.transactions where id = '20000000-0000-4000-8000-000000000401'), 'Précision historique SEC02', 'classification precision survives');
select extensions.is((select updated_at from public.transactions where id = '20000000-0000-4000-8000-000000000401'), '2025-06-16 10:00:00+00'::timestamptz, 'transaction updated_at survives referential cleanup');
select extensions.is(
  (select count(*) from public.transaction_documents where id = '20000000-0000-4000-8000-000000000501')
  + (select count(*) from public.bank_statements where id = '20000000-0000-4000-8000-000000000502')
  + (select count(*) from public.management_reports where id = '20000000-0000-4000-8000-000000000701')
  + (select count(*) from public.management_report_documents where id = '20000000-0000-4000-8000-000000000721')
  + (select count(*) from public.management_report_transmissions where id = '20000000-0000-4000-8000-000000000731')
  + (select count(*) from public.management_report_approvals where id = '20000000-0000-4000-8000-000000000741')
  + (select count(*) from public.management_report_difficulties where id = '20000000-0000-4000-8000-000000000751')
  + (select count(*) from public.management_report_account_selections where id = '20000000-0000-4000-8000-000000000711'),
  8::bigint,
  'all audit business rows survive'
);
select extensions.is(
  (select count(*) from (
    select created_by as audit_user from public.transaction_documents where id = '20000000-0000-4000-8000-000000000501'
    union all select created_by from public.bank_statements where id = '20000000-0000-4000-8000-000000000502'
    union all select created_by from public.management_reports where id = '20000000-0000-4000-8000-000000000701'
    union all select generated_by from public.management_report_documents where id = '20000000-0000-4000-8000-000000000721'
    union all select declared_by from public.management_report_transmissions where id = '20000000-0000-4000-8000-000000000731'
    union all select declared_by from public.management_report_approvals where id = '20000000-0000-4000-8000-000000000741'
    union all select declared_by from public.management_report_difficulties where id = '20000000-0000-4000-8000-000000000751'
    union all select created_by from public.management_report_account_selections where id = '20000000-0000-4000-8000-000000000711'
  ) audit_rows where audit_user is null),
  8::bigint,
  'all audit user references become null'
);
select extensions.is((select status::text from public.management_reports where id = '20000000-0000-4000-8000-000000000701'), 'approved', 'frozen approved report survives unchanged');
select extensions.is((select count(*) from public.management_report_documents where id = '20000000-0000-4000-8000-000000000721'), 1::bigint, 'frozen report document survives');
select extensions.is((select appointed_by from public.platform_administrators where user_id = '20000000-0000-4000-8000-000000000004'), null::uuid, 'former administrator appointed_by reference becomes null');

select * from extensions.finish();

rollback;
