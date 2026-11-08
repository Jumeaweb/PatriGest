begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_column(
  'public', 'account_administrative_entitlement_events',
  'identifiers_anonymized_at',
  'le journal expose la date d anonymisation'
);
select extensions.has_function(
  'public', 'scrub_deleted_account_identifier', array['jsonb','uuid'],
  'la fonction recursive de retrait existe'
);
select extensions.has_trigger(
  'auth', 'users', 'auth_users_anonymize_administrative_entitlement_history',
  'la suppression Auth declenche le retrait des identifiants'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.scrub_deleted_account_identifier(jsonb,uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.scrub_deleted_account_identifier(jsonb,uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.anonymize_administrative_entitlement_history_on_auth_delete()', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.anonymize_administrative_entitlement_history_on_auth_delete()', 'EXECUTE'
  ),
  'les fonctions internes ne sont appelables par aucun role API'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '98600000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'admin-anonymization@example.test', 'test', clock_timestamp(), '{}', '{}',
   clock_timestamp(), clock_timestamp()),
  ('00000000-0000-0000-0000-000000000000',
   '98600000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'target-anonymization@example.test', 'test', clock_timestamp(), '{}', '{}',
   clock_timestamp(), clock_timestamp());

update public.application_user_authorizations
set status = 'active', account_mode = 'autonomous',
    status_changed_at = clock_timestamp()
where user_id in (
  '98600000-0000-4000-8000-000000000001',
  '98600000-0000-4000-8000-000000000002'
);

insert into public.platform_administrators(user_id)
values ('98600000-0000-4000-8000-000000000001');

insert into public.account_subscriptions(owner_id, status)
select '98600000-0000-4000-8000-000000000002', 'development'
where not exists (
  select 1 from public.account_subscriptions
  where owner_id = '98600000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '98600000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"98600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98600000-0000-4000-8000-000000000002',
    'comfort', 'annual', 'five', 'Decision conservee',
    '98610000-0000-4000-8000-000000000001', 0
  )$$,
  'une attribution de reference est creee'
);
reset role;

select extensions.is(
  (select count(*) from public.account_administrative_entitlement_events
   where owner_id = '98600000-0000-4000-8000-000000000002'),
  1::bigint,
  'l attribution produit un evenement nominatif avant suppression'
);
select extensions.ok(
  (select request_payload::text like '%98600000-0000-4000-8000-000000000002%'
   from public.account_administrative_entitlement_events
   where request_id = '98610000-0000-4000-8000-000000000001'),
  'le payload initial porte bien l identifiant cible'
);

select set_config(
  'patrigest.test_assignment_id',
  (select id::text from public.account_administrative_plan_assignments
   where owner_id = '98600000-0000-4000-8000-000000000002'),
  true
);
select set_config(
  'patrigest.test_assignment_revision',
  (select revision::text from public.account_administrative_plan_assignments
   where owner_id = '98600000-0000-4000-8000-000000000002'),
  true
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '98600000-0000-4000-8000-000000000001', true
);
select extensions.lives_ok(
  format(
    'select * from public.revoke_administrative_plan(%L,%L,%L,%L,%s)',
    '98600000-0000-4000-8000-000000000002',
    current_setting('patrigest.test_assignment_id'),
    'Revocation ordinaire',
    '98610000-0000-4000-8000-000000000002',
    current_setting('patrigest.test_assignment_revision')
  ),
  'une revocation ordinaire reste possible'
);
reset role;

select extensions.ok(
  (select bool_and(owner_id = '98600000-0000-4000-8000-000000000002'
                   and identifiers_anonymized_at is null)
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002'
   )),
  'une simple revocation ne declenche aucune anonymisation'
);

insert into public.account_administrative_entitlement_events(
  request_id, owner_id, entity_type, entity_id, action, actor_kind, actor_id,
  reason, before_state, after_state, request_payload, payload_sha256,
  result_revision
) values (
  '98610000-0000-4000-8000-000000000003',
  '98600000-0000-4000-8000-000000000002',
  'plan_assignment', '98620000-0000-4000-8000-000000000001',
  'superseded', 'administrator',
  '98600000-0000-4000-8000-000000000001',
  'Fixture imbriquee',
  jsonb_build_object(
    'owner_id', '98600000-0000-4000-8000-000000000002',
    'plan_key', 'comfort'
  ),
  jsonb_build_object('plan_key', 'premium', 'capacity', 'ten'),
  jsonb_build_object(
    'nested', jsonb_build_array(
      jsonb_build_object(
        'ownerId', '98600000-0000-4000-8000-000000000002',
        'description',
        'target=98600000-0000-4000-8000-000000000002'
      )
    )
  ),
  public.administrative_entitlement_payload_hash(
    jsonb_build_object(
      'nested', jsonb_build_array(
        jsonb_build_object(
          'ownerId', '98600000-0000-4000-8000-000000000002',
          'description',
          'target=98600000-0000-4000-8000-000000000002'
        )
      )
    )
  ),
  1
);

select extensions.throws_ok(
  $$update public.account_administrative_entitlement_events
    set reason = 'Mutation interdite'
    where request_id = '98610000-0000-4000-8000-000000000003'$$,
  'P5A20', 'L historique administratif est immuable.',
  'le journal reste immuable hors suppression Auth'
);

select extensions.lives_ok(
  $$delete from auth.users
    where id = '98600000-0000-4000-8000-000000000002'$$,
  'la suppression definitive anonymise atomiquement l historique'
);

select extensions.is(
  (select count(*) from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  3::bigint,
  'aucun evenement d audit n est supprime'
);
select extensions.ok(
  (select bool_and(owner_id is null)
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  'l identifiant superieur de la personne supprimee est retire'
);
select extensions.ok(
  (select bool_and(actor_id = '98600000-0000-4000-8000-000000000001')
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  'l identite distincte de l administrateur est preservee'
);
select extensions.ok(
  (select bool_and(
     coalesce(before_state::text, '') not like '%98600000-0000-4000-8000-000000000002%'
     and coalesce(after_state::text, '') not like '%98600000-0000-4000-8000-000000000002%'
     and request_payload::text not like '%98600000-0000-4000-8000-000000000002%'
   )
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  'aucune copie de l identifiant cible ne subsiste dans les JSON'
);
select extensions.ok(
  (select request_payload #>> '{nested,0,description}' =
          'target=[deleted-account]'
   from public.account_administrative_entitlement_events
   where request_id = '98610000-0000-4000-8000-000000000003'),
  'les identifiants imbriques ou inclus dans un texte sont retires'
);
select extensions.ok(
  (select bool_and(identifiers_anonymized_at is not null)
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  'le retrait est explicitement date'
);
select extensions.ok(
  (select bool_and(
     payload_sha256 =
       public.administrative_entitlement_payload_hash(request_payload)
   )
   from public.account_administrative_entitlement_events
   where request_id in (
     '98610000-0000-4000-8000-000000000001',
     '98610000-0000-4000-8000-000000000002',
     '98610000-0000-4000-8000-000000000003'
   )),
  'les empreintes ne conservent pas le payload nominatif anterieur'
);
select extensions.ok(
  (select after_state->>'plan_key' = 'comfort'
   from public.account_administrative_entitlement_events
   where request_id = '98610000-0000-4000-8000-000000000001')
  and
  (select before_state->>'plan_key' = 'comfort'
          and after_state->>'status' = 'revoked'
   from public.account_administrative_entitlement_events
   where request_id = '98610000-0000-4000-8000-000000000002')
  and
  (select after_state->>'capacity' = 'ten'
   from public.account_administrative_entitlement_events
   where request_id = '98610000-0000-4000-8000-000000000003'),
  'les decisions, formules, capacites et revisions restent consultables'
);
select extensions.is(
  (select count(*) from public.account_administrative_plan_assignments
   where owner_id = '98600000-0000-4000-8000-000000000002'),
  0::bigint,
  'les attributions du compte supprime ne sont pas reactivees'
);
select extensions.throws_ok(
  $$update public.account_administrative_entitlement_events
    set reason = 'Toujours interdit'
    where request_id = '98610000-0000-4000-8000-000000000003'$$,
  'P5A20', 'L historique administratif est immuable.',
  'le journal anonymise demeure immuable'
);
select extensions.is(
  (select enforcement_enabled
   from public.account_trial_runtime_config where singleton),
  false,
  'les restrictions J30 et J60 restent desactivees'
);

select * from extensions.finish();
rollback;
