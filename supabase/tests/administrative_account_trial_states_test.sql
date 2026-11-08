begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(12);

select extensions.has_function(
  'public',
  'list_administrative_account_trial_states',
  array['uuid[]'],
  'la projection administrative des essais existe'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.list_administrative_account_trial_states(uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_administrative_account_trial_states(uuid[])', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_administrative_account_trial_states(uuid[])', 'EXECUTE'),
  'seul authenticated peut appeler la RPC, dont le controle metier reste interne'
);

select extensions.ok(
  not has_table_privilege('authenticated', 'public.account_trials', 'SELECT')
  and not has_table_privilege('service_role', 'public.account_trials', 'SELECT')
  and not has_table_privilege('authenticated', 'public.account_trial_legacy_access', 'SELECT')
  and not has_table_privilege('service_role', 'public.account_trial_legacy_access', 'SELECT'),
  'les tables techniques restent fermees'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'trial-admin@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'trial-active@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'trial-expired@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'trial-legacy@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'trial-subscriber@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '99100000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'trial-outsider@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp());

insert into public.platform_administrators(user_id)
values ('99100000-0000-4000-8000-000000000001');

update public.application_user_authorizations
set status = 'active', account_mode = 'autonomous', status_changed_at = statement_timestamp()
where user_id::text like '99100000-0000-4000-8000-%';

insert into public.account_trials(user_id, terms_version, terms_accepted_at, started_at, ends_at, deletion_eligible_at)
values
  ('99100000-0000-4000-8000-000000000002', 'trial-30-plus-30-v1', statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days', statement_timestamp() + interval '59 days'),
  ('99100000-0000-4000-8000-000000000003', 'trial-30-plus-30-v1', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days'),
  ('99100000-0000-4000-8000-000000000005', 'trial-30-plus-30-v1', statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days', statement_timestamp() + interval '59 days');

insert into public.account_trial_legacy_access(user_id, reason)
values ('99100000-0000-4000-8000-000000000004', 'active_before_trial_cutover');

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status,
  current_period_started_at, current_period_ends_at
) values (
  '99100000-0000-4000-8000-000000000005', 'essential', 'included', 'active',
  statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days'
);

select set_config('request.jwt.claims', json_build_object(
  'sub', '99100000-0000-4000-8000-000000000006', 'role', 'authenticated'
)::text, true);

select extensions.throws_ok(
  $$select * from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000002'::uuid])$$,
  '42501',
  'Acces administrateur requis.',
  'un utilisateur exterieur ne peut pas lire les essais'
);

select set_config('request.jwt.claims', json_build_object(
  'sub', '99100000-0000-4000-8000-000000000001', 'role', 'authenticated'
)::text, true);

select extensions.is(
  (select state from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000002'::uuid])),
  'active',
  'un essai en cours est identifie'
);
select extensions.is(
  (select state from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000003'::uuid])),
  'suspended',
  'un essai expire est identifie'
);
select extensions.is(
  (select state from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000004'::uuid])),
  'legacy_access',
  'un acces historique est identifie'
);
select extensions.is(
  (select state from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000005'::uuid])),
  'subscribed',
  'un abonnement commercial a priorite sur un essai encore date'
);
select extensions.is(
  (select count(*) from public.list_administrative_account_trial_states(array[
    '99100000-0000-4000-8000-000000000002'::uuid,
    '99100000-0000-4000-8000-000000000002'::uuid
  ])),
  1::bigint,
  'un identifiant repete ne duplique pas la projection'
);
select extensions.is(
  (select count(*) from public.list_administrative_account_trial_states(array['99100000-0000-4000-8000-000000000099'::uuid])),
  0::bigint,
  'un compte Auth absent ne produit aucune ligne'
);
select extensions.throws_ok(
  $$select * from public.list_administrative_account_trial_states(array_fill('99100000-0000-4000-8000-000000000002'::uuid, array[26]))$$,
  '22023',
  'Liste de comptes invalide.',
  'la RPC refuse plus que la page de 25 comptes'
);
select extensions.throws_ok(
  $$select * from public.list_administrative_account_trial_states(array[null]::uuid[])$$,
  '22023',
  'Liste de comptes invalide.',
  'la RPC refuse un identifiant nul'
);

select extensions.finish();
rollback;
