begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

update public.protected_person_archive_runtime_config
set lifecycle_enabled = true, updated_at = clock_timestamp()
where singleton;

select extensions.has_function(
  'public', 'lock_protected_person_sharing_lifecycle', array['uuid'],
  'le verrou de cycle de vie du partage existe'
);
select extensions.has_trigger(
  'public', 'protected_person_access',
  'protected_person_access_00_enforce_archive_lifecycle',
  'les accès partagés portent la garde d’archive'
);
select extensions.has_trigger(
  'public', 'protected_person_invitations',
  'protected_person_invitations_00_enforce_archive_lifecycle',
  'les invitations portent la garde d’archive'
);
select extensions.ok(
  (select bool_and(procedure.prosecdef and procedure.proconfig = array['search_path=""'])
   from pg_proc procedure
   where procedure.oid in (
     'public.lock_protected_person_sharing_lifecycle(uuid)'::regprocedure,
     'public.enforce_archived_protected_person_access_write()'::regprocedure,
     'public.enforce_archived_protected_person_invitation_write()'::regprocedure
   )),
  'les gardes sont SECURITY DEFINER avec un search_path vide'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.lock_protected_person_sharing_lifecycle(uuid)',
    'EXECUTE'
  ),
  'le verrou interne n’est pas directement appelable'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('9a000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'archive-share-' || user_number || '@example.test',
  'test-hash', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb, now(), now()
from generate_series(1, 9) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '9a000000-0000-4000-8000-%';

update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id = '9a000000-0000-4000-8000-000000000001';

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at
) values (
  '9a000000-0000-4000-8000-000000000001', null, null,
  'development', now()
);

insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('9a000000-0000-4000-8100-000000000001','9a000000-0000-4000-8000-000000000001','Partage','Archivé'),
  ('9a000000-0000-4000-8100-000000000002','9a000000-0000-4000-8000-000000000001','Partage','Actif');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('9a000000-0000-4000-8200-000000000001','9a000000-0000-4000-8100-000000000001','9a000000-0000-4000-8000-000000000002','manager','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8200-000000000002','9a000000-0000-4000-8100-000000000001','9a000000-0000-4000-8000-000000000003','read_only','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8200-000000000003','9a000000-0000-4000-8100-000000000001','9a000000-0000-4000-8000-000000000009','manager','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8200-000000000004','9a000000-0000-4000-8100-000000000002','9a000000-0000-4000-8000-000000000002','manager','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8200-000000000005','9a000000-0000-4000-8100-000000000002','9a000000-0000-4000-8000-000000000003','read_only','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8200-000000000006','9a000000-0000-4000-8100-000000000001','9a000000-0000-4000-8000-000000000008','manager','9a000000-0000-4000-8000-000000000001');

insert into public.protected_person_invitations(
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
) values
  ('9a000000-0000-4000-8300-000000000001','9a000000-0000-4000-8100-000000000001','archive-share-4@example.test','read_only',lpad(to_hex(901),64,'0'),now()+interval '1 day','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8300-000000000002','9a000000-0000-4000-8100-000000000001','archive-share-5@example.test','manager',lpad(to_hex(902),64,'0'),now()+interval '1 day','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8300-000000000003','9a000000-0000-4000-8100-000000000001','archive-revoke@example.test','read_only',lpad(to_hex(903),64,'0'),now()+interval '1 day','9a000000-0000-4000-8000-000000000001'),
  ('9a000000-0000-4000-8300-000000000004','9a000000-0000-4000-8100-000000000001','archive-reissue@example.test','read_only',lpad(to_hex(904),64,'0'),now()+interval '1 day','9a000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000001","role":"authenticated","email":"archive-share-1@example.test"}',true);

select extensions.is(
  public.archive_protected_person(
    '9a000000-0000-4000-8100-000000000001', 1,
    'Protection du partage'
  ),
  2::bigint,
  'le dossier avec accès et invitations peut être archivé'
);

select extensions.throws_ok(
  $$select public.issue_protected_person_invitation(
      '9a000000-0000-4000-8100-000000000001',
      'new-archive-share@example.test', 'read_only',
      lpad(to_hex(905),64,'0'), now()+interval '1 day'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'la création d’invitation par RPC est refusée sur archive'
);
select extensions.throws_ok(
  $$select public.reissue_protected_person_invitation(
      '9a000000-0000-4000-8300-000000000004',
      lpad(to_hex(906),64,'0'), now()+interval '2 days'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'la réémission est refusée sur archive'
);
select extensions.is(
  (select count(*) from public.protected_person_invitations
   where id='9a000000-0000-4000-8300-000000000004'
     and revoked_at is null and expires_at < now()+interval '25 hours'),
  1::bigint,
  'la réémission refusée conserve l’invitation et son expiration initiale'
);
select extensions.throws_ok(
  $$select public.change_protected_person_access_role(
      '9a000000-0000-4000-8100-000000000001',
      '9a000000-0000-4000-8200-000000000002', 'manager'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'la promotion d’un lecteur est refusée'
);

select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000004","role":"authenticated","email":"archive-share-4@example.test"}',true);
select extensions.throws_ok(
  $$select public.accept_protected_person_invitation(lpad(to_hex(901),64,'0'))$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'l’acceptation d’une invitation est suspendue'
);
select extensions.is(
  (select count(*) from public.protected_person_access
   where protected_person_id='9a000000-0000-4000-8100-000000000001'
     and user_id='9a000000-0000-4000-8000-000000000004'),
  0::bigint,
  'l’acceptation refusée ne crée aucun accès'
);

select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000005","role":"authenticated","email":"archive-share-5@example.test"}',true);
select extensions.lives_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(902),64,'0'))$$,
  'le destinataire peut refuser une invitation sur archive'
);
reset role;
select extensions.ok(
  (select declined_at is not null
   from public.protected_person_invitations
   where id='9a000000-0000-4000-8300-000000000002'),
  'le refus est conservé'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000001","role":"authenticated","email":"archive-share-1@example.test"}',true);
select extensions.lives_ok(
  $$select public.revoke_protected_person_invitation(
      '9a000000-0000-4000-8300-000000000003'
    )$$,
  'le propriétaire peut révoquer une invitation sur archive'
);
select extensions.lives_ok(
  $$select public.remove_protected_person_access(
      '9a000000-0000-4000-8100-000000000001',
      '9a000000-0000-4000-8200-000000000003'
    )$$,
  'le propriétaire peut retirer un accès sur archive'
);
select extensions.lives_ok(
  $$select public.change_protected_person_access_role(
      '9a000000-0000-4000-8100-000000000001',
      '9a000000-0000-4000-8200-000000000001', 'read_only'
    )$$,
  'le propriétaire peut rétrograder un gestionnaire sur archive'
);
select extensions.is(
  (select role from public.protected_person_access
   where id='9a000000-0000-4000-8200-000000000001'),
  'read_only',
  'la rétrogradation est appliquée'
);

select extensions.is(
  (select count(*) from public.protected_person_access
   where protected_person_id='9a000000-0000-4000-8100-000000000001'),
  3::bigint,
  'les accès restants demeurent consultables par le propriétaire'
);
select extensions.is(
  (select count(*) from public.protected_person_invitations
   where protected_person_id='9a000000-0000-4000-8100-000000000001'
     and accepted_at is null and revoked_at is null and declined_at is null),
  2::bigint,
  'les invitations en attente non traitées sont préservées'
);
select extensions.is(
  (select pending_invitation_count
   from public.get_protected_person_share_capacity(
     '9a000000-0000-4000-8100-000000000001'
   ) where share_role='read_only'),
  2::bigint,
  'les compteurs de quota restent cohérents'
);

reset role;
select extensions.throws_ok(
  $$insert into public.protected_person_invitations(
      protected_person_id,email,role,token_hash,expires_at,invited_by
    ) values (
      '9a000000-0000-4000-8100-000000000001','direct@example.test',
      'read_only',lpad(to_hex(907),64,'0'),now()+interval '1 day',
      '9a000000-0000-4000-8000-000000000001'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une insertion directe d’invitation est protégée'
);
select extensions.throws_ok(
  $$update public.protected_person_invitations
    set accepted_at=now()
    where id='9a000000-0000-4000-8300-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une acceptation directe est protégée'
);
select extensions.throws_ok(
  $$update public.protected_person_access
    set role='manager'
    where id='9a000000-0000-4000-8200-000000000002'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une promotion directe est protégée'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000008',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000008","role":"authenticated","email":"archive-share-8@example.test"}',true);
select extensions.is(
  (select count(*) from public.protected_person_access
   where protected_person_id='9a000000-0000-4000-8100-000000000001'),
  1::bigint,
  'le gestionnaire conserve la consultation autorisée de son accès'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation(
      '9a000000-0000-4000-8100-000000000001',
      'manager-archive@example.test','read_only',
      lpad(to_hex(908),64,'0'),now()+interval '1 day'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un gestionnaire ne peut pas inviter sur archive'
);

select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000003","role":"authenticated","email":"archive-share-3@example.test"}',true);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation(
      '9a000000-0000-4000-8100-000000000001',
      'reader-archive@example.test','read_only',
      lpad(to_hex(909),64,'0'),now()+interval '1 day'
    )$$,
  'P0001', 'Dossier introuvable.',
  'un lecteur conserve son absence de droit de gestion'
);

select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000001","role":"authenticated","email":"archive-share-1@example.test"}',true);
select extensions.is(
  public.restore_protected_person(
    '9a000000-0000-4000-8100-000000000001', 2,
    'Reprise du partage'
  ),
  3::bigint,
  'le dossier peut être restauré avec ses invitations en attente'
);

select set_config('request.jwt.claim.sub','9a000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"9a000000-0000-4000-8000-000000000004","role":"authenticated","email":"archive-share-4@example.test"}',true);
select extensions.lives_ok(
  $$select public.accept_protected_person_invitation(lpad(to_hex(901),64,'0'))$$,
  'une invitation toujours valide peut être acceptée après restauration'
);
select extensions.is(
  (select role from public.protected_person_access
   where protected_person_id='9a000000-0000-4000-8100-000000000001'
     and user_id='9a000000-0000-4000-8000-000000000004'),
  'read_only',
  'l’accès attendu est créé après restauration'
);

select * from extensions.finish();
rollback;
