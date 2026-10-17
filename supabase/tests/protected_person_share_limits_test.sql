begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'protected_person_share_limit_configuration',
  'la configuration centralisée des limites existe'
);
select extensions.has_column(
  'public', 'protected_person_invitations', 'declined_at',
  'la date de refus est conservée'
);
select extensions.has_column(
  'public', 'protected_person_invitations', 'declined_by',
  'l’auteur du refus est conservé'
);
select extensions.has_function(
  'public', 'get_protected_person_share_capacity', array['uuid'],
  'la RPC propriétaire des compteurs existe'
);
select extensions.has_function(
  'public', 'change_protected_person_access_role', array['uuid','uuid','text'],
  'la RPC de changement de rôle existe'
);
select extensions.has_function(
  'public', 'decline_protected_person_invitation', array['text'],
  'la RPC de refus existe'
);
select extensions.is(
  (select manager_limit::integer from public.protected_person_share_limit_configuration where configuration_key = 'default'),
  5,
  'la limite des gestionnaires est centralisée à cinq'
);
select extensions.is(
  (select read_only_limit::integer from public.protected_person_share_limit_configuration where configuration_key = 'default'),
  5,
  'la limite des lecteurs est centralisée à cinq'
);
select extensions.ok(
  (select class.relrowsecurity from pg_class class where class.oid = 'public.protected_person_share_limit_configuration'::regclass),
  'la configuration est protégée par RLS'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.protected_person_share_limit_configuration', 'SELECT'),
  'authenticated ne peut pas lire directement la configuration'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.protected_person_access', 'role', 'UPDATE'),
  'authenticated ne peut plus contourner la RPC par UPDATE du rôle'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_protected_person_share_capacity(uuid)', 'EXECUTE'),
  'authenticated peut appeler la RPC de compteurs sous contrôle PostgreSQL'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.get_protected_person_share_capacity(uuid)', 'EXECUTE'),
  'anon ne peut pas appeler la RPC de compteurs'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.get_protected_person_share_occupancy(uuid)', 'EXECUTE'),
  'la fonction interne d’occupation n’est pas exposée aux utilisateurs'
);
select extensions.ok(
  not has_function_privilege('service_role', 'public.get_protected_person_share_occupancy(uuid)', 'EXECUTE'),
  'la fonction interne n’est pas exposée à service_role'
);
select extensions.ok(
  (select procedure.prosecdef from pg_proc procedure where procedure.oid = 'public.get_protected_person_share_capacity(uuid)'::regprocedure),
  'la RPC propriétaire est SECURITY DEFINER'
);
select extensions.ok(
  position('FOR UPDATE' in upper(pg_get_functiondef('public.lock_protected_person_sharing(uuid)'::regprocedure))) > 0,
  'le verrou partagé verrouille la ligne du dossier'
);

select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.issue_protected_person_invitation(uuid,text,text,text,timestamptz)'::regprocedure)) > 0,
  'la création d’invitation verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.reissue_protected_person_invitation(uuid,text,timestamptz)'::regprocedure)) > 0,
  'la réémission verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.accept_protected_person_invitation(text)'::regprocedure)) > 0,
  'l’acceptation verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.revoke_protected_person_invitation(uuid)'::regprocedure)) > 0,
  'l’annulation verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.remove_protected_person_access(uuid,uuid)'::regprocedure)) > 0,
  'la révocation d’accès verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.change_protected_person_access_role(uuid,uuid,text)'::regprocedure)) > 0,
  'le changement de rôle verrouille le dossier'
);
select extensions.ok(
  position('lock_protected_person_sharing' in pg_get_functiondef('public.decline_protected_person_invitation(text)'::regprocedure)) > 0,
  'le refus verrouille le dossier'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('92000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'share-user-' || user_number || '@example.test',
  'test-hash',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
from generate_series(1, 35) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '92000000-0000-4000-8000-%';

insert into public.platform_administrators(user_id)
values ('92000000-0000-4000-8000-000000000007');

insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('92000000-0000-4000-8000-000000000101','92000000-0000-4000-8000-000000000001','Quota','Invitations'),
  ('92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000001','Quota','Rôles'),
  ('92000000-0000-4000-8000-000000000103','92000000-0000-4000-8000-000000000001','Quota','États'),
  ('92000000-0000-4000-8000-000000000104','92000000-0000-4000-8000-000000000001','Quota','Historique'),
  ('92000000-0000-4000-8000-000000000105','92000000-0000-4000-8000-000000000002','Quota','Étranger'),
  ('92000000-0000-4000-8000-000000000106','92000000-0000-4000-8000-000000000001','Quota','Gestionnaire'),
  ('92000000-0000-4000-8000-000000000107','92000000-0000-4000-8000-000000000001','Quota','Acceptation'),
  ('92000000-0000-4000-8000-000000000108','92000000-0000-4000-8000-000000000001','Quota','Refus');

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
values
  ('92000000-0000-4000-8000-000000000201','92000000-0000-4000-8000-000000000106','92000000-0000-4000-8000-000000000003','manager','92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000202','92000000-0000-4000-8000-000000000106','92000000-0000-4000-8000-000000000004','read_only','92000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);

select extensions.lives_ok(
  $$do $test$ begin
    for slot in 1..5 loop
      perform public.issue_protected_person_invitation(
        '92000000-0000-4000-8000-000000000101',
        'quota-manager-' || slot || '@example.test',
        'manager',
        lpad(to_hex(100 + slot), 64, '0'),
        now() + interval '1 day'
      );
      perform public.issue_protected_person_invitation(
        '92000000-0000-4000-8000-000000000101',
        'quota-reader-' || slot || '@example.test',
        'read_only',
        lpad(to_hex(200 + slot), 64, '0'),
        now() + interval '1 day'
      );
    end loop;
  end $test$;$$,
  'cinq invitations de chaque rôle peuvent réserver les dix places'
);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101') where share_role = 'manager'),
  5::bigint,
  'les cinq invitations gestionnaire sont comptabilisées'
);
select extensions.is(
  (select pending_invitation_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101') where share_role = 'read_only'),
  5::bigint,
  'les cinq invitations lecture seule sont comptabilisées'
);
select extensions.is(
  (select active_access_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101') where share_role = 'manager'),
  0::bigint,
  'le propriétaire est exclu du quota des gestionnaires'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000101','sixth-manager@example.test','manager',lpad(to_hex(106),64,'0'),now()+interval '1 day')$$,
  '23514', 'La limite de gestionnaires partagés est atteinte.',
  'une sixième place gestionnaire est refusée'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000101','sixth-reader@example.test','read_only',lpad(to_hex(206),64,'0'),now()+interval '1 day')$$,
  '23514', 'La limite de collaborateurs en lecture seule est atteinte.',
  'une sixième place lecture seule est refusée'
);

select extensions.lives_ok(
  $$select public.reissue_protected_person_invitation(
    (select id from public.protected_person_invitations where protected_person_id='92000000-0000-4000-8000-000000000101' and email='quota-manager-1@example.test' and accepted_at is null and revoked_at is null),
    lpad(to_hex(301),64,'0'),now()+interval '2 days')$$,
  'une invitation déjà comptée peut être réémise lorsque le rôle est plein'
);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101') where share_role='manager'),
  5::bigint,
  'la réémission ne double pas la réservation'
);

select extensions.lives_ok(
  $$select public.revoke_protected_person_invitation(
    (select id from public.protected_person_invitations where protected_person_id='92000000-0000-4000-8000-000000000101' and email='quota-reader-1@example.test' and accepted_at is null and revoked_at is null)
  )$$,
  'l’annulation d’une invitation pleine reste autorisée'
);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101') where share_role='read_only'),
  4::bigint,
  'l’annulation libère immédiatement une place'
);
select extensions.lives_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000101','replacement-reader@example.test','read_only',lpad(to_hex(302),64,'0'),now()+interval '1 day')$$,
  'la place libérée peut être réutilisée'
);

reset role;

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
values ('92000000-0000-4000-8000-000000000210','92000000-0000-4000-8000-000000000103','92000000-0000-4000-8000-000000000010','read_only','92000000-0000-4000-8000-000000000001');

insert into public.protected_person_invitations(
  id, protected_person_id, email, role, token_hash, expires_at,
  accepted_at, revoked_at, declined_at, declined_by, invited_by
)
values
  ('92000000-0000-4000-8000-000000000301','92000000-0000-4000-8000-000000000103','state-active@example.test','manager',lpad(to_hex(401),64,'0'),now()+interval '1 day',null,null,null,null,'92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000302','92000000-0000-4000-8000-000000000103','state-expired@example.test','manager',lpad(to_hex(402),64,'0'),now()-interval '1 minute',null,null,null,null,'92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000303','92000000-0000-4000-8000-000000000103','state-revoked@example.test','manager',lpad(to_hex(403),64,'0'),now()+interval '1 day',null,now(),null,null,'92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000304','92000000-0000-4000-8000-000000000103','state-declined@example.test','manager',lpad(to_hex(404),64,'0'),now()+interval '1 day',null,null,now(),'92000000-0000-4000-8000-000000000006','92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000305','92000000-0000-4000-8000-000000000103','share-user-10@example.test','read_only',lpad(to_hex(405),64,'0'),now()+interval '1 day',null,null,null,null,'92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000306','92000000-0000-4000-8000-000000000103','state-accepted@example.test','manager',lpad(to_hex(407),64,'0'),now()+interval '1 day',now(),null,null,null,'92000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);

select extensions.is(
  (select pending_invitation_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000103') where share_role='manager'),
  1::bigint,
  'les invitations expirée, annulée et refusée sont exclues'
);
select extensions.is(
  (select pending_invitation_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000103') where share_role='read_only'),
  0::bigint,
  'une invitation redondante avec un accès actif n’est pas comptée deux fois'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000103','share-user-10@example.test','read_only',lpad(to_hex(406),64,'0'),now()+interval '1 day')$$,
  '23505', 'Cette personne dispose déjà d''un accès au dossier.',
  'une nouvelle invitation redondante est refusée'
);

select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000006","role":"authenticated","email":"state-expired@example.test"}',true);
select extensions.throws_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(402),64,'0'))$$,
  'P0001', 'Invitation invalide ou expirée.',
  'une invitation expirée ne peut pas être refusée'
);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000006","role":"authenticated","email":"state-revoked@example.test"}',true);
select extensions.throws_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(403),64,'0'))$$,
  'P0001', 'Invitation invalide ou expirée.',
  'une invitation annulée ne peut pas être refusée'
);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000006","role":"authenticated","email":"state-accepted@example.test"}',true);
select extensions.throws_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(407),64,'0'))$$,
  'P0001', 'Invitation invalide ou expirée.',
  'une invitation acceptée ne peut pas être refusée'
);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000006","role":"authenticated","email":"state-declined@example.test"}',true);
select extensions.throws_ok(
  $$select public.accept_protected_person_invitation(lpad(to_hex(404),64,'0'))$$,
  'P0001', 'Invitation invalide ou expirée.',
  'une invitation refusée ne peut plus être acceptée'
);

select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);

select public.issue_protected_person_invitation(
  '92000000-0000-4000-8000-000000000107',
  'share-user-5@example.test',
  'read_only',
  lpad(to_hex(501),64,'0'),
  now()+interval '1 day'
);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000107') where share_role='read_only'),
  1::bigint,
  'l’invitation réserve une place avant acceptation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000005","role":"authenticated","email":"share-user-5@example.test"}',true);
select extensions.lives_ok(
  $$select public.accept_protected_person_invitation(lpad(to_hex(501),64,'0'))$$,
  'une invitation ayant réservé sa place peut être acceptée'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000107') where share_role='read_only'),
  1::bigint,
  'l’acceptation remplace la réservation sans double comptage'
);
select extensions.is(
  (select pending_invitation_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000107') where share_role='read_only'),
  0::bigint,
  'l’invitation acceptée quitte les réservations en attente'
);

select public.issue_protected_person_invitation(
  '92000000-0000-4000-8000-000000000108',
  'share-user-6@example.test',
  'manager',
  lpad(to_hex(502),64,'0'),
  now()+interval '1 day'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000004","role":"authenticated","email":"share-user-4@example.test"}',true);
select extensions.throws_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(502),64,'0'))$$,
  'P0001', 'Invitation invalide ou expirée.',
  'un autre utilisateur ne peut pas refuser l’invitation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000006","role":"authenticated","email":"share-user-6@example.test"}',true);
select extensions.lives_ok(
  $$select public.decline_protected_person_invitation(lpad(to_hex(502),64,'0'))$$,
  'le destinataire authentifié peut refuser son invitation'
);

reset role;
select extensions.is(
  (select declined_by from public.protected_person_invitations where token_hash=lpad(to_hex(502),64,'0')),
  '92000000-0000-4000-8000-000000000006'::uuid,
  'l’auteur du refus est imposé par PostgreSQL'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000108') where share_role='manager'),
  0::bigint,
  'le refus libère immédiatement la place'
);

reset role;

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
select
  ('92000000-0000-4000-8000-' || lpad((600 + slot)::text, 12, '0'))::uuid,
  '92000000-0000-4000-8000-000000000102'::uuid,
  ('92000000-0000-4000-8000-' || lpad((10 + slot)::text, 12, '0'))::uuid,
  'manager',
  '92000000-0000-4000-8000-000000000001'::uuid
from generate_series(1,5) slot;

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
values
  ('92000000-0000-4000-8000-000000000611','92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000021','read_only','92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000612','92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000022','read_only','92000000-0000-4000-8000-000000000001');

insert into public.protected_person_invitations(
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
) values (
  '92000000-0000-4000-8000-000000000613',
  '92000000-0000-4000-8000-000000000102',
  'share-user-11@example.test',
  'manager',
  lpad(to_hex(601),64,'0'),
  now()+interval '1 day',
  '92000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);

select extensions.throws_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000611','manager')$$,
  '23514', 'La limite de gestionnaires partagés est atteinte.',
  'un changement vers un rôle plein est refusé'
);
select extensions.lives_ok(
  $$select public.remove_protected_person_access('92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000601')$$,
  'la révocation d’un gestionnaire reste autorisée lorsque le rôle est plein'
);
select extensions.ok(
  (select revoked_at is not null from public.protected_person_invitations where id='92000000-0000-4000-8000-000000000613'),
  'la révocation annule atomiquement l’invitation pouvant rétablir l’accès'
);
select extensions.lives_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000102','92000000-0000-4000-8000-000000000611','manager')$$,
  'la place libérée permet le changement de rôle'
);
select extensions.is(
  (select role from public.protected_person_access where id='92000000-0000-4000-8000-000000000611'),
  'manager',
  'le rôle est modifié atomiquement par la RPC'
);
select extensions.throws_ok(
  $$update public.protected_person_access set role='manager' where id='92000000-0000-4000-8000-000000000612'$$,
  '42501', 'permission denied for table protected_person_access',
  'la modification directe du rôle est refusée'
);
select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000102') where share_role='manager'),
  5::bigint,
  'le rôle gestionnaire revient exactement à sa limite'
);

reset role;

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
select
  ('92000000-0000-4000-8000-' || lpad((700 + slot)::text, 12, '0'))::uuid,
  '92000000-0000-4000-8000-000000000104'::uuid,
  ('92000000-0000-4000-8000-' || lpad((22 + slot)::text, 12, '0'))::uuid,
  'manager',
  '92000000-0000-4000-8000-000000000001'::uuid
from generate_series(1,6) slot;

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by)
values ('92000000-0000-4000-8000-000000000707','92000000-0000-4000-8000-000000000104','92000000-0000-4000-8000-000000000029','read_only','92000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-user-1@example.test"}',true);

select extensions.is(
  (select used_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000104') where share_role='manager'),
  6::bigint,
  'un dépassement historique est conservé et compté'
);
select extensions.is(
  (select exceeded_by from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000104') where share_role='manager'),
  1::bigint,
  'le dépassement historique est explicitement signalé'
);
select extensions.lives_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000104','92000000-0000-4000-8000-000000000701','manager')$$,
  'une opération non croissante reste possible au-dessus de la limite'
);
select extensions.throws_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000104','92000000-0000-4000-8000-000000000707','manager')$$,
  '23514', 'La limite de gestionnaires partagés est atteinte.',
  'une opération croissante reste refusée au-dessus de la limite'
);
select extensions.lives_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000104','92000000-0000-4000-8000-000000000701','read_only')$$,
  'quitter un rôle en dépassement reste autorisé'
);
select extensions.is(
  (select active_access_count from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000104') where share_role='manager'),
  5::bigint,
  'la réduction ramène le rôle gestionnaire à sa limite'
);
select extensions.is(
  (select count(*) from public.protected_person_access where protected_person_id='92000000-0000-4000-8000-000000000104'),
  7::bigint,
  'aucun accès historique n’est supprimé automatiquement'
);

select extensions.throws_ok(
  $$select public.change_protected_person_access_role('92000000-0000-4000-8000-000000000101','92000000-0000-4000-8000-000000000612','manager')$$,
  'P0001', 'Accès collaborateur introuvable.',
  'un accès d’un autre dossier ne peut pas être modifié transversalement'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000003","role":"authenticated","email":"share-user-3@example.test"}',true);
select extensions.throws_ok(
  $$select * from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000106')$$,
  '42501', 'Accès propriétaire requis.',
  'un gestionnaire ne peut pas lire les compteurs'
);
select extensions.lives_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000106','manager-reader@example.test','read_only',lpad(to_hex(801),64,'0'),now()+interval '1 day')$$,
  'un gestionnaire conserve le droit d’inviter en lecture seule'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000106','manager-manager@example.test','manager',lpad(to_hex(802),64,'0'),now()+interval '1 day')$$,
  'P0001', 'Un gestionnaire ne peut inviter qu''en lecture seule.',
  'un gestionnaire ne peut toujours pas inviter un gestionnaire'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000004","role":"authenticated","email":"share-user-4@example.test"}',true);
select extensions.throws_ok(
  $$select * from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000106')$$,
  '42501', 'Accès propriétaire requis.',
  'un lecteur ne peut pas lire les compteurs'
);
select extensions.throws_ok(
  $$select public.issue_protected_person_invitation('92000000-0000-4000-8000-000000000106','reader-invite@example.test','read_only',lpad(to_hex(803),64,'0'),now()+interval '1 day')$$,
  'P0001', 'Dossier introuvable.',
  'un lecteur ne peut toujours pas inviter'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000002","role":"authenticated","email":"share-user-2@example.test"}',true);
select extensions.throws_ok(
  $$select * from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101')$$,
  '42501', 'Accès propriétaire requis.',
  'un utilisateur étranger ne peut pas lire les compteurs'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000007',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000007","role":"authenticated","email":"share-user-7@example.test"}',true);
select extensions.throws_ok(
  $$select * from public.get_protected_person_share_capacity('92000000-0000-4000-8000-000000000101')$$,
  '42501', 'Accès propriétaire requis.',
  'un administrateur de plateforme sans droit métier ne lit pas les compteurs'
);

reset role;
select * from extensions.finish();
rollback;
