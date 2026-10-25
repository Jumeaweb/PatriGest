begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'document_repair_authorizations',
  'le registre des autorisations de réparation existe'
);
select extensions.has_table(
  'public', 'document_repair_items',
  'le plan détaillé de réparation existe'
);
select extensions.has_table(
  'public', 'document_repair_events',
  'le journal append-only de réparation existe'
);
select extensions.has_function(
  'public', 'get_administrative_document_repair_diagnostic', array['uuid'],
  'le diagnostic administratif existe'
);
select extensions.has_function(
  'public', 'issue_administrative_document_repair_authorization',
  array['uuid','bigint','uuid','text','jsonb'],
  'l’autorisation spécialisée existe'
);
select extensions.has_function(
  'public', 'seal_administrative_document_repair',
  array['uuid','bigint','text'],
  'le scellement probant existe'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.document_repair_authorizations', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.document_repair_items', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.document_repair_events', 'INSERT'
  )
  and not has_table_privilege(
    'service_role', 'public.document_repair_authorizations', 'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.document_repair_items', 'UPDATE'
  ),
  'aucun rôle API ne reçoit d’accès direct aux tables techniques'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.normalize_administrative_document_repair_plan(uuid,bigint,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.assert_administrative_document_repair_sql_evidence(uuid,boolean)',
    'EXECUTE'
  ),
  'les décisions exigent une session administrateur et les primitives restent internes'
);
select extensions.ok(
  (
    select bool_and(procedure.prosecdef
      and procedure.proconfig = array['search_path=""'])
    from pg_proc procedure
    where procedure.oid in (
      'public.get_administrative_document_repair_diagnostic(uuid)'::regprocedure,
      'public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb)'::regprocedure,
      'public.get_administrative_document_repair_authorization(uuid,uuid)'::regprocedure,
      'public.cancel_administrative_document_repair_authorization(uuid,bigint)'::regprocedure,
      'public.seal_administrative_document_repair(uuid,bigint,text)'::regprocedure,
      'public.assert_administrative_document_repair_sql_evidence(uuid,boolean)'::regprocedure
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

-- L’instrumentation de lecture est strictement locale à cette transaction.
grant select on public.document_repair_authorizations,
  public.document_repair_items, public.document_repair_events,
  public.document_operations, public.document_operation_targets,
  public.document_object_locks to authenticated;
grant update on public.document_repair_events to authenticated;
create policy document_repair_authorizations_test_select
on public.document_repair_authorizations for select
to authenticated using (true);
create policy document_repair_items_test_select
on public.document_repair_items for select
to authenticated using (true);
create policy document_repair_events_test_select
on public.document_repair_events for select
to authenticated using (true);
create policy document_repair_events_test_update
on public.document_repair_events for update
to authenticated using (true) with check (true);
create policy document_repair_operations_test_select
on public.document_operations for select
to authenticated using (true);
create policy document_repair_targets_test_select
on public.document_operation_targets for select
to authenticated using (true);
create policy document_repair_locks_test_select
on public.document_object_locks for select
to authenticated using (true);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '99400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'repair-admin@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99400000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'repair-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99400000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'repair-other@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99400000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'repair-second-admin@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id in (
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000002',
  '99400000-0000-4000-8000-000000000003',
  '99400000-0000-4000-8000-000000000004'
);
insert into public.platform_administrators(user_id)
values
  ('99400000-0000-4000-8000-000000000001'),
  ('99400000-0000-4000-8000-000000000004');
insert into public.account_subscriptions(owner_id, status, started_at)
values ('99400000-0000-4000-8000-000000000002', 'development', now());
insert into public.protected_persons(id, owner_id, first_name, last_name)
values (
  '99400000-0000-4000-8100-000000000001',
  '99400000-0000-4000-8000-000000000002', 'Réparation', 'Documentaire'
);

-- Trois opérations isolent respectivement scellement, annulation et expiration.
insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, safe_error_code, row_revision
) values
  ('99400000-0000-4000-8200-000000000001',
   '99400000-0000-4000-8100-000000000001',
   '99400000-0000-4000-8000-000000000002',
   '99400000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99400000-0000-4000-8300-000000000001',
   '99400000-0000-4000-8400-000000000001', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 4),
  ('99400000-0000-4000-8200-000000000002',
   '99400000-0000-4000-8100-000000000001',
   '99400000-0000-4000-8000-000000000002',
   '99400000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99400000-0000-4000-8300-000000000002',
   '99400000-0000-4000-8400-000000000002', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 2),
  ('99400000-0000-4000-8200-000000000003',
   '99400000-0000-4000-8100-000000000001',
   '99400000-0000-4000-8000-000000000002',
   '99400000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99400000-0000-4000-8300-000000000003',
   '99400000-0000-4000-8400-000000000003', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 1);

insert into public.document_operation_targets (
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists
) values
  ('99400000-0000-4000-8500-000000000001',
   '99400000-0000-4000-8200-000000000001', 1, 'transaction-proofs',
   'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000001/proof',
   'primary', 'delete', 'insert', false),
  ('99400000-0000-4000-8500-000000000002',
   '99400000-0000-4000-8200-000000000002', 1, 'transaction-proofs',
   'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000002/proof',
   'primary', 'delete', 'insert', false),
  ('99400000-0000-4000-8500-000000000003',
   '99400000-0000-4000-8200-000000000003', 1, 'transaction-proofs',
   'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000003/proof',
   'primary', 'delete', 'insert', false);
insert into public.document_object_locks(
  bucket_id, object_path, target_id, operation_id
)
select target.bucket_id, target.object_path, target.id, target.operation_id
from public.document_operation_targets target
where target.operation_id in (
  '99400000-0000-4000-8200-000000000001',
  '99400000-0000-4000-8200-000000000002',
  '99400000-0000-4000-8200-000000000003'
);

create temporary table repair_test_values (
  name text primary key,
  authorization_id uuid,
  revision bigint,
  plan_hash text
);
grant select, insert, update on repair_test_values to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000003', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.get_administrative_document_repair_diagnostic(
    '99400000-0000-4000-8200-000000000001')$$,
  'P4R01', 'Diagnostic de réparation non autorisé.',
  'un utilisateur ordinaire ne peut pas diagnostiquer une réparation'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000001', 'Motif', '[]')$$,
  'P4R01', 'Autorisation de réparation refusée.',
  'service_role ou un utilisateur ordinaire ne remplace pas l’autorisation métier'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.is(
  public.get_administrative_document_repair_diagnostic(
    '99400000-0000-4000-8200-000000000001')->>'repairable',
  'true',
  'le diagnostic identifie une opération en attention_required réparable'
);
select extensions.is(
  public.get_administrative_document_repair_diagnostic(
    '99400000-0000-4000-8200-000000000001')
      #>> '{targets,0,catalogObservation,physicalBytesVerified}',
  'false',
  'le catalogue n’est jamais présenté comme une vérification des octets'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000001', ' ', '[]')$$,
  'P4R02', 'Demande de réparation invalide.',
  'le motif administratif est obligatoire'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 3,
    '99400000-0000-4000-8600-000000000001', 'Réparer',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R04', 'La révision de l’opération documentaire a changé.',
  'une révision obsolète de l’opération est refusée'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000098', 'Plan dupliqué',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false},{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R03', 'Le plan doit couvrir exactement toutes les cibles.',
  'un plan contenant une cible dupliquée est refusé'
);

with response as (
  select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000001',
    'Objet absent confirmé par contrôle administratif',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]'
  ) value
)
insert into repair_test_values(name, authorization_id, revision, plan_hash)
select 'sealed', (value->>'authorizationId')::uuid,
  (value->>'revision')::bigint, value->>'planHash'
from response;

select extensions.is(
  (select count(*) from public.document_repair_items
   where authorization_id = (
     select authorization_id from repair_test_values where name = 'sealed'
   )),
  1::bigint,
  'le plan couvre exactement la cible de l’opération'
);
select extensions.is(
  (select count(*) from public.document_repair_events
   where authorization_id = (
     select authorization_id from repair_test_values where name = 'sealed'
   ) and event_type = 'authorized'),
  1::bigint,
  'l’autorisation produit un événement d’audit'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000004', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select extensions.ok(
  public.get_administrative_document_repair_diagnostic(
    '99400000-0000-4000-8200-000000000001'
  ) #> '{activeAuthorization,attemptId}' is null
  and public.get_administrative_document_repair_diagnostic(
    '99400000-0000-4000-8200-000000000001'
  ) #>> '{activeAuthorization,ownedByCaller}' = 'false',
  'un autre administrateur voit le blocage sans obtenir la tentative engagée'
);
select extensions.is(
  public.get_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001',
    '99400000-0000-4000-8600-000000000001'
  ),
  null::jsonb,
  'un autre administrateur ne peut pas relire le plan engagé'
);
select extensions.throws_ok(
  format(
    'select public.cancel_administrative_document_repair_authorization(%L,0)',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  'P4R01', 'Annulation de réparation non autorisée.',
  'un autre administrateur ne peut pas annuler la décision engagée'
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    (select plan_hash from repair_test_values where name = 'sealed')
  ),
  'P4R01', 'Clôture de réparation non autorisée.',
  'un autre administrateur ne peut pas sceller la décision engagée'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000004', 'Tentative concurrente',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R06', 'Une réparation est déjà en cours pour cette opération.',
  'un autre administrateur ne peut pas ouvrir une réparation concurrente'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.is(
  (
    public.issue_administrative_document_repair_authorization(
      '99400000-0000-4000-8200-000000000001', 4,
      '99400000-0000-4000-8600-000000000001',
      'Objet absent confirmé par contrôle administratif',
      '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]'
    )->>'authorizationId'
  )::uuid,
  (select authorization_id from repair_test_values where name = 'sealed'),
  'une double soumission identique est idempotente'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000001', 'Motif divergent',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R05',
  'La tentative de réparation est déjà utilisée pour une autre décision.',
  'une clé d’idempotence ne peut pas changer d’intention'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000002', 2,
    '99400000-0000-4000-8600-000000000001',
    'Objet absent confirmé par contrôle administratif',
    '[{"targetId":"99400000-0000-4000-8500-000000000002","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R05',
  'La tentative de réparation est déjà utilisée pour une autre décision.',
  'un attempt_id ne peut pas être réutilisé pour une autre opération'
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000001', 4,
    '99400000-0000-4000-8600-000000000099', 'Deuxième réparation',
    '[{"targetId":"99400000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R06', 'Une réparation est déjà en cours pour cette opération.',
  'deux réparations actives concurrentes sont interdites'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000002', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.begin_document_operation_compensation(
    '99400000-0000-4000-8200-000000000001', 4, 'REPRISE_UTILISATEUR')$$,
  'P4R06', 'Une réparation administrative bloque la reprise ordinaire.',
  'une réparation administrative active gèle la reprise utilisateur concurrente'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    (select plan_hash from repair_test_values where name = 'sealed')
  ),
  'P4R07', 'La réparation ne dispose pas de toutes les preuves requises.',
  'le scellement est impossible avant la vérification de toutes les cibles'
);
reset role;

-- Une preuve ne peut pas sauter les phases d’exécution et de vérification.
select extensions.throws_ok(
  format(
    'update public.document_repair_items set progress_state=%L, result_kind=%L, backup_disposition=%L, observed_object_exists=false, observation_source=%L, observation_recorded_at=now(), verified_at=now(), row_revision=row_revision+1 where authorization_id=%L',
    'verified', 'already_conform', 'none', 'storage_catalog',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  '23514', 'Progression de réparation invalide.',
  'une cible ne peut pas passer directement de authorized à verified'
);
update public.document_repair_items
set progress_state = 'executing',
    execution_id = '99400000-0000-4000-8650-000000000001',
    execution_started_at = now(), row_revision = row_revision + 1
where authorization_id = (
  select authorization_id from repair_test_values where name = 'sealed'
);
select extensions.throws_ok(
  format(
    'update public.document_repair_items set progress_state=%L, row_revision=row_revision+1 where authorization_id=%L',
    'verification_required',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  'P4R07', 'L’observation documentaire est absente ou incohérente.',
  'la phase de vérification exige déjà une observation cohérente'
);
insert into public.document_repair_observations(
  id, authorization_id, operation_id, item_id, execution_id,
  observation_kind, object_exists, physical_bytes_verified,
  backup_present, observation_fingerprint
)
select '99400000-0000-4000-8950-000000000001', item.authorization_id,
  item.operation_id, item.id, item.execution_id, 'catalog_absent', false,
  false, false, repeat('0',64)
from public.document_repair_items item
where item.authorization_id = (
  select authorization_id from repair_test_values where name = 'sealed'
);
update public.document_repair_items
set progress_state = 'verification_required', observed_object_exists = false,
    observation_source = 'storage_catalog', observation_recorded_at = now(),
    last_observation_kind = 'catalog_absent',
    last_observation_id = '99400000-0000-4000-8950-000000000001',
    last_observation_at = now(),
    row_revision = row_revision + 1
where authorization_id = (
  select authorization_id from repair_test_values where name = 'sealed'
);
select extensions.throws_ok(
  format(
    'update public.document_repair_items set observed_object_exists=true where authorization_id=%L',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  '42501', 'Une preuve exige une transition de progression.',
  'une observation ne peut pas être remplacée silencieusement'
);
update public.document_repair_items
set progress_state = 'verified', result_kind = 'already_conform',
    backup_disposition = 'none', verified_at = now(),
    row_revision = row_revision + 1
where authorization_id = (
  select authorization_id from repair_test_values where name = 'sealed'
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    (select plan_hash from repair_test_values where name = 'sealed')
  ),
  'P4R07', 'Les preuves SQL de la réparation sont absentes ou divergentes.',
  'une cible vérifiée sans événement probant ne peut pas être scellée'
);
reset role;
select public.append_document_repair_event(
  (select authorization_id from repair_test_values where name = 'sealed'),
  'target_verified', 'success',
  (select id from public.document_repair_items where authorization_id = (
    select authorization_id from repair_test_values where name = 'sealed'
  )),
  null, 'already_conform'
);
select extensions.throws_ok(
  format(
    'update public.document_repair_items set action=%L where authorization_id=%L',
    'accept_residual_state',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  '42501', 'Le plan de réparation est immuable.',
  'la décision autorisée ne peut pas être modifiée'
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'update public.document_repair_events set safe_code=%L where authorization_id=%L',
    'ALTERED',
    (select authorization_id from repair_test_values where name = 'sealed')
  ),
  '42501', 'Le journal documentaire est immuable.',
  'le journal de réparation est append-only'
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    repeat('f', 64)
  ),
  'P4R05', 'Le plan de réparation a divergé.',
  'une empreinte divergente bloque le scellement'
);
select extensions.is(
  public.seal_administrative_document_repair(
    (select authorization_id from repair_test_values where name = 'sealed'),
    0,
    (select plan_hash from repair_test_values where name = 'sealed')
  )->>'state',
  'sealed',
  'une réparation entièrement prouvée peut être scellée'
);
select extensions.is(
  (select state from public.document_operations
   where id = '99400000-0000-4000-8200-000000000001'),
  'administratively_resolved',
  'le scellement clôt l’opération d’origine de manière explicite'
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    repeat('f', 64)
  ),
  'P4R05', 'Le plan de réparation a divergé.',
  'même un scellement déjà réussi refuse une empreinte divergente'
);
select extensions.is(
  public.seal_administrative_document_repair(
    (select authorization_id from repair_test_values where name = 'sealed'),
    0,
    (select plan_hash from repair_test_values where name = 'sealed')
  )->>'state',
  'sealed',
  'la répétition conforme du scellement reste idempotente'
);
reset role;
update public.document_operation_targets
set target_revision = target_revision + 1
where id = '99400000-0000-4000-8500-000000000001';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,0,%L)',
    (select authorization_id from repair_test_values where name = 'sealed'),
    (select plan_hash from repair_test_values where name = 'sealed')
  ),
  'P4R07', 'Les preuves SQL de la réparation sont absentes ou divergentes.',
  'une répétition du scellement ne masque pas une divergence SQL ultérieure'
);
reset role;
update public.document_operation_targets
set target_revision = 0
where id = '99400000-0000-4000-8500-000000000001';

-- Annulation explicite et impossibilité de réactivation.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
with response as (
  select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000002', 2,
    '99400000-0000-4000-8600-000000000002', 'Contrôle annulé',
    '[{"targetId":"99400000-0000-4000-8500-000000000002","action":"accept_residual_state","residualReason":"État à revoir","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]'
  ) value
)
insert into repair_test_values(name, authorization_id, revision, plan_hash)
select 'cancelled', (value->>'authorizationId')::uuid,
  (value->>'revision')::bigint, value->>'planHash' from response;
select extensions.is(
  public.cancel_administrative_document_repair_authorization(
    (select authorization_id from repair_test_values where name = 'cancelled'), 0
  )->>'state',
  'cancelled',
  'l’administrateur peut annuler une autorisation active'
);
select extensions.is(
  public.cancel_administrative_document_repair_authorization(
    (select authorization_id from repair_test_values where name = 'cancelled'), 0
  )->>'state',
  'cancelled',
  'la répétition d’une annulation est idempotente'
);
select extensions.throws_ok(
  format(
    'select public.seal_administrative_document_repair(%L,1,%L)',
    (select authorization_id from repair_test_values where name = 'cancelled'),
    (select plan_hash from repair_test_values where name = 'cancelled')
  ),
  'P4R05', 'Autorisation de réparation inactive ou expirée.',
  'une autorisation annulée ne peut pas être scellée'
);
reset role;

-- Une autorisation expirée reste inactive mais peut être annulée pour libérer
-- explicitement l’opération avant une nouvelle décision.
insert into public.document_repair_authorizations (
  id, administrator_subject_id, operation_id, attempt_id, reason,
  repair_plan, repair_plan_hash, target_count, observed_operation_revision,
  issued_at, expires_at
) values (
  '99400000-0000-4000-8700-000000000003',
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8200-000000000003',
  '99400000-0000-4000-8600-000000000003', 'Autorisation expirée',
  '[{"action":"confirm_already_conform","backupId":null,"expectedApplicationState":"pending","expectedBackupRevision":null,"expectedBackupState":null,"expectedObjectExists":false,"expectedObjectId":null,"expectedObjectVersion":null,"expectedOperationRevision":1,"expectedTargetRevision":0,"ordinal":1,"residualReason":null,"targetId":"99400000-0000-4000-8500-000000000003"}]',
  public.document_repair_plan_hash(
    '[{"action":"confirm_already_conform","backupId":null,"expectedApplicationState":"pending","expectedBackupRevision":null,"expectedBackupState":null,"expectedObjectExists":false,"expectedObjectId":null,"expectedObjectVersion":null,"expectedOperationRevision":1,"expectedTargetRevision":0,"ordinal":1,"residualReason":null,"targetId":"99400000-0000-4000-8500-000000000003"}]'
  ),
  1, 1, now() - interval '10 minutes', now() - interval '1 second'
);
insert into public.document_repair_items (
  authorization_id, operation_id, target_id, ordinal, action,
  expected_operation_revision, expected_target_revision,
  expected_application_state, expected_object_exists
) values (
  '99400000-0000-4000-8700-000000000003',
  '99400000-0000-4000-8200-000000000003',
  '99400000-0000-4000-8500-000000000003', 1,
  'confirm_already_conform', 1, 0, 'pending', false
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.seal_administrative_document_repair(
    '99400000-0000-4000-8700-000000000003', 0,
    (select repair_plan_hash from public.document_repair_authorizations
     where id = '99400000-0000-4000-8700-000000000003'))$$,
  'P4R05', 'Autorisation de réparation inactive ou expirée.',
  'une autorisation expirée ne peut pas conclure la réparation'
);
select extensions.is(
  public.cancel_administrative_document_repair_authorization(
    '99400000-0000-4000-8700-000000000003', 0
  )->>'state',
  'cancelled',
  'l’expiration se récupère par une annulation explicite et auditée'
);
reset role;

-- Les décisions typées de reprise de compensation et de restauration sont
-- autorisées uniquement lorsque l’état durable observé les justifie.
insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, safe_error_code, row_revision
) values
  ('99400000-0000-4000-8200-000000000004',
   '99400000-0000-4000-8100-000000000001',
   '99400000-0000-4000-8000-000000000002',
   '99400000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99400000-0000-4000-8300-000000000004',
   '99400000-0000-4000-8400-000000000004', 'attention_required',
   '[]', 'COMPENSATION_INTERRUPTED', 3),
  ('99400000-0000-4000-8200-000000000005',
   '99400000-0000-4000-8100-000000000001',
   '99400000-0000-4000-8000-000000000002',
   '99400000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_replace', 'transaction',
   '99400000-0000-4000-8300-000000000005',
   '99400000-0000-4000-8400-000000000005', 'attention_required',
   '[]', 'RESTORE_REQUIRED', 6);
insert into public.document_operation_targets (
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists, application_state,
  applied_at, target_revision
) values
  ('99400000-0000-4000-8500-000000000004',
   '99400000-0000-4000-8200-000000000004', 1, 'transaction-proofs',
   'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000004/proof',
   'primary', 'delete', 'insert', false, 'applied', now(), 2),
  ('99400000-0000-4000-8500-000000000005',
   '99400000-0000-4000-8200-000000000005', 1, 'transaction-proofs',
   'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000005/proof',
   'primary', 'update', 'update', true, 'pending', null, 0);
insert into public.document_object_locks(
  bucket_id, object_path, target_id, operation_id
)
select target.bucket_id, target.object_path, target.id, target.operation_id
from public.document_operation_targets target
where target.operation_id in (
  '99400000-0000-4000-8200-000000000004',
  '99400000-0000-4000-8200-000000000005'
);
insert into public.document_operation_backups (
  id, operation_id, target_id, protected_person_id, initiator_subject_id,
  original_bucket_id, original_object_path, original_object_id,
  original_object_version, recovery_object_path, byte_size, mime_type,
  sha256, state, recovery_object_id, recovery_object_version,
  upload_verified_at
) values (
  '99400000-0000-4000-8800-000000000005',
  '99400000-0000-4000-8200-000000000005',
  '99400000-0000-4000-8500-000000000005',
  '99400000-0000-4000-8100-000000000001',
  '99400000-0000-4000-8000-000000000002', 'transaction-proofs',
  'protected-persons/99400000-0000-4000-8100-000000000001/transactions/99400000-0000-4000-8300-000000000005/proof',
  '99400000-0000-4000-8900-000000000005', 'original-v1',
  'operations/99400000-0000-4000-8200-000000000005/targets/99400000-0000-4000-8500-000000000005/backup',
  12, 'application/pdf', repeat('a', 64), 'verified',
  '99400000-0000-4000-8900-000000000006', 'backup-v1', now()
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select public.issue_administrative_document_repair_authorization(
  '99400000-0000-4000-8200-000000000004', 3,
  '99400000-0000-4000-8600-000000000004', 'Reprendre la compensation',
  '[{"targetId":"99400000-0000-4000-8500-000000000004","action":"resume_compensation","expectedTargetRevision":2,"expectedApplicationState":"applied","expectedObjectExists":false}]'
);
select extensions.is(
  (select action from public.document_repair_items
   where operation_id = '99400000-0000-4000-8200-000000000004'),
  'resume_compensation',
  'la reprise de compensation est enregistrée comme décision typée'
);
select public.issue_administrative_document_repair_authorization(
  '99400000-0000-4000-8200-000000000005', 6,
  '99400000-0000-4000-8600-000000000005', 'Restaurer la sauvegarde vérifiée',
  '[{"targetId":"99400000-0000-4000-8500-000000000005","action":"restore_original","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false,"backupId":"99400000-0000-4000-8800-000000000005","expectedBackupRevision":0,"expectedBackupState":"verified"}]'
);
select extensions.is(
  (select action from public.document_repair_items
   where operation_id = '99400000-0000-4000-8200-000000000005'),
  'restore_original',
  'une sauvegarde vérifiée autorise une restauration ciblée'
);
select extensions.is(
  public.get_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000005',
    '99400000-0000-4000-8600-000000000005'
  ) #>> '{repairPlan,0,expectedBackupState}',
  'verified',
  'la reprise relit le plan et la révision de sauvegarde autorisés'
);
reset role;
update public.document_repair_items
set progress_state = 'executing',
    execution_id = '99400000-0000-4000-8650-000000000004',
    execution_started_at = now(), row_revision = row_revision + 1
where operation_id = '99400000-0000-4000-8200-000000000004';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.cancel_administrative_document_repair_authorization(%L,0)',
    (select id from public.document_repair_authorizations
     where operation_id = '99400000-0000-4000-8200-000000000004')
  ),
  'P4R07', 'Une réparation commencée doit être reprise ou vérifiée.',
  'une réparation partiellement exécutée ne peut pas être annulée'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000002', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.begin_document_operation_compensation(
    '99400000-0000-4000-8200-000000000004', 3, 'REPRISE_CONCURRENTE')$$,
  'P4R06', 'Une réparation administrative bloque la reprise ordinaire.',
  'le gel reste actif après le début d’une réparation'
);
reset role;

-- Une cible sans son verrou exclusif ne peut jamais recevoir un nouveau plan.
delete from public.document_object_locks
where operation_id = '99400000-0000-4000-8200-000000000003';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.issue_administrative_document_repair_authorization(
    '99400000-0000-4000-8200-000000000003', 1,
    '99400000-0000-4000-8600-000000000099', 'Nouvelle tentative',
    '[{"targetId":"99400000-0000-4000-8500-000000000003","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]')$$,
  'P4R06', 'La cible documentaire n’est pas verrouillée exclusivement.',
  'une réservation concurrente ou perdue bloque la réparation'
);
reset role;

-- Le contrat n’a touché ni Storage ni les indicateurs d’activation.
select extensions.is(
  (select count(*) from storage.objects where id::text like '99400000-%'),
  0::bigint,
  'le contrat SQL ne réalise aucune mutation physique Storage'
);
select extensions.is(
  (select lifecycle_enabled from public.protected_person_archive_runtime_config
   where singleton),
  false,
  'le cycle d’archivage reste désactivé'
);

select * from extensions.finish();
rollback;
