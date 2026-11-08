begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public', 'account_administrative_plan_assignments', 'les attributions administratives existent');
select extensions.has_table('public', 'account_administrative_entitlement_overrides', 'les derogations administratives existent');
select extensions.has_table('public', 'account_administrative_entitlement_events', 'l historique administratif existe');
select extensions.has_function('public', 'resolve_effective_account_entitlements', array['uuid', 'timestamp with time zone'], 'le resolveur effectif existe');
select extensions.has_function('public', 'assign_administrative_plan', array['uuid','text','text','text','text','uuid','bigint'], 'la RPC d attribution existe');
select extensions.has_function('public', 'replace_administrative_plan', array['uuid','uuid','text','text','text','text','uuid','bigint'], 'la RPC de remplacement existe');
select extensions.has_function('public', 'revoke_administrative_plan', array['uuid','uuid','text','uuid','bigint'], 'la RPC de revocation existe');

select extensions.ok(
  (select bool_and(class.relrowsecurity)
   from pg_class class
   where class.oid in (
     'public.account_administrative_plan_assignments'::regclass,
     'public.account_administrative_entitlement_overrides'::regclass,
     'public.account_administrative_entitlement_events'::regclass
   )),
  'RLS protege les trois tables techniques'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.account_administrative_plan_assignments', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role', 'public.account_administrative_plan_assignments', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon', 'public.account_administrative_plan_assignments', 'SELECT,INSERT,UPDATE,DELETE'),
  'aucun role API ne peut contourner les RPC sur les attributions'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.assign_administrative_plan(uuid,text,text,text,text,uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.assign_administrative_plan(uuid,text,text,text,text,uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.assign_administrative_plan(uuid,text,text,text,text,uuid,bigint)', 'EXECUTE'),
  'seul authenticated peut appeler la RPC qui recontrole le role administrateur'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('98500000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', 'admin-entitlement-' || n || '@example.test',
  'test', clock_timestamp(), '{}', '{}', clock_timestamp(), clock_timestamp()
from generate_series(1, 9) n;

update public.application_user_authorizations
set status = 'active',
    account_mode = case when user_id = '98500000-0000-4000-8000-000000000004' then 'collaborator' else 'autonomous' end,
    status_changed_at = clock_timestamp()
where user_id::text like '98500000-0000-4000-8000-%';

insert into public.platform_administrators(user_id)
values ('98500000-0000-4000-8000-000000000001');

insert into public.account_subscriptions(owner_id, status)
select user_id, 'development'
from public.application_user_authorizations
where user_id in (
  '98500000-0000-4000-8000-000000000002',
  '98500000-0000-4000-8000-000000000003',
  '98500000-0000-4000-8000-000000000005',
  '98500000-0000-4000-8000-000000000006',
  '98500000-0000-4000-8000-000000000007',
  '98500000-0000-4000-8000-000000000008',
  '98500000-0000-4000-8000-000000000009'
);

-- Un essai expire reste distinct de l attribution qui lui rend ensuite acces.
insert into public.account_trials(
  user_id, terms_version, terms_accepted_at, started_at, ends_at, deletion_eligible_at
) values
  ('98500000-0000-4000-8000-000000000005', 'trial-30-plus-30-v1',
   statement_timestamp() - interval '61 days', statement_timestamp() - interval '61 days',
   statement_timestamp() - interval '31 days', statement_timestamp() - interval '1 day'),
  ('98500000-0000-4000-8000-000000000009', 'trial-30-plus-30-v1',
   statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day',
   statement_timestamp() + interval '29 days', statement_timestamp() + interval '59 days');

insert into public.account_trial_legacy_access(user_id, reason)
values ('98500000-0000-4000-8000-000000000006', 'active_before_trial_cutover')
on conflict (user_id) do nothing;

-- Deux abonnements reels, dont une capacite historique > 10 a preserver.
update public.account_subscriptions
set plan_key = 'essential', dossier_capacity_key = 'included', status = 'active',
    started_at = statement_timestamp() - interval '1 day',
    current_period_started_at = statement_timestamp() - interval '1 day',
    current_period_ends_at = statement_timestamp() + interval '29 days'
where owner_id = '98500000-0000-4000-8000-000000000003';

update public.account_subscriptions
set plan_key = 'premium', dossier_capacity_key = 'custom', custom_active_dossier_limit = 12,
    status = 'active', started_at = statement_timestamp() - interval '1 day',
    current_period_started_at = statement_timestamp() - interval '1 day',
    current_period_ends_at = statement_timestamp() + interval '29 days'
where owner_id = '98500000-0000-4000-8000-000000000007';

set local role authenticated;
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"98500000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000002','essential','monthly','included',
    'Attribution de test','98510000-0000-4000-8000-000000000001',0)$$,
  'Essentiel avec deux dossiers peut etre attribue'
);
select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000002','essential','monthly','included',
    'Attribution de test','98510000-0000-4000-8000-000000000001',0)$$,
  'le rejeu identique est idempotent'
);
reset role;
select extensions.is(
  (select count(*) from public.account_administrative_plan_assignments where owner_id = '98500000-0000-4000-8000-000000000002'),
  1::bigint,
  'le rejeu ne duplique pas l attribution'
);
set local role authenticated;
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000002','comfort','monthly','included',
    'Contenu divergent','98510000-0000-4000-8000-000000000001',0)$$,
  'P5A02', 'Identifiant de requete deja utilise.',
  'une cle idempotente ne peut pas porter une autre intention'
);

select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000004','essential','monthly','included',
    'Collaborateur refuse','98510000-0000-4000-8000-000000000002',0)$$,
  'P5A04', 'Compte non eligible a une attribution administrative.',
  'un collaborateur exclusivement invite ne recoit pas de formule'
);
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000003','comfort','annual','five',
    'Commercial refuse','98510000-0000-4000-8000-000000000003',0)$$,
  'P5A05', 'Un abonnement commercial courant interdit cette attribution.',
  'une attribution ne remplace jamais un abonnement commercial'
);
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000005','comfort','annual','custom',
    'Capacite interdite','98510000-0000-4000-8000-000000000004',0)$$,
  'P5A09', 'Formule ou capacite administrative invalide.',
  'aucune nouvelle capacite superieure a dix n est attribuable'
);

select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000005','comfort','annual','included',
    'Acces apres essai','98510000-0000-4000-8000-000000000005',0)$$,
  'une attribution est possible apres expiration de l essai'
);
reset role;
select extensions.is(
  (select access_source from public.resolve_effective_account_entitlements(
    '98500000-0000-4000-8000-000000000005', statement_timestamp())),
  'administrative',
  'l attribution prend priorite sur l essai expire'
);
select extensions.is(
  (select access_source from public.resolve_effective_account_entitlements(
    '98500000-0000-4000-8000-000000000006', statement_timestamp())),
  'legacy',
  'un acces historique reste identifie distinctement'
);
select extensions.is(
  (select access_source from public.resolve_effective_account_entitlements(
    '98500000-0000-4000-8000-000000000009', statement_timestamp())),
  'trial',
  'un essai actif reste identifie distinctement'
);
select extensions.is(
  (select effective_active_dossier_limit from public.resolve_effective_account_entitlements(
    '98500000-0000-4000-8000-000000000007', statement_timestamp())),
  12,
  'une capacite commerciale historique superieure a dix est preservee'
);

select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','comfort','annual','five',
    'Confort cinq','98510000-0000-4000-8000-000000000013',1)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'Confort accepte cinq dossiers'
);
select extensions.throws_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','comfort','annual','ten',
    'Revision obsolete','98510000-0000-4000-8000-000000000014',1)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  '40001', 'Revision administrative obsolete.',
  'une revision obsolete ne remplace pas une attribution'
);
select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','comfort','monthly','ten',
    'Confort dix','98510000-0000-4000-8000-000000000015',2)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'Confort accepte dix dossiers'
);
select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','premium','monthly','included',
    'Premium deux','98510000-0000-4000-8000-000000000016',3)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'Premium accepte deux dossiers'
);
select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','premium','annual','five',
    'Premium cinq','98510000-0000-4000-8000-000000000017',4)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'Premium accepte cinq dossiers'
);
select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','premium','annual','ten',
    'Premium dix','98510000-0000-4000-8000-000000000018',5)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'Premium accepte dix dossiers'
);
select extensions.throws_ok(
  format($sql$select * from public.replace_administrative_plan(
    '98500000-0000-4000-8000-000000000005','%s','essential','monthly','five',
    'Essentiel invalide','98510000-0000-4000-8000-000000000019',6)$sql$,
    (select id from public.account_administrative_plan_assignments
     where owner_id = '98500000-0000-4000-8000-000000000005' and status = 'active')),
  'P5A09', 'Formule ou capacite administrative invalide.',
  'Essentiel reste strictement limite a deux dossiers'
);
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000009','comfort',null,'included',
    'Periodicite manquante','98510000-0000-4000-8000-000000000020',0)$$,
  'P5A09', 'Formule ou capacite administrative invalide.',
  'une periodicite administrative est obligatoire'
);

insert into public.account_trial_purge_requests(
  request_id, user_id, eligibility_observed_at, trial_deletion_eligible_at
) values (
  '98530000-0000-4000-8000-000000000001',
  '98500000-0000-4000-8000-000000000009',
  statement_timestamp(), statement_timestamp()
);
set local role authenticated;
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000009','comfort','monthly','included',
    'Purge ouverte','98510000-0000-4000-8000-000000000021',0)$$,
  'P5A17', 'Une purge de compte non terminale interdit cette attribution.',
  'une purge non terminale bloque une nouvelle attribution'
);

set local role authenticated;

select extensions.lives_ok(
  $$select * from public.assign_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000002','premium','ten',
    'Extension temporaire','98510000-0000-4000-8000-000000000006',0)$$,
  'une derogation augmente fonctionnalites et capacite'
);
reset role;
select extensions.lives_ok(
  format($sql$select * from public.replace_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000002','%s','comfort','five',
    'Reduction de la seule derogation','98510000-0000-4000-8000-000000000022',1)$sql$,
    (select id from public.account_administrative_entitlement_overrides
     where owner_id = '98500000-0000-4000-8000-000000000002' and status = 'active')),
  'une derogation peut etre remplacee avec revision'
);
select extensions.throws_ok(
  format($sql$select * from public.replace_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000002','%s','premium','ten',
    'Revision obsolete','98510000-0000-4000-8000-000000000023',1)$sql$,
    (select id from public.account_administrative_entitlement_overrides
     where owner_id = '98500000-0000-4000-8000-000000000002' and status = 'active')),
  '40001', 'Revision administrative obsolete.',
  'une revision obsolete ne remplace pas une derogation'
);
reset role;
select extensions.is(
  (select effective_plan_key || ':' || effective_active_dossier_limit::text
   from public.resolve_effective_account_entitlements(
     '98500000-0000-4000-8000-000000000002', statement_timestamp())),
  'comfort:5',
  'le resolveur applique la derogation sans modifier la base'
);
select extensions.is(
  (select plan_key || ':' || dossier_capacity_key
   from public.account_administrative_plan_assignments
   where owner_id = '98500000-0000-4000-8000-000000000002' and status = 'active'),
  'essential:included',
  'la derogation ne modifie pas la formule administrative de base'
);
set local role authenticated;

select extensions.lives_ok(
  $$select * from public.assign_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000003','comfort','five',
    'Extension du commercial','98510000-0000-4000-8000-000000000007',0)$$,
  'une derogation peut augmenter un abonnement commercial'
);
reset role;
select extensions.is(
  (select plan_key || ':' || dossier_capacity_key
   from public.account_subscriptions where owner_id = '98500000-0000-4000-8000-000000000003'),
  'essential:included',
  'la derogation ne modifie ni formule ni capacite commerciale'
);
set local role authenticated;
select extensions.throws_ok(
  $$select * from public.assign_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000007',null,'ten',
    'Reduction interdite','98510000-0000-4000-8000-000000000008',0)$$,
  'P5A12', 'La derogation de capacite doit augmenter le plafond.',
  'une capacite historique de douze ne peut pas etre diminuee par derogation'
);

-- La revocation qui ferait passer trois dossiers sous un plafond de deux est refusee.
reset role;
insert into public.protected_persons(id, owner_id, first_name, last_name, status)
select ('98520000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       '98500000-0000-4000-8000-000000000002', 'Fixture', n::text, 'active'
from generate_series(1, 3) n;
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000001',true);

select extensions.throws_ok(
  format($sql$select * from public.revoke_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000002','%s','Quota refuse',
    '98510000-0000-4000-8000-000000000009',2)$sql$,
    (select id from public.account_administrative_entitlement_overrides
     where owner_id = '98500000-0000-4000-8000-000000000002' and status = 'active')),
  'P5A13', 'La revocation placerait le compte au-dessus de son quota.',
  'une revocation est refusee sous le nombre de dossiers actifs'
);

reset role;
delete from public.protected_persons where id = '98520000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000001',true);
select extensions.lives_ok(
  format($sql$select * from public.revoke_administrative_entitlement_override(
    '98500000-0000-4000-8000-000000000002','%s','Retour au quota de base',
    '98510000-0000-4000-8000-000000000010',2)$sql$,
    (select id from public.account_administrative_entitlement_overrides
     where owner_id = '98500000-0000-4000-8000-000000000002' and status = 'active')),
  'la derogation est revocable une fois le quota respecte'
);

reset role;
select extensions.throws_ok(
  $$update public.account_administrative_entitlement_events set reason = 'Alteration'$$,
  'P5A20', 'L historique administratif est immuable.',
  'l historique refuse toute modification directe'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000002',true);
select extensions.throws_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000009','essential','monthly','included',
    'Tentative non admin','98510000-0000-4000-8000-000000000011',0)$$,
  '42501', 'Acces administrateur requis.',
  'un utilisateur ordinaire ne peut attribuer une formule'
);

-- Une formule administrative supersedee ne reprend pas apres la fin du commercial.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000001',true);
select extensions.lives_ok(
  $$select * from public.assign_administrative_plan(
    '98500000-0000-4000-8000-000000000008','comfort','monthly','five',
    'Attribution avant commercial','98510000-0000-4000-8000-000000000012',0)$$,
  'une attribution initiale est creee avant le commercial'
);
reset role;
update public.account_subscriptions
set plan_key = 'essential', dossier_capacity_key = 'included', status = 'active',
    current_period_started_at = statement_timestamp(),
    current_period_ends_at = statement_timestamp() + interval '30 days'
where owner_id = '98500000-0000-4000-8000-000000000008';
select extensions.is(
  (select status from public.account_administrative_plan_assignments
   where owner_id = '98500000-0000-4000-8000-000000000008'),
  'superseded',
  'le debut du commercial supersede definitivement l attribution'
);
update public.account_subscriptions
set status = 'ended', ended_at = statement_timestamp(),
    current_period_started_at = null, current_period_ends_at = null
where owner_id = '98500000-0000-4000-8000-000000000008';
select extensions.isnt(
  (select access_source from public.resolve_effective_account_entitlements(
    '98500000-0000-4000-8000-000000000008', statement_timestamp())),
  'administrative',
  'la fin du commercial ne reactive pas l ancienne attribution'
);

select extensions.is(
  (select count(*) from public.account_subscriptions
   where owner_id in ('98500000-0000-4000-8000-000000000003','98500000-0000-4000-8000-000000000007')),
  2::bigint,
  'les abonnements commerciaux restent presents'
);
select extensions.is(
  (select count(*) from public.account_administrative_entitlement_events
   where actor_kind = 'administrator' and actor_id is null),
  0::bigint,
  'chaque decision administrative conserve son administrateur'
);
select extensions.is(
  (select count(*) from public.account_administrative_entitlement_events
   where actor_kind = 'system' and before_state is null),
  0::bigint,
  'les supersessions automatiques conservent aussi l etat anterieur'
);

-- La nouvelle histoire administrative ne bloque pas la suppression Auth.
insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '98500000-0000-4000-8000-000000000010','authenticated','authenticated',
  'admin-entitlement-delete@example.test','test',clock_timestamp(),'{}','{}',
  clock_timestamp(),clock_timestamp()
);
update public.application_user_authorizations
set status = 'active', account_mode = 'autonomous'
where user_id = '98500000-0000-4000-8000-000000000010';
insert into public.account_subscriptions(owner_id, status)
values ('98500000-0000-4000-8000-000000000010','development');
select set_config('request.jwt.claim.sub','98500000-0000-4000-8000-000000000001',false);
select * from public.assign_administrative_plan(
  '98500000-0000-4000-8000-000000000010','essential','monthly','included',
  'Historique avant suppression','98510000-0000-4000-8000-000000000024',0
);
select extensions.lives_ok(
  $$delete from auth.users where id = '98500000-0000-4000-8000-000000000010'$$,
  'la suppression Auth reste compatible avec les nouvelles fondations'
);
select extensions.is(
  (select count(*) from public.account_administrative_plan_assignments
   where owner_id = '98500000-0000-4000-8000-000000000010'),
  0::bigint,
  'les donnees actives du compte supprime sont retirees'
);
select extensions.is(
  (select count(*) from public.account_administrative_entitlement_events
   where request_id = '98510000-0000-4000-8000-000000000024'
     and owner_id is null),
  1::bigint,
  'la decision est conservee avec sa cible Auth anonymisee'
);

select * from extensions.finish();
rollback;
