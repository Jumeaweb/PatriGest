begin;

create extension if not exists pgtap with schema extensions;

select extensions.no_plan();

create temporary table experimental_document_mutators (
  signature text primary key
) on commit drop;

insert into experimental_document_mutators(signature) values
  ('public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)'),
  ('public.begin_bank_statement_document_operation(uuid,uuid,uuid,text,uuid)'),
  ('public.begin_management_report_document_operation(uuid,uuid,text,uuid)'),
  ('public.start_document_operation(uuid,bigint)'),
  ('public.record_document_operation_target_applied(uuid,uuid,bigint,bigint)'),
  ('public.finalize_transaction_proof_document_operation(uuid,bigint,text,text,bigint)'),
  ('public.finalize_bank_statement_document_operation(uuid,bigint,date,date,numeric,text,text,text,bigint)'),
  ('public.finalize_management_report_document_operation(uuid,bigint,text,text,bigint,jsonb,integer)'),
  ('public.begin_document_operation_compensation(uuid,bigint,text)'),
  ('public.record_document_operation_target_compensated(uuid,uuid,bigint,bigint)'),
  ('public.complete_document_operation_compensation(uuid,bigint)'),
  ('public.mark_document_operation_attention_required(uuid,bigint,text)'),
  ('public.cancel_reserved_document_operation(uuid,bigint)'),
  ('public.reserve_document_operation_backup(uuid,uuid,bigint,text,text)'),
  ('public.confirm_document_operation_backup(uuid,uuid,bigint)'),
  ('public.mark_document_operation_backup_restored(uuid,uuid,bigint)'),
  ('public.authorize_document_operation_backup_cleanup(uuid,bigint)'),
  ('public.complete_document_operation_backup_cleanup(uuid,bigint)'),
  ('public.begin_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)'),
  ('public.issue_account_deletion_document_authorization(uuid,uuid)'),
  ('public.cancel_account_deletion_document_authorization(uuid)'),
  ('public.reserve_account_storage_neutralization_backup(uuid)'),
  ('public.confirm_account_storage_neutralization_backup(uuid,bigint,bigint,text,bigint)'),
  ('public.record_account_storage_neutralization_original_deleted(uuid,bigint)'),
  ('public.record_account_storage_neutralization_recreated(uuid,bigint,uuid,text)'),
  ('public.verify_account_storage_neutralization_content(uuid,bigint,text,bigint)'),
  ('public.authorize_account_storage_neutralization_recovery(uuid,bigint)'),
  ('public.confirm_account_storage_neutralization_recovery(uuid,bigint,uuid,text,text,bigint)'),
  ('public.authorize_account_storage_neutralization_backup_cleanup(uuid,bigint)'),
  ('public.confirm_account_storage_neutralization_backup_cleanup(uuid,bigint,bigint)'),
  ('public.finalize_account_storage_neutralization(uuid,bigint)'),
  ('public.mark_account_storage_neutralization_attention_required(uuid,bigint,text)'),
  ('public.assert_account_deletion_document_barrier(uuid)'),
  ('public.issue_administrative_account_deletion_authorization(uuid,uuid,text,jsonb)'),
  ('public.cancel_administrative_account_deletion_authorization(uuid,bigint)'),
  ('public.begin_administrative_account_storage_neutralization(uuid,uuid,text,text,uuid,text,text,bigint,text)'),
  ('public.assert_administrative_account_deletion_barrier(uuid,bigint,text)'),
  ('public.issue_administrative_document_repair_authorization(uuid,bigint,uuid,text,jsonb)'),
  ('public.cancel_administrative_document_repair_authorization(uuid,bigint)'),
  ('public.seal_administrative_document_repair(uuid,bigint,text)'),
  ('public.renew_administrative_document_repair_authorization(uuid,uuid,text,uuid,bigint)'),
  ('public.start_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,bigint)'),
  ('public.record_administrative_document_repair_observation(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,boolean,uuid,text,bigint,text,boolean,uuid,bigint,text)'),
  ('public.verify_administrative_document_repair_item(uuid,uuid,uuid,uuid,text,text,uuid,bigint,text,text)'),
  ('public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'),
  ('public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'),
  ('public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'),
  ('public.request_administrative_document_exceptional_recovery(uuid,uuid,text,uuid,text,bigint)'),
  ('public.decide_administrative_document_exceptional_recovery(uuid,uuid,boolean,text,bigint)'),
  ('public.activate_administrative_document_exceptional_recovery(uuid,uuid,bigint)'),
  ('public.begin_administrative_document_physical_verification(text,uuid)'),
  ('public.complete_administrative_document_physical_verification(uuid,text,text,text,uuid,text,bigint,text,text)'),
  ('public.issue_document_storage_mutation_permit(uuid,uuid,uuid,bigint,bigint,bigint)'),
  ('public.issue_document_backup_storage_mutation_permit(uuid,text,uuid,bigint,bigint,bigint)'),
  ('public.record_document_storage_mutation_permit_evidence(uuid,bigint,uuid,text,bigint,text,uuid,text,bigint,text)'),
  ('public.cancel_document_storage_mutation_permit(uuid,bigint)');

select extensions.ok(
  not exists (
    select 1
    from experimental_document_mutators mutator
    cross join lateral aclexplode(
      coalesce(
        (select routine.proacl from pg_proc routine where routine.oid = to_regprocedure(mutator.signature)),
        acldefault('f', (select routine.proowner from pg_proc routine where routine.oid = to_regprocedure(mutator.signature)))
      )
    ) privilege
    where privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC ne peut exécuter aucune RPC documentaire expérimentale mutante'
);

select extensions.ok(
  (select bool_and(not has_function_privilege('anon', signature, 'EXECUTE')) from experimental_document_mutators),
  'anon ne peut exécuter aucune RPC documentaire expérimentale mutante'
);

select extensions.ok(
  (select bool_and(not has_function_privilege('authenticated', signature, 'EXECUTE')) from experimental_document_mutators),
  'authenticated ne peut exécuter aucune RPC documentaire expérimentale mutante'
);

select extensions.ok(
  (select bool_and(not has_function_privilege('service_role', signature, 'EXECUTE')) from experimental_document_mutators),
  'service_role ne constitue pas une autorisation documentaire implicite'
);

set local role authenticated;

select extensions.throws_ok(
  $$
    select public.begin_transaction_proof_document_operation(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000002'::uuid,
      'create',
      '00000000-0000-4000-8000-000000000003'::uuid
    );
  $$,
  '42501',
  null,
  'un appel Data API authenticated ne contourne pas la fermeture'
);

reset role;

set local role service_role;

select extensions.throws_ok(
  $$
    select public.issue_document_storage_mutation_permit(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000002'::uuid,
      '00000000-0000-4000-8000-000000000003'::uuid,
      1,
      1,
      1
    );
  $$,
  '42501',
  null,
  'service_role ne contourne pas la fermeture des permis expérimentaux'
);

reset role;

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_document_operation_progress(uuid)', 'EXECUTE'),
  'la lecture de progression historique reste accordée à authenticated'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_administrative_document_inventory(integer,text,text,text)', 'EXECUTE'),
  'le diagnostic administratif en lecture seule reste accordé'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_administrative_document_physical_observations(text,integer,timestamptz)', 'EXECUTE'),
  'les observations physiques en lecture seule restent consultables'
);

select extensions.ok(
  has_function_privilege('service_role', 'public.get_document_storage_mutation_permit_for_service(uuid)', 'EXECUTE'),
  'la relecture technique des permis reste disponible sans autoriser leur création'
);

select extensions.ok(
  has_table_privilege('authenticated', 'public.transaction_documents', 'SELECT')
  and has_table_privilege('authenticated', 'public.bank_statements', 'SELECT')
  and has_table_privilege('authenticated', 'public.management_report_documents', 'SELECT'),
  'les métadonnées des trois parcours documentaires historiques restent lisibles sous RLS'
);

select extensions.is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and cmd = 'SELECT'
      and policyname in (
        'transaction_proofs_select_accessible',
        'bank_statements_storage_select_accessible',
        'management_reports_storage_select_accessible'
      )
  ),
  3,
  'les trois politiques de téléchargement historiques restent installées'
);

select * from extensions.finish();

rollback;
