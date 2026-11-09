begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(11);

select extensions.has_table(
  'public',
  'registration_rejection_notifications',
  'le registre prive des notifications de refus existe'
);

select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.registration_rejection_notifications'::regclass),
  'RLS est activee sur le registre'
);

select extensions.ok(
  not exists (
    select 1
    from pg_class relation
    cross join lateral aclexplode(coalesce(relation.relacl, acldefault('r', relation.relowner))) privilege
    where relation.oid = 'public.registration_rejection_notifications'::regclass
      and privilege.grantee = 0
      and privilege.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'PUBLIC ne dispose d aucun acces direct'
);

select extensions.ok(
  not has_table_privilege('anon', 'public.registration_rejection_notifications', 'SELECT,INSERT,UPDATE,DELETE'),
  'anon ne dispose d aucun acces direct'
);

select extensions.ok(
  not has_table_privilege('authenticated', 'public.registration_rejection_notifications', 'SELECT,INSERT,UPDATE,DELETE'),
  'authenticated ne dispose d aucun acces direct'
);

select extensions.ok(
  has_table_privilege('service_role', 'public.registration_rejection_notifications', 'SELECT,INSERT,UPDATE')
  and not has_table_privilege('service_role', 'public.registration_rejection_notifications', 'DELETE'),
  'service_role peut suivre les envois sans les supprimer'
);

select extensions.col_is_pk(
  'public',
  'registration_rejection_notifications',
  'user_id',
  'une seule notification logique existe par inscription refusee'
);

select extensions.ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.registration_rejection_notifications'::regclass
      and conname = 'registration_rejection_notifications_sent_check'
  ),
  'un envoi marque sent exige une date d envoi'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '98400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rejection-admin@example.test', 'test', statement_timestamp(), '{}', '{}', statement_timestamp(), statement_timestamp()),
  ('00000000-0000-0000-0000-000000000000', '98400000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rejection-owner@example.test', 'test', statement_timestamp(), '{}', '{"patrigest_registration_intent":"autonomous"}', statement_timestamp(), statement_timestamp());

insert into public.platform_administrators(user_id)
values ('98400000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '98400000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"98400000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.is(
  public.review_application_user_registration('98400000-0000-4000-8000-000000000002', 'rejected'),
  'rejected',
  'le refus administratif reste operationnel'
);
reset role;

select extensions.is(
  (select autonomous_registration_status from public.application_user_authorizations where user_id = '98400000-0000-4000-8000-000000000002'),
  'rejected',
  'le compte reste refuse sans acces autonome'
);

select extensions.ok(
  not exists (
    select 1 from public.account_trials
    where user_id = '98400000-0000-4000-8000-000000000002'
      and started_at is not null
  ),
  'le refus ne demarre aucun essai gratuit'
);

select * from extensions.finish();
rollback;
