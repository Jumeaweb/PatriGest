begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(7);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '20000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'securities-owner@example.test', 'test-hash', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
);

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id = '20000000-0000-4000-8000-000000000001';

insert into public.protected_persons (id, owner_id, first_name, last_name)
values (
  '20000000-0000-4000-8000-000000000101',
  '20000000-0000-4000-8000-000000000001',
  'Dossier', 'Compte-titres'
);

select extensions.lives_ok(
  $$
    insert into public.financial_accounts (
      id, protected_person_id, account_type, institution_name, account_name,
      initial_balance, initial_balance_date
    ) values (
      '20000000-0000-4000-8000-000000000301',
      '20000000-0000-4000-8000-000000000101',
      'securities_account', 'Courtier', 'Compte-titres', 1000, '2026-01-01'
    )
  $$,
  'securities_account is accepted'
);

select extensions.lives_ok(
  $$
    insert into public.financial_accounts (
      id, protected_person_id, account_type, institution_name, account_name,
      initial_balance, initial_balance_date
    ) values
      ('20000000-0000-4000-8000-000000000302', '20000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Compte courant', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000303', '20000000-0000-4000-8000-000000000101', 'livret_a', 'Banque', 'Livret A', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000304', '20000000-0000-4000-8000-000000000101', 'ldds', 'Banque', 'LDDS', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000305', '20000000-0000-4000-8000-000000000101', 'csl', 'Banque', 'CSL', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000306', '20000000-0000-4000-8000-000000000101', 'lep', 'Banque', 'LEP', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000307', '20000000-0000-4000-8000-000000000101', 'pel', 'Banque', 'PEL', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000308', '20000000-0000-4000-8000-000000000101', 'term_account', 'Banque', 'Compte à terme', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000309', '20000000-0000-4000-8000-000000000101', 'life_insurance', 'Assureur', 'Assurance-vie', 0, '2026-01-01'),
      ('20000000-0000-4000-8000-000000000310', '20000000-0000-4000-8000-000000000101', 'other_investment', 'Banque', 'Autre placement', 0, '2026-01-01')
  $$,
  'all existing financial account types remain accepted'
);

select extensions.set_eq(
  $$
    select account_type
    from public.financial_accounts
    where protected_person_id = '20000000-0000-4000-8000-000000000101'
  $$,
  $$
    values
      ('checking'::text), ('livret_a'::text), ('ldds'::text), ('csl'::text),
      ('lep'::text), ('pel'::text), ('term_account'::text),
      ('life_insurance'::text), ('other_investment'::text),
      ('securities_account'::text)
  $$,
  'the account type constraint exposes exactly the existing types plus securities_account'
);

select extensions.throws_ok(
  $$
    insert into public.financial_accounts (
      id, protected_person_id, account_type, institution_name, account_name,
      initial_balance, initial_balance_date
    ) values (
      '20000000-0000-4000-8000-000000000399',
      '20000000-0000-4000-8000-000000000101',
      'invalid_investment', 'Banque', 'Type invalide', 0, '2026-01-01'
    )
  $$,
  '23514',
  null,
  'an invalid financial account type is rejected'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, accounting_nature
    ) values (
      '20000000-0000-4000-8000-000000000401',
      '20000000-0000-4000-8000-000000000301',
      '2026-06-01', 'income', 'Recette ordinaire interdite', 10, 'ordinary'
    )
  $$,
  'P0001',
  'Les recettes et dépenses nécessitent un compte transactionnel.',
  'ordinary transactions are rejected on a securities account'
);

select extensions.lives_ok(
  $$
    select public.create_internal_transfer(
      '20000000-0000-4000-8000-000000000101',
      '20000000-0000-4000-8000-000000000302',
      '20000000-0000-4000-8000-000000000301',
      '2026-06-02', 250, 'Versement compte-titres', null
    )
  $$,
  'a structured transfer to a securities account is accepted'
);

select extensions.results_eq(
  $$
    select array_agg(transaction_type order by transaction_type)
    from public.transactions
    where financial_account_id in (
      '20000000-0000-4000-8000-000000000301',
      '20000000-0000-4000-8000-000000000302'
    )
      and transfer_id is not null
  $$,
  $$ values (array['transfer_in', 'transfer_out']::text[]) $$,
  'the structured transfer creates its two protected legs'
);

reset role;

select * from extensions.finish();

rollback;
