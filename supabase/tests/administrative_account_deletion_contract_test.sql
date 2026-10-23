begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'administrative_account_deletion_authorizations',
  'le registre des autorisations administratives existe'
);
select extensions.has_table(
  'public', 'administrative_account_deletion_events',
  'le journal administratif immuable existe'
);
select extensions.has_function(
  'public', 'get_administrative_account_deletion_diagnostic', array['uuid'],
  'le diagnostic administratif existe'
);
select extensions.has_function(
  'public', 'issue_administrative_account_deletion_authorization',
  array['uuid','uuid','text','jsonb'],
  'l’émission administrative existe'
);
select extensions.has_function(
  'public', 'begin_administrative_account_storage_neutralization',
  array['uuid','uuid','text','text','uuid','text','text','bigint','text'],
  'la réservation administrative spécialisée existe'
);
select extensions.has_function(
  'public', 'assert_administrative_account_deletion_barrier',
  array['uuid','bigint','text'],
  'la barrière administrative existe'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.administrative_account_deletion_authorizations',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.administrative_account_deletion_authorizations',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.administrative_account_deletion_authorizations',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.administrative_account_deletion_authorizations',
    'DELETE'
  )
  and not has_table_privilege(
    'service_role', 'public.administrative_account_deletion_authorizations',
    'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.administrative_account_deletion_events', 'INSERT'
  ),
  'les tables techniques ne sont accessibles directement à aucun rôle API'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.assert_administrative_account_deletion_barrier(uuid,bigint,text)',
    'EXECUTE'
  ),
  'les décisions métier utilisent uniquement la session administrateur authentifiée'
);
select extensions.ok(
  (
    select bool_and(proc.prosecdef and proc.proconfig = array['search_path=""'])
    from pg_proc proc
    where proc.oid in (
      'public.get_administrative_account_deletion_diagnostic(uuid)'::regprocedure,
      'public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb)'::regprocedure,
      'public.cancel_administrative_account_deletion_authorization(uuid,bigint)'::regprocedure,
      'public.begin_administrative_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)'::regprocedure,
      'public.assert_administrative_account_deletion_barrier(uuid,bigint,text)'::regprocedure
    )
  ),
  'les RPC exposées sont SECURITY DEFINER avec search_path fermé'
);
select extensions.is(
  (select guard_enabled from public.document_storage_guard_runtime_config
   where singleton),
  false,
  'la garde Storage reste désactivée'
);
select extensions.is(
  (select lifecycle_enabled from public.protected_person_archive_runtime_config
   where singleton),
  false,
  'le cycle d’archivage reste désactivé'
);

-- Instrumentation de lecture strictement transactionnelle pour les assertions.
grant select on public.administrative_account_deletion_authorizations,
  public.administrative_account_deletion_events,
  public.account_storage_neutralizations,
  public.document_operations,
  public.document_operation_targets,
  public.document_operation_backups,
  public.document_object_locks to authenticated, service_role;
create policy administrative_deletion_authorizations_test_select
on public.administrative_account_deletion_authorizations for select
to authenticated, service_role using (true);
create policy administrative_deletion_events_test_select
on public.administrative_account_deletion_events for select
to authenticated, service_role using (true);
create policy administrative_neutralizations_test_select
on public.account_storage_neutralizations for select
to authenticated, service_role using (true);
create policy administrative_operations_test_select
on public.document_operations for select
to authenticated, service_role using (true);
create policy administrative_targets_test_select
on public.document_operation_targets for select
to authenticated, service_role using (true);
create policy administrative_backups_test_select
on public.document_operation_backups for select
to authenticated, service_role using (true);
create policy administrative_locks_test_select
on public.document_object_locks for select
to authenticated, service_role using (true);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'administrative-delete-admin@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'administrative-delete-user@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'administrative-delete-clean@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'administrative-delete-storage@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
   'administrative-delete-other@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000006', 'authenticated', 'authenticated',
   'administrative-delete-admin-target@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000007', 'authenticated', 'authenticated',
   'administrative-delete-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000008', 'authenticated', 'authenticated',
   'administrative-delete-dependent@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-000000000009', 'authenticated', 'authenticated',
   'administrative-delete-expired@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated',
   'administrative-delete-cancelled@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated',
   'administrative-delete-nonterminal@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated',
   'administrative-delete-backup@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated',
   'administrative-delete-neutralization@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000e', 'authenticated', 'authenticated',
   'administrative-delete-dossier-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99600000-0000-4000-8000-00000000000f', 'authenticated', 'authenticated',
   'administrative-delete-unplanned@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now(),
    account_mode = case
      when user_id = '99600000-0000-4000-8000-000000000008' then null
      else 'autonomous'
    end
where user_id::text like '99600000-0000-4000-8000-%';
insert into public.platform_administrators(user_id)
values
  ('99600000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000006');
insert into public.account_subscriptions(owner_id, status, started_at)
values
  ('99600000-0000-4000-8000-000000000007', 'development', now()),
  ('99600000-0000-4000-8000-00000000000e', 'development', now());
insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('99600000-0000-4000-8100-000000000001',
   '99600000-0000-4000-8000-000000000007', 'Dossier', 'Bloquant'),
  ('99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8000-00000000000e', 'Dossier', 'Documents');
insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values (
  '99600000-0000-4000-8200-000000000001',
  '99600000-0000-4000-8100-000000000002',
  '99600000-0000-4000-8000-000000000008', 'read_only',
  '99600000-0000-4000-8000-00000000000e'
);
insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values (
  '99600000-0000-4000-8300-000000000001',
  '99600000-0000-4000-8100-000000000002',
  'checking', 'Banque test', 'Compte test', 0, '2026-01-01'
);
insert into public.transactions(
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values (
  '99600000-0000-4000-8400-000000000001',
  '99600000-0000-4000-8300-000000000001', '2026-01-02',
  'expense', 'Document administratif', 10
);
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99600000-0000-4000-8500-000000000001', 'transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
  '99600000-0000-4000-8000-000000000004',
  '99600000-0000-4000-8000-000000000004',
  '{"size":12,"mimetype":"application/pdf"}', 'admin-v1'
);

create temporary table administrative_test_values (
  name text primary key,
  authorization_id uuid,
  revision bigint,
  plan_hash text,
  operation_id uuid,
  target_id uuid
);
create temporary table administrative_test_plan(plan jsonb not null);
grant select, insert, update, delete on administrative_test_values,
  administrative_test_plan to authenticated;
insert into administrative_test_plan(plan)
values (jsonb_build_array(jsonb_build_object(
  'ordinal', 1,
  'bucketId', 'transaction-proofs',
  'objectPath', 'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
  'objectId', '99600000-0000-4000-8500-000000000001'::uuid,
  'objectVersion', 'admin-v1',
  'sha256', repeat('a', 64),
  'byteSize', 12,
  'mimeType', 'application/pdf',
  'protectedPersonId', '99600000-0000-4000-8100-000000000002'::uuid,
  'businessEntityType', 'transaction',
  'businessEntityId', '99600000-0000-4000-8400-000000000001'::uuid
)));

-- Un utilisateur ordinaire ne peut jamais invoquer les décisions métier.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000002', true
);
select extensions.throws_ok(
  $$select public.get_administrative_account_deletion_diagnostic(
      '99600000-0000-4000-8000-000000000003'
    )$$,
  'P4D01', 'Diagnostic administratif non autorisé.',
  'un non-administrateur ne peut pas consulter le diagnostic'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000003',
      '99600000-0000-4000-8600-000000000001', 'Motif', '[]'::jsonb
    )$$,
  'P4D01',
  'Suppression administrative non autorisée.',
  'un non-administrateur ne peut pas émettre une autorisation'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);

select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000001',
      '99600000-0000-4000-8600-000000000002', 'Auto-suppression', '[]'::jsonb
    )$$,
  'P4D01',
  'Le compte ne satisfait pas les conditions de suppression administrative.',
  'l’auto-suppression de l’administrateur est refusée'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000006',
      '99600000-0000-4000-8600-000000000003', 'Administrateur cible', '[]'::jsonb
    )$$,
  'P4D01',
  'Le compte ne satisfait pas les conditions de suppression administrative.',
  'un administrateur de plateforme ne peut pas être ciblé'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000007',
      '99600000-0000-4000-8600-000000000004', 'Propriétaire', '[]'::jsonb
    )$$,
  'P4D01',
  'Le compte ne satisfait pas les conditions de suppression administrative.',
  'le propriétaire d’un dossier est refusé'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000008',
      '99600000-0000-4000-8600-000000000005', 'Dépendance', '[]'::jsonb
    )$$,
  'P4D01',
  'Le compte ne satisfait pas les conditions de suppression administrative.',
  'une dépendance métier existante bloque la suppression'
);
select extensions.ok(
  (public.get_administrative_account_deletion_diagnostic(
    '99600000-0000-4000-8000-000000000004'
  )->'storageObjects'->0->>'objectPath') like 'protected-persons/%',
  'le diagnostic inventorie uniquement les métadonnées nécessaires'
);
select extensions.is(
  public.get_administrative_account_deletion_diagnostic(
    '99600000-0000-4000-8000-000000000004'
  )->'blockingAnomalies',
  '[]'::jsonb,
  'un objet canonique et correctement décrit ne crée pas d’anomalie'
);

insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select 'clean',
  (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint,
  result->>'planHash'
from (
  select public.issue_administrative_account_deletion_authorization(
    '99600000-0000-4000-8000-000000000003',
    '99600000-0000-4000-8600-000000000010',
    'Suppression administrative contrôlée', '[]'::jsonb
  ) result
) issued;
select extensions.is(
  (select state from public.administrative_account_deletion_authorizations
   where id = (select authorization_id from administrative_test_values
               where name = 'clean')),
  'active',
  'un administrateur autorisé crée une autorisation active'
);
select extensions.is(
  (
    public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000003',
      '99600000-0000-4000-8600-000000000010',
      'Suppression administrative contrôlée', '[]'::jsonb
    )->>'authorizationId'
  )::uuid,
  (select authorization_id from administrative_test_values where name = 'clean'),
  'une double soumission identique reste idempotente'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000003',
      '99600000-0000-4000-8600-000000000010',
      'Motif divergent', '[]'::jsonb
    )$$,
  'P4D04',
  'La tentative administrative est déjà utilisée pour une autre demande.',
  'un attempt_id ne peut pas être réutilisé pour une autre intention'
);

insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select 'expired', (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint, result->>'planHash'
from (
  select public.issue_administrative_account_deletion_authorization(
    '99600000-0000-4000-8000-000000000009',
    '99600000-0000-4000-8600-000000000011', 'Expiration', '[]'::jsonb
  ) result
) issued;
reset role;
update public.administrative_account_deletion_authorizations
set issued_at = timing.expired_at - interval '10 minutes',
    expires_at = timing.expired_at
from (select clock_timestamp() - interval '1 minute' as expired_at) timing
where id = (select authorization_id from administrative_test_values
            where name = 'expired');
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'expired'),
    (select plan_hash from administrative_test_values where name = 'expired')
  ),
  'P4D01', 'Autorisation administrative inactive ou expirée.',
  'une autorisation expirée ne permet pas de franchir la barrière'
);

insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select 'cancelled', (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint, result->>'planHash'
from (
  select public.issue_administrative_account_deletion_authorization(
    '99600000-0000-4000-8000-00000000000a',
    '99600000-0000-4000-8600-000000000012', 'Annulation', '[]'::jsonb
  ) result
) issued;
select extensions.is(
  public.cancel_administrative_account_deletion_authorization(
    (select authorization_id from administrative_test_values where name = 'cancelled'),
    0
  )->>'state',
  'cancelled',
  'une autorisation active peut être annulée explicitement'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 1, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'cancelled'),
    (select plan_hash from administrative_test_values where name = 'cancelled')
  ),
  'P4D01', 'Autorisation administrative inactive ou expirée.',
  'une autorisation annulée ne peut pas franchir la barrière'
);

select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000004',
      '99600000-0000-4000-8600-000000000013', 'Plan divergent',
      jsonb_build_array(jsonb_build_object(
        'ordinal', 1, 'bucketId', 'transaction-proofs',
        'objectPath', 'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
        'objectId', '99600000-0000-4000-8500-000000000001'::uuid,
        'objectVersion', 'version-incorrecte', 'sha256', repeat('a',64),
        'byteSize', 12, 'mimeType', 'application/pdf',
        'protectedPersonId', '99600000-0000-4000-8100-000000000002'::uuid,
        'businessEntityType', 'transaction',
        'businessEntityId', '99600000-0000-4000-8400-000000000001'::uuid
      ))
    )$$,
  'P4D03', 'Le plan ne correspond pas à l’inventaire Storage courant.',
  'un plan divergent du catalogue Storage est refusé'
);

insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select 'storage', (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint, result->>'planHash'
from (
  select public.issue_administrative_account_deletion_authorization(
    '99600000-0000-4000-8000-000000000004',
    '99600000-0000-4000-8600-000000000014', 'Objet Storage',
    (select plan from administrative_test_plan)
  ) result
) issued;
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'storage'),
    (select plan_hash from administrative_test_values where name = 'storage')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'un objet encore possédé par la cible bloque la barrière'
);

insert into administrative_test_values(name, operation_id, target_id)
select 'storage-operation',
  (result->>'operationId')::uuid, (result->>'targetId')::uuid
from (
  select public.begin_administrative_account_storage_neutralization(
    (select authorization_id from administrative_test_values where name = 'storage'),
    '99600000-0000-4000-8600-000000000114',
    'transaction-proofs',
    'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
    '99600000-0000-4000-8500-000000000001', 'admin-v1', repeat('a',64),
    12, 'application/pdf'
  ) result
) reserved;
select extensions.is(
  (
    public.begin_administrative_account_storage_neutralization(
      (select authorization_id from administrative_test_values where name = 'storage'),
      '99600000-0000-4000-8600-000000000114',
      'transaction-proofs',
      'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
      '99600000-0000-4000-8500-000000000001', 'admin-v1', repeat('a',64),
      12, 'application/pdf'
    )->>'operationId'
  )::uuid,
  (select operation_id from administrative_test_values where name = 'storage-operation'),
  'une réservation répétée avec la même intention est idempotente'
);
select extensions.is(
  (select initiator_kind from public.document_operations
   where id = (select operation_id from administrative_test_values
               where name = 'storage-operation')),
  'platform_admin',
  'la neutralisation conserve l’administrateur réel sans usurper la cible'
);
select extensions.lives_ok(
  $$select public.get_account_storage_neutralization_progress(
      (select operation_id from administrative_test_values
       where name = 'storage-operation')
    )$$,
  'l’administrateur initiateur peut consulter la progression'
);
reset role;

-- La cible ne peut pas lire la progression interne d’une suppression administrative.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000004', true
);
select extensions.throws_ok(
  $$select public.get_account_storage_neutralization_progress(
      (select operation_id from administrative_test_values
       where name = 'storage-operation')
    )$$,
  'P4N01', 'Accès à la neutralisation documentaire refusé.',
  'la cible ne reçoit pas les détails de la neutralisation administrative'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000006', true
);
select extensions.throws_ok(
  $$select public.get_account_storage_neutralization_progress(
      (select operation_id from administrative_test_values
       where name = 'storage-operation')
    )$$,
  'P4N01', 'Accès à la neutralisation documentaire refusé.',
  'un autre administrateur ne peut pas consulter une tentative non transférable'
);
reset role;

-- Une seconde autorisation ne peut réserver le même objet déjà verrouillé.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select 'storage-concurrent', (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint, result->>'planHash'
from (
  select public.issue_administrative_account_deletion_authorization(
    '99600000-0000-4000-8000-000000000004',
    '99600000-0000-4000-8600-000000000015', 'Concurrence',
    (select plan from administrative_test_plan)
  ) result
) issued;
select extensions.throws_ok(
  format(
    $sql$select public.begin_administrative_account_storage_neutralization(
      %L, '99600000-0000-4000-8600-000000000115', 'transaction-proofs',
      'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof',
      '99600000-0000-4000-8500-000000000001', 'admin-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select authorization_id from administrative_test_values
     where name = 'storage-concurrent'), repeat('a',64)
  ),
  'P4O05', 'Ce fichier est déjà réservé par une autre opération.',
  'la réservation unique empêche deux neutralisations concurrentes'
);
reset role;

-- Simulation SQL de l’état terminal produit par le moteur durable : l’objet
-- planifié n’est plus possédé, la neutralisation et l’opération sont terminées.
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99600000-0000-4000-8500-000000000001';
select set_config('storage.allow_delete_query', 'false', true);
update public.document_operations
set state = 'executing', started_at = now(), row_revision = row_revision + 1
where id = (
  select operation_id from administrative_test_values
  where name = 'storage-operation'
);
update public.account_storage_neutralizations
set phase = 'finalized', finalized_at = now(), row_revision = row_revision + 1
where operation_id = (
  select operation_id from administrative_test_values
  where name = 'storage-operation'
);
update public.document_operations
set state = 'completed', closed_at = now(), row_revision = row_revision + 1
where id = (
  select operation_id from administrative_test_values
  where name = 'storage-operation'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.assert_administrative_account_deletion_barrier(
    (select authorization_id from administrative_test_values where name = 'storage'),
    0,
    (select plan_hash from administrative_test_values where name = 'storage')
  )->>'alreadySealed',
  'false',
  'un plan non vide entièrement neutralisé franchit la barrière'
);
reset role;

-- Une écriture privilégiée postérieure au scellement doit invalider la
-- répétition de la barrière tant que l’anomalie subsiste.
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99600000-0000-4000-8500-000000000013', 'transaction-proofs',
  'unexpected-after-seal', '99600000-0000-4000-8000-000000000004',
  '99600000-0000-4000-8000-000000000004',
  '{"size":1,"mimetype":"application/pdf"}', 'unexpected-v1'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 1, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'storage'),
    (select plan_hash from administrative_test_values where name = 'storage')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'un objet nouveau bloque aussi la répétition d’une barrière scellée'
);
reset role;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99600000-0000-4000-8500-000000000013';
select set_config('storage.allow_delete_query', 'false', true);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.assert_administrative_account_deletion_barrier(
    (select authorization_id from administrative_test_values where name = 'storage'),
    1,
    (select plan_hash from administrative_test_values where name = 'storage')
  )->>'alreadySealed',
  'true',
  'une barrière scellée redevient utilisable après correction de l’anomalie'
);
reset role;

-- Les trois classes d’anomalies documentaires bloquent la barrière finale.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
insert into administrative_test_values(name, authorization_id, revision, plan_hash)
select label, (result->>'authorizationId')::uuid,
  (result->>'revision')::bigint, result->>'planHash'
from (
  values
    ('nonterminal', public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-00000000000b',
      '99600000-0000-4000-8600-000000000020', 'Opération non terminale', '[]'::jsonb)),
    ('backup', public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-00000000000c',
      '99600000-0000-4000-8600-000000000021', 'Sauvegarde résiduelle', '[]'::jsonb)),
    ('unfinished', public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-00000000000d',
      '99600000-0000-4000-8600-000000000022', 'Neutralisation inachevée', '[]'::jsonb)),
    ('unplanned', public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-00000000000f',
      '99600000-0000-4000-8600-000000000023', 'Neutralisation hors plan', '[]'::jsonb))
) issued(label, result);
reset role;

insert into public.document_operations(
  id, protected_person_id, initiated_by, initiator_subject_id,
  initiator_kind, workflow, business_entity_type, business_entity_id,
  client_request_id, state, target_signature, closed_at
) values
  ('99600000-0000-4000-8700-000000000020',
   '99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8000-000000000001',
   '99600000-0000-4000-8000-00000000000b', 'platform_admin',
   'administrative_repair', 'protected_person',
   '99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8600-000000000120', 'reserved', '[]'::jsonb, null),
  ('99600000-0000-4000-8700-000000000021',
   '99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8000-000000000001',
   '99600000-0000-4000-8000-00000000000c', 'platform_admin',
   'administrative_repair', 'protected_person',
   '99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8600-000000000121', 'completed', '[]'::jsonb, now()),
  ('99600000-0000-4000-8700-000000000022',
   '99600000-0000-4000-8100-000000000002',
   '99600000-0000-4000-8000-000000000001',
   '99600000-0000-4000-8000-00000000000d', 'platform_admin',
   'account_storage_neutralization', 'transaction',
   '99600000-0000-4000-8400-000000000001',
   '99600000-0000-4000-8600-000000000122', 'reserved', '[]'::jsonb, null);
insert into public.document_operations(
  id, protected_person_id, initiated_by, initiator_subject_id,
  initiator_kind, workflow, business_entity_type, business_entity_id,
  client_request_id, state, target_signature, closed_at
) values (
  '99600000-0000-4000-8700-000000000023',
  '99600000-0000-4000-8100-000000000002',
  '99600000-0000-4000-8000-000000000001',
  '99600000-0000-4000-8000-00000000000f', 'platform_admin',
  'account_storage_neutralization', 'transaction',
  '99600000-0000-4000-8400-000000000001',
  '99600000-0000-4000-8600-000000000123', 'completed', '[]'::jsonb, now()
);
insert into public.document_operation_targets(
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists,
  expected_object_id, expected_object_version, expected_snapshot_captured_at
) values
  ('99600000-0000-4000-8800-000000000021',
   '99600000-0000-4000-8700-000000000021', 1, 'transaction-proofs',
   'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof-backup',
   'primary', 'delete', 'insert', true,
   '99600000-0000-4000-8500-000000000021', 'backup-v1', now()),
  ('99600000-0000-4000-8800-000000000022',
   '99600000-0000-4000-8700-000000000022', 1, 'transaction-proofs',
   'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof-unfinished',
   'primary', 'delete', 'insert', true,
   '99600000-0000-4000-8500-000000000022', 'unfinished-v1', now()),
  ('99600000-0000-4000-8800-000000000023',
   '99600000-0000-4000-8700-000000000023', 1, 'transaction-proofs',
   'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof-unplanned',
   'primary', 'delete', 'insert', true,
   '99600000-0000-4000-8500-000000000023', 'unplanned-v1', now());
insert into public.document_operation_backups(
  id, operation_id, target_id, protected_person_id, initiator_subject_id,
  original_bucket_id, original_object_path, original_object_id,
  original_object_version, recovery_object_path, byte_size, mime_type,
  sha256, state, recovery_object_id, recovery_object_version,
  upload_verified_at
) values (
  '99600000-0000-4000-8900-000000000021',
  '99600000-0000-4000-8700-000000000021',
  '99600000-0000-4000-8800-000000000021',
  '99600000-0000-4000-8100-000000000002',
  '99600000-0000-4000-8000-00000000000c', 'transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000002/transactions/99600000-0000-4000-8400-000000000001/proof-backup',
  '99600000-0000-4000-8500-000000000021', 'backup-v1',
  'operations/99600000-0000-4000-8700-000000000021/targets/99600000-0000-4000-8800-000000000021/backup',
  12, 'application/pdf', repeat('b',64), 'verified',
  '99600000-0000-4000-8900-000000000121', 'recovery-v1', now()
);
insert into public.account_storage_neutralizations(
  operation_id, target_id, authorization_id,
  administrative_authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type
) values (
  '99600000-0000-4000-8700-000000000022',
  '99600000-0000-4000-8800-000000000022', null,
  (select authorization_id from administrative_test_values
   where name = 'unfinished'),
  '99600000-0000-4000-8000-00000000000d', repeat('c',64), 12,
  'application/pdf'
);
insert into public.account_storage_neutralizations(
  operation_id, target_id, authorization_id,
  administrative_authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type, phase, finalized_at
) values (
  '99600000-0000-4000-8700-000000000023',
  '99600000-0000-4000-8800-000000000023', null,
  (select authorization_id from administrative_test_values
   where name = 'unplanned'),
  '99600000-0000-4000-8000-00000000000f', repeat('d',64), 12,
  'application/pdf', 'finalized', now()
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.ok(
  public.get_administrative_account_deletion_diagnostic(
    '99600000-0000-4000-8000-00000000000b'
  )->'blockingAnomalies' ? 'NON_TERMINAL_DOCUMENT_OPERATION',
  'le diagnostic classe une opération documentaire non terminale'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'nonterminal'),
    (select plan_hash from administrative_test_values where name = 'nonterminal')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'une opération non terminale bloque la barrière'
);
select extensions.ok(
  public.get_administrative_account_deletion_diagnostic(
    '99600000-0000-4000-8000-00000000000c'
  )->'blockingAnomalies' ? 'UNCLEARED_DURABLE_BACKUP',
  'le diagnostic classe une sauvegarde durable non nettoyée'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'backup'),
    (select plan_hash from administrative_test_values where name = 'backup')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'une sauvegarde non nettoyée bloque la barrière'
);
select extensions.ok(
  public.get_administrative_account_deletion_diagnostic(
    '99600000-0000-4000-8000-00000000000d'
  )->'blockingAnomalies' ? 'UNFINISHED_STORAGE_NEUTRALIZATION',
  'le diagnostic classe une neutralisation inachevée'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'unfinished'),
    (select plan_hash from administrative_test_values where name = 'unfinished')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'une neutralisation inachevée bloque la barrière'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'unplanned'),
    (select plan_hash from administrative_test_values where name = 'unplanned')
  ),
  'P4D05', 'La suppression Auth reste bloquée par l’état documentaire.',
  'une neutralisation terminale supplémentaire hors du plan bloque la barrière'
);
select extensions.is(
  public.cancel_administrative_account_deletion_authorization(
    (select authorization_id from administrative_test_values where name = 'unfinished'),
    0
  )->>'state',
  'cancelled',
  'la tentative inachevée peut être annulée sans masquer sa récupération'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.lives_ok(
  $$select public.get_account_storage_neutralization_progress(
      '99600000-0000-4000-8700-000000000022'
    )$$,
  'le moteur durable peut reprendre une neutralisation déjà commencée après annulation'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-00000000000d","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-00000000000d', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une neutralisation inachevée maintient le gel après annulation'
);
reset role;

-- Le gel administratif agit sur la cible et non sur les autres utilisateurs.
grant select, insert, update, delete on storage.objects to authenticated;
create policy administrative_deletion_freeze_test_select
on storage.objects for select to authenticated using (true);
create policy administrative_deletion_freeze_test_insert
on storage.objects for insert to authenticated with check (true);
create policy administrative_deletion_freeze_test_update
on storage.objects for update to authenticated using (true) with check (true);
create policy administrative_deletion_freeze_test_delete
on storage.objects for delete to authenticated using (true);
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99600000-0000-4000-8500-000000000012', 'transaction-proofs',
  'freeze-admin-existing', '99600000-0000-4000-8000-000000000003',
  '99600000-0000-4000-8000-000000000003',
  '{"size":1,"mimetype":"application/pdf"}', 'freeze-v1'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000003', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une autorisation administrative active gèle les écritures de la cible'
);
select extensions.throws_ok(
  $$insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
    values (
      '99600000-0000-4000-8500-000000000010', 'transaction-proofs',
      'freeze-admin-insert', '99600000-0000-4000-8000-000000000003',
      '99600000-0000-4000-8000-000000000003',
      '{"size":1,"mimetype":"application/pdf"}', 'freeze-v1'
    )$$,
  '42501',
  'new row violates row-level security policy "account_deletion_freeze_storage_insert" for table "objects"',
  'le gel refuse INSERT pour la cible'
);
select extensions.results_eq(
  $$with changed as (
      update storage.objects set user_metadata = '{"changed":true}'
      where id = '99600000-0000-4000-8500-000000000012'
      returning 1
    ) select count(*)::integer from changed$$,
  array[0],
  'le gel refuse UPDATE pour la cible'
);
select set_config('storage.allow_delete_query', 'true', true);
select extensions.results_eq(
  $$with removed as (
      delete from storage.objects
      where id = '99600000-0000-4000-8500-000000000012'
      returning 1
    ) select count(*)::integer from removed$$,
  array[0],
  'le gel refuse DELETE pour la cible'
);
select set_config('storage.allow_delete_query', 'false', true);
select extensions.throws_ok(
  $$select public.begin_transaction_proof_document_operation(
      gen_random_uuid(), gen_random_uuid(), 'create', gen_random_uuid()
    )$$,
  'P4N06',
  'Les écritures documentaires sont suspendues pendant la suppression du compte.',
  'le gel couvre aussi les nouvelles réservations documentaires'
);
reset role;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99600000-0000-4000-8500-000000000012';
select set_config('storage.allow_delete_query', 'false', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000005', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), false,
  'le gel de la cible ne bloque pas un autre utilisateur'
);
select extensions.lives_ok(
  $$insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
    values (
      '99600000-0000-4000-8500-000000000011', 'transaction-proofs',
      'freeze-admin-other', '99600000-0000-4000-8000-000000000005',
      '99600000-0000-4000-8000-000000000005',
      '{"size":1,"mimetype":"application/pdf"}', 'freeze-v1'
    )$$,
  'un autre utilisateur peut toujours écrire'
);
reset role;

-- Barrière vide : scellement atomique, idempotence et non-réactivation.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99600000-0000-4000-8000-000000000001', true
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 99, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'clean'),
    (select plan_hash from administrative_test_values where name = 'clean')
  ),
  'P4D01', 'Autorisation administrative inactive ou expirée.',
  'une révision obsolète ne peut pas franchir la barrière'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_administrative_account_deletion_barrier(%L, 0, %L)$sql$,
    (select authorization_id from administrative_test_values where name = 'clean'),
    repeat('f',64)
  ),
  'P4D03', 'Le plan documentaire administratif a divergé.',
  'une empreinte de plan divergente bloque la barrière'
);
select extensions.is(
  public.assert_administrative_account_deletion_barrier(
    (select authorization_id from administrative_test_values where name = 'clean'),
    0,
    (select plan_hash from administrative_test_values where name = 'clean')
  )->>'alreadySealed',
  'false',
  'la première barrière conforme scelle l’autorisation'
);
select extensions.is(
  public.assert_administrative_account_deletion_barrier(
    (select authorization_id from administrative_test_values where name = 'clean'),
    0,
    (select plan_hash from administrative_test_values where name = 'clean')
  )->>'alreadySealed',
  'true',
  'la répétition de la barrière scellée est idempotente'
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_administrative_account_storage_neutralization(
      %L, gen_random_uuid(), 'transaction-proofs', 'objet-inexistant',
      gen_random_uuid(), 'v1', %L, 1, 'application/pdf'
    )$sql$,
    (select authorization_id from administrative_test_values where name = 'clean'),
    repeat('a',64)
  ),
  'P4D01', 'Autorisation administrative inactive ou expirée.',
  'une autorisation scellée ne peut pas ouvrir une nouvelle neutralisation'
);
select extensions.throws_ok(
  format(
    $sql$select public.cancel_administrative_account_deletion_authorization(%L, 1)$sql$,
    (select authorization_id from administrative_test_values where name = 'clean')
  ),
  'P4D04', 'Une autorisation scellée ne peut plus être annulée.',
  'une autorisation scellée ne peut pas être réactivée par annulation'
);
select extensions.throws_ok(
  $$select public.issue_administrative_account_deletion_authorization(
      '99600000-0000-4000-8000-000000000005',
      '99600000-0000-4000-8600-000000000010',
      'Réutilisation après scellement', '[]'::jsonb
    )$$,
  'P4D04',
  'La tentative administrative est déjà utilisée pour une autre demande.',
  'une tentative scellée ne peut pas être transférée à une autre cible'
);
reset role;

-- Les opérations personnelles conservent leurs privilèges historiques.
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.issue_account_deletion_document_authorization(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.finalize_account_storage_neutralization(uuid,bigint)',
    'EXECUTE'
  ),
  'le contrat personnel historique conserve ses droits d’exécution'
);

select * from extensions.finish();
rollback;
