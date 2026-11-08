begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(20);

select extensions.has_function(
  'public',
  'list_administrative_account_entitlement_states',
  array['uuid[]'],
  'la projection administrative des droits existe'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.list_administrative_account_entitlement_states(uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_administrative_account_entitlement_states(uuid[])', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_administrative_account_entitlement_states(uuid[])', 'EXECUTE'),
  'seul authenticated peut appeler la RPC qui recontrole le role administrateur'
);

select extensions.ok(
  not has_table_privilege('authenticated', 'public.account_administrative_plan_assignments', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role', 'public.account_administrative_plan_assignments', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.account_administrative_entitlement_overrides', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role', 'public.account_administrative_entitlement_overrides', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.account_administrative_entitlement_events', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role', 'public.account_administrative_entitlement_events', 'SELECT,INSERT,UPDATE,DELETE'),
  'les trois tables techniques restent fermees'
);

select extensions.ok(
  position('reason' in pg_get_function_result(
    'public.list_administrative_account_entitlement_states(uuid[])'::regprocedure
  )) = 0,
  'la liste n expose ni motif ni historique complet'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('99200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', 'entitlement-state-' || n || '@example.test',
  'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()
from generate_series(1, 7) n;

update public.application_user_authorizations
set status = 'active',
    account_mode = case when user_id = '99200000-0000-4000-8000-000000000004' then 'collaborator' else 'autonomous' end,
    status_changed_at = statement_timestamp()
where user_id::text like '99200000-0000-4000-8000-%';

insert into public.platform_administrators(user_id)
values
  ('99200000-0000-4000-8000-000000000001'),
  ('99200000-0000-4000-8000-000000000007');

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status,
  current_period_started_at, current_period_ends_at
) values (
  '99200000-0000-4000-8000-000000000003', 'essential', 'included', 'active',
  statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','99200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99200000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select * from public.assign_administrative_plan(
  '99200000-0000-4000-8000-000000000002', 'essential', 'monthly', 'included',
  'Attribution de lecture', '99210000-0000-4000-8000-000000000001', 0
);
select * from public.assign_administrative_entitlement_override(
  '99200000-0000-4000-8000-000000000002', 'comfort', 'five',
  'Derogation de lecture', '99210000-0000-4000-8000-000000000002', 0
);
select * from public.assign_administrative_entitlement_override(
  '99200000-0000-4000-8000-000000000003', 'premium', 'ten',
  'Derogation commerciale de lecture', '99210000-0000-4000-8000-000000000003', 0
);

select set_config('request.jwt.claim.sub','99200000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"99200000-0000-4000-8000-000000000005","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select * from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000002'::uuid])$$,
  '42501',
  'Acces administrateur requis.',
  'un utilisateur ordinaire ne peut pas lire les droits des autres comptes'
);

select set_config('request.jwt.claim.sub','99200000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99200000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.list_administrative_account_entitlement_states(array[
    '99200000-0000-4000-8000-000000000002'::uuid,
    '99200000-0000-4000-8000-000000000002'::uuid
  ])),
  1::bigint,
  'un identifiant repete ne duplique pas la projection'
);

select extensions.is(
  (select count(*) from public.list_administrative_account_entitlement_states(array[
    '99200000-0000-4000-8000-000000000002'::uuid,
    '99200000-0000-4000-8000-000000000003'::uuid
  ]) where user_id = '99200000-0000-4000-8000-000000000006'),
  0::bigint,
  'la projection ne retourne aucun compte non demande'
);

select extensions.is(
  (select administrative_plan_key from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000002'::uuid])),
  'essential',
  'la formule administrative active est retournee'
);

select extensions.is(
  (select administrative_assignment_revision from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000002'::uuid])),
  1::bigint,
  'la revision de l attribution active est retournee'
);

select extensions.is(
  (select administrative_override_feature_plan_key from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000002'::uuid])),
  'comfort',
  'la derogation fonctionnelle active est retournee'
);

select extensions.is(
  (select effective_active_dossier_limit from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000002'::uuid])),
  5,
  'la capacite effective tient compte de la derogation'
);

select extensions.is(
  (select access_source from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000003'::uuid])),
  'commercial',
  'la base commerciale reste distincte de la derogation'
);

select extensions.is(
  (select base_plan_key from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000003'::uuid])),
  'essential',
  'la derogation ne modifie pas la formule commerciale de base'
);

select extensions.is(
  (select effective_plan_key from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000003'::uuid])),
  'premium',
  'la formule effective integre la derogation commerciale'
);

select extensions.is(
  (select plan_assignment_block_code from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000003'::uuid])),
  'commercial_subscription_active',
  'une attribution ne peut pas remplacer un abonnement commercial'
);

select extensions.is(
  (select entitlement_override_block_code from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000004'::uuid])),
  'account_not_autonomous',
  'un collaborateur est identifie comme non modifiable'
);

select extensions.is(
  (select plan_assignment_block_code from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000007'::uuid])),
  'platform_administrator',
  'un administrateur cible est identifie comme non modifiable'
);

select extensions.is(
  (select entitlement_override_block_code from public.list_administrative_account_entitlement_states(array['99200000-0000-4000-8000-000000000006'::uuid])),
  'entitlement_base_required',
  'un compte sans base commerciale ou administrative ne peut pas recevoir de derogation'
);

select extensions.throws_ok(
  $$select * from public.list_administrative_account_entitlement_states(array_fill('99200000-0000-4000-8000-000000000002'::uuid, array[26]))$$,
  '22023',
  'Liste de comptes invalide.',
  'la RPC refuse plus que la page de 25 comptes'
);

select extensions.throws_ok(
  $$select * from public.list_administrative_account_entitlement_states(array[null]::uuid[])$$,
  '22023',
  'Liste de comptes invalide.',
  'la RPC refuse un identifiant nul'
);

select extensions.finish();
rollback;
