begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

update public.protected_person_archive_runtime_config
set lifecycle_enabled = true, updated_at = clock_timestamp()
where singleton;

select extensions.has_function(
  'public', 'get_owned_dossier_capacity', array[]::text[],
  'la RPC propriétaire de capacité existe'
);
select extensions.has_function(
  'public', 'resolve_owner_dossier_capacity', array['uuid'],
  'le résolveur interne existe'
);
select extensions.has_trigger(
  'public', 'protected_persons', 'protected_persons_quota_guard',
  'les mutations de dossiers sont protégées'
);
select extensions.has_trigger(
  'public', 'account_subscriptions', 'account_subscriptions_serialize_dossier_capacity',
  'les changements de capacité suivent le protocole de verrouillage'
);
select extensions.has_trigger(
  'public', 'application_user_authorizations',
  'application_user_authorizations_provision_development_subscription',
  'les nouveaux propriétaires peuvent recevoir leur abonnement development'
);
select extensions.ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'protected_persons_owner_active_idx'
      and indexdef like '%WHERE (status = ''active''::text)%'
  ),
  'le comptage dispose d’un index partiel sur les dossiers actifs'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_owned_dossier_capacity()', 'EXECUTE'),
  'authenticated peut appeler uniquement la RPC publique'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.get_owned_dossier_capacity()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.get_owned_dossier_capacity()', 'EXECUTE'),
  'la RPC de compteur n’est ouverte ni à anon ni implicitement à service_role'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.resolve_owner_dossier_capacity(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.assert_owner_dossier_capacity(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.lock_owner_dossier_capacity(uuid)', 'EXECUTE'),
  'les fonctions internes ne sont pas appelables par les utilisateurs'
);
select extensions.ok(
  (select procedure.prosecdef
   from pg_proc procedure
   where procedure.oid = 'public.get_owned_dossier_capacity()'::regprocedure)
  and (select procedure.proconfig = array['search_path=""']
       from pg_proc procedure
       where procedure.oid = 'public.get_owned_dossier_capacity()'::regprocedure),
  'la RPC privilégiée fixe un search_path vide'
);
select extensions.ok(
  (select bool_and(procedure.prosecdef and procedure.proconfig = array['search_path=""'])
   from pg_proc procedure
   where procedure.oid in (
     'public.resolve_owner_dossier_capacity(uuid)'::regprocedure,
     'public.assert_owner_dossier_capacity(uuid)'::regprocedure,
     'public.lock_owner_dossier_capacity(uuid)'::regprocedure,
     'public.enforce_protected_person_dossier_capacity()'::regprocedure,
     'public.provision_new_development_owner_subscription()'::regprocedure,
     'public.serialize_account_subscription_capacity_change()'::regprocedure
   )),
  'toutes les fonctions privilégiées internes fixent un search_path vide'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('96000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'dossier-quota-' || user_number || '@example.test',
  'test', now(), '{}', '{}', now(), now()
from generate_series(1, 15) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '96000000-0000-4000-8000-%';

-- Le compte 11 représente un titulaire dont l'inscription autonome a déjà été
-- validée, mais qui n'a pas encore créé son premier dossier.
update public.application_user_authorizations
set autonomous_registration_status = 'active'
where user_id = '96000000-0000-4000-8000-000000000011';

-- Propriétaires commerciaux et development préparés administrativement.
update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id::text like '96000000-0000-4000-8000-%'
  and user_id not in (
    '96000000-0000-4000-8000-000000000011',
    '96000000-0000-4000-8000-000000000012',
    '96000000-0000-4000-8000-000000000013',
    '96000000-0000-4000-8000-000000000014',
    '96000000-0000-4000-8000-000000000015'
  );

insert into public.platform_administrators(user_id)
values ('96000000-0000-4000-8000-000000000014');

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, custom_active_dossier_limit,
  status, started_at, ended_at
) values
  ('96000000-0000-4000-8000-000000000001','essential','included',null,'active',now(),null),
  ('96000000-0000-4000-8000-000000000002','comfort','five',null,'active',now(),null),
  ('96000000-0000-4000-8000-000000000003','premium','ten',null,'active',now(),null),
  ('96000000-0000-4000-8000-000000000004','premium','custom',12,'active',now(),null),
  ('96000000-0000-4000-8000-000000000005',null,null,null,'development',now(),null),
  ('96000000-0000-4000-8000-000000000007','essential','included',null,'ended',now()-interval '2 months',now()-interval '1 month'),
  ('96000000-0000-4000-8000-000000000008','essential','included',null,'past_due',now(),null),
  ('96000000-0000-4000-8000-000000000009','essential','included',null,'canceled',now(),null),
  ('96000000-0000-4000-8000-000000000010','essential','included',null,'active',now(),null);

-- Le compte 15 simule un historique commercial terminé avant une nouvelle
-- tentative de prise du mode autonome.
update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id = '96000000-0000-4000-8000-000000000015';
insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at, ended_at
) values (
  '96000000-0000-4000-8000-000000000015', 'essential', 'included', 'ended',
  now()-interval '2 months', now()-interval '1 month'
);
update public.application_user_authorizations
set account_mode = null
where user_id = '96000000-0000-4000-8000-000000000015';

-- Données initiales : les insertions administratives sans JWT préservent les
-- fixtures et permettent de représenter un dépassement existant.
insert into public.protected_persons(id, owner_id, first_name, last_name, status, archived_at)
values
  ('96000000-0000-4000-8001-000000000101','96000000-0000-4000-8000-000000000001','Inclus','Actif','active',null),
  ('96000000-0000-4000-8001-000000000102','96000000-0000-4000-8000-000000000001','Inclus','Archivé','archived',now()),
  ('96000000-0000-4000-8002-000000000101','96000000-0000-4000-8000-000000000002','Cinq','Un','active',null),
  ('96000000-0000-4000-8002-000000000102','96000000-0000-4000-8000-000000000002','Cinq','Deux','active',null),
  ('96000000-0000-4000-8002-000000000103','96000000-0000-4000-8000-000000000002','Cinq','Trois','active',null),
  ('96000000-0000-4000-8002-000000000104','96000000-0000-4000-8000-000000000002','Cinq','Quatre','active',null),
  ('96000000-0000-4000-8002-000000000105','96000000-0000-4000-8000-000000000002','Cinq','Archive A','archived',now()),
  ('96000000-0000-4000-8002-000000000106','96000000-0000-4000-8000-000000000002','Cinq','Archive B','archived',now()),
  ('96000000-0000-4000-8003-000000000101','96000000-0000-4000-8000-000000000003','Dix','Actif','active',null),
  ('96000000-0000-4000-8004-000000000101','96000000-0000-4000-8000-000000000004','Custom','Actif','active',null),
  ('96000000-0000-4000-8005-000000000101','96000000-0000-4000-8000-000000000005','Développement','Actif','active',null),
  ('96000000-0000-4000-8010-000000000101','96000000-0000-4000-8000-000000000010','Dépassement','Un','active',null),
  ('96000000-0000-4000-8010-000000000102','96000000-0000-4000-8000-000000000010','Dépassement','Deux','active',null),
  ('96000000-0000-4000-8010-000000000103','96000000-0000-4000-8000-000000000010','Dépassement','Trois','active',null);

-- Le compte 12 devient Gestionnaire, le compte 13 Lecteur.
insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('96000000-0000-4000-9000-000000000201','96000000-0000-4000-8001-000000000101','96000000-0000-4000-8000-000000000012','manager','96000000-0000-4000-8000-000000000001'),
  ('96000000-0000-4000-9000-000000000202','96000000-0000-4000-8001-000000000101','96000000-0000-4000-8000-000000000013','read_only','96000000-0000-4000-8000-000000000001');

-- Capacité incluse : un dossier actif possédé et l’archive exclue.
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  (select active_dossier_count from public.get_owned_dossier_capacity()),
  1::bigint,
  'seuls les dossiers actifs possédés sont comptés'
);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()),
  2,
  'la capacité included vaut deux'
);
select extensions.is(
  (select remaining_dossier_count from public.get_owned_dossier_capacity()),
  1::bigint,
  'une place incluse reste disponible'
);
select extensions.lives_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8101-000000000103','96000000-0000-4000-8000-000000000001','Inclus','Deuxième')$$,
  'la dernière place incluse peut être consommée'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8101-000000000104','96000000-0000-4000-8000-000000000001','Inclus','Refusé')$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'une création directe est refusée au plafond'
);

-- L’archivage libère immédiatement une place.
select extensions.lives_ok(
  $$select public.archive_protected_person(
    '96000000-0000-4000-8101-000000000103', 1, 'Test de libération du quota'
  )$$,
  'l’archivage reste autorisé au plafond'
);
select extensions.lives_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8101-000000000105','96000000-0000-4000-8000-000000000001','Inclus','Remplacement')$$,
  'la place libérée peut être réutilisée'
);

-- Capacité cinq : restauration autorisée pour la cinquième place puis refusée.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 5,
  'la capacité five vaut cinq'
);
select extensions.lives_ok(
  $$select public.restore_protected_person(
    '96000000-0000-4000-8002-000000000105', 1, 'Test de consommation du quota'
  )$$,
  'une restauration utilise la dernière place disponible'
);
select extensions.throws_ok(
  $$select public.restore_protected_person(
    '96000000-0000-4000-8002-000000000106', 1, 'Test de refus au plafond'
  )$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'une restauration est refusée au plafond'
);

-- Capacités dix et personnalisée.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000003',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 10,
  'la capacité ten vaut dix'
);
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000004',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 12,
  'la capacité personnalisée est conservée exactement'
);

-- Sans forfait commercial : le palier included de deux dossiers s'applique.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000005',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 2,
  'development utilise la capacité incluse de deux dossiers'
);
select extensions.lives_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8105-000000000102','96000000-0000-4000-8000-000000000005','Développement','Deux')$$,
  'le deuxième dossier sans forfait est autorisé'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8105-000000000103','96000000-0000-4000-8000-000000000005','Développement','Trois')$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'le troisième dossier sans forfait est refusé'
);

-- Abonnement absent et historique terminé : aucun repli silencieux à deux.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000006',true);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8106-000000000101','96000000-0000-4000-8000-000000000006','Sans','Abonnement')$$,
  'P4D02', 'Capacité de dossiers indisponible.',
  'l’absence d’abonnement courant bloque la création'
);
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000007',true);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8107-000000000101','96000000-0000-4000-8000-000000000007','Abonnement','Terminé')$$,
  'P4D02', 'Capacité de dossiers indisponible.',
  'un abonnement terminé ne constitue pas un abonnement courant'
);

-- past_due et canceled conservent le plafond courant.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000008',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 2,
  'past_due conserve la capacité courante'
);
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000009',true);
select extensions.is(
  (select active_dossier_limit from public.get_owned_dossier_capacity()), 2,
  'canceled non terminé conserve la capacité courante'
);

-- Un dépassement existant est signalé sans mutation ni blocage de gestion.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000010',true);
select extensions.is(
  (select exceeded_by from public.get_owned_dossier_capacity()), 1::bigint,
  'le dépassement existant est calculé'
);
select extensions.is(
  (select count(*) from public.protected_persons
   where owner_id='96000000-0000-4000-8000-000000000010' and status='active'),
  3::bigint,
  'aucun dossier en dépassement n’est supprimé ou archivé'
);
select extensions.lives_ok(
  $$update public.protected_persons set notes='gestion conservée'
    where id='96000000-0000-4000-8010-000000000101'$$,
  'la gestion d’un dossier existant reste possible en dépassement'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8110-000000000104','96000000-0000-4000-8000-000000000010','Dépassement','Refusé')$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'seules les opérations augmentant l’occupation sont refusées'
);

-- Gestionnaire et lecteur : dossiers partagés non comptés, aucun quota propre.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000012',true);
select extensions.throws_ok(
  $$select * from public.get_owned_dossier_capacity()$$,
  '42501', 'Accès propriétaire requis.',
  'un gestionnaire ne peut pas consulter le compteur du propriétaire'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8112-000000000101','96000000-0000-4000-8000-000000000012','Gestionnaire','Interdit')$$,
  'P0001', 'Un compte collaborateur ne peut pas créer ou posséder de dossier.',
  'un gestionnaire ne peut pas créer de dossier'
);
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000013',true);
select extensions.throws_ok(
  $$select * from public.get_owned_dossier_capacity()$$,
  '42501', 'Accès propriétaire requis.',
  'un lecteur ne peut pas consulter le compteur du propriétaire'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8113-000000000101','96000000-0000-4000-8000-000000000013','Lecteur','Interdit')$$,
  'P0001', 'Un compte collaborateur ne peut pas créer ou posséder de dossier.',
  'un lecteur ne peut pas créer de dossier'
);

select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000014',true);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8114-000000000101','96000000-0000-4000-8000-000000000014','Administrateur','Interdit')$$,
  'P0001', 'Un administrateur de plateforme ne peut pas utiliser les fonctions métier.',
  'un administrateur de plateforme ne peut pas créer de dossier'
);

-- Premier dossier réel : prise de mode autonome et abonnement development
-- atomiques. Le compte possède initialement account_mode NULL et aucun historique.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000011',true);
select extensions.lives_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8111-000000000101','96000000-0000-4000-8000-000000000011','Nouveau','Propriétaire')$$,
  'le premier dossier initialise sûrement le mode développement'
);
select extensions.is(
  (select status from public.account_subscriptions
   where owner_id='96000000-0000-4000-8000-000000000011' and ended_at is null),
  'development',
  'le nouveau propriétaire reçoit un abonnement development courant'
);
select extensions.is(
  (select account_mode from public.application_user_authorizations
   where user_id='96000000-0000-4000-8000-000000000011'),
  'autonomous',
  'le nouveau propriétaire devient autonome'
);
select extensions.lives_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8111-000000000102','96000000-0000-4000-8000-000000000011','Nouveau','Deuxième')$$,
  'un propriétaire sans forfait peut créer un deuxième dossier'
);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8111-000000000103','96000000-0000-4000-8000-000000000011','Nouveau','Troisième')$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'un propriétaire sans forfait ne peut pas créer un troisième dossier'
);

-- Un historique commercial terminé interdit toute recréation development.
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000015',true);
select extensions.throws_ok(
  $$insert into public.protected_persons(id,owner_id,first_name,last_name)
    values('96000000-0000-4000-8115-000000000101','96000000-0000-4000-8000-000000000015','Ancien','Commercial')$$,
  'P4D02', 'Capacité de dossiers indisponible.',
  'un historique commercial terminé n’est pas transformé en development'
);
select extensions.is(
  (select count(*) from public.account_subscriptions
   where owner_id='96000000-0000-4000-8000-000000000015' and status='development'),
  0::bigint,
  'aucun abonnement development n’est créé pour l’ancien compte commercial'
);

reset role;

-- Le verrou de capacité ne doit pas empêcher la suppression administrative
-- sûre d’un compte, dont les abonnements sont supprimés par cascade.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000','96000000-0000-4000-8000-000000000016',
  'authenticated','authenticated','dossier-quota-delete@example.test','test',now(),
  '{}','{}',now(),now()
);
update public.application_user_authorizations
set status='active',status_changed_at=now(),account_mode='autonomous'
where user_id='96000000-0000-4000-8000-000000000016';
insert into public.account_subscriptions(owner_id,status)
values('96000000-0000-4000-8000-000000000016','development');
select extensions.lives_ok(
  $$delete from auth.users where id='96000000-0000-4000-8000-000000000016'$$,
  'la cascade de suppression d’un compte reste compatible avec le verrou de capacité'
);
select extensions.is(
  (select count(*) from public.account_subscriptions
   where owner_id='96000000-0000-4000-8000-000000000016'),
  0::bigint,
  'la suppression du compte retire son abonnement par cascade'
);

select * from extensions.finish();
rollback;
