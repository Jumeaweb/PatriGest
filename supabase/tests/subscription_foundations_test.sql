begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table('public', 'subscription_plans', 'le catalogue des forfaits existe');
select extensions.has_table('public', 'subscription_features', 'le catalogue des fonctionnalités existe');
select extensions.has_table('public', 'subscription_plan_features', 'la matrice des forfaits existe');
select extensions.has_table('public', 'subscription_dossier_capacities', 'le catalogue des capacités existe');
select extensions.has_table('public', 'account_subscriptions', 'les abonnements propriétaires existent');
select extensions.has_trigger(
  'public',
  'account_subscriptions',
  'account_subscriptions_validate_owner',
  'les abonnements sont réservés aux comptes propriétaires'
);

select extensions.is(
  (select string_agg(plan_key, ',' order by sort_order) from public.subscription_plans),
  'essential,comfort,premium',
  'les trois identifiants de forfait sont stables'
);
select extensions.is(
  (select string_agg(monthly_price_cents::text, ',' order by sort_order) from public.subscription_plans),
  '300,500,600',
  'les tarifs mensuels correspondent au catalogue commercial'
);
select extensions.is(
  (select string_agg(annual_price_cents::text, ',' order by sort_order) from public.subscription_plans),
  '3000,5000,6000',
  'les tarifs annuels correspondent au catalogue commercial'
);
select extensions.is(
  (select count(*) from public.subscription_features),
  5::bigint,
  'les cinq capacités fonctionnelles sont définies'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features),
  15::bigint,
  'la matrice explicite contient toutes les combinaisons forfait-fonctionnalité'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features where plan_key = 'essential' and included),
  3::bigint,
  'Essentiel inclut le socle, les documents existants et l’export'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features where plan_key = 'comfort' and included),
  4::bigint,
  'Confort ajoute l’automatisation bancaire'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features where plan_key = 'premium' and included),
  5::bigint,
  'Premium inclut toutes les capacités'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features where feature_key = 'data_export' and included),
  3::bigint,
  'l’export est inclus dans les trois forfaits'
);
select extensions.is(
  (select count(*) from public.subscription_plan_features where feature_key = 'existing_accounting_documents' and included),
  3::bigint,
  'les documents comptables existants restent inclus partout'
);
select extensions.is(
  (select string_agg(coalesce(active_dossier_limit::text, 'custom'), ',' order by sort_order)
   from public.subscription_dossier_capacities),
  '2,5,10,custom',
  'les quatre capacités non cumulatives sont définies'
);
select extensions.is(
  (select implementation_status from public.subscription_features where feature_key = 'bank_operation_automation'),
  'upcoming',
  'l’automatisation bancaire reste signalée comme à venir'
);
select extensions.is(
  (select implementation_status from public.subscription_features where feature_key = 'central_document_management'),
  'upcoming',
  'la gestion documentaire centralisée reste signalée comme à venir'
);

select extensions.ok(
  (select bool_and(class.relrowsecurity)
   from pg_class class
   where class.oid in (
     'public.subscription_plans'::regclass,
     'public.subscription_features'::regclass,
     'public.subscription_plan_features'::regclass,
     'public.subscription_dossier_capacities'::regclass,
     'public.account_subscriptions'::regclass
   )),
  'RLS protège les cinq tables'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.account_subscriptions', 'SELECT'),
  'authenticated peut lire un abonnement sous contrôle RLS'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.account_subscriptions', 'INSERT')
  and not has_table_privilege('authenticated', 'public.account_subscriptions', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.account_subscriptions', 'DELETE'),
  'authenticated ne peut pas administrer directement les abonnements'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.account_subscriptions', 'SELECT'),
  'anon ne peut pas lire les abonnements'
);
select extensions.ok(
  not has_table_privilege('service_role', 'public.account_subscriptions', 'SELECT'),
  'aucun accès implicite service_role n’est ouvert avant le mécanisme administratif'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.subscription_plans', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.subscription_plan_features', 'UPDATE'),
  'le catalogue et sa matrice ne sont pas modifiables par les utilisateurs'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000001','authenticated','authenticated','subscription-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000002','authenticated','authenticated','subscription-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000003','authenticated','authenticated','subscription-outsider@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000004','authenticated','authenticated','subscription-admin@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000005','authenticated','authenticated','subscription-custom-owner@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '94000000-0000-4000-8000-%';

insert into public.platform_administrators(user_id)
values ('94000000-0000-4000-8000-000000000004');

insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('94000000-0000-4000-8000-000000000101','94000000-0000-4000-8000-000000000001','Dossier','Abonnement'),
  ('94000000-0000-4000-8000-000000000102','94000000-0000-4000-8000-000000000003','Dossier','Historique'),
  ('94000000-0000-4000-8000-000000000103','94000000-0000-4000-8000-000000000005','Dossier','Capacité personnalisée');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values (
  '94000000-0000-4000-8000-000000000201',
  '94000000-0000-4000-8000-000000000101',
  '94000000-0000-4000-8000-000000000002',
  'manager',
  '94000000-0000-4000-8000-000000000001'
);

insert into public.account_subscriptions(owner_id, status)
values ('94000000-0000-4000-8000-000000000001', 'development');

select extensions.is(
  (select count(*) from public.account_subscriptions
   where owner_id = '94000000-0000-4000-8000-000000000001'
     and status = 'development'
     and plan_key is null
     and dossier_capacity_key is null),
  1::bigint,
  'le mode Développement n’attribue aucun forfait ni capacité payante'
);

select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, plan_key, dossier_capacity_key, status)
    values ('94000000-0000-4000-8000-000000000001','essential','included','active')$$,
  '23505',
  'duplicate key value violates unique constraint "account_subscriptions_one_current_per_owner_idx"',
  'un propriétaire ne peut avoir qu’un abonnement courant'
);
select extensions.lives_ok(
  $$insert into public.account_subscriptions(
      owner_id, plan_key, dossier_capacity_key, status, started_at, ended_at
    ) values (
      '94000000-0000-4000-8000-000000000003',
      'essential',
      'included',
      'ended',
      now() - interval '2 months',
      now() - interval '1 month'
    )$$,
  'un abonnement terminé peut être conservé dans l’historique'
);
select extensions.lives_ok(
  $$insert into public.account_subscriptions(owner_id, status)
    values ('94000000-0000-4000-8000-000000000003','development')$$,
  'un abonnement courant peut suivre un abonnement terminé'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, status)
    values ('94000000-0000-4000-8000-000000000003','development')$$,
  '23505',
  'duplicate key value violates unique constraint "account_subscriptions_one_current_per_owner_idx"',
  'l’unicité vaut aussi pour deux modes Développement'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, status)
    values ('94000000-0000-4000-8000-000000000002','development')$$,
  '23514',
  'Un abonnement ne peut être associé qu’à un compte propriétaire.',
  'un compte collaborateur ne peut pas recevoir un abonnement propriétaire'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, plan_key, dossier_capacity_key, status)
    values ('94000000-0000-4000-8000-000000000005',null,'included','active')$$,
  '23514',
  null,
  'un abonnement commercial exige un forfait'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, plan_key, dossier_capacity_key, status)
    values ('94000000-0000-4000-8000-000000000005','premium',null,'active')$$,
  '23514',
  null,
  'un abonnement commercial exige une capacité'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, plan_key, dossier_capacity_key, status)
    values ('94000000-0000-4000-8000-000000000005','premium','included','development')$$,
  '23514',
  null,
  'le mode Développement refuse un forfait fictif'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(
      owner_id, plan_key, dossier_capacity_key, custom_active_dossier_limit, status
    ) values (
      '94000000-0000-4000-8000-000000000005','premium','custom',10,'active'
    )$$,
  '23514',
  null,
  'une capacité personnalisée doit être supérieure à dix'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(
      owner_id, plan_key, dossier_capacity_key, custom_active_dossier_limit, status
    ) values (
      '94000000-0000-4000-8000-000000000005','premium','ten',12,'active'
    )$$,
  '23514',
  null,
  'un palier fixe ne peut pas cumuler une capacité personnalisée'
);
select extensions.lives_ok(
  $$insert into public.account_subscriptions(owner_id, status)
    values ('94000000-0000-4000-8000-000000000005','development')$$,
  'un nouveau propriétaire peut commencer en mode Développement'
);
select extensions.lives_ok(
  $$update public.account_subscriptions
    set ended_at = now()
    where owner_id = '94000000-0000-4000-8000-000000000005'
      and status = 'development'$$,
  'le mode Développement peut être clôturé sans lui attribuer de forfait fictif'
);
select extensions.lives_ok(
  $$insert into public.account_subscriptions(
      owner_id, plan_key, dossier_capacity_key, custom_active_dossier_limit, status
    ) values (
      '94000000-0000-4000-8000-000000000005','premium','custom',24,'active'
    )$$,
  'une capacité sur devis explicite supérieure à dix est acceptée'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.account_subscriptions),
  1::bigint,
  'le propriétaire ne voit que son abonnement courant'
);
select extensions.throws_ok(
  $$update public.account_subscriptions
    set plan_key = 'premium', dossier_capacity_key = 'ten', status = 'active'
    where owner_id = '94000000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table account_subscriptions',
  'le propriétaire ne peut pas modifier son propre forfait ou sa capacité'
);
select extensions.is(
  (select count(*) from public.subscription_plans),
  3::bigint,
  'un utilisateur authentifié peut consulter le catalogue général'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000002","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.account_subscriptions
   where owner_id = '94000000-0000-4000-8000-000000000001'),
  0::bigint,
  'un gestionnaire ne peut pas lire les informations commerciales du propriétaire'
);
select extensions.is(
  (select count(*) from public.account_subscriptions),
  0::bigint,
  'un gestionnaire sans abonnement propriétaire ne voit aucune donnée commerciale'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000003","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.account_subscriptions),
  2::bigint,
  'un autre propriétaire ne voit que son propre historique et son abonnement courant'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000004","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.account_subscriptions),
  5::bigint,
  'un administrateur de plateforme peut auditer les abonnements'
);

reset role;
select extensions.lives_ok(
  $$insert into public.protected_persons(id, owner_id, first_name, last_name)
    select
      ('94000000-0000-4000-8000-' || lpad((300 + number)::text, 12, '0'))::uuid,
      '94000000-0000-4000-8000-000000000001'::uuid,
      'Dossier',
      'Sans quota ' || number
    from generate_series(1, 12) number$$,
  'aucun quota commercial ne bloque encore la création de dossiers'
);
select extensions.is(
  (select count(*) from public.protected_persons
   where owner_id = '94000000-0000-4000-8000-000000000001'),
  13::bigint,
  'les dossiers existants et nouveaux restent préservés au-delà des futurs paliers'
);
select extensions.is(
  (select count(*) from public.protected_person_access
   where protected_person_id = '94000000-0000-4000-8000-000000000101'
     and user_id = '94000000-0000-4000-8000-000000000002'
     and role = 'manager'),
  1::bigint,
  'les droits de partage existants restent inchangés'
);

select * from extensions.finish();
rollback;
