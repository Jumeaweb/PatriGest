begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(52);

-- Deterministic Auth users. The application authorization trigger creates the
-- corresponding pending rows; fixture setup activates every user except the
-- deliberately inactive account.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000101',
    'authenticated', 'authenticated', 'owner@example.test', 'test-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000102',
    'authenticated', 'authenticated', 'manager@example.test', 'test-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000103',
    'authenticated', 'authenticated', 'reader@example.test', 'test-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000104',
    'authenticated', 'authenticated', 'other@example.test', 'test-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000105',
    'authenticated', 'authenticated', 'inactive@example.test', 'test-hash', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000103',
  '00000000-0000-0000-0000-000000000104'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  (
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000101',
    'Alice', 'Dossier'
  ),
  (
    '00000000-0000-0000-0000-000000000205',
    '00000000-0000-0000-0000-000000000105',
    'Inès', 'Inactive'
  );

insert into public.protected_person_access (
  id, protected_person_id, user_id, role, invited_by
)
values
  (
    '00000000-0000-0000-0000-000000000211',
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000102',
    'manager',
    '00000000-0000-0000-0000-000000000101'
  ),
  (
    '00000000-0000-0000-0000-000000000212',
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000103',
    'read_only',
    '00000000-0000-0000-0000-000000000101'
  );

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
)
values
  (
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000201',
    'checking', 'Banque locale', 'Compte courant', 1000, '2025-01-01'
  ),
  (
    '00000000-0000-0000-0000-000000000302',
    '00000000-0000-0000-0000-000000000201',
    'livret_a', 'Banque locale', 'Livret', 500, '2025-01-01'
  ),
  (
    '00000000-0000-0000-0000-000000000305',
    '00000000-0000-0000-0000-000000000205',
    'checking', 'Banque locale', 'Compte inactif', 0, '2025-01-01'
  );

insert into public.management_periods (
  id, protected_person_id, start_date, end_date, status, closed_at
)
values
  (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000201',
    '2026-01-01', '2026-12-31', 'open', null
  ),
  (
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000201',
    '2025-01-01', '2025-12-31', 'open', null
  );

insert into public.categories (
  id, owner_id, name, usage, is_system, official_category_id
)
values
  (
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000101',
    'Autre dépense personnelle', 'expense', false,
    (select id from public.categories where official_code = 'DEP-1-08')
  ),
  (
    '00000000-0000-0000-0000-000000000704',
    '00000000-0000-0000-0000-000000000104',
    'Alimentation personnelle', 'expense', false,
    (select id from public.categories where official_code = 'DEP-1-02')
  );

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount,
  category_id
)
values
  (
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000301',
    '2026-01-10', 'expense', 'Dépense partagée', 20,
    (select id from public.categories where official_code = 'DEP-1-02')
  ),
  (
    '00000000-0000-0000-0000-000000000502',
    '00000000-0000-0000-0000-000000000301',
    '2026-02-10', 'expense', 'Historique inactif', 30,
    (select id from public.categories where official_code = 'DEP-1-01')
  ),
  (
    '00000000-0000-0000-0000-000000000503',
    '00000000-0000-0000-0000-000000000301',
    '2025-06-10', 'expense', 'Exercice clos', 40,
    (select id from public.categories where official_code = 'DEP-1-03')
  );

update public.management_periods
set status = 'closed', closed_at = now()
where id = '00000000-0000-0000-0000-000000000402';

insert into public.transfers (
  id, protected_person_id, source_account_id, destination_account_id,
  transfer_date, amount, label
)
values (
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000302',
  '2026-04-10', 50, 'Virement structuré'
);

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount,
  transfer_id
)
values
  (
    '00000000-0000-0000-0000-000000000510',
    '00000000-0000-0000-0000-000000000301',
    '2026-04-10', 'transfer_out', 'Virement structuré', 50,
    '00000000-0000-0000-0000-000000000601'
  ),
  (
    '00000000-0000-0000-0000-000000000511',
    '00000000-0000-0000-0000-000000000302',
    '2026-04-10', 'transfer_in', 'Virement structuré', 50,
    '00000000-0000-0000-0000-000000000601'
  );

-- Produce a valid historical reference to an inactive official category.
alter table public.categories disable trigger categories_validate_update;
update public.categories set active = false where official_code = 'DEP-1-01';
alter table public.categories enable trigger categories_validate_update;

-- Owner context.
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000101';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated","email":"owner@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000101'::uuid, 'owner uses an authenticated JWT context');
select extensions.is((select count(*) from public.protected_persons where id = '00000000-0000-0000-0000-000000000201'), 1::bigint, 'owner reads the dossier');
select extensions.is((select count(*) from public.financial_accounts where id = '00000000-0000-0000-0000-000000000301'), 1::bigint, 'owner reads the account');
select extensions.is((select count(*) from public.management_periods where id = '00000000-0000-0000-0000-000000000401'), 1::bigint, 'owner reads the management journal');
select extensions.is((select count(*) from public.transactions where id = '00000000-0000-0000-0000-000000000501'), 1::bigint, 'owner reads the transaction');

select extensions.lives_ok(
  $$
    select public.create_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000301',
      '2026-03-01', 'income', 'Recette owner', 100,
      null, (select id from public.categories where official_code = 'RES-1-01'),
      null, null, '00000000-0000-0000-0000-000000000901'
    )
  $$,
  'owner creates an income transaction'
);
select extensions.results_eq(
  $$
    select accounting_nature, category_id is null, official_category_id = (
      select id from public.categories where official_code = 'RES-1-01'
    )
    from public.transactions
    where label = 'Recette owner'
  $$,
  $$ values ('ordinary'::text, true, true) $$,
  'owner income receives a coherent stable classification'
);
select extensions.results_eq(
  $$
    select (public.correct_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000501', 1,
      '00000000-0000-0000-0000-000000000301', '2026-01-10', 'expense',
      'Owner updated', 20,
      (select id from public.categories where official_code = 'DEP-1-02'),
      (select id from public.categories where official_code = 'DEP-1-02'),
      null, null, 'Correction auditée owner',
      '00000000-0000-0000-0000-000000000902'
    ) ->> 'id')::uuid
  $$,
  $$ values ('00000000-0000-0000-0000-000000000501'::uuid) $$,
  'owner modifies a classic transaction'
);

-- Manager context.
reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000102';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated","email":"manager@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000102'::uuid, 'manager uses an authenticated JWT context');
select extensions.is((select count(*) from public.protected_persons where id = '00000000-0000-0000-0000-000000000201'), 1::bigint, 'manager reads the dossier');
select extensions.is((select count(*) from public.financial_accounts where id = '00000000-0000-0000-0000-000000000301'), 1::bigint, 'manager reads the account');
select extensions.is((select count(*) from public.management_periods where id = '00000000-0000-0000-0000-000000000401'), 1::bigint, 'manager reads the management journal');
select extensions.is((select count(*) from public.transactions where id = '00000000-0000-0000-0000-000000000501'), 1::bigint, 'manager reads the transaction');
select extensions.lives_ok(
  $$
    select public.create_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000301',
      '2026-03-02', 'expense', 'Dépense manager', 25,
      null, (select id from public.categories where official_code = 'DEP-1-02'),
      null, null, '00000000-0000-0000-0000-000000000903'
    )
  $$,
  'manager creates an expense transaction'
);
select extensions.results_eq(
  $$
    select accounting_nature, official_category_id = (
      select id from public.categories where official_code = 'DEP-1-02'
    )
    from public.transactions
    where label = 'Dépense manager'
  $$,
  $$ values ('ordinary'::text, true) $$,
  'manager expense receives a coherent stable classification'
);
select extensions.results_eq(
  $$
    select (public.correct_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000501', 2,
      '00000000-0000-0000-0000-000000000301', '2026-01-10', 'expense',
      'Manager updated', 20,
      (select id from public.categories where official_code = 'DEP-1-02'),
      (select id from public.categories where official_code = 'DEP-1-02'),
      null, null, 'Correction auditée manager',
      '00000000-0000-0000-0000-000000000904'
    ) ->> 'id')::uuid
  $$,
  $$ values ('00000000-0000-0000-0000-000000000501'::uuid) $$,
  'manager modifies a classic transaction'
);

-- Read-only context. The UPDATE result is measured rather than inferred from
-- the absence of a PostgreSQL exception.
reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000103';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated","email":"reader@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000103'::uuid, 'read_only uses an authenticated JWT context');
select extensions.is((select count(*) from public.protected_persons where id = '00000000-0000-0000-0000-000000000201'), 1::bigint, 'read_only reads the dossier');
select extensions.is((select count(*) from public.financial_accounts where id = '00000000-0000-0000-0000-000000000301'), 1::bigint, 'read_only reads the account');
select extensions.is((select count(*) from public.management_periods where id = '00000000-0000-0000-0000-000000000401'), 1::bigint, 'read_only reads the management journal');
select extensions.is((select count(*) from public.transactions where id = '00000000-0000-0000-0000-000000000501'), 1::bigint, 'read_only reads the transaction');
select extensions.throws_like(
  $$
    select public.create_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000301',
      '2026-03-03', 'expense', 'Dépense read_only', 10,
      null, (select id from public.categories where official_code = 'DEP-1-02'),
      null, null, '00000000-0000-0000-0000-000000000905'
    )
  $$,
  '%Dossier introuvable ou accès refusé.%',
  'read_only cannot create a transaction'
);
select extensions.throws_ok(
  $$
    select public.correct_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000501', 3,
      '00000000-0000-0000-0000-000000000301', '2026-01-10', 'expense',
      'Read-only false success', 20,
      (select id from public.categories where official_code = 'DEP-1-02'),
      (select id from public.categories where official_code = 'DEP-1-02'),
      null, null, 'Tentative lecteur',
      '00000000-0000-0000-0000-000000000906'
    )
  $$,
  '42501', 'Dossier introuvable ou accès refusé.',
  'read_only cannot correct a transaction through the audited RPC'
);
select extensions.is(
  (select label from public.transactions where id = '00000000-0000-0000-0000-000000000501'),
  'Manager updated'::text,
  'read_only UPDATE leaves the transaction unchanged'
);

-- Inactive application account context.
reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000105';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated","email":"inactive@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000105'::uuid, 'inactive account uses an authenticated JWT context');
select extensions.is(public.is_application_user_active(), false, 'inactive application account is rejected by the authorization gate');
select extensions.is((select count(*) from public.protected_persons where id = '00000000-0000-0000-0000-000000000205'), 0::bigint, 'inactive owner cannot read their own dossier');
select extensions.throws_like(
  $$
    insert into public.protected_persons (id, owner_id, first_name, last_name)
    values (
      '00000000-0000-0000-0000-000000000206',
      '00000000-0000-0000-0000-000000000105',
      'Dossier', 'Refusé'
    )
  $$,
  '%row-level security policy%',
  'inactive account cannot create a dossier'
);

-- Personal preset isolation and historical inactive official category.
reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000101';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated","email":"owner@example.test"}';
set local role authenticated;

select extensions.is((select count(*) from public.categories where id = '00000000-0000-0000-0000-000000000701'), 1::bigint, 'owner sees their personal preset');
select extensions.is((select count(*) from public.categories where id = '00000000-0000-0000-0000-000000000704'), 0::bigint, 'owner cannot see another user personal preset');
select extensions.is((select count(*) from public.categories where official_code = 'DEP-1-01' and not active), 1::bigint, 'inactive official category remains readable');
select extensions.is((select count(*) from public.transactions where id = '00000000-0000-0000-0000-000000000502'), 1::bigint, 'transaction retaining an inactive official category remains historically readable');

reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000104';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated","email":"other@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000104'::uuid, 'other user uses an authenticated JWT context');
select extensions.is((select count(*) from public.categories where id = '00000000-0000-0000-0000-000000000704'), 1::bigint, 'other user sees their personal preset');
select extensions.is((select count(*) from public.categories where id = '00000000-0000-0000-0000-000000000701'), 0::bigint, 'other user cannot see owner personal preset');

-- Classification normalization, validation and stable-field priority.
reset role;
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000101';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated","email":"owner@example.test"}';
set local role authenticated;

select extensions.is(auth.uid(), '00000000-0000-0000-0000-000000000101'::uuid, 'classification scenarios restore the owner JWT context');
reset role;
select extensions.lives_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, category_id, classification_precision
    ) values (
      '00000000-0000-0000-0000-000000000530',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-01', 'expense', 'Classification personnelle', 60,
      '00000000-0000-0000-0000-000000000701', '  détail normalisé  '
    )
  $$,
  'owner creates a transaction from a personal preset'
);
select extensions.results_eq(
  $$
    select
      category_id::text,
      accounting_nature,
      (select official_code from public.categories where id = transactions.official_category_id),
      classification_precision
    from public.transactions
    where id = '00000000-0000-0000-0000-000000000530'
  $$,
  $$
    values (
      '00000000-0000-0000-0000-000000000701'::text,
      'ordinary'::text,
      'DEP-1-08'::text,
      'détail normalisé'::text
    )
  $$,
  'legacy preset, nature, stable category and precision are coherent and normalized'
);
select extensions.lives_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, official_category_id
    ) values (
      '00000000-0000-0000-0000-000000000531',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-02', 'expense', 'Précision obligatoire absente', 61,
      (select id from public.categories where official_code = 'DEP-1-08')
    )
  $$,
  'historical SQL compatibility accepts NULL precision for a requires_precision category'
);
select extensions.is(
  (
    select classification_precision is null
    from public.transactions
    where id = '00000000-0000-0000-0000-000000000531'
  ),
  true,
  'historical SQL compatibility preserves NULL classification precision'
);
select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, official_category_id, classification_precision
    ) values (
      '00000000-0000-0000-0000-000000000532',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-03', 'expense', 'Précision parasite', 62,
      (select id from public.categories where official_code = 'DEP-1-02'), 'parasite'
    )
  $$,
  'P0001',
  'Cette catégorie officielle n’accepte pas de précision.',
  'precision is rejected for an official category that does not accept it'
);
select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, classification_precision
    ) values (
      '00000000-0000-0000-0000-000000000533',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-04', 'expense', 'Précision sans cible', 63, 'parasite'
    )
  $$,
  'P0001',
  'Une précision de classification nécessite une catégorie officielle.',
  'precision without an official target is rejected'
);
select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, official_category_id
    ) values (
      '00000000-0000-0000-0000-000000000534',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-05', 'expense', 'Cible non officielle', 64,
      '00000000-0000-0000-0000-000000000701'
    )
  $$,
  'P0001',
  'La catégorie de classification doit être une catégorie officielle terminale.',
  'non-official stable target is rejected'
);
select extensions.results_eq(
  $$
    with changed as (
      update public.transactions as updated_transaction
      set category_id = (select id from public.categories where official_code = 'DEP-1-02')
      where id = '00000000-0000-0000-0000-000000000530'
      returning
        (select official_code from public.categories where id = updated_transaction.official_category_id),
        classification_precision
    )
    select * from changed
  $$,
  $$ values ('DEP-1-02'::text, null::text) $$,
  'changing only legacy category takes priority and clears obsolete precision'
);
select extensions.results_eq(
  $$
    with changed as (
      update public.transactions as updated_transaction
      set
        category_id = '00000000-0000-0000-0000-000000000701',
        official_category_id = (select id from public.categories where official_code = 'DEP-1-03')
      where id = '00000000-0000-0000-0000-000000000530'
      returning
        category_id::text,
        (select official_code from public.categories where id = updated_transaction.official_category_id)
    )
    select * from changed
  $$,
  $$ values ('00000000-0000-0000-0000-000000000701'::text, 'DEP-1-03'::text) $$,
  'explicit stable category takes priority when both classification fields change'
);
select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, official_category_id
    ) values (
      '00000000-0000-0000-0000-000000000535',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-06', 'expense', 'Nouvelle cible inactive', 65,
      (select id from public.categories where official_code = 'DEP-1-01')
    )
  $$,
  'P0001',
  'Une catégorie officielle inactive ne peut pas être attribuée.',
  'inactive official category cannot be newly assigned'
);
select extensions.throws_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, accounting_nature, classification_precision
    ) values (
      '00000000-0000-0000-0000-000000000536',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-07', 'expense', 'Capital parasite', 66,
      'capital_movement', 'parasite'
    )
  $$,
  'P0001',
  'Un mouvement de capital ne peut pas porter de catégorie, de précision ou de transfert.',
  'capital movement rejects parasitic classification precision'
);
select extensions.lives_ok(
  $$
    insert into public.transactions (
      id, financial_account_id, transaction_date, transaction_type, label,
      amount, accounting_nature
    ) values (
      '00000000-0000-0000-0000-000000000537',
      '00000000-0000-0000-0000-000000000301',
      '2026-05-08', 'income', 'Mouvement de capital', 67, 'capital_movement'
    )
  $$,
  'valid capital movement can be created without category or precision'
);
select extensions.results_eq(
  $$
    select accounting_nature, category_id is null, official_category_id is null,
      classification_precision is null
    from public.transactions
    where id = '00000000-0000-0000-0000-000000000537'
  $$,
  $$ values ('capital_movement'::text, true, true, true) $$,
  'valid capital movement has the required empty classification shape'
);
set local role authenticated;

select extensions.throws_ok(
  $$
    select public.correct_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000503', 1,
      '00000000-0000-0000-0000-000000000301', '2025-06-10', 'expense',
      'Modification exercice clos', 40,
      (select id from public.categories where official_code = 'DEP-1-03'),
      (select id from public.categories where official_code = 'DEP-1-03'),
      null, null, 'Tentative exercice clos',
      '00000000-0000-0000-0000-000000000907'
    )
  $$,
  'P0001',
  'Cette opération appartient à un exercice clôturé.',
  'closed management period prevents transaction modification'
);
select extensions.throws_ok(
  $$
    select public.correct_financial_transaction(
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000510', 1,
      '00000000-0000-0000-0000-000000000301', '2026-04-10', 'expense',
      'Modification ordinaire interdite', 50, null, null, null, null,
      'Tentative mouvement isolé',
      '00000000-0000-0000-0000-000000000908'
    )
  $$,
  'P0002', 'Opération introuvable.',
  'an isolated structured-transfer leg cannot be corrected through the ordinary RPC'
);
select extensions.is(
  (select label from public.transactions where id = '00000000-0000-0000-0000-000000000510'),
  'Virement structuré'::text,
  'structured transfer transaction remains unchanged'
);

reset role;
select * from extensions.finish();
rollback;
