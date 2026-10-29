begin;
\ir experimental_document_operations_enabled.inc

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_function(
  'public', 'is_current_account_deletion_document_write_frozen', array[]::text[],
  'la détection du gel documentaire existe'
);
select extensions.has_function(
  'public', 'list_account_storage_neutralization_operations', array['uuid'],
  'la reprise privilégiée dispose de son inventaire'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.is_current_account_deletion_document_write_frozen()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.list_account_storage_neutralization_operations(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.list_account_storage_neutralization_operations(uuid)',
    'EXECUTE'
  ),
  'le gel est visible par son utilisateur et l’inventaire reste privilégié'
);
select extensions.is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'account_deletion_freeze_storage_%'
      and permissive = 'RESTRICTIVE'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
  ),
  3,
  'les trois mutations Storage sont couvertes par des politiques restrictives'
);
select extensions.ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'account_deletion_freeze_storage_%'
      and roles is distinct from array['authenticated']::name[]
  ),
  'les politiques de gel ciblent authenticated sans exemption service_role'
);
select extensions.ok(
  not exists (
    select 1
    from pg_trigger trigger_row
    join pg_proc procedure_row on procedure_row.oid = trigger_row.tgfoid
    where trigger_row.tgrelid = 'storage.objects'::regclass
      and not trigger_row.tgisinternal
      and procedure_row.proname in (
        'is_current_account_deletion_document_write_frozen',
        'assert_account_deletion_document_writes_allowed'
      )
  ),
  'aucun trigger de garde Storage n’est installé par ce lot'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99400000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'freeze@example.test', 'test', now(),
  '{}', '{}', now(), now()
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id = '99400000-0000-4000-8000-000000000001';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.issue_account_deletion_document_authorization(
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8100-000000000001'
);
reset role;

-- Instrumentation locale, annulée avec la transaction, pour isoler l’effet
-- des politiques restrictives des politiques métier permissives existantes.
grant select, insert, update, delete on storage.objects to authenticated;
create policy account_deletion_freeze_test_select
on storage.objects for select to authenticated using (true);
create policy account_deletion_freeze_test_insert
on storage.objects for insert to authenticated with check (true);
create policy account_deletion_freeze_test_update
on storage.objects for update to authenticated using (true) with check (true);
create policy account_deletion_freeze_test_delete
on storage.objects for delete to authenticated using (true);
insert into storage.objects (
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99400000-0000-4000-8600-000000000001',
  'transaction-proofs', 'freeze-existing-object',
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000001',
  '{"size":1,"mimetype":"application/pdf"}', 'freeze-v1'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une autorisation active et non expirée gèle les écritures du compte'
);
select extensions.throws_ok(
  $$insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
    values (
      '99400000-0000-4000-8600-000000000002',
      'transaction-proofs', 'freeze-new-object',
      '99400000-0000-4000-8000-000000000001',
      '99400000-0000-4000-8000-000000000001',
      '{"size":1,"mimetype":"application/pdf"}', 'freeze-v1'
    )$$,
  '42501',
  'new row violates row-level security policy "account_deletion_freeze_storage_insert" for table "objects"',
  'le gel refuse un nouvel objet Storage même avec une politique permissive'
);
select extensions.results_eq(
  $$with changed as (
      update storage.objects set user_metadata = '{"changed":true}'
      where id = '99400000-0000-4000-8600-000000000001'
      returning 1
    ) select count(*)::integer from changed$$,
  array[0],
  'le gel rend les objets existants non modifiables'
);
select set_config('storage.allow_delete_query', 'true', true);
select extensions.results_eq(
  $$with removed as (
      delete from storage.objects
      where id = '99400000-0000-4000-8600-000000000001'
      returning 1
    ) select count(*)::integer from removed$$,
  array[0],
  'le gel rend les objets existants non supprimables'
);
select set_config('storage.allow_delete_query', 'false', true);
select extensions.throws_ok(
  $$select public.begin_transaction_proof_document_operation(
      '99400000-0000-4000-8200-000000000001',
      '99400000-0000-4000-8300-000000000001',
      'create',
      '99400000-0000-4000-8400-000000000001'
    )$$,
  'P4N06',
  'Les écritures documentaires sont suspendues pendant la suppression du compte.',
  'une nouvelle réservation documentaire concurrente est refusée'
);
reset role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99400000-0000-4000-8000-000000000004',
  'authenticated', 'authenticated', 'unfrozen@example.test', 'test', now(),
  '{}', '{}', now(), now()
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id = '99400000-0000-4000-8000-000000000004';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000004', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), false,
  'le gel d’un compte ne s’applique pas aux autres utilisateurs'
);
select extensions.lives_ok(
  $$insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version)
    values (
      '99400000-0000-4000-8600-000000000004',
      'transaction-proofs', 'unfrozen-object',
      '99400000-0000-4000-8000-000000000004',
      '99400000-0000-4000-8000-000000000004',
      '{"size":1,"mimetype":"application/pdf"}', 'unfrozen-v1'
    )$$,
  'un autre utilisateur autorisé peut encore insérer un objet'
);
select extensions.results_eq(
  $$with changed as (
      update storage.objects set user_metadata = '{"changed":true}'
      where id = '99400000-0000-4000-8600-000000000004'
      returning 1
    ) select count(*)::integer from changed$$,
  array[1],
  'un autre utilisateur autorisé peut encore modifier son objet'
);
select set_config('storage.allow_delete_query', 'true', true);
select extensions.results_eq(
  $$with removed as (
      delete from storage.objects
      where id = '99400000-0000-4000-8600-000000000004'
      returning 1
    ) select count(*)::integer from removed$$,
  array[1],
  'un autre utilisateur autorisé peut encore supprimer son objet'
);
select set_config('storage.allow_delete_query', 'false', true);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.cancel_account_deletion_document_authorization(
  (public.issue_account_deletion_document_authorization(
    '99400000-0000-4000-8000-000000000001',
    '99400000-0000-4000-8100-000000000001'
  )->>'authorizationId')::uuid
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), false,
  'une tentative annulée libère le gel'
);
reset role;

insert into public.account_deletion_document_authorizations (
  id, account_user_id, attempt_id, issued_at, expires_at
) values (
  '99400000-0000-4000-8500-000000000002',
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8100-000000000002',
  clock_timestamp() - interval '2 minutes',
  clock_timestamp() - interval '1 minute'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), false,
  'une tentative active expirée ne bloque plus les écritures'
);
reset role;

insert into public.protected_persons (
  id, owner_id, first_name, last_name
) values (
  '99400000-0000-4000-8200-000000000004',
  '99400000-0000-4000-8000-000000000004',
  'Dossier', 'Récupération'
);
insert into public.document_operations (
  id, protected_person_id, initiated_by, initiator_subject_id,
  initiator_kind, workflow, business_entity_type, business_entity_id,
  client_request_id, target_signature
) values (
  '99400000-0000-4000-8700-000000000001',
  '99400000-0000-4000-8200-000000000004',
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000001',
  'account_deletion', 'account_storage_neutralization',
  'transaction', '99400000-0000-4000-8300-000000000004',
  '99400000-0000-4000-8100-000000000004', '[]'::jsonb
);
insert into public.document_operation_targets (
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists,
  expected_object_id, expected_object_version, expected_snapshot_captured_at
) values (
  '99400000-0000-4000-8800-000000000001',
  '99400000-0000-4000-8700-000000000001', 1,
  'transaction-proofs',
  'protected-persons/99400000-0000-4000-8200-000000000004/transactions/99400000-0000-4000-8300-000000000004/proof',
  'primary', 'delete', 'insert', true,
  '99400000-0000-4000-8600-000000000005', 'expired-recovery-v1', now()
);
insert into public.account_storage_neutralizations (
  operation_id, target_id, authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type
) values (
  '99400000-0000-4000-8700-000000000001',
  '99400000-0000-4000-8800-000000000001',
  '99400000-0000-4000-8500-000000000002',
  '99400000-0000-4000-8000-000000000001',
  repeat('a', 64), 1, 'application/pdf'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une neutralisation non finalisée maintient le gel après expiration'
);
select extensions.throws_ok(
  $$select public.begin_transaction_proof_document_operation(
      '99400000-0000-4000-8200-000000000001',
      '99400000-0000-4000-8300-000000000001',
      'create',
      '99400000-0000-4000-8400-000000000001'
    )$$,
  'P4N06',
  'Les écritures documentaires sont suspendues pendant la suppression du compte.',
  'la récupération expirée ne permet pas une nouvelle réservation'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  public.get_account_storage_neutralization_progress(
    '99400000-0000-4000-8700-000000000001'
  )->>'phase',
  'reserved',
  'le service privilégié peut reprendre l’opération expirée existante'
);
select public.cancel_account_deletion_document_authorization(
  '99400000-0000-4000-8500-000000000002'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une annulation ne libère pas le gel d’une neutralisation non finalisée'
);
reset role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99400000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'sealed-freeze@example.test', 'test', now(),
  '{}', '{}', now(), now()
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id = '99400000-0000-4000-8000-000000000002';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.issue_account_deletion_document_authorization(
  '99400000-0000-4000-8000-000000000002',
  '99400000-0000-4000-8100-000000000003'
);
select public.assert_account_deletion_document_barrier(
  (public.issue_account_deletion_document_authorization(
    '99400000-0000-4000-8000-000000000002',
    '99400000-0000-4000-8100-000000000003'
  )->>'authorizationId')::uuid
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99400000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99400000-0000-4000-8000-000000000002', true
);
select extensions.is(
  public.is_current_account_deletion_document_write_frozen(), true,
  'une autorisation scellée reste gelée jusqu’à la suppression Auth'
);
select extensions.lives_ok(
  $$select 1 from storage.objects where false$$,
  'le gel ne bloque pas la consultation Storage'
);
reset role;

select extensions.finish();
rollback;
