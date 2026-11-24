begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(40);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'mode-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'mode-collaborator@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"patrigest_registration_intent":"collaborator"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'mode-future-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'mode-second-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'mode-direct-collaborator@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"patrigest_registration_intent":"collaborator"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'mode-admin@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'mode-invalid@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active'
where user_id in (
  '60000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000003',
  '60000000-0000-4000-8000-000000000004',
  '60000000-0000-4000-8000-000000000005'
);

insert into public.platform_administrators (user_id)
values ('60000000-0000-4000-8000-000000000006');

select extensions.has_column(
  'public', 'application_user_authorizations', 'account_mode',
  'application authorization stores the exclusive account mode'
);

select extensions.ok(
  has_column_privilege('authenticated', 'public.application_user_authorizations', 'account_mode', 'SELECT'),
  'authenticated users may read their account mode through RLS'
);

select extensions.ok(
  not has_column_privilege('authenticated', 'public.application_user_authorizations', 'account_mode', 'UPDATE'),
  'authenticated users cannot freely convert their account mode'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('60000000-0000-4000-8000-000000000101', '60000000-0000-4000-8000-000000000001', 'Premier', 'Dossier'),
  ('60000000-0000-4000-8000-000000000102', '60000000-0000-4000-8000-000000000004', 'Second', 'Dossier');

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000001'),
  'autonomous',
  'creating a first dossier assigns autonomous mode'
);

insert into public.protected_person_invitations (
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
)
values (
  '60000000-0000-4000-8000-000000000201',
  '60000000-0000-4000-8000-000000000101',
  ' MODE-PENDING@EXAMPLE.TEST ',
  'read_only',
  repeat('a', 64),
  now() + interval '1 day',
  '60000000-0000-4000-8000-000000000001'
);

select extensions.is(
  (select email from public.protected_person_invitations where id = '60000000-0000-4000-8000-000000000201'),
  'mode-pending@example.test',
  'new invitation emails are normalized with lower trim'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '60000000-0000-4000-8000-000000000008',
  'authenticated', 'authenticated', 'mode-pending@example.test', 'test-hash', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"patrigest_registration_intent":"autonomous"}'::jsonb,
  now(), now()
);

insert into public.account_trials(user_id, terms_version, terms_accepted_at)
select
  '60000000-0000-4000-8000-000000000008',
  current_terms_version,
  statement_timestamp()
from public.account_trial_runtime_config
where singleton;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-4000-8000-000000000006',
    'email', 'mode-admin@example.test',
    'role', 'authenticated'
  )::text,
  true
);

select extensions.throws_ok(
  $$ select public.review_application_user_registration('60000000-0000-4000-8000-000000000008', 'active') $$,
  'P4M03',
  'L activation du compte autonome est impossible tant qu une invitation collaborateur est active pour cette adresse. Utilisez une adresse électronique distincte ou refusez l invitation.',
  'administrative activation is blocked while a collaborator invitation is active'
);

reset role;

select extensions.is(
  (select autonomous_registration_status from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000008'),
  'pending',
  'failed activation preserves the pending autonomous registration'
);

select extensions.throws_ok(
  $$
    insert into public.protected_persons (owner_id, first_name, last_name)
    values ('60000000-0000-4000-8000-000000000008', 'Invitation', 'Active')
  $$,
  'P4M03',
  'L activation du compte autonome est impossible tant qu une invitation collaborateur est active pour cette adresse. Utilisez une adresse électronique distincte ou refusez l invitation.',
  'an active collaborator invitation blocks autonomous ownership'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-4000-8000-000000000008',
    'email', 'mode-pending@example.test',
    'role', 'authenticated'
  )::text,
  true
);

select extensions.throws_ok(
  $$ select public.accept_protected_person_invitation(repeat('a', 64)) $$,
  'P4M01',
  'Un compte autonome ne peut pas devenir collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.',
  'an autonomous registration cannot accept a collaborator invitation'
);

reset role;

select extensions.ok(
  (select accepted_at is null from public.protected_person_invitations where id = '60000000-0000-4000-8000-000000000201')
  and not exists (
    select 1 from public.protected_person_access
    where user_id = '60000000-0000-4000-8000-000000000008'
  ),
  'failed acceptance preserves the pending invitation without creating access'
);

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('60000000-0000-4000-8000-000000000103', '60000000-0000-4000-8000-000000000003', 'Futur', 'Autonome');

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000003'),
  'autonomous',
  'creating a first dossier assigns autonomous mode to an autonomous registration'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '60000000-0000-4000-8000-000000000101',
      ' MODE-FUTURE-OWNER@EXAMPLE.TEST ',
      'read_only',
      repeat('9', 64),
      now() + interval '1 day',
      '60000000-0000-4000-8000-000000000001'
    )
  $$,
  'P4M01',
  'Un compte autonome ne peut pas être invité comme collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.',
  'an autonomous account cannot be invited to another dossier'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '60000000-0000-4000-8000-000000000101',
      'mode-owner@example.test',
      'manager',
      repeat('b', 64),
      now() + interval '1 day',
      '60000000-0000-4000-8000-000000000001'
    )
  $$,
  'P4I01',
  'Le propriétaire du dossier ne peut pas être invité comme collaborateur.',
  'a dossier owner cannot invite themselves as a collaborator'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '60000000-0000-4000-8000-000000000101',
      ' MODE-OWNER@EXAMPLE.TEST ',
      'read_only',
      repeat('c', 64),
      now() + interval '1 day',
      '60000000-0000-4000-8000-000000000001'
    )
  $$,
  'P4I01',
  'Le propriétaire du dossier ne peut pas être invité comme collaborateur.',
  'owner self-invitation detection normalizes email case and spaces'
);

insert into public.protected_person_invitations (
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
)
values (
  '60000000-0000-4000-8000-000000000202',
  '60000000-0000-4000-8000-000000000101',
  'mode-collaborator@example.test',
  'manager',
  repeat('d', 64),
  now() + interval '1 day',
  '60000000-0000-4000-8000-000000000001'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000002'),
  null::text,
  'the invitee has no mode before first acceptance'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-4000-8000-000000000002',
    'email', 'mode-collaborator@example.test',
    'role', 'authenticated'
  )::text,
  true
);

select extensions.lives_ok(
  $$ select public.accept_protected_person_invitation(repeat('d', 64)) $$,
  'accepting the first invitation succeeds'
);

reset role;

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000002'),
  'collaborator',
  'accepting the first invitation assigns collaborator mode'
);

select extensions.is(
  (select status from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000002'),
  'active',
  'invitation acceptance still activates a pending application account'
);

select extensions.is(
  (select role from public.protected_person_access where protected_person_id = '60000000-0000-4000-8000-000000000101' and user_id = '60000000-0000-4000-8000-000000000002'),
  'manager',
  'manager remains a dossier role independent from account mode'
);

insert into public.protected_person_invitations (
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
)
values (
  '60000000-0000-4000-8000-000000000203',
  '60000000-0000-4000-8000-000000000102',
  'mode-collaborator@example.test',
  'read_only',
  repeat('e', 64),
  now() + interval '1 day',
  '60000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', '60000000-0000-4000-8000-000000000002',
    'email', 'mode-collaborator@example.test',
    'role', 'authenticated'
  )::text,
  true
);

select extensions.lives_ok(
  $$ select public.accept_protected_person_invitation(repeat('e', 64)) $$,
  'a collaborator can accept access to another owner dossier'
);

reset role;

select extensions.is(
  (select count(*)::integer from public.protected_person_access where user_id = '60000000-0000-4000-8000-000000000002'),
  2,
  'a collaborator can access multiple dossiers'
);

select extensions.is(
  (select count(*)::integer from public.protected_person_access where user_id = '60000000-0000-4000-8000-000000000002' and role in ('manager', 'read_only')),
  2,
  'manager and read only roles do not change collaborator mode'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000002'),
  'collaborator',
  'multiple dossier roles preserve collaborator mode'
);

select extensions.throws_ok(
  $$
    insert into public.protected_persons (owner_id, first_name, last_name)
    values ('60000000-0000-4000-8000-000000000002', 'Interdit', 'Collaborateur')
  $$,
  'P4M02',
  'Un compte collaborateur ne peut pas créer ou posséder de dossier. Utilisez une adresse électronique distincte pour le compte autonome.',
  'a collaborator cannot create a dossier'
);

insert into public.protected_person_access (
  protected_person_id, user_id, role, invited_by
)
values (
  '60000000-0000-4000-8000-000000000102',
  '60000000-0000-4000-8000-000000000005',
  'read_only',
  '60000000-0000-4000-8000-000000000004'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000005'),
  'collaborator',
  'direct access creation also assigns collaborator mode'
);

select extensions.throws_ok(
  $$
    insert into public.protected_persons (owner_id, first_name, last_name)
    values ('60000000-0000-4000-8000-000000000006', 'Interdit', 'Administrateur')
  $$,
  'P0001',
  'Un administrateur de plateforme ne peut pas utiliser les fonctions métier.',
  'platform administrator still cannot own a dossier'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_access (protected_person_id, user_id, role, invited_by)
    values (
      '60000000-0000-4000-8000-000000000101',
      '60000000-0000-4000-8000-000000000006',
      'read_only',
      '60000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'Un administrateur de plateforme ne peut pas devenir collaborateur d''un dossier.',
  'platform administrator still cannot become a collaborator'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '60000000-0000-4000-8000-000000000101',
      'mode-admin@example.test',
      'read_only',
      repeat('f', 64),
      now() + interval '1 day',
      '60000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'Un administrateur de plateforme ne peut pas recevoir d''invitation métier.',
  'platform administrator still cannot be invited'
);

select extensions.ok(
  position('for update' in lower(pg_get_functiondef('public.claim_application_user_account_mode(uuid,text)'::regprocedure))) > 0,
  'first-use account mode claim locks the authorization row'
);

select extensions.ok(
  position('lock_patrigest_email' in lower(pg_get_functiondef('public.claim_application_user_account_mode(uuid,text)'::regprocedure))) > 0
  and position('lock_patrigest_email' in lower(pg_get_functiondef('public.reject_autonomous_protected_person_invitation()'::regprocedure))) > 0,
  'mode claims and invitations serialize concurrent decisions for the same email'
);

select extensions.ok(
  not has_function_privilege('anon', 'public.enforce_application_user_account_mode_exclusivity()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.enforce_application_user_account_mode_exclusivity()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.enforce_application_user_account_mode_exclusivity()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.enforce_collaborator_has_no_trial()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.enforce_collaborator_has_no_trial()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.enforce_collaborator_has_no_trial()', 'EXECUTE'),
  'new trigger functions are not directly callable by API roles'
);

select extensions.has_trigger(
  'public',
  'application_user_authorizations',
  'application_user_authorizations_enforce_mode_exclusivity',
  'direct authorization changes are protected by a database trigger'
);

select extensions.throws_ok(
  $$
    update public.application_user_authorizations
    set account_mode = 'collaborator'
    where user_id = '60000000-0000-4000-8000-000000000003'
  $$,
  'P4M04',
  'Le mode du compte ne correspond pas à son parcours d inscription.',
  'a privileged direct update cannot create a mixed account mode'
);

select extensions.is(
  (
    select count(*)::integer
    from public.application_user_authorizations user_authorization
    where user_authorization.account_mode = 'collaborator'
      and exists (select 1 from public.protected_persons persons where persons.owner_id = user_authorization.user_id)
  ),
  0,
  'a collaborator-only account still cannot own a dossier'
);

select extensions.throws_ok(
  $$
    update public.application_user_authorizations
    set account_mode = 'invalid'
    where user_id = '60000000-0000-4000-8000-000000000007'
  $$,
  '23514',
  null,
  'invalid account modes are rejected by the database constraint'
);

select extensions.is(
  (select count(*)::integer from public.protected_persons where owner_id = '60000000-0000-4000-8000-000000000002'),
  0,
  'failed collaborator ownership creates no dossier'
);

select extensions.ok(
  (select count(*) = 0 from public.protected_person_access where user_id = '60000000-0000-4000-8000-000000000003')
  and (select account_mode = 'autonomous' from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000003'),
  'an autonomous account never receives shared access'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '60000000-0000-4000-8000-000000000005'),
  'collaborator',
  'a direct collaborator cannot later drift to autonomous mode'
);

select extensions.throws_ok(
  $$
    update public.protected_person_invitations
    set email = ' MODE-OWNER@EXAMPLE.TEST '
    where id = '60000000-0000-4000-8000-000000000201'
  $$,
  'P4I01',
  'Le propriétaire du dossier ne peut pas être invité comme collaborateur.',
  'an invitation cannot be changed to target the dossier owner'
);

select extensions.ok(
  not has_function_privilege('anon', 'public.prevent_protected_person_owner_self_invitation()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.prevent_protected_person_owner_self_invitation()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.prevent_protected_person_owner_self_invitation()', 'EXECUTE'),
  'the trigger function is not directly executable by API roles'
);

select * from extensions.finish();

rollback;
