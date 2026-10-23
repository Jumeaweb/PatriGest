begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
('00000000-0000-0000-0000-000000000000','9c000000-0000-4000-8000-000000000001',
 'authenticated','authenticated','terminal-actor-1@example.test','',now(),
 '{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','9c000000-0000-4000-8000-000000000002',
 'authenticated','authenticated','terminal-actor-2@example.test','',now(),
 '{"provider":"email","providers":["email"]}','{}',now(),now());

update public.application_user_authorizations
set status='active', account_mode='autonomous', status_changed_at=now()
where user_id in (
  '9c000000-0000-4000-8000-000000000001',
  '9c000000-0000-4000-8000-000000000002'
);

insert into public.account_subscriptions(owner_id,status,started_at)
values('9c000000-0000-4000-8000-000000000001','development',now());

insert into public.protected_persons(id,owner_id,first_name,last_name)
values('9c000000-0000-4000-8100-000000000001',
       '9c000000-0000-4000-8000-000000000001','Audit','Terminal');

insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, closed_at, resolution_by, resolution_reason,
  resolution_at
) values (
  '9c000000-0000-4000-8200-000000000001',
  '9c000000-0000-4000-8100-000000000001',
  '9c000000-0000-4000-8000-000000000002',
  '9c000000-0000-4000-8000-000000000002',
  'system','administrative_repair','protected_person',
  '9c000000-0000-4000-8100-000000000001',
  '9c000000-0000-4000-8300-000000000001',
  'administratively_resolved','[]'::jsonb,clock_timestamp(),
  '9c000000-0000-4000-8000-000000000002',
  'Résolution de test',clock_timestamp()
);

select extensions.lives_ok(
  $$delete from auth.users where id='9c000000-0000-4000-8000-000000000002'$$,
  'la suppression Auth anonymise les acteurs d’une opération terminale'
);

select extensions.ok(
  (
    select initiated_by is null
       and resolution_by is null
       and initiator_subject_id='9c000000-0000-4000-8000-000000000002'
       and state='administratively_resolved'
    from public.document_operations
    where id='9c000000-0000-4000-8200-000000000001'
  ),
  'les références Auth sont nulles et l’identité durable reste intacte'
);

select extensions.throws_ok(
  $$update public.document_operations
    set initiated_by='9c000000-0000-4000-8000-000000000001'
    where id='9c000000-0000-4000-8200-000000000001'$$,
  '23514','Une opération documentaire terminale est immuable.',
  'un acteur anonymisé ne peut pas être réattribué'
);

select extensions.throws_ok(
  $$update public.document_operations
    set safe_error_code='ALTERED'
    where id='9c000000-0000-4000-8200-000000000001'$$,
  '23514','Une opération documentaire terminale est immuable.',
  'les autres champs d’une opération terminale restent immuables'
);

select * from extensions.finish();
rollback;

