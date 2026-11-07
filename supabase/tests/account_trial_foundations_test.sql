begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public', 'account_trials', 'la chronologie unique des essais existe');
select extensions.has_table('public', 'account_trial_events', 'la preuve minimale et les evenements existent');
select extensions.has_table('public', 'account_trial_purge_requests', 'le contrat de reprise de purge existe');
select extensions.has_function('public', 'get_current_account_trial_state', array[]::text[], 'la RPC de lecture personnelle existe');
select extensions.has_function('public', 'prepare_account_trial_purge', array['uuid', 'uuid'], 'la preparation idempotente de purge existe');

select extensions.is(
  (select count(*) from public.account_trial_legacy_access),
  (
    select count(*)
    from public.application_user_authorizations user_authorization
    join auth.users existing_user on existing_user.id = user_authorization.user_id
    where user_authorization.status = 'active'
  ),
  'les exemptions historiques concernent exactement les comptes Auth actifs existants'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_current_account_trial_state()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_current_account_trial_state()', 'EXECUTE'),
  'seul un utilisateur authentifie peut lire son etat'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.record_account_trial_terms_acceptance(uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.record_account_trial_terms_acceptance(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.record_account_trial_terms_acceptance(uuid,text)', 'EXECUTE'),
  'le consentement ne peut etre enregistre que par le serveur privilegie'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.account_trials', 'SELECT')
  and not has_table_privilege('service_role', 'public.account_trials', 'INSERT,UPDATE,DELETE'),
  'les tables techniques ne sont pas accessibles directement'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('99000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', 'trial-' || n || '@example.test', 'test',
  clock_timestamp(), '{}', '{}', clock_timestamp(), clock_timestamp()
from generate_series(1, 7) n;

insert into public.account_trials(
  user_id, terms_version, terms_accepted_at, started_at, ends_at, deletion_eligible_at
) values
  ('99000000-0000-4000-8000-000000000001', 'trial-30-plus-30-v1', statement_timestamp() - interval '29 days', statement_timestamp() - interval '29 days', statement_timestamp() + interval '1 day', statement_timestamp() + interval '31 days'),
  ('99000000-0000-4000-8000-000000000002', 'trial-30-plus-30-v1', statement_timestamp() - interval '30 days', statement_timestamp() - interval '30 days', statement_timestamp(), statement_timestamp() + interval '30 days'),
  ('99000000-0000-4000-8000-000000000003', 'trial-30-plus-30-v1', statement_timestamp() - interval '60 days', statement_timestamp() - interval '60 days', statement_timestamp() - interval '30 days', statement_timestamp()),
  ('99000000-0000-4000-8000-000000000004', 'trial-30-plus-30-v1', statement_timestamp() - interval '31 days', statement_timestamp() - interval '31 days', statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days'),
  ('99000000-0000-4000-8000-000000000005', 'trial-30-plus-30-v1', statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day', statement_timestamp() + interval '29 days', statement_timestamp() + interval '59 days');

update public.application_user_authorizations
set status = 'active',
    account_mode = case
      when user_id = '99000000-0000-4000-8000-000000000002' then 'collaborator'
      else 'autonomous'
    end,
    status_changed_at = clock_timestamp()
where user_id::text like '99000000-0000-4000-8000-%';

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at,
  current_period_started_at, current_period_ends_at
) values (
  '99000000-0000-4000-8000-000000000004', 'essential', 'included', 'active',
  clock_timestamp() - interval '1 day', clock_timestamp() - interval '1 day', clock_timestamp() + interval '29 days'
);

update public.account_trial_runtime_config
set enforcement_enabled = true, updated_at = clock_timestamp()
where singleton;

select extensions.is(
  (select state from public.compute_account_trial_state(
    '99000000-0000-4000-8000-000000000001',
    (select started_at + interval '29 days' from public.account_trials where user_id = '99000000-0000-4000-8000-000000000001')
  )),
  'active',
  'J29 reste dans la periode active'
);
select extensions.is(
  (select remaining_days from public.compute_account_trial_state(
    '99000000-0000-4000-8000-000000000001',
    (select started_at + interval '29 days' from public.account_trials where user_id = '99000000-0000-4000-8000-000000000001')
  )),
  1,
  'J29 affiche un jour restant'
);
select extensions.is(
  (select state from public.compute_account_trial_state(
    '99000000-0000-4000-8000-000000000001',
    (select started_at + interval '30 days' from public.account_trials where user_id = '99000000-0000-4000-8000-000000000001')
  )),
  'suspended',
  'la borne exacte J30 suspend l acces'
);
select extensions.is(
  (select state from public.compute_account_trial_state(
    '99000000-0000-4000-8000-000000000001',
    (select started_at + interval '60 days' from public.account_trials where user_id = '99000000-0000-4000-8000-000000000001')
  )),
  'deletion_due',
  'la borne exacte J60 rend le compte eligible a la purge'
);
select extensions.is(
  (select state from public.compute_account_trial_state('99000000-0000-4000-8000-000000000004', clock_timestamp())),
  'subscribed',
  'un abonnement commercial confirme avant J60 restaure l acces'
);

select set_config('request.jwt.claims', json_build_object(
  'sub', '99000000-0000-4000-8000-000000000001', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select extensions.ok(public.is_application_user_active(), 'un essai actif autorise les fonctions metier');
reset role;

select set_config('request.jwt.claims', json_build_object(
  'sub', '99000000-0000-4000-8000-000000000002', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select extensions.ok(not public.is_application_user_active(), 'un compte a J30 ne peut plus appeler les RPC metier');
reset role;

insert into public.protected_persons(id, owner_id, first_name, last_name, status)
values ('99010000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', 'Fixture', 'Essai', 'active');
insert into public.protected_person_access(protected_person_id, user_id, role, invited_by)
values ('99010000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000002', 'manager', '99000000-0000-4000-8000-000000000001');

select set_config('request.jwt.claims', json_build_object(
  'sub', '99000000-0000-4000-8000-000000000002', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select extensions.ok(
  not public.can_read_protected_person('99010000-0000-4000-8000-000000000001'),
  'un partage ne contourne pas la suspension du gestionnaire'
);
select extensions.ok(
  not public.can_manage_protected_person('99010000-0000-4000-8000-000000000001'),
  'les mutations partagees restent bloquees pour le compte suspendu'
);
reset role;

select extensions.is(
  (select active_dossier_limit from public.compute_account_trial_state('99000000-0000-4000-8000-000000000001', clock_timestamp())),
  2,
  'le plafond d essai provient de la capacite incluse de deux dossiers'
);

select extensions.throws_ok(
  $$select public.record_account_trial_terms_acceptance(
    '99000000-0000-4000-8000-000000000001', 'trial-30-plus-30-v2'
  )$$,
  'P4T02',
  'Version des conditions invalide.',
  'une autre version ne renouvelle pas un essai existant'
);

select extensions.lives_ok(
  $$select public.prepare_account_trial_purge(
    '99000000-0000-4000-8000-000000000003',
    '99020000-0000-4000-8000-000000000001'
  )$$,
  'la preparation de purge est possible a J60'
);
select extensions.lives_ok(
  $$select public.prepare_account_trial_purge(
    '99000000-0000-4000-8000-000000000003',
    '99020000-0000-4000-8000-000000000001'
  )$$,
  'la meme demande de purge est rejouable sans doublon'
);
select extensions.is(
  (select count(*)::integer from public.account_trial_purge_requests where user_id = '99000000-0000-4000-8000-000000000003'),
  1,
  'le rejeu ne duplique pas la preparation de purge'
);
select extensions.ok(
  exists (select 1 from auth.users where id = '99000000-0000-4000-8000-000000000003'),
  'PAT-TRIAL-01 ne supprime aucun utilisateur reel ou fictif'
);

select extensions.throws_ok(
  $$select public.prepare_account_trial_purge(
    '99000000-0000-4000-8000-000000000004',
    '99020000-0000-4000-8000-000000000002'
  )$$,
  'P4T05',
  'Compte non eligible a la purge.',
  'un abonnement actif interdit la preparation de purge'
);

select extensions.finish();
rollback;
