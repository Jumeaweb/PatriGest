begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'account_deletion_document_authorizations',
  'le registre des autorisations courtes existe'
);
select extensions.has_table(
  'public', 'account_storage_neutralizations',
  'la progression spécialisée des neutralisations existe'
);
select extensions.has_function(
  'public', 'begin_account_storage_neutralization',
  array['uuid','uuid','text','text','uuid','text','text','bigint','text'],
  'la RPC de réservation spécialisée existe'
);
select extensions.has_function(
  'public', 'assert_account_deletion_document_barrier', array['uuid'],
  'la barrière préalable à la suppression Auth existe'
);
select extensions.has_function(
  'public', 'cancel_account_deletion_document_authorization', array['uuid'],
  'l’annulation privilégiée d’une tentative existe'
);
select extensions.has_function(
  'public', 'confirm_account_storage_neutralization_recovery',
  array['uuid','bigint','uuid','text','text','bigint'],
  'la confirmation de récupération durable existe'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.account_deletion_document_authorizations', 'SELECT'
  )
  and not has_table_privilege(
    'authenticated', 'public.account_storage_neutralizations', 'INSERT'
  )
  and not has_table_privilege(
    'service_role', 'public.account_storage_neutralizations', 'UPDATE'
  ),
  'les tables techniques restent fermées aux rôles applicatifs et privilégiés'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.issue_account_deletion_document_authorization(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.issue_account_deletion_document_authorization(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.cancel_account_deletion_document_authorization(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.cancel_account_deletion_document_authorization(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.authorize_account_storage_neutralization_recovery(uuid,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.finalize_account_storage_neutralization(uuid,bigint)',
    'EXECUTE'
  ),
  'l’ouverture appartient au compte et la progression destructive au serveur'
);
select extensions.ok(
  (select bool_and(proc.prosecdef and proc.proconfig = array['search_path=""'])
   from pg_proc proc
   where proc.oid in (
     'public.issue_account_deletion_document_authorization(uuid,uuid)'::regprocedure,
     'public.cancel_account_deletion_document_authorization(uuid)'::regprocedure,
     'public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)'::regprocedure,
     'public.assert_account_deletion_document_barrier(uuid)'::regprocedure
   )),
  'les RPC exposées sont SECURITY DEFINER avec un search_path vide'
);
select extensions.ok(
  (
    select bool_and(
      has_function_privilege('service_role', procedure_oid, 'EXECUTE')
      and not has_function_privilege('authenticated', procedure_oid, 'EXECUTE')
      and position(
        'assert_account_storage_neutralization_service()'
        in pg_get_functiondef(procedure_oid)
      ) > 0
    )
    from unnest(array[
      'public.issue_account_deletion_document_authorization(uuid,uuid)'::regprocedure,
      'public.cancel_account_deletion_document_authorization(uuid)'::regprocedure,
      'public.reserve_account_storage_neutralization_backup(uuid)'::regprocedure,
      'public.confirm_account_storage_neutralization_backup(uuid,bigint,bigint,text,bigint)'::regprocedure,
      'public.record_account_storage_neutralization_original_deleted(uuid,bigint)'::regprocedure,
      'public.record_account_storage_neutralization_recreated(uuid,bigint,uuid,text)'::regprocedure,
      'public.verify_account_storage_neutralization_content(uuid,bigint,text,bigint)'::regprocedure,
      'public.authorize_account_storage_neutralization_recovery(uuid,bigint)'::regprocedure,
      'public.confirm_account_storage_neutralization_recovery(uuid,bigint,uuid,text,text,bigint)'::regprocedure,
      'public.authorize_account_storage_neutralization_backup_cleanup(uuid,bigint)'::regprocedure,
      'public.confirm_account_storage_neutralization_backup_cleanup(uuid,bigint,bigint)'::regprocedure,
      'public.finalize_account_storage_neutralization(uuid,bigint)'::regprocedure,
      'public.mark_account_storage_neutralization_attention_required(uuid,bigint,text)'::regprocedure,
      'public.assert_account_deletion_document_barrier(uuid)'::regprocedure
    ]) as service_procedure(procedure_oid)
  ),
  'chaque RPC privilégiée est fermée au client et vérifie le contexte service_role'
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

-- Instrumentation de lecture limitée à cette transaction pgTAP. Les
-- privilèges réellement livrés ont été vérifiés ci-dessus et restent fermés.
grant select on public.account_deletion_document_authorizations,
  public.account_storage_neutralizations,
  public.document_operations,
  public.document_operation_targets,
  public.document_operation_backups,
  public.document_object_locks to authenticated, service_role;
create policy account_deletion_document_authorizations_test_select
on public.account_deletion_document_authorizations for select
to authenticated, service_role using (true);
create policy account_storage_neutralizations_test_select
on public.account_storage_neutralizations for select
to authenticated, service_role using (true);
create policy document_operations_neutralization_test_select
on public.document_operations for select
to authenticated, service_role using (true);
create policy document_operation_targets_neutralization_test_select
on public.document_operation_targets for select
to authenticated, service_role using (true);
create policy document_operation_backups_neutralization_test_select
on public.document_operation_backups for select
to authenticated, service_role using (true);
create policy document_object_locks_neutralization_test_select
on public.document_object_locks for select
to authenticated, service_role using (true);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '99300000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'neutralization-owner@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99300000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'neutralization-reader@example.test', 'test', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '99300000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'neutralization-other@example.test', 'test', now(), '{}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '99300000-0000-4000-8000-000000000001',
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8000-000000000003'
);
update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id = '99300000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id, status, started_at)
values ('99300000-0000-4000-8000-000000000001', 'development', now());

insert into public.protected_persons(id, owner_id, first_name, last_name)
values (
  '99300000-0000-4000-8100-000000000001',
  '99300000-0000-4000-8000-000000000001',
  'Neutralisation', 'Documentaire'
);
insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values (
  '99300000-0000-4000-8900-000000000001',
  '99300000-0000-4000-8100-000000000001',
  '99300000-0000-4000-8000-000000000002',
  'read_only',
  '99300000-0000-4000-8000-000000000001'
);
insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values (
  '99300000-0000-4000-8200-000000000001',
  '99300000-0000-4000-8100-000000000001',
  'checking', 'Banque test', 'Compte test', 0, '2026-01-01'
);
insert into public.transactions(
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values
  ('99300000-0000-4000-8300-000000000001',
   '99300000-0000-4000-8200-000000000001', '2026-01-02',
   'expense', 'Objet du lecteur', 12),
  ('99300000-0000-4000-8300-000000000002',
   '99300000-0000-4000-8200-000000000001', '2026-01-03',
   'expense', 'Workflow ordinaire', 8),
  ('99300000-0000-4000-8300-000000000003',
   '99300000-0000-4000-8200-000000000001', '2026-01-04',
   'expense', 'Objet incertain', 6),
  ('99300000-0000-4000-8300-000000000004',
   '99300000-0000-4000-8200-000000000001', '2026-01-05',
   'expense', 'Objet à récupérer', 7);

insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
   '99300000-0000-4000-8800-000000000001', 'transaction-proofs',
   'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
   '99300000-0000-4000-8000-000000000002',
   '99300000-0000-4000-8000-000000000002',
   '{"size":12,"mimetype":"application/pdf"}', 'original-v1'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select extensions.throws_ok(
  $$insert into public.account_storage_neutralizations(
      operation_id, target_id, authorization_id, account_user_id,
      expected_sha256, expected_byte_size, mime_type
    ) values (
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      '99300000-0000-4000-8000-000000000002', repeat('a',64), 12,
      'application/pdf'
    )$$,
  '42501',
  'permission denied for table account_storage_neutralizations',
  'un utilisateur ne peut pas contourner les RPC par écriture directe'
);
select extensions.throws_ok(
  $$select public.issue_account_deletion_document_authorization(
      '99300000-0000-4000-8000-000000000002',
      '99300000-0000-4000-8400-000000000001'
    )$$,
  '42501',
  'permission denied for function issue_account_deletion_document_authorization',
  'le client ne peut pas fabriquer sa preuve de réauthentification'
);
select extensions.throws_ok(
  $$select public.cancel_account_deletion_document_authorization(
      '99300000-0000-4000-8400-000000000099'
    )$$,
  '42501',
  'permission denied for function cancel_account_deletion_document_authorization',
  'le client ne peut pas annuler lui-même une tentative privilégiée'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.issue_account_deletion_document_authorization(
    '99300000-0000-4000-8000-000000000002',
    '99300000-0000-4000-8400-000000000001'
  )->>'accountUserId'),
  '99300000-0000-4000-8000-000000000002',
  'le serveur crée une autorisation courte liée au compte et à la tentative'
);
select extensions.is(
  (select count(*) from public.account_deletion_document_authorizations
   where account_user_id = '99300000-0000-4000-8000-000000000002'
     and attempt_id = '99300000-0000-4000-8400-000000000001'),
  1::bigint,
  'une émission répétée reste idempotente'
) from public.issue_account_deletion_document_authorization(
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8400-000000000001'
);
select public.issue_account_deletion_document_authorization(
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8400-000000000004'
);
select public.issue_account_deletion_document_authorization(
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8400-000000000005'
);
select extensions.is(
  (public.cancel_account_deletion_document_authorization(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000005')
  )->>'state'),
  'cancelled',
  'le serveur annule explicitement une tentative encore active'
);
select extensions.is(
  (public.cancel_account_deletion_document_authorization(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000005')
  )->>'state'),
  'cancelled',
  'une annulation répétée reste idempotente'
);
reset role;

update public.account_deletion_document_authorizations
set issued_at = timing.expired_at - interval '10 minutes',
    expires_at = timing.expired_at
from (select clock_timestamp() - interval '10 minutes' as expired_at) timing
where attempt_id = '99300000-0000-4000-8400-000000000004';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000001', 'original-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000004'),
    '99300000-0000-4000-8500-000000000004', repeat('a',64)
  ),
  'P4N01',
  'Autorisation de suppression de compte inactive ou expirée.',
  'une tentative expirée ne peut pas ouvrir de neutralisation'
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000001', 'original-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000005'),
    '99300000-0000-4000-8500-000000000005', repeat('a',64)
  ),
  'P4N01',
  'Autorisation de suppression de compte inactive ou expirée.',
  'une tentative annulée ne peut pas ouvrir de neutralisation'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000003', true
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000001', 'original-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000001', repeat('a',64)
  ),
  'P4N01',
  'Autorisation de suppression de compte inactive ou expirée.',
  'un autre utilisateur ne peut pas employer l’autorisation'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000001', 'wrong-version', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000002', repeat('a',64)
  ),
  'P4N03',
  'L’objet Storage a changé depuis son inventaire.',
  'une version Storage divergente est refusée'
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000099', 'original-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000099', repeat('a',64)
  ),
  'P4N03',
  'L’objet Storage a changé depuis son inventaire.',
  'un identifiant Storage divergent est refusé'
);
select extensions.is(
  (public.begin_account_storage_neutralization(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000001', 'transaction-proofs',
    'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
    '99300000-0000-4000-8800-000000000001', 'original-v1', repeat('a',64),
    12, 'application/pdf'
  )->>'phase'),
  'reserved',
  'un lecteur peut réserver la neutralisation de son propre objet Storage'
);
select extensions.is(
  (public.begin_account_storage_neutralization(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000001', 'transaction-proofs',
    'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
    '99300000-0000-4000-8800-000000000001', 'original-v1', repeat('a',64),
    12, 'application/pdf'
  )->>'phase'),
  'reserved',
  'une double réservation identique retrouve la même progression'
);
select extensions.is(
  (select count(*) from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000001'),
  1::bigint,
  'l’idempotence ne duplique ni l’opération ni sa cible'
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000001', 'original-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000003', repeat('a',64)
  ),
  'P4O05',
  'Ce fichier est déjà réservé par une autre opération.',
  'une réservation concurrente du même chemin est refusée'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    $sql$select public.finalize_account_storage_neutralization(%L, 0)$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001')
  ),
  'P4N04',
  'La neutralisation documentaire n’est pas finalisable.',
  'une finalisation prématurée est refusée'
);
select extensions.is(
  (public.reserve_account_storage_neutralization_backup(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001')
  )->>'state'),
  'upload_pending',
  'la sauvegarde durable est réservée sur la cible unique'
);
select extensions.throws_ok(
  format(
    $sql$select public.confirm_account_storage_neutralization_backup(
      %L, 0, 0, %L, 12
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    repeat('a',64)
  ),
  'P4B04',
  'L’objet de récupération est absent.',
  'une sauvegarde absente ne peut pas être déclarée vérifiée'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_account_deletion_document_barrier(%L)$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001')
  ),
  'P4N05',
  'La suppression Auth reste bloquée par l’état documentaire.',
  'la barrière refuse une neutralisation non terminale'
);
reset role;

insert into storage.objects(id, bucket_id, name, metadata, version)
select
  '99300000-0000-4000-8800-000000000002',
  'document-operation-backups', recovery_object_path,
  '{"size":12,"mimetype":"application/pdf"}', 'backup-v1'
from public.document_operation_backups
where operation_id = (
  select id from public.document_operations
  where client_request_id = '99300000-0000-4000-8500-000000000001'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.confirm_account_storage_neutralization_backup(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    0, 0, repeat('a',64), 12
  )->>'phase'),
  'backup_verified',
  'la sauvegarde présente et vérifiée ouvre l’exécution'
);
select extensions.throws_ok(
  format(
    $sql$select public.confirm_account_storage_neutralization_backup(
      %L, 1, 1, %L, 12
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    repeat('b',64)
  ),
  'P4N04',
  'La progression de neutralisation a changé.',
  'une répétition avec une autre empreinte ne bénéficie pas de l’idempotence'
);
select extensions.is(
  (public.get_account_storage_neutralization_progress(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001')
  )->>'backupState'),
  'verified',
  'la reprise retrouve la dernière étape durable confirmée'
);
select extensions.throws_ok(
  format(
    $sql$select public.record_account_storage_neutralization_original_deleted(
      %L, 1
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001')
  ),
  'P4N03',
  'L’objet Storage original existe encore.',
  'la progression ne peut pas anticiper la suppression réelle'
);
reset role;

select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99300000-0000-4000-8800-000000000001';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.record_account_storage_neutralization_original_deleted(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    1
  )->>'phase'),
  'original_deleted',
  'la disparition réelle de l’original est enregistrée'
);
select extensions.is(
  (public.get_account_storage_neutralization_progress(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001')
  )->>'recoveryRequired'),
  'true',
  'la reprise signale explicitement qu’une récupération est nécessaire'
);
select extensions.is(
  (public.authorize_account_storage_neutralization_recovery(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    2
  )->>'sourceBucketId'),
  'document-operation-backups',
  'la récupération autorisée utilise exclusivement la sauvegarde durable vérifiée'
);
select extensions.throws_ok(
  format(
    $sql$select public.verify_account_storage_neutralization_content(
      %L, 2, %L, 12
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    repeat('a',64)
  ),
  'P4N03',
  'Les octets recréés ne correspondent pas à la sauvegarde.',
  'la vérification ne peut pas précéder la recréation'
);
reset role;

insert into storage.objects(id, bucket_id, name, metadata, version)
values (
  '99300000-0000-4000-8800-000000000004', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
  '{"size":12,"mimetype":"application/pdf"}', 'recreated-v1'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.record_account_storage_neutralization_recreated(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    2, '99300000-0000-4000-8800-000000000004', 'recreated-v1'
  )->>'phase'),
  'recreated',
  'la recréation au même chemin sans l’ancien propriétaire est enregistrée'
);
select extensions.throws_ok(
  format(
    $sql$select public.verify_account_storage_neutralization_content(
      %L, 3, %L, 12
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    repeat('b',64)
  ),
  'P4N03',
  'Les octets recréés ne correspondent pas à la sauvegarde.',
  'une empreinte divergente est refusée'
);
select extensions.is(
  (public.verify_account_storage_neutralization_content(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    3, repeat('a',64), 12
  )->>'phase'),
  'verified',
  'l’identité et les octets recréés sont vérifiés séparément'
);
select extensions.is(
  (public.authorize_account_storage_neutralization_backup_cleanup(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    4
  )->>'bucketId'),
  'document-operation-backups',
  'le nettoyage vise uniquement la sauvegarde durable réservée'
);
reset role;

delete from storage.objects
where id = '99300000-0000-4000-8800-000000000002';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.confirm_account_storage_neutralization_backup_cleanup(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    5, 1
  )->>'phase'),
  'backup_cleaned',
  'la disparition de la sauvegarde est confirmée avant finalisation'
);
select extensions.is(
  (public.finalize_account_storage_neutralization(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'),
    6
  )->>'state'),
  'completed',
  'la finalisation intervient seulement après vérification et nettoyage'
);
select extensions.is(
  (select count(*) from public.document_object_locks
   where operation_id = (
     select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000001'
   )),
  0::bigint,
  'l’état terminal libère le verrou du chemin'
);
select extensions.is(
  (public.assert_account_deletion_document_barrier(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001')
  )->>'ready'),
  'true',
  'la barrière autorise la suite quand objets, opérations et sauvegardes sont propres'
);
select extensions.is(
  (select state from public.account_deletion_document_authorizations
   where attempt_id = '99300000-0000-4000-8400-000000000001'),
  'sealed',
  'une barrière réussie scelle irréversiblement la tentative'
);
select extensions.is(
  (public.issue_account_deletion_document_authorization(
    '99300000-0000-4000-8000-000000000002',
    '99300000-0000-4000-8400-000000000001'
  )->>'state'),
  'sealed',
  'réémettre le même identifiant de tentative ne le réactive pas'
);
select extensions.is(
  (public.assert_account_deletion_document_barrier(
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001')
  )->>'ready'),
  'true',
  'la répétition de la barrière scellée reste idempotente tant que l’état est propre'
);
select extensions.throws_ok(
  format(
    $sql$select public.cancel_account_deletion_document_authorization(%L)$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001')
  ),
  'P4N04',
  'Une autorisation scellée ne peut plus être annulée.',
  'une tentative scellée ne peut pas changer de sens après la barrière'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select extensions.throws_ok(
  format(
    $sql$select public.begin_account_storage_neutralization(
      %L, %L, 'transaction-proofs',
      'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000001/proof',
      '99300000-0000-4000-8800-000000000004', 'recreated-v1', %L, 12,
      'application/pdf'
    )$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001'),
    '99300000-0000-4000-8500-000000000006', repeat('a',64)
  ),
  'P4N01',
  'Autorisation de suppression de compte inactive ou expirée.',
  'une tentative scellée ne peut pas autoriser une nouvelle opération'
);
reset role;

-- La barrière n’est pas un verrou de prédicat sur Storage : un objet peut
-- encore apparaître après son retour tant que la future garde n’est pas active.
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99300000-0000-4000-8800-000000000008', 'transaction-proofs',
  'post-barrier-race/object',
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8000-000000000002',
  '{"size":1,"mimetype":"application/pdf"}', 'race-v1'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    $sql$select public.assert_account_deletion_document_barrier(%L)$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000001')
  ),
  'P4N05',
  'La suppression Auth reste bloquée par l’état documentaire.',
  'un nouvel objet apparu après la barrière est détecté par un nouveau contrôle'
);
reset role;
delete from storage.objects
where id = '99300000-0000-4000-8800-000000000008';

-- Les workflows utilisateur existants restent accessibles au gestionnaire.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000001', true
);
select extensions.lives_ok(
  $$select public.begin_transaction_proof_document_operation(
      '99300000-0000-4000-8100-000000000001',
      '99300000-0000-4000-8300-000000000002', 'create',
      '99300000-0000-4000-8500-000000000010'
    )$$,
  'un workflow documentaire utilisateur existant reste fonctionnel'
);
reset role;
select public.transition_document_operation(
  (select id from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000010'),
  'reserved', 'cancelled'
);

-- Une seconde tentative illustre l’état incertain conservé avec sa sauvegarde.
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99300000-0000-4000-8800-000000000003', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000003/proof',
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8000-000000000002',
  '{"size":6,"mimetype":"application/pdf"}', 'uncertain-v1'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.issue_account_deletion_document_authorization(
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8400-000000000002'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select public.begin_account_storage_neutralization(
  (select id from public.account_deletion_document_authorizations
   where attempt_id = '99300000-0000-4000-8400-000000000002'),
  '99300000-0000-4000-8500-000000000020', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000003/proof',
  '99300000-0000-4000-8800-000000000003', 'uncertain-v1', repeat('c',64),
  6, 'application/pdf'
);
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.mark_account_storage_neutralization_attention_required(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000020'),
    0, 'STORAGE_STATE_UNCERTAIN'
  )->>'resumePhase'),
  'reserved',
  'un état incertain conserve explicitement la dernière phase sûre'
);
select extensions.throws_ok(
  format(
    $sql$select public.mark_account_storage_neutralization_attention_required(
      %L, 1, 'DIFFERENT_ERROR'
    )$sql$,
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000020')
  ),
  'P4N04',
  'La mise en attention existante est incompatible.',
  'une répétition avec un autre motif ne réécrit pas l’état d’attention'
);
select extensions.is(
  (select state from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000020'),
  'attention_required',
  'l’opération incertaine n’est jamais présentée comme terminée'
);
select extensions.throws_ok(
  format(
    $sql$select public.assert_account_deletion_document_barrier(%L)$sql$,
    (select id from public.account_deletion_document_authorizations
     where attempt_id = '99300000-0000-4000-8400-000000000002')
  ),
  'P4N05',
  'La suppression Auth reste bloquée par l’état documentaire.',
  'attention_required bloque toujours la suppression Auth'
);
select extensions.throws_ok(
  $$insert into public.account_deletion_document_authorizations(
      account_user_id, attempt_id, expires_at
    ) values (
      '99300000-0000-4000-8000-000000000002', gen_random_uuid(),
      clock_timestamp() + interval '5 minutes'
    )$$,
  '42501',
  'permission denied for table account_deletion_document_authorizations',
  'service_role ne contourne pas le contrat par écriture directe'
);
reset role;

-- Récupération durable après interruption entre suppression et recréation.
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99300000-0000-4000-8800-000000000005', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000004/proof',
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8000-000000000002',
  '{"size":7,"mimetype":"application/pdf"}', 'recovery-original-v1'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.issue_account_deletion_document_authorization(
  '99300000-0000-4000-8000-000000000002',
  '99300000-0000-4000-8400-000000000003'
);
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '99300000-0000-4000-8000-000000000002', true
);
select public.begin_account_storage_neutralization(
  (select id from public.account_deletion_document_authorizations
   where attempt_id = '99300000-0000-4000-8400-000000000003'),
  '99300000-0000-4000-8500-000000000030', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000004/proof',
  '99300000-0000-4000-8800-000000000005', 'recovery-original-v1',
  repeat('d',64), 7, 'application/pdf'
);
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.reserve_account_storage_neutralization_backup(
  (select id from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000030')
);
reset role;
insert into storage.objects(id, bucket_id, name, metadata, version)
select
  '99300000-0000-4000-8800-000000000006',
  'document-operation-backups', recovery_object_path,
  '{"size":7,"mimetype":"application/pdf"}', 'recovery-backup-v1'
from public.document_operation_backups
where operation_id = (
  select id from public.document_operations
  where client_request_id = '99300000-0000-4000-8500-000000000030'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.confirm_account_storage_neutralization_backup(
  (select id from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000030'),
  0, 0, repeat('d',64), 7
);
reset role;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
where id = '99300000-0000-4000-8800-000000000005';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.record_account_storage_neutralization_original_deleted(
  (select id from public.document_operations
   where client_request_id = '99300000-0000-4000-8500-000000000030'),
  1
);
select extensions.is(
  (public.authorize_account_storage_neutralization_recovery(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000030'),
    2
  )->>'expectedSha256'),
  repeat('d',64),
  'la reprise expose l’empreinte exacte de la sauvegarde à restaurer'
);
reset role;
insert into storage.objects(id, bucket_id, name, metadata, version)
values (
  '99300000-0000-4000-8800-000000000007', 'transaction-proofs',
  'protected-persons/99300000-0000-4000-8100-000000000001/transactions/99300000-0000-4000-8300-000000000004/proof',
  '{"size":7,"mimetype":"application/pdf"}', 'recovery-restored-v1'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (public.confirm_account_storage_neutralization_recovery(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000030'),
    2, '99300000-0000-4000-8800-000000000007',
    'recovery-restored-v1', repeat('d',64), 7
  )->>'phase'),
  'verified',
  'la restauration des octets exacts reprend la neutralisation en phase vérifiée'
);
select extensions.is(
  (select state from public.document_operation_backups
   where operation_id = (
     select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000030'
   )),
  'restored',
  'la sauvegarde conserve la trace durable de la restauration'
);
select extensions.is(
  (public.confirm_account_storage_neutralization_recovery(
    (select id from public.document_operations
     where client_request_id = '99300000-0000-4000-8500-000000000030'),
    3, '99300000-0000-4000-8800-000000000007',
    'recovery-restored-v1', repeat('d',64), 7
  )->>'phase'),
  'verified',
  'une confirmation de récupération répétée reste idempotente'
);
reset role;

select * from extensions.finish();
rollback;
