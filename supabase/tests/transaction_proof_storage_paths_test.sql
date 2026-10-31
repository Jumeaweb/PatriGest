begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'transaction_proofs_select_accessible',
        'transaction_proofs_insert_manage',
        'transaction_proofs_update_manage',
        'transaction_proofs_delete_manage'
      )
      and (
        coalesce(qual, '') like '%regexp_match%'
        or coalesce(with_check, '') like '%regexp_match%'
      )
  ),
  4,
  'les quatre politiques imposent un chemin canonique par expression régulière'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '99500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'proof-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '99500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'proof-manager@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '99500000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'proof-reader@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '99500000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'proof-outsider@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id in (
  '99500000-0000-4000-8000-000000000001',
  '99500000-0000-4000-8000-000000000004'
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'collaborator'
where user_id in (
  '99500000-0000-4000-8000-000000000002',
  '99500000-0000-4000-8000-000000000003'
);

insert into public.protected_persons (id, owner_id, first_name, last_name) values
  ('99500000-0000-4000-8100-000000000001', '99500000-0000-4000-8000-000000000001', 'Dossier', 'Justificatifs'),
  ('99500000-0000-4000-8100-000000000002', '99500000-0000-4000-8000-000000000004', 'Dossier', 'Étranger');

insert into public.protected_person_access (
  id, protected_person_id, user_id, role, invited_by
) values
  ('99500000-0000-4000-8900-000000000001', '99500000-0000-4000-8100-000000000001', '99500000-0000-4000-8000-000000000002', 'manager', '99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8900-000000000002', '99500000-0000-4000-8100-000000000001', '99500000-0000-4000-8000-000000000003', 'read_only', '99500000-0000-4000-8000-000000000001');

insert into public.financial_accounts (
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values
  ('99500000-0000-4000-8200-000000000001', '99500000-0000-4000-8100-000000000001', 'checking', 'Banque test', 'Compte principal', 0, '2026-01-01'),
  ('99500000-0000-4000-8200-000000000002', '99500000-0000-4000-8100-000000000001', 'checking', 'Banque test', 'Compte secondaire', 0, '2026-01-01'),
  ('99500000-0000-4000-8200-000000000003', '99500000-0000-4000-8100-000000000002', 'checking', 'Banque test', 'Compte étranger', 0, '2026-01-01');

insert into public.transfers (
  id, protected_person_id, source_account_id, destination_account_id,
  transfer_date, amount, label
) values (
  '99500000-0000-4000-8700-000000000001',
  '99500000-0000-4000-8100-000000000001',
  '99500000-0000-4000-8200-000000000001',
  '99500000-0000-4000-8200-000000000002',
  '2026-01-02', 15, 'Virement test'
);

insert into public.transactions (
  id, financial_account_id, transaction_date, transaction_type, label, amount,
  transfer_id
) values
  ('99500000-0000-4000-8300-000000000001', '99500000-0000-4000-8200-000000000001', '2026-01-02', 'expense', 'Dépense existante', 10, null),
  ('99500000-0000-4000-8300-000000000002', '99500000-0000-4000-8200-000000000001', '2026-01-03', 'expense', 'Dépense propriétaire', 11, null),
  ('99500000-0000-4000-8300-000000000003', '99500000-0000-4000-8200-000000000001', '2026-01-04', 'expense', 'Dépense gestionnaire', 12, null),
  ('99500000-0000-4000-8300-000000000004', '99500000-0000-4000-8200-000000000001', '2026-01-05', 'expense', 'Dépense refusée', 13, null),
  ('99500000-0000-4000-8300-000000000005', '99500000-0000-4000-8200-000000000001', '2026-01-06', 'income', 'Recette sans justificatif', 14, null),
  ('99500000-0000-4000-8300-000000000006', '99500000-0000-4000-8200-000000000001', '2026-01-02', 'transfer_out', 'Virement sortant', 15, '99500000-0000-4000-8700-000000000001'),
  ('99500000-0000-4000-8300-000000000007', '99500000-0000-4000-8200-000000000003', '2026-01-07', 'expense', 'Dépense étrangère', 16, null);

insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version) values
  ('99500000-0000-4000-8600-000000000001', 'transaction-proofs', 'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000001/proof', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{"size":10,"mimetype":"application/pdf"}', 'v1'),
  ('99500000-0000-4000-8600-000000000002', 'transaction-proofs', 'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000001/extra/proof', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{"size":10,"mimetype":"application/pdf"}', 'v1'),
  ('99500000-0000-4000-8600-000000000003', 'transaction-proofs', 'protected-persons/99500000-0000-4000-8100-000000000002/transactions/99500000-0000-4000-8300-000000000007/proof', '99500000-0000-4000-8000-000000000004', '99500000-0000-4000-8000-000000000004', '{"size":10,"mimetype":"application/pdf"}', 'v1');

set local "request.jwt.claim.sub" = '99500000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from storage.objects where id = '99500000-0000-4000-8600-000000000001'),
  1::bigint,
  'le propriétaire lit un justificatif canonique'
);
select extensions.is(
  (select count(*) from storage.objects where id in (
    '99500000-0000-4000-8600-000000000002',
    '99500000-0000-4000-8600-000000000003'
  )),
  0::bigint,
  'les chemins non canoniques et les dossiers étrangers restent invisibles'
);
select extensions.lives_ok(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (
      '99500000-0000-4000-8600-000000000004', 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000002/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001',
      '{"size":10,"mimetype":"application/pdf"}', 'v1'
    )$$,
  'le propriétaire crée un justificatif canonique'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/extra/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'un segment supplémentaire avant proof est refusé'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof/extra',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'un segment supplémentaire après proof est refusé'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/not-a-uuid/transactions/not-a-uuid/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'les UUID mal formés sont refusés sans erreur de conversion'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000002/transactions/99500000-0000-4000-8300-000000000007/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'un dossier étranger est refusé'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000005/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'une recette ne peut pas recevoir un justificatif de dépense'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000006/proof',
      '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '{}', 'v1')$$,
  '%row-level security policy%',
  'un mouvement de transfert ne peut pas recevoir un justificatif de dépense'
);
select extensions.results_eq(
  $$with changed as (
      update storage.objects set user_metadata = '{"verified":true}'
      where id = '99500000-0000-4000-8600-000000000001'
      returning 1
    ) select count(*)::bigint from changed$$,
  $$values (1::bigint)$$,
  'le propriétaire conserve le remplacement du justificatif canonique'
);

reset role;
set local "request.jwt.claim.sub" = '99500000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"99500000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (
      '99500000-0000-4000-8600-000000000005', 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000003/proof',
      '99500000-0000-4000-8000-000000000002', '99500000-0000-4000-8000-000000000002',
      '{"size":10,"mimetype":"application/pdf"}', 'v1'
    )$$,
  'le gestionnaire conserve son droit de création'
);
select set_config('storage.allow_delete_query', 'true', true);
select extensions.results_eq(
  $$with removed as (
      delete from storage.objects
      where id = '99500000-0000-4000-8600-000000000005'
      returning 1
    ) select count(*)::bigint from removed$$,
  $$values (1::bigint)$$,
  'le gestionnaire conserve son droit de suppression canonique'
);
select set_config('storage.allow_delete_query', 'false', true);

reset role;
set local "request.jwt.claim.sub" = '99500000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"99500000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from storage.objects where id = '99500000-0000-4000-8600-000000000001'),
  1::bigint,
  'le lecteur conserve son droit de consultation'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
      '99500000-0000-4000-8000-000000000003', '99500000-0000-4000-8000-000000000003', '{}', 'v1')$$,
  '%row-level security policy%',
  'le lecteur ne peut pas créer de justificatif'
);
select extensions.results_eq(
  $$with changed as (
      update storage.objects set user_metadata = '{"forbidden":true}'
      where id = '99500000-0000-4000-8600-000000000001'
      returning 1
    ) select count(*)::bigint from changed$$,
  $$values (0::bigint)$$,
  'le lecteur ne peut pas remplacer un justificatif'
);
select set_config('storage.allow_delete_query', 'true', true);
select extensions.results_eq(
  $$with removed as (
      delete from storage.objects
      where id = '99500000-0000-4000-8600-000000000001'
      returning 1
    ) select count(*)::bigint from removed$$,
  $$values (0::bigint)$$,
  'le lecteur ne peut pas supprimer un justificatif'
);
select set_config('storage.allow_delete_query', 'false', true);

reset role;
set local "request.jwt.claim.sub" = '99500000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"99500000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  (select count(*) from storage.objects where id = '99500000-0000-4000-8600-000000000001'),
  0::bigint,
  'un utilisateur extérieur ne lit pas le justificatif'
);
select extensions.throws_like(
  $$insert into storage.objects (id, bucket_id, name, owner, owner_id, metadata, version)
    values (gen_random_uuid(), 'transaction-proofs',
      'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
      '99500000-0000-4000-8000-000000000004', '99500000-0000-4000-8000-000000000004', '{}', 'v1')$$,
  '%row-level security policy%',
  'un utilisateur extérieur ne crée pas de justificatif'
);

reset role;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id in (
  '99500000-0000-4000-8600-000000000001',
  '99500000-0000-4000-8600-000000000002',
  '99500000-0000-4000-8600-000000000003',
  '99500000-0000-4000-8600-000000000004'
);
select set_config('storage.allow_delete_query', 'false', true);

select * from extensions.finish();
rollback;
