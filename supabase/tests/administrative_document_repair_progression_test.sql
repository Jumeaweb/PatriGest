begin;
\ir experimental_document_operations_enabled.inc

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'document_repair_observations',
  'le journal append-only des observations existe'
);
select extensions.has_column(
  'public', 'document_repair_observations', 'backup_object_id',
  'l’identité catalogue de la sauvegarde est figée dans l’observation'
);
select extensions.has_column(
  'public', 'document_repair_observations', 'backup_object_version',
  'la version catalogue de la sauvegarde est figée dans l’observation'
);
select extensions.has_function(
  'public', 'start_administrative_document_repair_item',
  array['uuid','uuid','uuid','uuid','text','text','uuid','bigint','bigint'],
  'la RPC technique de démarrage existe'
);
select extensions.has_function(
  'public', 'record_administrative_document_repair_observation',
  array[
    'uuid','uuid','uuid','uuid','text','text','uuid','bigint','text',
    'boolean','uuid','text','bigint','text','boolean','uuid','bigint','text'
  ],
  'la RPC technique d’observation existe'
);
select extensions.has_function(
  'public', 'verify_administrative_document_repair_item',
  array['uuid','uuid','uuid','uuid','text','text','uuid','bigint','text','text'],
  'la RPC technique de vérification existe'
);
select extensions.has_function(
  'public', 'renew_administrative_document_repair_authorization',
  array['uuid','uuid','text','uuid','bigint'],
  'la RPC administrative de reprise existe'
);
select extensions.has_function(
  'public', 'get_administrative_document_repair_progress_for_service',
  array['uuid','uuid','uuid','text'],
  'la lecture technique de reprise existe'
);

select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.document_repair_observations', 'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.document_repair_observations', 'INSERT'
  ),
  'les observations ne sont jamais accessibles directement par la Data API'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.renew_administrative_document_repair_authorization(uuid,uuid,text,uuid,bigint)',
    'EXECUTE'
  ),
  'les RPC séparent exécution technique et décision administrative'
);
select extensions.ok(
  (
    select bool_and(procedure.prosecdef
      and procedure.proconfig = array['search_path=""'])
    from pg_proc procedure
    where procedure.oid in (
      'public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint)'::regprocedure,
      'public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text)'::regprocedure,
      'public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text)'::regprocedure,
      'public.get_administrative_document_repair_progress_for_service(uuid,uuid,uuid,text)'::regprocedure,
      'public.renew_administrative_document_repair_authorization(uuid,uuid,text,uuid,bigint)'::regprocedure
    )
  ),
  'les RPC exposées sont SECURITY DEFINER avec search_path fermé'
);

-- Lecture locale des états techniques pour les assertions seulement.
grant select on public.document_repair_authorizations,
  public.document_repair_items, public.document_repair_observations,
  public.document_repair_events to authenticated;
grant select on public.document_repair_events to service_role;
grant update on public.document_repair_items,
  public.document_repair_observations to authenticated;
create policy document_repair_progression_authz_test_select
on public.document_repair_authorizations for select to authenticated using (true);
create policy document_repair_progression_items_test_select
on public.document_repair_items for select to authenticated using (true);
create policy document_repair_progression_items_test_update
on public.document_repair_items for update to authenticated
using (true) with check (true);
create policy document_repair_progression_observations_test_select
on public.document_repair_observations for select to authenticated using (true);
create policy document_repair_progression_observations_test_update
on public.document_repair_observations for update to authenticated
using (true) with check (true);
create policy document_repair_progression_events_test_select
on public.document_repair_events for select to authenticated using (true);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '99500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'progress-admin@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'progress-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99500000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'progress-other@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99500000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'progress-admin-two@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id in (
  '99500000-0000-4000-8000-000000000001',
  '99500000-0000-4000-8000-000000000002',
  '99500000-0000-4000-8000-000000000003',
  '99500000-0000-4000-8000-000000000004'
);
insert into public.platform_administrators(user_id) values
  ('99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8000-000000000004');
insert into public.account_subscriptions(owner_id, status, started_at)
values ('99500000-0000-4000-8000-000000000002', 'development', now());
insert into public.protected_persons(id, owner_id, first_name, last_name)
values (
  '99500000-0000-4000-8100-000000000001',
  '99500000-0000-4000-8000-000000000002', 'Progression', 'Réparation'
);

insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, safe_error_code, row_revision
) values
  ('99500000-0000-4000-8200-000000000001',
   '99500000-0000-4000-8100-000000000001',
   '99500000-0000-4000-8000-000000000002',
   '99500000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99500000-0000-4000-8300-000000000001',
   '99500000-0000-4000-8400-000000000001', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 4),
  ('99500000-0000-4000-8200-000000000002',
   '99500000-0000-4000-8100-000000000001',
   '99500000-0000-4000-8000-000000000002',
   '99500000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99500000-0000-4000-8300-000000000002',
   '99500000-0000-4000-8400-000000000002', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 2),
  ('99500000-0000-4000-8200-000000000003',
   '99500000-0000-4000-8100-000000000001',
   '99500000-0000-4000-8000-000000000002',
   '99500000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_delete', 'transaction',
   '99500000-0000-4000-8300-000000000003',
   '99500000-0000-4000-8400-000000000003', 'attention_required',
   '[]', 'DELETE_UNCERTAIN', 1),
  ('99500000-0000-4000-8200-000000000004',
   '99500000-0000-4000-8100-000000000001',
   '99500000-0000-4000-8000-000000000002',
   '99500000-0000-4000-8000-000000000002', 'user',
   'transaction_proof_replace', 'transaction',
   '99500000-0000-4000-8300-000000000004',
   '99500000-0000-4000-8400-000000000004', 'attention_required',
   '[]', 'CONTENT_UNCERTAIN', 3);

insert into public.document_operation_targets (
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists
) values
  ('99500000-0000-4000-8500-000000000001',
   '99500000-0000-4000-8200-000000000001', 1, 'transaction-proofs',
   'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000001/proof',
   'primary', 'delete', 'insert', false),
  ('99500000-0000-4000-8500-000000000002',
   '99500000-0000-4000-8200-000000000002', 1, 'transaction-proofs',
   'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000002/proof',
   'primary', 'delete', 'insert', false),
  ('99500000-0000-4000-8500-000000000003',
   '99500000-0000-4000-8200-000000000003', 1, 'transaction-proofs',
   'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000003/proof',
   'primary', 'delete', 'insert', false),
  ('99500000-0000-4000-8500-000000000004',
   '99500000-0000-4000-8200-000000000004', 1, 'transaction-proofs',
   'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
   'primary', 'update', 'update', true);

insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99500000-0000-4000-8900-000000000004', 'transaction-proofs',
  'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
  '99500000-0000-4000-8000-000000000002',
  '99500000-0000-4000-8000-000000000002',
  '{"size":12,"mimetype":"application/pdf"}', 'object-v1'
);

insert into public.document_operation_backups (
  id, operation_id, target_id, protected_person_id, initiator_subject_id,
  original_bucket_id, original_object_path, original_object_id,
  original_object_version, recovery_object_path, byte_size, mime_type,
  sha256, state, recovery_object_id, recovery_object_version,
  upload_verified_at
) values (
  '99500000-0000-4000-8980-000000000004',
  '99500000-0000-4000-8200-000000000004',
  '99500000-0000-4000-8500-000000000004',
  '99500000-0000-4000-8100-000000000001',
  '99500000-0000-4000-8000-000000000002', 'transaction-proofs',
  'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
  '99500000-0000-4000-8900-000000000004', 'object-v1',
  'operations/99500000-0000-4000-8200-000000000004/targets/99500000-0000-4000-8500-000000000004/backup',
  12, 'application/pdf', repeat('b',64), 'verified',
  '99500000-0000-4000-8990-000000000004', 'backup-v1', now()
);
insert into storage.objects(
  id, bucket_id, name, metadata, version
) values (
  '99500000-0000-4000-8990-000000000004',
  'document-operation-backups',
  'operations/99500000-0000-4000-8200-000000000004/targets/99500000-0000-4000-8500-000000000004/backup',
  '{"size":12,"mimetype":"application/pdf"}', 'backup-v1'
);
insert into public.document_object_locks(
  bucket_id, object_path, target_id, operation_id
)
select target.bucket_id, target.object_path, target.id, target.operation_id
from public.document_operation_targets target
where target.operation_id in (
  '99500000-0000-4000-8200-000000000001',
  '99500000-0000-4000-8200-000000000002',
  '99500000-0000-4000-8200-000000000003',
  '99500000-0000-4000-8200-000000000004'
);

create temporary table repair_progression_values (
  name text primary key,
  authorization_id uuid,
  item_id uuid,
  attempt_id uuid,
  plan_hash text,
  revision bigint
);
grant select, insert, update on repair_progression_values
to authenticated, service_role;

-- Une session non administratrice ne peut ni autoriser ni renouveler.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000003', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$select public.renew_administrative_document_repair_authorization(
    '99500000-0000-4000-8700-000000000099',
    '99500000-0000-4000-8600-000000000099', repeat('a',64),
    '99500000-0000-4000-8650-000000000099', 0)$$,
  'P4R01', 'Prolongation de réparation non autorisée.',
  'un non-administrateur ne peut pas prolonger une réparation'
);
reset role;

-- Autorisation administrative d'une cible absente déjà conforme.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
with response as (
  select public.issue_administrative_document_repair_authorization(
    '99500000-0000-4000-8200-000000000001', 4,
    '99500000-0000-4000-8600-000000000001', 'État absent confirmé',
    '[{"targetId":"99500000-0000-4000-8500-000000000001","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":false}]'
  ) value
)
insert into repair_progression_values(
  name, authorization_id, item_id, attempt_id, plan_hash, revision
)
select 'main', (value->>'authorizationId')::uuid,
  (select id from public.document_repair_items
   where authorization_id = (value->>'authorizationId')::uuid),
  (value->>'attemptId')::uuid, value->>'planHash',
  (value->>'revision')::bigint
from response;
reset role;
update repair_progression_values values_table
set item_id = item.id
from public.document_repair_items item
where values_table.name = 'main'
  and item.authorization_id = values_table.authorization_id;

-- Le service technique sans liaison exacte à l'autorisation est refusé.
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000004',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001'
  ),
  'P4R01', 'Contexte technique de réparation non autorisé.',
  'service_role ne peut pas substituer un autre administrateur'
);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    '99500000-0000-4000-8600-000000000099',
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001'
  ),
  'P4R01', 'Contexte technique de réparation non autorisé.',
  'service_role sans tentative exacte est refusé'
);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    repeat('f',64), 'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001'
  ),
  'P4R05', 'Le plan de réparation a divergé.',
  'un mauvais plan ne permet pas de démarrer'
);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'accept_residual_state',
    '99500000-0000-4000-8660-000000000001'
  ),
  'P4R05', 'La cible ou l’action de réparation a divergé.',
  'le service ne peut pas choisir une autre action'
);

select extensions.is(
  public.start_administrative_document_repair_item(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 0, 0
  )->>'progressState',
  'executing',
  'la cible autorisée démarre exactement en executing'
);
select extensions.is(
  public.start_administrative_document_repair_item(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 0, 0
  )->>'idempotent',
  'true',
  'une réponse de démarrage perdue se rejoue sans mutation'
);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000099'
  ),
  'P4R05', 'Une autre exécution a déjà commencé cette cible.',
  'une identité d’exécution divergente est refusée'
);

-- Une observation insuffisante reste bloquante et append-only.
select extensions.is(
  public.record_administrative_document_repair_observation(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 1,
    'physical_read_impossible', false, null, null, null, null,
    false, null, null, null
  )->>'progressState',
  'executing',
  'une lecture physique impossible ne déclare jamais la cible vérifiée'
);
select extensions.throws_ok(
  format(
    'select public.verify_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,2,%L,%L)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001',
    'already_conform', 'none'
  ),
  'P4R04', 'La cible n’est pas prête pour vérification.',
  'une transition directe de executing à verified est impossible'
);
select extensions.throws_ok(
  format(
    'select public.record_administrative_document_repair_observation(%L,%L,%L,%L,%L,%L,%L,1,%L,false,null,null,null,null,false,null,null,null)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001',
    'catalog_absent'
  ),
  'P4R04', 'La révision de la cible de réparation a changé.',
  'une révision obsolète ne peut pas enregistrer une preuve'
);

select extensions.is(
  public.record_administrative_document_repair_observation(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 2,
    'catalog_absent', false, null, null, null, null,
    false, null, null, null
  )->>'progressState',
  'verification_required',
  'une absence catalogue cohérente requiert ensuite la vérification'
);
select extensions.is(
  public.record_administrative_document_repair_observation(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 2,
    'catalog_absent', false, null, null, null, null,
    false, null, null, null
  )->>'idempotent',
  'true',
  'une réponse d’observation perdue se rejoue sans nouvelle preuve'
);
select extensions.throws_ok(
  format(
    'select public.verify_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,3,%L,%L)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001',
    'residual_accepted', 'none'
  ),
  'P4R07', 'Le résultat ne correspond pas à l’action approuvée.',
  'une preuve incompatible avec l’action est refusée'
);
select extensions.is(
  public.verify_administrative_document_repair_item(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 3,
    'already_conform', 'none'
  )->>'progressState',
  'verified',
  'la progression complète atteint verified avec une preuve cohérente'
);
select extensions.is(
  public.verify_administrative_document_repair_item(
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001', 3,
    'already_conform', 'none'
  )->>'idempotent',
  'true',
  'une réponse de vérification perdue se rejoue sans double événement'
);
select extensions.throws_ok(
  format(
    'select public.record_administrative_document_repair_observation(%L,%L,%L,%L,%L,%L,%L,4,%L,false,null,null,null,null,false,null,null,null)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select item_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000001',
    'catalog_absent'
  ),
  'P4R05', 'L’exécution de réparation ne correspond pas à la cible.',
  'aucune observation nouvelle ne peut être ajoutée après verified'
);
select extensions.is(
  (select count(*) from public.document_repair_events
   where item_id = (
     select item_id from repair_progression_values where name = 'main'
   ) and event_type = 'target_verified'),
  1::bigint,
  'la vérification idempotente ne duplique pas l’événement probant'
);
select extensions.is(
  public.get_administrative_document_repair_progress_for_service(
    (select authorization_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main')
  ) #>> '{items,0,progressState}',
  'verified',
  'la reprise technique relit la phase durable exacte'
);
select extensions.is(
  jsonb_array_length(
    public.get_administrative_document_repair_progress_for_service(
      (select authorization_id from repair_progression_values where name = 'main'),
      '99500000-0000-4000-8000-000000000001',
      (select attempt_id from repair_progression_values where name = 'main'),
      (select plan_hash from repair_progression_values where name = 'main')
    ) #> '{items,0,observations}'
  ),
  2,
  'la reprise conserve l’anomalie antérieure et la preuve concluante'
);
reset role;

-- Les observations persistées sont immuables même avec un accès de test.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  $$update public.document_repair_observations
    set observation_kind = 'unqualifiable'
    where item_id = (
      select item_id from repair_progression_values where name = 'main'
    )$$,
  '42501', 'Le journal documentaire est immuable.',
  'une observation enregistrée ne peut pas être modifiée'
);
select extensions.throws_ok(
  format(
    'update public.document_repair_items set last_observation_at=last_observation_at+interval %L where id=%L',
    '1 second',
    (select item_id from repair_progression_values where name = 'main')
  ),
  '42501', 'Le dernier constat probant de la réparation est immuable.',
  'la référence au dernier constat ne peut plus changer après vérification'
);
select extensions.is(
  public.seal_administrative_document_repair(
    (select authorization_id from repair_progression_values where name = 'main'),
    0,
    (select plan_hash from repair_progression_values where name = 'main')
  )->>'state',
  'sealed',
  'le scellement reste compatible avec la progression complète'
);
select extensions.throws_ok(
  format(
    'select public.renew_administrative_document_repair_authorization(%L,%L,%L,%L,%s)',
    (select authorization_id from repair_progression_values where name = 'main'),
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8650-000000000099',
    (select row_revision from public.document_repair_authorizations
     where id = (
       select authorization_id from repair_progression_values where name = 'main'
     ))
  ),
  'P4R05', 'La reprise de réparation ne peut pas être prolongée.',
  'une autorisation scellée ne peut pas ouvrir une nouvelle reprise'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  public.get_administrative_document_repair_progress_for_service(
    (select authorization_id from repair_progression_values where name = 'main'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'main'),
    (select plan_hash from repair_progression_values where name = 'main')
  )->>'state',
  'sealed',
  'une réparation scellée reste relisible pour une reprise sans mutation'
);
reset role;

-- Une cible présente exige une preuve physique complète. Le verrou et la
-- sauvegarde éventuellement annoncée restent soumis au plan autorisé.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
with response as (
  select public.issue_administrative_document_repair_authorization(
    '99500000-0000-4000-8200-000000000004', 3,
    '99500000-0000-4000-8600-000000000004', 'Vérifier les octets présents',
    '[{"targetId":"99500000-0000-4000-8500-000000000004","action":"confirm_already_conform","expectedTargetRevision":0,"expectedApplicationState":"pending","expectedObjectExists":true,"expectedObjectId":"99500000-0000-4000-8900-000000000004","expectedObjectVersion":"object-v1","backupId":"99500000-0000-4000-8980-000000000004","expectedBackupRevision":0,"expectedBackupState":"verified"}]'
  ) value
)
insert into repair_progression_values(
  name, authorization_id, item_id, attempt_id, plan_hash, revision
)
select 'present', (value->>'authorizationId')::uuid, null,
  (value->>'attemptId')::uuid, value->>'planHash', 0 from response;
reset role;
update repair_progression_values values_table
set item_id = item.id
from public.document_repair_items item
where values_table.name = 'present'
  and item.authorization_id = values_table.authorization_id;

delete from public.document_object_locks
where operation_id = '99500000-0000-4000-8200-000000000004';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004'
  ),
  'P4R06', 'La cible documentaire n’est pas verrouillée exclusivement.',
  'un verrou perdu bloque le démarrage technique'
);
reset role;
insert into public.document_object_locks(
  bucket_id, object_path, target_id, operation_id
)
select target.bucket_id, target.object_path, target.id, target.operation_id
from public.document_operation_targets target
where target.operation_id = '99500000-0000-4000-8200-000000000004';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.start_administrative_document_repair_item(
  (select authorization_id from repair_progression_values where name = 'present'),
  (select item_id from repair_progression_values where name = 'present'),
  '99500000-0000-4000-8000-000000000001',
  (select attempt_id from repair_progression_values where name = 'present'),
  (select plan_hash from repair_progression_values where name = 'present'),
  'confirm_already_conform',
  '99500000-0000-4000-8660-000000000004', 0, 0
);
select extensions.throws_ok(
  format(
    'select public.record_administrative_document_repair_observation(%L,%L,%L,%L,%L,%L,%L,1,%L,true,%L,%L,12,null,true,%L,0,%L)',
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004',
    'physical_verified',
    '99500000-0000-4000-8900-000000000004', 'object-v1',
    '99500000-0000-4000-8980-000000000004', 'verified'
  ),
  'P4R07', 'La preuve physique de l’objet est absente ou incohérente.',
  'un objet présent sans SHA-256 physique ne peut pas progresser'
);
select extensions.throws_ok(
  format(
    'select public.record_administrative_document_repair_observation(%L,%L,%L,%L,%L,%L,%L,1,%L,true,%L,%L,12,%L,true,%L,0,%L)',
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004',
    'physical_verified',
    '99500000-0000-4000-8900-000000000004', 'object-v1', repeat('b',64),
    '99500000-0000-4000-8990-000000000099', 'verified'
  ),
  'P4R04', 'L’observation de sauvegarde a divergé.',
  'une sauvegarde non autorisée ne peut pas être injectée dans la preuve'
);
select extensions.is(
  public.record_administrative_document_repair_observation(
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004', 1,
    'physical_verified', true,
    '99500000-0000-4000-8900-000000000004', 'object-v1',
    12, repeat('b',64), true,
    '99500000-0000-4000-8980-000000000004', 0, 'verified'
  )->>'progressState',
  'verification_required',
  'une lecture physique complète produit une preuve à vérifier'
);
reset role;
select extensions.is(
  (select backup_object_id::text
   from public.document_repair_observations
   where item_id = (
     select item_id from repair_progression_values where name = 'present'
   ) and observation_kind = 'physical_verified'),
  '99500000-0000-4000-8990-000000000004',
  'l’observation fige l’identité catalogue exacte de la sauvegarde'
);

select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99500000-0000-4000-8990-000000000004';
select set_config('storage.allow_delete_query', 'false', true);
insert into storage.objects(id, bucket_id, name, metadata, version)
values (
  '99500000-0000-4000-8990-000000000099',
  'document-operation-backups',
  'operations/99500000-0000-4000-8200-000000000004/targets/99500000-0000-4000-8500-000000000004/backup',
  '{"size":12,"mimetype":"application/pdf"}', 'backup-v2'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.verify_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,2,%L,%L)',
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004',
    'already_conform', 'retained_for_review'
  ),
  'P4R07', 'La sauvegarde ne correspond pas au résultat annoncé.',
  'un remplacement catalogue de la sauvegarde invalide la preuve enregistrée'
);
reset role;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99500000-0000-4000-8990-000000000099';
select set_config('storage.allow_delete_query', 'false', true);
insert into storage.objects(id, bucket_id, name, metadata, version)
values (
  '99500000-0000-4000-8990-000000000004',
  'document-operation-backups',
  'operations/99500000-0000-4000-8200-000000000004/targets/99500000-0000-4000-8500-000000000004/backup',
  '{"size":12,"mimetype":"application/pdf"}', 'backup-v1'
);

insert into public.account_deletion_document_authorizations(
  id, account_user_id, attempt_id, issued_at, expires_at
) values (
  '99500000-0000-4000-8970-000000000004',
  '99500000-0000-4000-8000-000000000002',
  '99500000-0000-4000-8980-000000000004',
  now(), now() + interval '10 minutes'
);
insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature
) values (
  '99500000-0000-4000-8920-000000000004',
  '99500000-0000-4000-8100-000000000001', null,
  '99500000-0000-4000-8000-000000000002', 'account_deletion',
  'account_storage_neutralization', 'protected_person',
  '99500000-0000-4000-8100-000000000001',
  '99500000-0000-4000-8930-000000000004', 'executing', '[]'
);
insert into public.document_operation_targets (
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists,
  expected_object_id, expected_object_version
) values (
  '99500000-0000-4000-8940-000000000004',
  '99500000-0000-4000-8920-000000000004', 1, 'transaction-proofs',
  'protected-persons/99500000-0000-4000-8100-000000000001/transactions/99500000-0000-4000-8300-000000000004/proof',
  'primary', 'delete', 'insert', true,
  '99500000-0000-4000-8900-000000000004', 'object-v1'
);
insert into public.account_storage_neutralizations(
  operation_id, target_id, authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type
) values (
  '99500000-0000-4000-8920-000000000004',
  '99500000-0000-4000-8940-000000000004',
  '99500000-0000-4000-8970-000000000004',
  '99500000-0000-4000-8000-000000000002', repeat('b',64), 12,
  'application/pdf'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.verify_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,2,%L,%L)',
    (select authorization_id from repair_progression_values where name = 'present'),
    (select item_id from repair_progression_values where name = 'present'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'present'),
    (select plan_hash from repair_progression_values where name = 'present'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000004',
    'already_conform', 'none'
  ),
  'P4R06', 'Une neutralisation de compte est en conflit avec la réparation.',
  'une neutralisation de compte concurrente bloque la vérification'
);
reset role;

-- Préparation d'une autorisation expirée avant démarrage et d'une autorisation
-- expirant après son démarrage.
with plans as (
  select
    'not_started'::text as name,
    '99500000-0000-4000-8700-000000000002'::uuid as authorization_id,
    '99500000-0000-4000-8750-000000000002'::uuid as item_id,
    '99500000-0000-4000-8200-000000000002'::uuid as operation_id,
    '99500000-0000-4000-8500-000000000002'::uuid as target_id,
    '99500000-0000-4000-8600-000000000002'::uuid as attempt_id,
    2::bigint as operation_revision,
    'authorized'::text as progress_state,
    null::uuid as execution_id,
    0::bigint as item_revision
  union all
  select
    'started',
    '99500000-0000-4000-8700-000000000003',
    '99500000-0000-4000-8750-000000000003',
    '99500000-0000-4000-8200-000000000003',
    '99500000-0000-4000-8500-000000000003',
    '99500000-0000-4000-8600-000000000003',
    1, 'executing',
    '99500000-0000-4000-8660-000000000003', 1
), normalized as (
  select plans.*, jsonb_build_array(jsonb_build_object(
    'action', 'confirm_already_conform',
    'backupId', null,
    'expectedApplicationState', 'pending',
    'expectedBackupRevision', null,
    'expectedBackupState', null,
    'expectedObjectExists', false,
    'expectedObjectId', null,
    'expectedObjectVersion', null,
    'expectedOperationRevision', plans.operation_revision,
    'expectedTargetRevision', 0,
    'ordinal', 1,
    'residualReason', null,
    'targetId', plans.target_id
  )) as repair_plan
  from plans
), inserted as (
  insert into public.document_repair_authorizations (
    id, administrator_subject_id, operation_id, attempt_id, reason,
    repair_plan, repair_plan_hash, target_count, observed_operation_revision,
    issued_at, expires_at
  )
  select authorization_id, '99500000-0000-4000-8000-000000000001',
    operation_id, attempt_id, 'Autorisation expirée', repair_plan,
    public.document_repair_plan_hash(repair_plan), 1, operation_revision,
    clock_timestamp() - interval '10 minutes',
    clock_timestamp() - interval '1 second'
  from normalized
  returning id, repair_plan_hash
)
insert into repair_progression_values(
  name, authorization_id, item_id, attempt_id, plan_hash, revision
)
select normalized.name, normalized.authorization_id, normalized.item_id,
  normalized.attempt_id, inserted.repair_plan_hash, 0
from normalized join inserted on inserted.id = normalized.authorization_id;

insert into public.document_repair_items (
  id, authorization_id, operation_id, target_id, ordinal, action,
  expected_operation_revision, expected_target_revision,
  expected_application_state, expected_object_exists, progress_state,
  execution_id, execution_started_at, row_revision
)
select values_table.item_id, values_table.authorization_id,
  case values_table.name
    when 'not_started' then '99500000-0000-4000-8200-000000000002'::uuid
    else '99500000-0000-4000-8200-000000000003'::uuid
  end,
  case values_table.name
    when 'not_started' then '99500000-0000-4000-8500-000000000002'::uuid
    else '99500000-0000-4000-8500-000000000003'::uuid
  end,
  1, 'confirm_already_conform',
  case values_table.name when 'not_started' then 2 else 1 end,
  0, 'pending', false,
  case values_table.name when 'not_started' then 'authorized' else 'executing' end,
  case values_table.name when 'started'
    then '99500000-0000-4000-8660-000000000003'::uuid
  end,
  case values_table.name when 'started'
    then clock_timestamp() - interval '2 minutes'
  end,
  case values_table.name when 'started' then 1 else 0 end
from repair_progression_values values_table
where values_table.name in ('not_started', 'started');

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'not_started'),
    (select item_id from repair_progression_values where name = 'not_started'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'not_started'),
    (select plan_hash from repair_progression_values where name = 'not_started'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000002'
  ),
  'P4R05', 'Autorisation de réparation expirée.',
  'une autorisation expirée avant démarrage reste inutilisable'
);
select extensions.throws_ok(
  format(
    'select public.record_administrative_document_repair_observation(%L,%L,%L,%L,%L,%L,%L,1,%L,false,null,null,null,null,false,null,null,null)',
    (select authorization_id from repair_progression_values where name = 'started'),
    (select item_id from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000003',
    'catalog_absent'
  ),
  'P4R05', 'Autorisation de réparation expirée.',
  'service_role ne prolonge jamais automatiquement une réparation commencée'
);
select extensions.is(
  public.get_administrative_document_repair_progress_for_service(
    (select authorization_id from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started')
  )->>'expired',
  'true',
  'le service peut diagnostiquer sans muter une réparation expirée'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.renew_administrative_document_repair_authorization(%L,%L,%L,%L,0)',
    (select authorization_id from repair_progression_values where name = 'not_started'),
    (select attempt_id from repair_progression_values where name = 'not_started'),
    (select plan_hash from repair_progression_values where name = 'not_started'),
    '99500000-0000-4000-8650-000000000002'
  ),
  'P4R05', 'Une autorisation non commencée ne peut pas être prolongée.',
  'une autorisation expirée non commencée ne peut pas être renouvelée'
);
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000004', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select extensions.throws_ok(
  format(
    'select public.renew_administrative_document_repair_authorization(%L,%L,%L,%L,0)',
    (select authorization_id from repair_progression_values where name = 'started'),
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8650-000000000003'
  ),
  'P4R01', 'Prolongation de réparation non autorisée.',
  'un administrateur différent ne reprend pas la tentative'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select extensions.is(
  public.renew_administrative_document_repair_authorization(
    (select authorization_id from repair_progression_values where name = 'started'),
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8650-000000000003', 0
  )->>'revision',
  '1',
  'l’administrateur initiateur ouvre une reprise bornée et auditée'
);
select extensions.is(
  public.renew_administrative_document_repair_authorization(
    (select authorization_id from repair_progression_values where name = 'started'),
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8650-000000000003', 0
  )->>'idempotent',
  'true',
  'une réponse de prolongation perdue se rejoue avec la même identité'
);
do $$
declare
  renewal_number integer;
  authorization_value uuid;
  attempt_value uuid;
  plan_hash_value text;
  renewal_value uuid;
begin
  select authorization_id, attempt_id, plan_hash
  into authorization_value, attempt_value, plan_hash_value
  from repair_progression_values where name = 'started';
  for renewal_number in 2..6 loop
    renewal_value := (
      '99500000-0000-4000-8670-'
      || lpad(renewal_number::text, 12, '0')
    )::uuid;
    perform public.renew_administrative_document_repair_authorization(
      authorization_value, attempt_value, plan_hash_value,
      renewal_value, renewal_number - 1
    );
  end loop;
end;
$$;
select extensions.is(
  (select renewal_count
   from public.document_repair_authorizations
   where id = (
     select authorization_id from repair_progression_values where name = 'started'
   )),
  6::smallint,
  'le plafond cumulé de six prolongations est enregistré'
);
select extensions.is(
  (select count(*) from public.document_repair_events
   where authorization_id = (
     select authorization_id from repair_progression_values where name = 'started'
   ) and event_type = 'authorization_renewed'),
  6::bigint,
  'chaque prolongation effective produit un événement d’audit'
);
select extensions.throws_ok(
  format(
    'select public.renew_administrative_document_repair_authorization(%L,%L,%L,%L,6)',
    (select authorization_id from repair_progression_values where name = 'started'),
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8670-000000000007'
  ),
  'P4R05', 'La reprise de réparation ne peut pas être prolongée.',
  'un septième renouvellement ne peut pas contourner le plafond'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  public.record_administrative_document_repair_observation(
    (select authorization_id from repair_progression_values where name = 'started'),
    (select item_id from repair_progression_values where name = 'started'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'started'),
    (select plan_hash from repair_progression_values where name = 'started'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000003', 1,
    'catalog_absent', false, null, null, null, null,
    false, null, null, null
  )->>'progressState',
  'verification_required',
  'la réparation commencée reprend après prolongation contrôlée'
);
reset role;

-- Le verrou et une neutralisation concurrente sont revérifiés au démarrage.
delete from public.document_object_locks
where operation_id = '99500000-0000-4000-8200-000000000002';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.start_administrative_document_repair_item(%L,%L,%L,%L,%L,%L,%L,0,0)',
    (select authorization_id from repair_progression_values where name = 'not_started'),
    (select item_id from repair_progression_values where name = 'not_started'),
    '99500000-0000-4000-8000-000000000001',
    (select attempt_id from repair_progression_values where name = 'not_started'),
    (select plan_hash from repair_progression_values where name = 'not_started'),
    'confirm_already_conform',
    '99500000-0000-4000-8660-000000000002'
  ),
  'P4R05', 'Autorisation de réparation expirée.',
  'l’expiration est évaluée avant toute mutation malgré la perte du verrou'
);
reset role;

select extensions.is(
  (select count(*) from storage.objects where id::text like '99500000-%'),
  2::bigint,
  'les RPC de progression ne mutent aucun objet Storage'
);
select extensions.is(
  (select guard_enabled from public.document_storage_guard_runtime_config
   where singleton),
  false,
  'la garde Storage reste désactivée'
);

select * from extensions.finish();
rollback;
