begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(27);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '61000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'email-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '61000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'email-collaborator@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '61000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'email-mode-null@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '61000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'email-admin@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '61000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'email-pending-source@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active'
where user_id in (
  '61000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000002',
  '61000000-0000-4000-8000-000000000003',
  '61000000-0000-4000-8000-000000000005'
);

insert into public.platform_administrators (user_id)
values ('61000000-0000-4000-8000-000000000004');

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('61000000-0000-4000-8000-000000000101', '61000000-0000-4000-8000-000000000001', 'Email', 'Owner');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values (
  '61000000-0000-4000-8000-000000000201',
  '61000000-0000-4000-8000-000000000101',
  '61000000-0000-4000-8000-000000000002',
  'read_only',
  '61000000-0000-4000-8000-000000000001'
);

insert into public.protected_person_invitations (
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
)
values (
  '61000000-0000-4000-8000-000000000301',
  '61000000-0000-4000-8000-000000000101',
  'invite-active@example.test',
  'read_only',
  repeat('1', 64),
  now() + interval '1 day',
  '61000000-0000-4000-8000-000000000001'
);

insert into public.account_requests (
  id, email, first_name, last_name, status
)
values (
  '61000000-0000-4000-8000-000000000401',
  'request-active@example.test',
  'Active',
  'Request',
  'pending'
);

select extensions.has_function(
  'public', 'check_own_email_change_availability', array['text'],
  'the authenticated preflight function exists'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.check_own_email_change_availability(text)', 'EXECUTE'),
  'authenticated users may execute the email change preflight'
);

select extensions.ok(
  position('pg_advisory_xact_lock' in lower(pg_get_functiondef('public.lock_patrigest_email(text)'::regprocedure))) > 0,
  'all email reservations use a transaction advisory lock'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000001', 'email', 'email-owner@example.test', 'role', 'authenticated')::text,
  true
);

select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('  INVITE-ACTIVE@EXAMPLE.TEST  ') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an autonomous account cannot claim a case-varied active invitation email'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000003', 'email', 'email-mode-null@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('invite-active@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'a mode-null account cannot claim an active invitation email'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000002', 'email', 'email-collaborator@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('request-active@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'a collaborator cannot claim an active autonomous reservation'
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('email-owner@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'a collaborator cannot claim an autonomous identity email'
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('email-admin@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'a collaborator cannot claim a platform administrator email'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000001', 'email', 'email-owner@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('email-collaborator@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an autonomous account cannot claim a collaborator identity email'
);

reset role;

update auth.users
set email_change = 'email-pending-target@example.test'
where id = '61000000-0000-4000-8000-000000000005';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000001', 'email', 'email-owner@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.throws_ok(
  $$ select public.check_own_email_change_availability('email-pending-target@example.test') $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'another pending Auth email change reserves its target'
);

reset role;

select extensions.throws_ok(
  $$
    update auth.users
    set email_change = 'invite-active@example.test'
    where id = '61000000-0000-4000-8000-000000000003'
  $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'the auth.users trigger authoritatively rejects an active invitation collision'
);

select extensions.is(
  (select accepted_at from public.protected_person_invitations where id = '61000000-0000-4000-8000-000000000301'),
  null::timestamptz,
  'a rejected email change does not consume the invitation'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '61000000-0000-4000-8000-000000000101',
      ' EMAIL-PENDING-TARGET@EXAMPLE.TEST ',
      'read_only', repeat('2', 64), now() + interval '1 day',
      '61000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an invitation cannot win after an Auth email target is pending'
);

select extensions.throws_ok(
  $$
    insert into public.account_requests (email, first_name, last_name)
    values (' EMAIL-PENDING-TARGET@EXAMPLE.TEST ', 'Pending', 'Auth')
  $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an account request cannot win after an Auth email target is pending'
);

insert into public.protected_person_invitations (
  id, protected_person_id, email, role, token_hash, expires_at, accepted_at, revoked_at, invited_by
)
values
  ('61000000-0000-4000-8000-000000000302', '61000000-0000-4000-8000-000000000101', 'invite-accepted@example.test', 'read_only', repeat('3', 64), now() + interval '1 day', now(), null, '61000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-8000-000000000303', '61000000-0000-4000-8000-000000000101', 'invite-revoked@example.test', 'read_only', repeat('4', 64), now() + interval '1 day', null, now(), '61000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-8000-000000000304', '61000000-0000-4000-8000-000000000101', 'invite-expired@example.test', 'read_only', repeat('5', 64), now() - interval '1 minute', null, null, '61000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000003', 'email', 'email-mode-null@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('invite-accepted@example.test') $$,
  'an accepted invitation is historical and does not reserve the email'
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('invite-revoked@example.test') $$,
  'a revoked invitation is historical and does not reserve the email'
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('invite-expired@example.test') $$,
  'an expired invitation is historical and does not reserve the email'
);
reset role;

insert into public.account_requests (
  id, email, first_name, last_name, status, invitation_expires_at, invitation_used_at
)
values
  ('61000000-0000-4000-8000-000000000402', 'request-rejected@example.test', 'Rejected', 'Request', 'rejected', null, null),
  ('61000000-0000-4000-8000-000000000403', 'request-used@example.test', 'Used', 'Request', 'approved', now() + interval '1 day', now()),
  ('61000000-0000-4000-8000-000000000404', 'request-expired@example.test', 'Expired', 'Request', 'approved', now() - interval '1 minute', null);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '61000000-0000-4000-8000-000000000003', 'email', 'email-mode-null@example.test', 'role', 'authenticated')::text,
  true
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('request-rejected@example.test') $$,
  'a rejected account request does not reserve the email'
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('request-used@example.test') $$,
  'a used approved account request does not reserve the email'
);
select extensions.lives_ok(
  $$ select public.check_own_email_change_availability('request-expired@example.test') $$,
  'an expired approved account request does not reserve the email'
);
reset role;

select extensions.throws_ok(
  $$
    insert into public.protected_person_invitations (
      protected_person_id, email, role, token_hash, expires_at, invited_by
    ) values (
      '61000000-0000-4000-8000-000000000101',
      'request-active@example.test',
      'read_only', repeat('6', 64), now() + interval '1 day',
      '61000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an active account request blocks a collaborator invitation'
);

select extensions.throws_ok(
  $$
    insert into public.account_requests (email, first_name, last_name)
    values ('invite-active@example.test', 'Invite', 'Collision')
  $$,
  'P0001',
  'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.',
  'an active collaborator invitation blocks an autonomous account request'
);

select extensions.throws_ok(
  $$
    insert into public.protected_person_access (protected_person_id, user_id, role, invited_by)
    values (
      '61000000-0000-4000-8000-000000000101',
      '61000000-0000-4000-8000-000000000001',
      'read_only',
      '61000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'Un compte autonome ne peut pas devenir collaborateur.',
  'LOT 0A still prevents an autonomous account from becoming a collaborator'
);

select extensions.is(
  (select count(*)::integer from public.protected_person_access where user_id = '61000000-0000-4000-8000-000000000001'),
  0,
  'a failed LOT 0A transition creates no access'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '61000000-0000-4000-8000-000000000002'),
  'collaborator',
  'the collaborator account mode remains unchanged'
);

select extensions.is(
  (select account_mode from public.application_user_authorizations where user_id = '61000000-0000-4000-8000-000000000003'),
  null::text,
  'a rejected address collision does not assign a mode-null account'
);

select extensions.is(
  (select count(*)::integer from public.protected_person_invitations where accepted_at is null and revoked_at is null and expires_at > now()),
  1,
  'failed collisions do not create or consume active invitations'
);

select * from extensions.finish();

rollback;
