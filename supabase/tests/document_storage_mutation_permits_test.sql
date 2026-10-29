begin;
\ir experimental_document_operations_enabled.inc

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_table(
  'public', 'document_storage_mutation_permits',
  'le registre privé des permis Storage existe'
);
select extensions.has_table(
  'public', 'document_storage_mutation_permit_events',
  'le journal append-only des permis existe'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.document_storage_mutation_permits', 'SELECT')
  and not has_table_privilege('authenticated', 'public.document_storage_mutation_permits', 'SELECT')
  and not has_table_privilege('service_role', 'public.document_storage_mutation_permits', 'SELECT'),
  'aucun rôle API ne lit directement le registre privé'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.document_storage_mutation_permits', 'INSERT')
  and not has_table_privilege('authenticated', 'public.document_storage_mutation_permits', 'INSERT')
  and not has_table_privilege('service_role', 'public.document_storage_mutation_permits', 'INSERT'),
  'aucun rôle API ne fabrique directement un permis'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint)',
    'EXECUTE'
  ),
  'seul le rôle technique peut matérialiser la décision métier déjà enregistrée'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.consume_document_storage_mutation_permit(uuid,bigint,text,text,text,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.consume_document_storage_mutation_permit(uuid,bigint,text,text,text,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.consume_document_storage_mutation_permit(uuid,bigint,text,text,text,uuid,text)',
    'EXECUTE'
  ),
  'la consommation reste interne au futur point de garde'
);
select extensions.ok(
  not exists (
    select 1 from pg_trigger trigger
    join pg_class relation on relation.oid = trigger.tgrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'storage' and relation.relname = 'objects'
      and not trigger.tgisinternal
      and trigger.tgname like '%document_storage%permit%'
  ),
  'aucun trigger de permis n’est installé sur storage.objects'
);
select extensions.ok(
  not (select guard_enabled
       from public.document_storage_guard_runtime_config where singleton),
  'la garde Storage reste désactivée'
);

-- Les contrats documentaires sont privés sans politique SELECT. Ces droits de
-- lecture temporaires servent uniquement à résoudre les UUID générés par les
-- fixtures dans les expressions du test ; la transaction finale les annule.
grant select on public.document_operations,
  public.document_operation_targets,
  public.document_operation_backups,
  public.document_storage_mutation_permits
to authenticated, service_role;
alter table public.document_operations disable row level security;
alter table public.document_operation_targets disable row level security;
alter table public.document_operation_backups disable row level security;
alter table public.document_storage_mutation_permits disable row level security;

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '99600000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'permits-owner@example.test', 'test', now(),
  '{}', '{}', now(), now()
), (
  '00000000-0000-0000-0000-000000000000',
  '99600000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'permits-outsider@example.test', 'test', now(),
  '{}', '{}', now(), now()
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id in (
  '99600000-0000-4000-8000-000000000001',
  '99600000-0000-4000-8000-000000000002'
);
insert into public.account_subscriptions(owner_id, status, started_at)
values
  ('99600000-0000-4000-8000-000000000001', 'development', now()),
  ('99600000-0000-4000-8000-000000000002', 'development', now());

insert into public.protected_persons(id, owner_id, first_name, last_name)
values(
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8000-000000000001', 'Permis', 'Storage'
);
insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values (
  '99600000-0000-4000-8200-000000000001',
  '99600000-0000-4000-8100-000000000001',
  'checking', 'Banque test', 'Compte permis', 0, '2026-01-01'
);
insert into public.transactions(
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values (
  '99600000-0000-4000-8300-000000000001',
  '99600000-0000-4000-8200-000000000001',
  '2026-01-02', 'expense', 'Test permis remplacement', 10
), (
  '99600000-0000-4000-8300-000000000002',
  '99600000-0000-4000-8200-000000000001',
  '2026-01-03', 'expense', 'Test permis insertion', 11
), (
  '99600000-0000-4000-8300-000000000003',
  '99600000-0000-4000-8200-000000000001',
  '2026-01-04', 'expense', 'Test permis expiration', 12
), (
  '99600000-0000-4000-8300-000000000004',
  '99600000-0000-4000-8200-000000000001',
  '2026-01-05', 'expense', 'Test permis annulation', 13
);

insert into public.transaction_documents(
  id, transaction_id, storage_path, file_name, mime_type, file_size, created_by
) values (
  '99600000-0000-4000-8500-000000000001',
  '99600000-0000-4000-8300-000000000001',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000001/proof',
  'preuve.pdf', 'application/pdf', 12,
  '99600000-0000-4000-8000-000000000001'
);
insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata, version
) values (
  '99600000-0000-4000-8800-000000000001', 'transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000001/proof',
  '99600000-0000-4000-8000-000000000001',
  '99600000-0000-4000-8000-000000000001',
  '{"size":12,"mimetype":"application/pdf"}'::jsonb, 'version-1'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select public.begin_transaction_proof_document_operation(
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8300-000000000001', 'replace',
  '99600000-0000-4000-8400-000000000001'
);
select public.reserve_document_operation_backup(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000001'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id = target.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
  12, 'application/pdf', repeat('a', 64)
);
reset role;

insert into storage.objects(id, bucket_id, name, metadata, version)
select
  '99600000-0000-4000-8800-000000000002',
  'document-operation-backups', backup.recovery_object_path,
  '{"size":12,"mimetype":"application/pdf"}'::jsonb, 'backup-version-1'
from public.document_operation_backups backup
join public.document_operations operation on operation.id = backup.operation_id
where operation.client_request_id = '99600000-0000-4000-8400-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select public.confirm_document_operation_backup(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000001'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id = target.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
  0
);
select public.start_document_operation(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000001'),
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000001')
);
reset role;

select extensions.throws_ok(
  format(
    'select public.issue_document_storage_mutation_permit(%L,%L,%L,%s,%s,%s)',
    (select id from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id = target.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
    '99600000-0000-4000-8400-000000000101',
    (select row_revision + 1 from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    0,
    (select backup.row_revision from public.document_operation_backups backup
     join public.document_operations operation on operation.id = backup.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001')
  ),
  '42501', 'Accès privilégié requis.',
  'une session ordinaire ne peut pas émettre un permis même avec des UUID valides'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.issue_document_storage_mutation_permit(%L,%L,%L,%s,%s,%s)',
    (select id from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id = target.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
    '99600000-0000-4000-8400-000000000101',
    (select row_revision + 1 from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    0,
    (select backup.row_revision from public.document_operation_backups backup
     join public.document_operations operation on operation.id = backup.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001')
  ),
  'P4G02', 'Le contexte documentaire ou sa révision a changé.',
  'une révision de plan falsifiée est refusée'
);
select extensions.lives_ok(
  format(
    'select public.issue_document_storage_mutation_permit(%L,%L,%L,%s,%s,%s)',
    (select id from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id = target.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
    '99600000-0000-4000-8400-000000000101',
    (select row_revision from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    0,
    (select backup.row_revision from public.document_operation_backups backup
     join public.document_operations operation on operation.id = backup.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001')
  ),
  'le rôle technique matérialise une décision métier autoritative'
);
select extensions.is(
  (public.issue_document_storage_mutation_permit(
    (select id from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id = target.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001'),
    '99600000-0000-4000-8400-000000000101',
    (select row_revision from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000001'),
    0,
    (select backup.row_revision from public.document_operation_backups backup
     join public.document_operations operation on operation.id = backup.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000001')
  )->>'idempotent')::boolean,
  true,
  'la même clé et la même intention rejouent le même permis'
);
reset role;

select extensions.is(
  (select count(*) from public.document_storage_mutation_permits),
  1::bigint,
  'le rejeu idempotent ne duplique pas le permis'
);
select extensions.is(
  (select expires_at - issued_at from public.document_storage_mutation_permits),
  interval '2 minutes',
  'le permis utilise une référence temporelle unique et dure exactement deux minutes'
);
select extensions.is(
  (select storage_action from public.document_storage_mutation_permits),
  'update',
  'l’action est dérivée de la cible autoritative'
);
select extensions.is(
  (select bucket_id from public.document_storage_mutation_permits),
  'transaction-proofs',
  'le bucket est dérivé sans paramètre client'
);
select extensions.is(
  (select backup_required from public.document_storage_mutation_permits),
  true,
  'un remplacement exige une sauvegarde durable'
);

select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,0,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'bank-statements',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE',
    '99600000-0000-4000-8800-000000000001', 'version-1'
  ),
  'P4G03', 'La mutation ne correspond pas au permis exact.',
  'un bucket falsifié est refusé au point de consommation'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,0,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs', 'chemin/falsifie', 'UPDATE',
    '99600000-0000-4000-8800-000000000001', 'version-1'
  ),
  'P4G03', 'La mutation ne correspond pas au permis exact.',
  'un chemin falsifié est refusé au point de consommation'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,0,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE', '99600000-0000-4000-8800-000000000099', 'version-1'
  ),
  'P4G03', 'La mutation ne correspond pas au permis exact.',
  'un UUID Storage divergent est refusé'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,0,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE', '99600000-0000-4000-8800-000000000001', 'version-divergente'
  ),
  'P4G03', 'La mutation ne correspond pas au permis exact.',
  'une version Storage divergente est refusée'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,0,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE', '99600000-0000-4000-8800-000000000001', 'version-1'
  ),
  'P4G08', 'Une preuve physique récente est requise.',
  'une mutation destructive sans preuve physique récente est refusée'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  format(
    'select public.record_document_storage_mutation_permit_evidence(%L,0,%L,%L,12,%L,%L,%L,12,%L)',
    (select id from public.document_storage_mutation_permits),
    '99600000-0000-4000-8800-000000000001', 'version-obsolete', repeat('a', 64),
    '99600000-0000-4000-8800-000000000002', 'backup-version-1', repeat('a', 64)
  ),
  'P4G08', 'La preuve physique de la cible est divergente.',
  'une preuve de version divergente est refusée'
);
select extensions.lives_ok(
  format(
    'select public.record_document_storage_mutation_permit_evidence(%L,0,%L,%L,12,%L,%L,%L,12,%L)',
    (select id from public.document_storage_mutation_permits),
    '99600000-0000-4000-8800-000000000001', 'version-1', repeat('a', 64),
    '99600000-0000-4000-8800-000000000002', 'backup-version-1', repeat('a', 64)
  ),
  'la preuve physique cohérente est enregistrée'
);
reset role;

select extensions.lives_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,1,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE', '99600000-0000-4000-8800-000000000001', 'version-1'
  ),
  'la consommation exacte réussit une seule fois'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,2,%L,%L,%L,%L,%L)',
    (select id from public.document_storage_mutation_permits),
    'transaction-proofs',
    (select object_path from public.document_storage_mutation_permits),
    'UPDATE', '99600000-0000-4000-8800-000000000001', 'version-1'
  ),
  'P4G06', 'Le permis Storage est déjà consommé ou a changé.',
  'un permis consommé ne peut jamais être réutilisé'
);
select extensions.is(
  (select state from public.document_storage_mutation_permits),
  'consumed',
  'la consommation est enregistrée séparément du résultat physique'
);
select extensions.is(
  (select count(*) from public.document_storage_mutation_permit_events),
  3::bigint,
  'émission, preuve et consommation sont auditées'
);
select extensions.throws_ok(
  $$update public.document_storage_mutation_permit_events
    set event_type = 'cancelled'$$,
  '42501', 'Les lignes d’audit sont immuables.',
  'le journal des permis est append-only'
);
select extensions.throws_ok(
  $$delete from public.document_storage_mutation_permits$$,
  '42501', 'Un permis de mutation Storage ne peut pas être supprimé.',
  'les permis ne peuvent pas être supprimés'
);

-- Trois opérations d’insertion sans sauvegarde couvrent expiration et annulation.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select public.begin_transaction_proof_document_operation(
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8300-000000000002', 'create',
  '99600000-0000-4000-8400-000000000002'
);
select public.start_document_operation(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000002'),
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000002')
);
select public.begin_transaction_proof_document_operation(
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8300-000000000003', 'create',
  '99600000-0000-4000-8400-000000000003'
);
select public.start_document_operation(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000003'),
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000003')
);
select public.begin_transaction_proof_document_operation(
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8300-000000000004', 'create',
  '99600000-0000-4000-8400-000000000004'
);
select public.start_document_operation(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000004'),
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000004')
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.issue_document_storage_mutation_permit(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000002'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id = target.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000002'),
  '99600000-0000-4000-8400-000000000102',
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000002'), 0, null
);
select public.issue_document_storage_mutation_permit(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000003'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id = target.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
  '99600000-0000-4000-8400-000000000103',
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000003'), 0, null
);
select public.issue_document_storage_mutation_permit(
  (select id from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000004'),
  (select target.id from public.document_operation_targets target
   join public.document_operations operation on operation.id = target.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000004'),
  '99600000-0000-4000-8400-000000000104',
  (select row_revision from public.document_operations
   where client_request_id = '99600000-0000-4000-8400-000000000004'), 0, null
);
select public.cancel_document_storage_mutation_permit(
  (select permit.id from public.document_storage_mutation_permits permit
   join public.document_operations operation on operation.id = permit.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000002'),
  0
);
reset role;

select public.expire_document_storage_mutation_permits(
  (select permit.bucket_id from public.document_storage_mutation_permits permit
   join public.document_operations operation on operation.id = permit.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
  (select permit.object_path from public.document_storage_mutation_permits permit
   join public.document_operations operation on operation.id = permit.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
  clock_timestamp() + interval '3 minutes'
);

select extensions.is(
  (select permit.state from public.document_storage_mutation_permits permit
   join public.document_operations operation on operation.id = permit.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000002'),
  'cancelled', 'une annulation contrôlée est terminale'
);
select extensions.is(
  (select permit.state from public.document_storage_mutation_permits permit
   join public.document_operations operation on operation.id = permit.operation_id
   where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
  'expired', 'une expiration contrôlée est terminale'
);
select extensions.throws_ok(
  format(
    'select public.consume_document_storage_mutation_permit(%L,1,%L,%L,%L,null,null)',
    (select permit.id from public.document_storage_mutation_permits permit
     join public.document_operations operation on operation.id = permit.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
    'transaction-proofs',
    (select permit.object_path from public.document_storage_mutation_permits permit
     join public.document_operations operation on operation.id = permit.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000003'),
    'INSERT'
  ),
  'P4G06', 'Le permis Storage est déjà consommé ou a changé.',
  'un permis expiré ne peut pas être consommé'
);

select extensions.throws_ok(
  format(
    'select public.issue_document_storage_mutation_permit(%L,%L,%L,%s,%s,null)',
    (select id from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000004'),
    (select target.id from public.document_operation_targets target
     join public.document_operations operation on operation.id = target.operation_id
     where operation.client_request_id = '99600000-0000-4000-8400-000000000004'),
    '99600000-0000-4000-8400-000000000199',
    (select row_revision from public.document_operations
     where client_request_id = '99600000-0000-4000-8400-000000000004'), 0
  ),
  'P4G05', 'Un permis existe déjà pour cette cible ou ce chemin.',
  'une seconde clé ne crée pas de permis concurrent pour la même cible'
);

select extensions.ok(
  not (select is_canonical
       from public.resolve_document_operation_backup_storage_path(
         'document-operation-backups',
         'operations/../../targets/incorrect/backup'
       )),
  'un chemin de sauvegarde non canonique est refusé'
);
select extensions.ok(
  (select is_canonical
   from public.resolve_document_operation_backup_storage_path(
     'document-operation-backups',
     (select recovery_object_path from public.document_operation_backups limit 1)
   )),
  'un chemin de sauvegarde enregistré est résolu strictement'
);

-- Une sauvegarde d’une opération compensée, sans original restauré, reste protégée.
insert into public.document_operations(
  id, protected_person_id, initiated_by, initiator_subject_id, initiator_kind,
  workflow, business_entity_type, business_entity_id, client_request_id,
  state, target_signature, closed_at
) values (
  '99600000-0000-4000-8900-000000000001',
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8000-000000000001',
  '99600000-0000-4000-8000-000000000001', 'user',
  'transaction_proof_replace', 'transaction',
  '99600000-0000-4000-8300-000000000001',
  '99600000-0000-4000-8400-000000000099', 'compensated', '[]', now()
);
insert into public.document_operation_targets(
  id, operation_id, ordinal, bucket_id, object_path, target_role,
  forward_action, compensation_action, expected_exists,
  expected_object_id, expected_object_version, expected_snapshot_captured_at,
  application_state, applied_object_id, applied_object_version, applied_at,
  compensation_expected_exists, compensation_expected_object_id,
  compensation_expected_object_version, compensation_started_at,
  compensated_object_id, compensated_object_version, compensated_at,
  target_revision
) values (
  '99600000-0000-4000-8900-000000000002',
  '99600000-0000-4000-8900-000000000001', 1, 'transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000099/proof',
  'primary', 'update', 'update', true,
  '99600000-0000-4000-8900-000000000003', 'original-v1', now(),
  'compensated', '99600000-0000-4000-8900-000000000004', 'applied-v1', now(),
  true, '99600000-0000-4000-8900-000000000004', 'applied-v1', now(),
  '99600000-0000-4000-8900-000000000005', 'restored-v1', now(), 2
);
insert into public.document_operation_backups(
  id, operation_id, target_id, protected_person_id, initiator_subject_id,
  original_bucket_id, original_object_path, original_object_id,
  original_object_version, recovery_object_path, byte_size, mime_type,
  sha256, state, recovery_object_id, recovery_object_version,
  upload_verified_at, restored_at, row_revision
) values (
  '99600000-0000-4000-8900-000000000006',
  '99600000-0000-4000-8900-000000000001',
  '99600000-0000-4000-8900-000000000002',
  '99600000-0000-4000-8100-000000000001',
  '99600000-0000-4000-8000-000000000001', 'transaction-proofs',
  'protected-persons/99600000-0000-4000-8100-000000000001/transactions/99600000-0000-4000-8300-000000000099/proof',
  '99600000-0000-4000-8900-000000000003', 'original-v1',
  'operations/99600000-0000-4000-8900-000000000001/targets/99600000-0000-4000-8900-000000000002/backup',
  12, 'application/pdf', repeat('b', 64), 'restored',
  '99600000-0000-4000-8900-000000000007', 'backup-v1', now(), now(), 1
);
insert into storage.objects(id, bucket_id, name, metadata, version)
values (
  '99600000-0000-4000-8900-000000000007',
  'document-operation-backups',
  'operations/99600000-0000-4000-8900-000000000001/targets/99600000-0000-4000-8900-000000000002/backup',
  '{"size":12,"mimetype":"application/pdf"}'::jsonb, 'backup-v1'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  $$select public.issue_document_backup_storage_mutation_permit(
    '99600000-0000-4000-8900-000000000006', 'cleanup',
    '99600000-0000-4000-8900-000000000008', 0, 2, 1)$$,
  'P4G07', 'La sauvegarde constitue encore la dernière copie récupérable.',
  'la dernière copie récupérable ne reçoit aucun permis de suppression'
);
reset role;

select extensions.is(
  (select count(*) from storage.objects
   where bucket_id in (
     'transaction-proofs', 'bank-statements', 'management-reports',
     'document-operation-backups'
   )),
  3::bigint,
  'les permis et leur consommation ne provoquent aucune mutation Storage'
);

select extensions.finish();
rollback;
