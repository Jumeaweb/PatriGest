begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_function(
  'public', 'get_administrative_document_inventory',
  array['integer','text','text','text'],
  'la RPC d’inventaire paginé existe'
);
select extensions.has_function(
  'public', 'get_administrative_document_repair_capabilities', array[]::text[],
  'les capacités de réparation sont relues côté serveur'
);
select extensions.ok(
  to_regclass('public.document_operation_targets_inventory_object_idx') is not null,
  'le rapprochement catalogue-historique dispose d’un index sur le chemin cible'
);
select extensions.ok(
  (
    select bool_and(procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.proconfig = array['search_path=""'])
    from pg_proc procedure
    where procedure.oid in (
      'public.get_administrative_document_inventory(integer,text,text,text)'::regprocedure,
      'public.get_administrative_document_repair_capabilities()'::regprocedure
    )
  ),
  'les RPC de lecture sont stables, SECURITY DEFINER et à search_path fermé'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.get_administrative_document_inventory(integer,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_administrative_document_inventory(integer,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_administrative_document_inventory(integer,text,text,text)',
    'EXECUTE'
  ),
  'authenticated est le seul rôle API autorisé, sans autorisation métier implicite pour service_role'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '99510000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'inventory-admin@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99510000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'inventory-other-admin@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99510000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'inventory-user@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id in (
  '99510000-0000-4000-8000-000000000001',
  '99510000-0000-4000-8000-000000000002',
  '99510000-0000-4000-8000-000000000003'
);
insert into public.platform_administrators(user_id) values
  ('99510000-0000-4000-8000-000000000001'),
  ('99510000-0000-4000-8000-000000000002');
insert into public.account_subscriptions(owner_id, status, started_at)
values ('99510000-0000-4000-8000-000000000003', 'development', now());

insert into public.protected_persons(id, owner_id, first_name, last_name) values
  ('99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8000-000000000003', 'Inventaire', 'Principal'),
  ('99510000-0000-4000-8100-000000000002',
   '99510000-0000-4000-8000-000000000003', 'Inventaire', 'Secondaire');
insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values (
  '99510000-0000-4000-8200-000000000001',
  '99510000-0000-4000-8100-000000000001',
  'checking', 'Banque test', 'Compte test', 0, '2026-01-01'
);
insert into public.transactions(
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values
  ('99510000-0000-4000-8300-000000000001',
   '99510000-0000-4000-8200-000000000001', '2026-01-02',
   'expense', 'Référence sans objet', 10),
  ('99510000-0000-4000-8300-000000000002',
   '99510000-0000-4000-8200-000000000001', '2026-01-03',
   'expense', 'Chemin historique', 11),
  ('99510000-0000-4000-8300-000000000003',
   '99510000-0000-4000-8200-000000000001', '2026-01-04',
   'expense', 'Rattachement incohérent', 12);
insert into public.transaction_documents(
  id, transaction_id, storage_path, file_name, mime_type, file_size, created_by
) values
  ('99510000-0000-4000-8400-000000000001',
   '99510000-0000-4000-8300-000000000001',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000001/proof',
   'missing.pdf', 'application/pdf', 10, '99510000-0000-4000-8000-000000000003'),
  ('99510000-0000-4000-8400-000000000002',
   '99510000-0000-4000-8300-000000000002',
   'legacy/transaction-proof-2.pdf',
   'legacy.pdf', 'application/pdf', 10, '99510000-0000-4000-8000-000000000003'),
  ('99510000-0000-4000-8400-000000000003',
   '99510000-0000-4000-8300-000000000003',
   'protected-persons/99510000-0000-4000-8100-000000000002/transactions/99510000-0000-4000-8300-000000000003/proof',
   'mismatch.pdf', 'application/pdf', 10, '99510000-0000-4000-8000-000000000003');

insert into storage.objects(id, bucket_id, name, owner, owner_id, metadata, version) values
  ('99510000-0000-4000-8500-000000000001', 'transaction-proofs',
   'legacy/transaction-proof-2.pdf',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003',
   '{"size":10,"mimetype":"application/pdf"}', 'legacy-v1'),
  ('99510000-0000-4000-8500-000000000002', 'transaction-proofs',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000099/proof',
   null, null, null, null),
  ('99510000-0000-4000-8500-000000000003', 'transaction-proofs',
   'legacy/unresolved-orphan.pdf',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003',
   '{"size":10,"mimetype":"application/pdf"}', 'legacy-v2');

insert into public.document_operations(
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, safe_error_code, closed_at
) values
  ('99510000-0000-4000-8600-000000000001',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003', 'user',
   'transaction_proof_delete', 'transaction',
   '99510000-0000-4000-8300-000000000001',
   '99510000-0000-4000-8700-000000000001', 'attention_required', '[]',
   'DELETE_UNCERTAIN', null),
  ('99510000-0000-4000-8600-000000000002',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003', 'account_deletion',
   'account_storage_neutralization', 'protected_person',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8700-000000000002', 'executing', '[]', null, null),
  ('99510000-0000-4000-8600-000000000003',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003', 'user',
   'transaction_proof_delete', 'transaction',
   '99510000-0000-4000-8300-000000000002',
   '99510000-0000-4000-8700-000000000003', 'completed', '[]', null, now()),
  ('99510000-0000-4000-8600-000000000004',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8000-000000000003',
   '99510000-0000-4000-8000-000000000003', 'account_deletion',
   'account_storage_neutralization', 'protected_person',
   '99510000-0000-4000-8100-000000000001',
   '99510000-0000-4000-8700-000000000004', 'completed', '[]', null, now());
insert into public.document_operation_targets(
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists
) values
  ('99510000-0000-4000-8800-000000000001',
   '99510000-0000-4000-8600-000000000001', 1, 'transaction-proofs',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000001/proof',
   'primary', 'delete', 'insert', false),
  ('99510000-0000-4000-8800-000000000002',
   '99510000-0000-4000-8600-000000000002', 1, 'transaction-proofs',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000002/proof',
   'primary', 'update', 'update', true),
  ('99510000-0000-4000-8800-000000000003',
   '99510000-0000-4000-8600-000000000003', 1, 'transaction-proofs',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000002/proof',
   'primary', 'delete', 'insert', true),
  ('99510000-0000-4000-8800-000000000004',
   '99510000-0000-4000-8600-000000000004', 1, 'transaction-proofs',
   'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000099/proof',
   'primary', 'update', 'update', true);
insert into public.document_object_locks(bucket_id, object_path, target_id, operation_id)
values (
  'transaction-proofs',
  'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000002/proof',
  '99510000-0000-4000-8800-000000000003',
  '99510000-0000-4000-8600-000000000003'
);

insert into public.account_deletion_document_authorizations(
  id, account_user_id, attempt_id, issued_at, expires_at
) values (
  '99510000-0000-4000-8900-000000000001',
  '99510000-0000-4000-8000-000000000003',
  '99510000-0000-4000-8900-000000000002', now(), now() + interval '5 minutes'
);
insert into public.account_storage_neutralizations(
  operation_id, target_id, authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type, phase
) values (
  '99510000-0000-4000-8600-000000000002',
  '99510000-0000-4000-8800-000000000002',
  '99510000-0000-4000-8900-000000000001',
  '99510000-0000-4000-8000-000000000003', repeat('a',64), 10,
  'application/pdf', 'reserved'
);
insert into public.account_storage_neutralizations(
  operation_id, target_id, authorization_id, account_user_id,
  expected_sha256, expected_byte_size, mime_type, phase, finalized_at
) values (
  '99510000-0000-4000-8600-000000000004',
  '99510000-0000-4000-8800-000000000004',
  '99510000-0000-4000-8900-000000000001',
  '99510000-0000-4000-8000-000000000003', repeat('d',64), 10,
  'application/pdf', 'finalized', now()
);

insert into public.document_operation_backups(
  id, operation_id, target_id, protected_person_id, initiator_subject_id,
  original_bucket_id, original_object_path, original_object_id,
  original_object_version, recovery_object_path, byte_size, mime_type, sha256,
  state, recovery_object_id, recovery_object_version, upload_verified_at
) values (
  '99510000-0000-4000-8a00-000000000001',
  '99510000-0000-4000-8600-000000000001',
  '99510000-0000-4000-8800-000000000001',
  '99510000-0000-4000-8100-000000000001',
  '99510000-0000-4000-8000-000000000003', 'transaction-proofs',
  'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000002/proof',
  '99510000-0000-4000-8500-000000000001', 'legacy-v1',
  'operations/99510000-0000-4000-8600-000000000003/targets/99510000-0000-4000-8800-000000000003/backup',
  10, 'application/pdf', repeat('b',64), 'verified',
  '99510000-0000-4000-8b00-000000000001', 'backup-v1', now()
);

insert into public.document_repair_authorizations(
  id, administrator_subject_id, operation_id, attempt_id, reason,
  repair_plan, repair_plan_hash, target_count, observed_operation_revision,
  state, issued_at, expires_at, recovery_expires_at, renewal_count,
  last_renewal_id, last_renewed_at
) values (
  '99510000-0000-4000-8c00-000000000001',
  '99510000-0000-4000-8000-000000000002',
  '99510000-0000-4000-8600-000000000001',
  '99510000-0000-4000-8c00-000000000002', 'Réparation expirée',
  '[]', repeat('c',64), 1, 0, 'active',
  now() - interval '20 minutes', now() - interval '15 minutes',
  now() - interval '1 minute', 6,
  '99510000-0000-4000-8c00-000000000003', now() - interval '5 minutes'
);

set local "request.jwt.claim.sub" = '99510000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"99510000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select extensions.throws_ok(
  $$select public.get_administrative_document_inventory(25,null,null,null)$$,
  'P4I01', 'Inventaire documentaire non autorisé.',
  'un utilisateur non administrateur est refusé'
);
reset role;

create temporary table inventory_mutation_snapshot as
select jsonb_build_object(
  'transaction_documents', (select count(*) from public.transaction_documents),
  'bank_statements', (select count(*) from public.bank_statements),
  'management_report_documents', (select count(*) from public.management_report_documents),
  'storage_objects', (select count(*) from storage.objects),
  'document_operations', (select count(*) from public.document_operations),
  'document_operation_targets', (select count(*) from public.document_operation_targets),
  'document_object_locks', (select count(*) from public.document_object_locks),
  'document_operation_events', (select count(*) from public.document_operation_events),
  'document_operation_backups', (select count(*) from public.document_operation_backups),
  'account_storage_neutralizations', (select count(*) from public.account_storage_neutralizations),
  'document_repair_authorizations', (select count(*) from public.document_repair_authorizations),
  'document_repair_items', (select count(*) from public.document_repair_items),
  'document_repair_events', (select count(*) from public.document_repair_events),
  'document_repair_observations', (select count(*) from public.document_repair_observations)
) as counts;

set local "request.jwt.claim.sub" = '99510000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"99510000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok(
  $$select public.get_administrative_document_inventory(25,null,null,null)$$,
  'un administrateur authentifié peut consulter l’inventaire'
);
select extensions.throws_ok(
  $$select public.get_administrative_document_inventory(101,null,null,null)$$,
  'P4I02', 'Limite d’inventaire invalide.',
  'la limite maximale est imposée côté SQL'
);
select extensions.throws_ok(
  $$select public.get_administrative_document_inventory(25,'../../secret',null,null)$$,
  'P4I02', 'Curseur d’inventaire invalide.',
  'un curseur assimilable à un chemin est refusé'
);
select extensions.throws_ok(
  $$select public.get_administrative_document_inventory(25,null,'storage.objects',null)$$,
  'P4I02', 'Catégorie d’inventaire invalide.',
  'une catégorie arbitraire est refusée directement par la RPC'
);
select extensions.throws_ok(
  $$select public.get_administrative_document_inventory(25,null,null,'arbitrary_path')$$,
  'P4I02', 'Filtre d’inventaire invalide.',
  'un constat arbitraire est refusé directement par la RPC'
);
select extensions.ok(
  (select jsonb_array_length(result->'items') = 1 and (result->>'hasMore')::boolean
   from (select public.get_administrative_document_inventory(1,null,'document_operation',null) result) value),
  'la première page bornée annonce une page suivante'
);
select extensions.ok(
  (select (result->>'nextCursor') is not null
   from (select public.get_administrative_document_inventory(1,null,'document_operation',null) result) value),
  'la pagination fournit un curseur déterministe opaque'
);
select extensions.ok(
  (select bool_and(item->>'documentCategory' = 'transaction_proof')
   from jsonb_array_elements(public.get_administrative_document_inventory(
     100,null,'transaction_proof',null
   )->'items') item),
  'le filtre de catégorie est appliqué côté SQL'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'business_reference_without_catalog_object'
    )->'items') item
    where item->>'findingStatus' = 'sql_fact'
      and item->>'physicalVerification' = 'not_performed'
  ),
  'une référence métier sans objet est démontrée sans prétendre lire les octets'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'historical_noncanonical_path'
    )->'items') item
    where item->>'findingStatus' = 'historical_legitimate'
  ),
  'un chemin historique reste qualifié comme potentiellement légitime'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'catalog_object_without_business_reference'
    )->'items') item
    where item->>'findingStatus' = 'possible_anomaly'
  ),
  'un objet sans référence directe reste une anomalie possible'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'unresolved_catalog_path'
    )->'items') item
    where item->>'findingStatus' = 'possible_anomaly'
      and item->>'protectedPersonId' is null
      and item->>'businessEntityId' is null
  ),
  'un chemin de catalogue non résolu est distingué sans identité métier fabriquée'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'storage_identity_incomplete'
    )->'items') item
  ),
  'une version ou des métadonnées manquantes sont détectées'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'backup_catalog_object_missing'
    )->'items') item
  ),
  'une sauvegarde cataloguée sans objet Storage est détectée'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'terminal_operation_residual'
    )->'items') item
    where (item->>'storageGuardRequired')::boolean
  ),
  'un résidu d’opération terminale est bloqué derrière la garde Storage'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'incomplete_account_neutralization'
    )->'items') item
  ),
  'une neutralisation de compte inachevée est inventoriée séparément'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'expired_repair_authorization'
    )->'items') item
  ) and exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'repair_renewals_exhausted'
    )->'items') item
  ),
  'expiration et épuisement des renouvellements sont distingués'
);
select extensions.ok(
  exists (
    select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
      100,null,null,'storage_owner_unrecorded'
    )->'items') item
    where item->>'detailCode' = 'OWNER_NEUTRALIZED'
      and item->>'findingStatus' = 'historical_legitimate'
  ),
  'un propriétaire retiré par une neutralisation finalisée reste un état historique légitime'
);
select extensions.ok(
  position('protected-persons/' in public.get_administrative_document_inventory(
    100,null,null,null
  )::text) = 0
  and position('operations/' in public.get_administrative_document_inventory(
    100,null,null,null
  )::text) = 0,
  'aucun chemin métier ou de sauvegarde n’est exposé'
);
select extensions.is(
  public.get_administrative_document_inventory(100,null,null,null)->>'physicalInspectionPerformed',
  'false',
  'la RPC annonce explicitement l’absence de lecture physique'
);
select extensions.is(
  (public.get_administrative_document_repair_capabilities()->>'storageGuardEnabled')::boolean,
  false,
  'la garde Storage reste désactivée'
);
reset role;

select extensions.is(
  (select counts from inventory_mutation_snapshot),
  jsonb_build_object(
    'transaction_documents', (select count(*) from public.transaction_documents),
    'bank_statements', (select count(*) from public.bank_statements),
    'management_report_documents', (select count(*) from public.management_report_documents),
    'storage_objects', (select count(*) from storage.objects),
    'document_operations', (select count(*) from public.document_operations),
    'document_operation_targets', (select count(*) from public.document_operation_targets),
    'document_object_locks', (select count(*) from public.document_object_locks),
    'document_operation_events', (select count(*) from public.document_operation_events),
    'document_operation_backups', (select count(*) from public.document_operation_backups),
    'account_storage_neutralizations', (select count(*) from public.account_storage_neutralizations),
    'document_repair_authorizations', (select count(*) from public.document_repair_authorizations),
    'document_repair_items', (select count(*) from public.document_repair_items),
    'document_repair_events', (select count(*) from public.document_repair_events),
    'document_repair_observations', (select count(*) from public.document_repair_observations)
  ),
  'l’inventaire ne modifie ni le catalogue, ni les références, ni les opérations documentaires'
);

set local "request.jwt.claim.sub" = '99510000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"99510000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select extensions.ok(
  position('99510000-0000-4000-8000-000000000002' in
    public.get_administrative_document_inventory(100,null,null,null)::text) = 0,
  'l’inventaire ne révèle pas l’identité de l’administrateur propriétaire d’une réparation'
);
reset role;

-- La garde transactionnelle refuse les plans destructifs même en cas de
-- contournement de l’interface. L’échec de l’insertion ne consomme aucun item.
select extensions.throws_ok(
  $$insert into public.document_repair_items(
      authorization_id, operation_id, target_id, ordinal, action,
      expected_operation_revision, expected_target_revision,
      expected_application_state, expected_object_exists, backup_id,
      expected_backup_revision, expected_backup_state
    ) values (
      '99510000-0000-4000-8c00-000000000001',
      '99510000-0000-4000-8600-000000000001',
      '99510000-0000-4000-8800-000000000001', 1,
      'complete_backup_cleanup', 0, 0, 'pending', false,
      '99510000-0000-4000-8a00-000000000001', 0, 'verified'
    )$$,
  'P4R08', 'Cette action exige la garde Storage conditionnelle.',
  'le nettoyage est refusé par SQL avant création de l’item'
);
select extensions.is(
  (select count(*) from public.document_repair_items
   where authorization_id = '99510000-0000-4000-8c00-000000000001'),
  0::bigint,
  'un refus préalable ne consomme aucune cible de réparation'
);
select extensions.throws_ok(
  $sql$do $block$
    begin
      insert into storage.objects(id, bucket_id, name, metadata, version)
      values (
        '99510000-0000-4000-8d00-000000000001', 'transaction-proofs',
        'protected-persons/99510000-0000-4000-8100-000000000001/transactions/99510000-0000-4000-8300-000000000001/proof',
        '{"size":10,"mimetype":"application/pdf"}', 'concurrent-v1'
      );
      insert into public.document_repair_items(
        authorization_id, operation_id, target_id, ordinal, action,
        expected_operation_revision, expected_target_revision,
        expected_application_state, expected_object_exists, backup_id,
        expected_backup_revision, expected_backup_state
      ) values (
        '99510000-0000-4000-8c00-000000000001',
        '99510000-0000-4000-8600-000000000001',
        '99510000-0000-4000-8800-000000000001', 1,
        'restore_original', 0, 0, 'pending', false,
        '99510000-0000-4000-8a00-000000000001', 0, 'verified'
      );
    end
  $block$ $sql$,
  'P4R08', 'Cette action exige la garde Storage conditionnelle.',
  'une cible devenue présente entre diagnostic et autorisation est refusée'
);
select extensions.lives_ok(
  $$insert into public.document_repair_items(
      authorization_id, operation_id, target_id, ordinal, action,
      expected_operation_revision, expected_target_revision,
      expected_application_state, expected_object_exists, backup_id,
      expected_backup_revision, expected_backup_state
    ) values (
      '99510000-0000-4000-8c00-000000000001',
      '99510000-0000-4000-8600-000000000001',
      '99510000-0000-4000-8800-000000000001', 1,
      'restore_original', 0, 0, 'pending', false,
      '99510000-0000-4000-8a00-000000000001', 0, 'verified'
    )$$,
  'une restauration vers une cible absente reste autorisable par la garde préalable'
);
select extensions.throws_ok(
  $$update public.document_repair_items
    set action = 'complete_backup_cleanup'
    where authorization_id = '99510000-0000-4000-8c00-000000000001'$$,
  '42501', 'Le plan de réparation est immuable.',
  'une action autorisée ne peut pas être transformée ensuite en action destructive'
);

select * from extensions.finish();
rollback;
