begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_function(
  'public',
  'get_protected_person_feature_capabilities',
  array['uuid'],
  'la résolution centralisée des capacités existe'
);
select extensions.has_function(
  'public',
  'check_protected_person_feature_access',
  array['uuid', 'text', 'text'],
  'la vérification unitaire d’une capacité existe'
);
select extensions.ok(
  (select procedure.prosecdef
   from pg_proc procedure
   where procedure.oid = 'public.get_protected_person_feature_capabilities(uuid)'::regprocedure),
  'la résolution est SECURITY DEFINER pour franchir uniquement la RLS commerciale du propriétaire'
);
select extensions.ok(
  not (select procedure.prosecdef
       from pg_proc procedure
       where procedure.oid = 'public.check_protected_person_feature_access(uuid,text,text)'::regprocedure),
  'le helper de vérification reste SECURITY INVOKER'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.get_protected_person_feature_capabilities(uuid)',
    'EXECUTE'
  ),
  'authenticated peut résoudre les capacités sous contrôle PostgreSQL'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.get_protected_person_feature_capabilities(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_protected_person_feature_capabilities(uuid)',
    'EXECUTE'
  ),
  'la fonction privilégiée n’est exposée ni à anon ni directement à service_role'
);
select extensions.ok(
  pg_get_function_result(
    'public.get_protected_person_feature_capabilities(uuid)'::regprocedure
  ) not ilike '%owner_id%'
  and pg_get_function_result(
    'public.get_protected_person_feature_capabilities(uuid)'::regprocedure
  ) not ilike '%plan_key%'
  and pg_get_function_result(
    'public.get_protected_person_feature_capabilities(uuid)'::regprocedure
  ) not ilike '%subscription_status%'
  and pg_get_function_result(
    'public.get_protected_person_feature_capabilities(uuid)'::regprocedure
  ) not ilike '%capacity%'
  and pg_get_function_result(
    'public.get_protected_person_feature_capabilities(uuid)'::regprocedure
  ) not ilike '%price%','la sortie ne révèle aucune donnée commerciale privée'
);
select extensions.ok(
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_proc procedure
   where procedure.oid = 'public.get_protected_person_feature_capabilities(uuid)'::regprocedure),
  'la fonction privilégiée fixe un search_path vide'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000001','authenticated','authenticated','essential-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000002','authenticated','authenticated','comfort-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000003','authenticated','authenticated','premium-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000004','authenticated','authenticated','development-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000005','authenticated','authenticated','missing-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000006','authenticated','authenticated','premium-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000007','authenticated','authenticated','premium-reader@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000008','authenticated','authenticated','essential-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000009','authenticated','authenticated','foreign-user@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000010','authenticated','authenticated','inactive-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','95000000-0000-4000-8000-000000000011','authenticated','authenticated','platform-admin@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '95000000-0000-4000-8000-%';

insert into public.platform_administrators(user_id)
values ('95000000-0000-4000-8000-000000000011');

insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('95000000-0000-4000-8000-000000000101','95000000-0000-4000-8000-000000000001','Forfait','Essentiel'),
  ('95000000-0000-4000-8000-000000000102','95000000-0000-4000-8000-000000000002','Forfait','Confort'),
  ('95000000-0000-4000-8000-000000000103','95000000-0000-4000-8000-000000000003','Forfait','Premium'),
  ('95000000-0000-4000-8000-000000000104','95000000-0000-4000-8000-000000000004','Mode','Développement'),
  ('95000000-0000-4000-8000-000000000105','95000000-0000-4000-8000-000000000005','Abonnement','Absent');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('95000000-0000-4000-8000-000000000201','95000000-0000-4000-8000-000000000103','95000000-0000-4000-8000-000000000006','manager','95000000-0000-4000-8000-000000000003'),
  ('95000000-0000-4000-8000-000000000202','95000000-0000-4000-8000-000000000103','95000000-0000-4000-8000-000000000007','read_only','95000000-0000-4000-8000-000000000003'),
  ('95000000-0000-4000-8000-000000000203','95000000-0000-4000-8000-000000000101','95000000-0000-4000-8000-000000000008','manager','95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-8000-000000000204','95000000-0000-4000-8000-000000000103','95000000-0000-4000-8000-000000000010','manager','95000000-0000-4000-8000-000000000003');

update public.application_user_authorizations
set status = 'rejected', status_changed_at = now()
where user_id = '95000000-0000-4000-8000-000000000010';

insert into public.account_subscriptions(
  owner_id,
  plan_key,
  dossier_capacity_key,
  status
) values
  ('95000000-0000-4000-8000-000000000001','essential','included','active'),
  ('95000000-0000-4000-8000-000000000002','comfort','included','active'),
  ('95000000-0000-4000-8000-000000000003','premium','included','active');

insert into public.account_subscriptions(owner_id, status)
values ('95000000-0000-4000-8000-000000000004','development');

set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (select count(*) from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000101')),
  5::bigint,
  'le propriétaire Essentiel reçoit une décision pour chaque fonctionnalité'
);
select extensions.ok(
  (select can_read from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000101') where feature_key = 'core_management'),
  'le propriétaire Essentiel conserve le socle métier'
);
select extensions.ok(
  (select can_write from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000101') where feature_key = 'existing_accounting_documents'),
  'le propriétaire Essentiel conserve l’écriture des documents comptables existants'
);
select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','data_export','read')),
  'l’export reste inclus pour un propriétaire Essentiel'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','data_export','write')),
  'operation_not_supported',
  'l’export est une capacité de lecture/exécution, pas une écriture métier'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','bank_operation_automation','write')),
  'feature_upcoming',
  'une fonctionnalité à venir reste indisponible avant toute lecture du forfait'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000004","role":"authenticated"}',true);

select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000104','core_management','read')),
  'le mode Développement contourne les restrictions commerciales disponibles'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000104','central_document_management','write')),
  'feature_upcoming',
  'le mode Développement ne contourne pas l’état upcoming'
);

reset role;

-- Simule la livraison future des deux fonctions afin de tester dès maintenant
-- la matrice commerciale et les rôles sans modifier leur état livré.
update public.subscription_features
set implementation_status = 'available'
where feature_key in (
  'bank_operation_automation',
  'central_document_management'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','bank_operation_automation','write')),
  'not_in_plan',
  'Essentiel n’inclut pas l’automatisation bancaire lorsqu’elle devient disponible'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','central_document_management','read')),
  'not_in_plan',
  'Essentiel n’inclut pas la gestion documentaire centralisée'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000002","role":"authenticated"}',true);

select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000102','bank_operation_automation','write')),
  'Confort inclut l’automatisation bancaire lorsqu’elle devient disponible'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000102','central_document_management','read')),
  'not_in_plan',
  'Confort n’inclut pas la gestion documentaire centralisée'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000003","role":"authenticated"}',true);

select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','bank_operation_automation','write')),
  'Premium inclut l’automatisation bancaire'
);
select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','central_document_management','write')),
  'Premium inclut la gestion documentaire centralisée'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000006","role":"authenticated"}',true);

select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','central_document_management','write')),
  'un gestionnaire bénéficie du Premium du propriétaire du dossier'
);
select extensions.is(
  (select count(*) from public.account_subscriptions),
  0::bigint,
  'le gestionnaire ne peut pas lire l’abonnement Premium du propriétaire'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000008',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000008","role":"authenticated"}',true);

select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','central_document_management','write')),
  'not_in_plan',
  'un gestionnaire ne peut pas élever un dossier Essentiel au-delà du forfait du propriétaire'
);
select extensions.throws_ok(
  $$insert into public.account_subscriptions(owner_id, plan_key, dossier_capacity_key, status)
    values ('95000000-0000-4000-8000-000000000008','premium','included','active')$$,
  '42501',
  'permission denied for table account_subscriptions',
  'un gestionnaire ne peut ni se donner Premium ni modifier les abonnements'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000007',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000007","role":"authenticated"}',true);

select extensions.ok(
  (select allowed from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','existing_accounting_documents','read')),
  'un lecteur conserve la consultation des documents comptables existants'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','existing_accounting_documents','write')),
  'role_forbidden',
  'le forfait Premium ne contourne pas le rôle lecture seule en écriture'
);
select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000103','data_export','read')),
  'role_forbidden',
  'l’export ZIP complet reste refusé au lecteur'
);
select extensions.ok(
  public.can_read_protected_person('95000000-0000-4000-8000-000000000103'),
  'les permissions de consultation historiques du lecteur restent actives'
);
select extensions.ok(
  not public.can_manage_protected_person('95000000-0000-4000-8000-000000000103'),
  'le moteur n’élève pas le lecteur au rôle gestionnaire'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000005","role":"authenticated"}',true);

select extensions.is(
  (select denial_reason from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000105','core_management','read')),
  'subscription_missing',
  'l’absence d’abonnement n’attribue jamais silencieusement Premium'
);
select extensions.is(
  (select count(*) from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000105') where can_read or can_write),
  0::bigint,
  'aucune capacité commerciale n’est accordée sans abonnement'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000009',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000009","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select * from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000103')$$,
  '42501',
  'Dossier introuvable.',
  'un utilisateur étranger ne peut pas résoudre les capacités du dossier'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000010',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000010","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select * from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000103')$$,
  '42501',
  'Dossier introuvable.',
  'un utilisateur administrativement inactif ne reçoit aucune capacité'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000011',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000011","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select * from public.get_protected_person_feature_capabilities('95000000-0000-4000-8000-000000000103')$$,
  '42501',
  'Dossier introuvable.',
  'le rôle administrateur de plateforme n’accorde aucun accès métier transversal'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.throws_ok(
  $$select * from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','unknown_feature','read')$$,
  '23514',
  'Fonctionnalité inconnue.',
  'une clé de fonctionnalité inconnue est refusée'
);
select extensions.throws_ok(
  $$select * from public.check_protected_person_feature_access('95000000-0000-4000-8000-000000000101','core_management','admin')$$,
  '23514',
  'Mode d’accès invalide.',
  'un mode d’accès inconnu est refusé'
);

select * from extensions.finish();
rollback;
