begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_column(
  'public', 'application_user_authorizations', 'registration_intent',
  'l intention d inscription est explicite'
);
select extensions.has_column(
  'public', 'application_user_authorizations', 'autonomous_registration_status',
  'la validation autonome est distincte de l acces applicatif'
);
select extensions.has_function(
  'public', 'complete_own_autonomous_trial_registration', array[]::text[],
  'la reprise authentifiee du consentement existe'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.complete_own_autonomous_trial_registration()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.complete_own_autonomous_trial_registration()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.complete_own_autonomous_trial_registration()', 'EXECUTE'),
  'la reprise est reservee au compte authentifie'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '98300000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'registration-admin@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '98300000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'registration-owner@example.test', 'test', statement_timestamp(), '{}', '{"patrigest_registration_intent":"autonomous","patrigest_trial_terms_accepted":true,"patrigest_trial_terms_version":"trial-30-plus-30-v1"}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '98300000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'registration-collaborator@example.test', 'test', statement_timestamp(), '{}', '{"patrigest_registration_intent":"collaborator"}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '98300000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'registration-trial@example.test', 'test', statement_timestamp(), '{}', '{"patrigest_registration_intent":"autonomous","patrigest_trial_terms_accepted":true,"patrigest_trial_terms_version":"trial-30-plus-30-v1"}', statement_timestamp(), statement_timestamp());

insert into public.platform_administrators(user_id)
values ('98300000-0000-4000-8000-000000000001');

select extensions.is(
  (select registration_intent from public.application_user_authorizations where user_id = '98300000-0000-4000-8000-000000000002'),
  'autonomous',
  'une inscription publique cree une intention autonome en attente'
);
select extensions.is(
  (select autonomous_registration_status from public.application_user_authorizations where user_id = '98300000-0000-4000-8000-000000000002'),
  'pending',
  'la validation Jumeaweb reste requise'
);
select extensions.is(
  (select registration_intent from public.application_user_authorizations where user_id = '98300000-0000-4000-8000-000000000003'),
  'collaborator',
  'une invitation cree un parcours collaborateur distinct'
);
select extensions.is(
  (select count(*) from public.account_trials where user_id = '98300000-0000-4000-8000-000000000003'),
  0::bigint,
  'un collaborateur invite ne recoit aucun essai autonome'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98300000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"98300000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select extensions.lives_ok(
  $$select public.complete_own_autonomous_trial_registration()$$,
  'le titulaire confirme peut reprendre son consentement'
);
reset role;

select extensions.ok(
  exists (
    select 1 from public.account_trials
    where user_id = '98300000-0000-4000-8000-000000000002'
      and started_at is null
  ),
  'la reprise enregistre le consentement sans demarrer l essai avant validation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98300000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"98300000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select extensions.lives_ok(
  $$select public.complete_own_autonomous_trial_registration()$$,
  'le second titulaire confirme enregistre aussi son consentement avant validation'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98300000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"98300000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select extensions.throws_ok(
  $$select public.complete_own_autonomous_trial_registration()$$,
  'P4T08',
  'Inscription autonome requise.',
  'un collaborateur ne peut pas creer un essai par la RPC de reprise'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98300000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"98300000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.is(
  public.review_application_user_registration('98300000-0000-4000-8000-000000000002', 'active'),
  'active',
  'Jumeaweb active le titulaire apres confirmation et consentement'
);
select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98300000-0000-4000-8000-000000000002', 'essential', 'monthly', 'included',
    'Attribution avant premier dossier', '98310000-0000-4000-8000-000000000001', 0
  )$$,
  'une attribution administrative est possible avant le premier dossier'
);
select extensions.is(
  public.review_application_user_registration('98300000-0000-4000-8000-000000000004', 'active'),
  'active',
  'un second titulaire peut etre active pour verifier les exports d essai'
);
reset role;

select extensions.ok(
  exists (
    select 1 from public.account_trials
    where user_id = '98300000-0000-4000-8000-000000000002'
      and started_at is not null
  ),
  'l essai commence exactement lors de la validation autonome'
);
select extensions.ok(
  exists (
    select 1 from public.account_subscriptions
    where owner_id = '98300000-0000-4000-8000-000000000002'
      and status = 'development'
  ),
  'le quota de deux dossiers est provisionne avant le premier dossier'
);

-- Le second titulaire reste en essai, sans attribution administrative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98300000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"98300000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select extensions.lives_ok(
  $$insert into public.protected_persons(id, owner_id, first_name, last_name, status)
    values ('98320000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000004', 'Essai', 'Export', 'active')$$,
  'le premier dossier d essai respecte le quota'
);
select extensions.ok(
  (select can_read from public.get_protected_person_feature_capabilities('98320000-0000-4000-8000-000000000001') where feature_key = 'data_export'),
  'l export est accessible pendant l essai actif'
);
reset role;

-- Un titulaire autonome peut aussi recevoir un acces partage sans perdre son mode.
insert into public.protected_persons(id, owner_id, first_name, last_name, status)
values ('98320000-0000-4000-8000-000000000002', '98300000-0000-4000-8000-000000000002', 'Compte', 'Partage', 'active');
insert into public.protected_person_access(protected_person_id, user_id, role, invited_by)
values ('98320000-0000-4000-8000-000000000002', '98300000-0000-4000-8000-000000000004', 'read_only', '98300000-0000-4000-8000-000000000002');
select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '98300000-0000-4000-8000-000000000004'),
  'autonomous',
  'un titulaire conserve son mode autonome lorsqu il devient aussi collaborateur'
);

select extensions.is(
  (select enforcement_enabled from public.account_trial_runtime_config where singleton),
  false,
  'PAT-INSCRIPTION-01B ne reactive pas les restrictions J30 J60'
);

select extensions.finish();
rollback;
