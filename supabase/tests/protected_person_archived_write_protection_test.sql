begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_function(
  'public', 'assert_protected_person_active_for_write', array['uuid'],
  'la garde centralisée de dossier actif existe'
);
select extensions.has_function(
  'public', 'enforce_active_protected_person_business_write', array[]::text[],
  'la garde générique des tables métier existe'
);
select extensions.has_trigger(
  'public', 'protected_persons',
  'protected_persons_00_require_active_for_business_write',
  'les écritures directes du dossier sont protégées'
);
select extensions.is(
  (select count(*)
   from pg_trigger trigger_row
   join pg_class relation on relation.oid = trigger_row.tgrelid
   join pg_namespace namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and not trigger_row.tgisinternal
     and trigger_row.tgfoid =
       'public.enforce_active_protected_person_business_write()'::regprocedure),
  25::bigint,
  'les vingt-cinq tables métier enfants portent la garde commune'
);
select extensions.ok(
  (select bool_and(procedure.prosecdef and procedure.proconfig = array['search_path=""'])
   from pg_proc procedure
   where procedure.oid in (
     'public.assert_protected_person_active_for_write(uuid)'::regprocedure,
     'public.resolve_business_row_protected_person_id(text,jsonb)'::regprocedure,
     'public.enforce_active_protected_person_business_write()'::regprocedure,
     'public.enforce_active_protected_person_row_write()'::regprocedure
   )),
  'les gardes sont SECURITY DEFINER avec un search_path vide'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.assert_protected_person_active_for_write(uuid)',
    'EXECUTE'
  ),
  'la garde interne ne peut pas être appelée directement par un utilisateur applicatif'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('98000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'archive-write-' || user_number || '@example.test',
  'test', now(), '{}', '{}', now(), now()
from generate_series(1, 3) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '98000000-0000-4000-8000-%';

update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id = '98000000-0000-4000-8000-000000000001';

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at, ended_at
) values (
  '98000000-0000-4000-8000-000000000001', null, null,
  'development', now(), null
);

insert into public.protected_persons(
  id, owner_id, first_name, last_name
) values
  ('98000000-0000-4000-8100-000000000001','98000000-0000-4000-8000-000000000001','Dossier','Complet'),
  ('98000000-0000-4000-8100-000000000002','98000000-0000-4000-8000-000000000001','Dossier','Actif'),
  ('98000000-0000-4000-8100-000000000003','98000000-0000-4000-8000-000000000001','Dossier','Vide');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('98000000-0000-4000-8200-000000000001','98000000-0000-4000-8100-000000000001','98000000-0000-4000-8000-000000000002','manager','98000000-0000-4000-8000-000000000001'),
  ('98000000-0000-4000-8200-000000000002','98000000-0000-4000-8100-000000000001','98000000-0000-4000-8000-000000000003','read_only','98000000-0000-4000-8000-000000000001'),
  ('98000000-0000-4000-8200-000000000003','98000000-0000-4000-8100-000000000002','98000000-0000-4000-8000-000000000002','manager','98000000-0000-4000-8000-000000000001'),
  ('98000000-0000-4000-8200-000000000004','98000000-0000-4000-8100-000000000002','98000000-0000-4000-8000-000000000003','read_only','98000000-0000-4000-8000-000000000001');

insert into public.protection_measures(
  id, protected_person_id, measure_type, active
) values (
  '98000000-0000-4000-8300-000000000001',
  '98000000-0000-4000-8100-000000000001', 'simple_curatorship', true
);

insert into public.management_periods(
  id, protected_person_id, start_date, end_date
) values (
  '98000000-0000-4000-8400-000000000001',
  '98000000-0000-4000-8100-000000000001', '2026-01-01', '2026-12-31'
);

insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values
  ('98000000-0000-4000-8500-000000000001','98000000-0000-4000-8100-000000000001','checking','Banque test','Compte principal',100,'2026-01-01'),
  ('98000000-0000-4000-8500-000000000002','98000000-0000-4000-8100-000000000001','checking','Banque test','Compte secondaire',50,'2026-01-01');

insert into public.account_valuations(
  id, financial_account_id, valuation_date, value
) values (
  '98000000-0000-4000-8600-000000000001',
  '98000000-0000-4000-8500-000000000001', '2026-01-31', 110
);

insert into public.transactions(
  id, financial_account_id, transaction_date, transaction_type, label, amount
) values (
  '98000000-0000-4000-8700-000000000001',
  '98000000-0000-4000-8500-000000000001', '2026-02-01', 'expense',
  'Dépense test', 10
);

insert into public.transaction_documents(
  id, transaction_id, storage_path, file_name, mime_type, file_size, created_by
) values (
  '98000000-0000-4000-8800-000000000001',
  '98000000-0000-4000-8700-000000000001',
  '98000000-0000-4000-8100-000000000001/transaction-test.pdf',
  'transaction-test.pdf', 'application/pdf', 100,
  '98000000-0000-4000-8000-000000000001'
);

insert into public.real_estate_properties(
  id, protected_person_id, property_type, designation, status
) values (
  '98000000-0000-4000-8900-000000000001',
  '98000000-0000-4000-8100-000000000001', 'house', 'Bien test', 'active'
);

insert into public.property_events(
  id, property_id, protected_person_id, event_type, event_date, description, amount
) values (
  '98000000-0000-4000-8a00-000000000001',
  '98000000-0000-4000-8900-000000000001',
  '98000000-0000-4000-8100-000000000001',
  'acquisition', '2025-01-01', 'Acquisition test', 100000
);

insert into public.debts(
  id, protected_person_id, creditor, debt_type, designation, status
) values (
  '98000000-0000-4000-8b00-000000000001',
  '98000000-0000-4000-8100-000000000001', 'Créancier test',
  'bank_loan', 'Dette test', 'active'
);

insert into public.debt_balances(
  id, debt_id, balance_date, remaining_balance
) values (
  '98000000-0000-4000-8c00-000000000001',
  '98000000-0000-4000-8b00-000000000001', '2026-01-31', 5000
);

insert into public.bank_statements(
  id, financial_account_id, statement_end_date, statement_balance,
  storage_path, original_file_name, mime_type, file_size, created_by
) values (
  '98000000-0000-4000-8d00-000000000001',
  '98000000-0000-4000-8500-000000000001', '2026-02-28', 100,
  '98000000-0000-4000-8100-000000000001/statement-test.pdf',
  'statement-test.pdf', 'application/pdf', 100,
  '98000000-0000-4000-8000-000000000001'
);

insert into public.bank_reconciliations(
  id, bank_statement_id, created_by
) values (
  '98000000-0000-4000-8e00-000000000001',
  '98000000-0000-4000-8d00-000000000001',
  '98000000-0000-4000-8000-000000000001'
);

insert into public.management_reports(
  id, protected_person_id, management_period_id, report_year,
  period_start, period_end, created_by
) values (
  '98000000-0000-4000-8f00-000000000001',
  '98000000-0000-4000-8100-000000000001',
  '98000000-0000-4000-8400-000000000001', 2026,
  '2026-01-01', '2026-12-31',
  '98000000-0000-4000-8000-000000000001'
);

insert into public.management_report_documents(
  id, management_report_id, document_type, storage_path, file_name,
  mime_type, file_size, generated_by
) values (
  '98000000-0000-4000-9000-000000000001',
  '98000000-0000-4000-8f00-000000000001', 'management_report_draft',
  '98000000-0000-4000-8100-000000000001/report-test.pdf',
  'report-test.pdf', 'application/pdf', 100,
  '98000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','98000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.lives_ok(
  $$insert into public.protection_measures(
      protected_person_id, measure_type, active
    ) values (
      '98000000-0000-4000-8100-000000000002', 'guardianship', true
    )$$,
  'une écriture métier reste possible sur un dossier actif'
);

select extensions.is(
  public.archive_protected_person(
    '98000000-0000-4000-8100-000000000001', 1, 'Fin de gestion'
  ),
  2::bigint,
  'le dossier peut être archivé avec ses données existantes'
);
select extensions.is(
  (select active_dossier_count from public.get_owned_dossier_capacity()),
  2::bigint,
  'le dossier archivé ne compte plus dans le quota actif'
);

select extensions.throws_ok(
  $$update public.protected_persons
    set email='interdit@example.test'
    where id='98000000-0000-4000-8100-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'les informations du dossier archivé ne peuvent pas être modifiées'
);
select extensions.throws_ok(
  $$insert into public.protection_measures(
      protected_person_id,measure_type,active
    ) values (
      '98000000-0000-4000-8100-000000000001','guardianship',true
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une insertion métier directe est refusée'
);
select extensions.throws_ok(
  $$update public.account_valuations
    set value=120
    where id='98000000-0000-4000-8600-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une mise à jour indirectement rattachée au dossier est refusée'
);
select extensions.throws_ok(
  $$delete from public.account_valuations
    where id='98000000-0000-4000-8600-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une suppression métier est refusée'
);
select extensions.throws_ok(
  $$insert into public.transactions(
      financial_account_id,transaction_date,transaction_type,label,amount
    ) values (
      '98000000-0000-4000-8500-000000000001','2026-02-02','income','Recette interdite',25
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une opération bancaire indirecte est refusée'
);
select extensions.throws_ok(
  $$insert into public.debt_balances(debt_id,balance_date,remaining_balance)
    values ('98000000-0000-4000-8b00-000000000001','2026-02-28',4900)$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un solde de dette indirect est refusé avant sa synchronisation'
);
select extensions.throws_ok(
  $$update public.management_reports
    set observations='Modification interdite'
    where id='98000000-0000-4000-8f00-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'les données du compte de gestion sont protégées'
);
select extensions.throws_ok(
  $$delete from public.bank_statements
    where id='98000000-0000-4000-8d00-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'les métadonnées de relevé sont protégées'
);

select extensions.throws_ok(
  $$select public.create_internal_transfer(
      '98000000-0000-4000-8100-000000000001',
      '98000000-0000-4000-8500-000000000001',
      '98000000-0000-4000-8500-000000000002',
      '2026-02-15', 5, 'Virement interdit', null
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une RPC SECURITY DEFINER de virement ne contourne pas la garde'
);
select extensions.throws_ok(
  $$select public.delete_transaction_with_document(
      '98000000-0000-4000-8700-000000000001'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une RPC privilégiée de suppression documentaire ne contourne pas la garde'
);
select extensions.throws_ok(
  $$select public.archive_real_estate_property(
      '98000000-0000-4000-8100-000000000001',
      '98000000-0000-4000-8900-000000000001', 1,
      'Archivage immobilier interdit'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'une RPC immobilière privilégiée ne contourne pas la garde'
);
select extensions.throws_ok(
  $$select public.set_patrimony_absence_confirmation(
      '98000000-0000-4000-8100-000000000001','real_estate',true
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'la RPC de confirmation patrimoniale ne contourne pas la garde'
);

select extensions.is(
  (select count(*) from public.financial_accounts
   where protected_person_id='98000000-0000-4000-8100-000000000001'),
  2::bigint,
  'les lectures métier restent autorisées'
);
select extensions.is(
  (select count(*) from public.transaction_documents
   where transaction_id='98000000-0000-4000-8700-000000000001'),
  1::bigint,
  'les métadonnées nécessaires au téléchargement restent lisibles'
);
select extensions.is(
  (select count(*) from public.management_report_documents
   where management_report_id='98000000-0000-4000-8f00-000000000001'),
  1::bigint,
  'les documents historiques du compte de gestion restent lisibles'
);

select set_config('request.jwt.claim.sub','98000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  $$update public.financial_accounts
    set notes='Gestionnaire interdit'
    where id='98000000-0000-4000-8500-000000000001'$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un gestionnaire ne peut pas modifier un dossier archivé'
);
select extensions.lives_ok(
  $$insert into public.protection_measures(
      protected_person_id,measure_type,active
    ) values (
      '98000000-0000-4000-8100-000000000002','simple_curatorship',true
    )$$,
  'un gestionnaire conserve ses droits d’écriture sur un dossier actif'
);

select set_config('request.jwt.claim.sub','98000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$insert into public.protection_measures(
      protected_person_id,measure_type,active
    ) values (
      '98000000-0000-4000-8100-000000000002','guardianship',true
    )$$,
  '42501', null,
  'un lecteur reste privé d’écriture sur un dossier actif'
);

select set_config('request.jwt.claim.sub','98000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  public.restore_protected_person(
    '98000000-0000-4000-8100-000000000001', 2, 'Reprise de gestion'
  ),
  3::bigint,
  'la restauration reste possible malgré la garde métier'
);
select extensions.is(
  (select active_dossier_count from public.get_owned_dossier_capacity()),
  3::bigint,
  'la restauration réintègre exactement le dossier dans le quota actif'
);
select extensions.lives_ok(
  $$update public.financial_accounts
    set notes='Modification après restauration'
    where id='98000000-0000-4000-8500-000000000001'$$,
  'les écritures reprennent après restauration'
);

select extensions.is(
  public.archive_protected_person(
    '98000000-0000-4000-8100-000000000003', 1,
    'Suppression du dossier vide'
  ),
  2::bigint,
  'un dossier vide peut toujours être archivé'
);
select extensions.lives_ok(
  $$select public.delete_empty_protected_person(
      '98000000-0000-4000-8100-000000000003'
    )$$,
  'la suppression contrôlée d’un dossier vide archivé reste possible'
);
select extensions.is(
  (select count(*) from public.protected_persons
   where id='98000000-0000-4000-8100-000000000003'),
  0::bigint,
  'le dossier vide archivé est effectivement supprimé'
);

select * from extensions.finish();
rollback;
