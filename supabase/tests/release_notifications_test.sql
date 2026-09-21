begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(17);

select extensions.has_table('public', 'release_notifications', 'release notifications table exists');
select extensions.has_column('public', 'release_notifications', 'version', 'version column exists');
select extensions.has_column('public', 'release_notifications', 'delivery_kind', 'delivery kind column exists');
select extensions.has_column('public', 'release_notifications', 'provider_message_id', 'provider message id column exists');
select extensions.ok((select relrowsecurity from pg_class where oid = 'public.release_notifications'::regclass), 'RLS is enabled');
select extensions.ok(not has_table_privilege('authenticated', 'public.release_notifications', 'SELECT'), 'authenticated cannot select notifications');
select extensions.ok(not has_table_privilege('authenticated', 'public.release_notifications', 'INSERT'), 'authenticated cannot insert notifications');
select extensions.ok(not has_table_privilege('authenticated', 'public.release_notifications', 'UPDATE'), 'authenticated cannot update notifications');
select extensions.ok(not has_table_privilege('authenticated', 'public.release_notifications', 'DELETE'), 'authenticated cannot delete notifications');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '33000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'release@example.test', 'hash', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role service_role;

select extensions.lives_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind, status, attempt_count
  ) values (
    '0.7.0', '33000000-0000-4000-8000-000000000001',
    'release@example.test', 'global', 'sending', 1
  )
$$, 'service role reserves one global notification');

select extensions.throws_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind
  ) values (
    '0.7.0', '33000000-0000-4000-8000-000000000001',
    'release@example.test', 'global'
  )
$$, '23505', null, 'one global notification exists per version and user');

select extensions.lives_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind, status, attempt_count, sent_at
  ) values
    ('0.7.0', '33000000-0000-4000-8000-000000000001', 'release@example.test', 'test', 'sent', 1, now()),
    ('0.7.0', '33000000-0000-4000-8000-000000000001', 'release@example.test', 'test', 'sent', 1, now())
$$, 'multiple test notifications are allowed');

select extensions.is(
  (select count(*) from public.release_notifications where delivery_kind = 'test'),
  2::bigint,
  'test notifications are independent from global state'
);

select extensions.throws_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind
  ) values (
    '0.7.0', '33000000-0000-4000-8000-000000000001',
    'release@example.test', 'other'
  )
$$, '23514', null, 'invalid delivery kind is rejected');

select extensions.throws_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind, status
  ) values (
    '0.8.0', '33000000-0000-4000-8000-000000000001',
    'release@example.test', 'global', 'unknown'
  )
$$, '23514', null, 'invalid status is rejected');

select extensions.throws_ok($$
  insert into public.release_notifications (
    version, user_id, email_snapshot, delivery_kind, attempt_count
  ) values (
    '0.8.0', '33000000-0000-4000-8000-000000000001',
    'release@example.test', 'global', -1
  )
$$, '23514', null, 'negative attempt count is rejected');

update public.release_notifications
set status = 'failed', last_error_safe = 'Échec de l’envoi e-mail.'
where delivery_kind = 'global';

select extensions.lives_ok($$
  update public.release_notifications
  set status = 'sending', attempt_count = attempt_count + 1, last_error_safe = null
  where version = '0.7.0'
    and user_id = '33000000-0000-4000-8000-000000000001'
    and delivery_kind = 'global'
    and status = 'failed'
$$, 'failed global notification can be reserved for retry');

reset role;
select extensions.finish();
rollback;
