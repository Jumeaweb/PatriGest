begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(36);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '32000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rapp6-owner@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '32000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rapp6-manager@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '32000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rapp6-reader@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '32000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'rapp6-outsider@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '32000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'rapp6-admin@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.application_user_authorizations set status = 'active', status_changed_at = now()
where user_id in ('32000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000002', '32000000-0000-4000-8000-000000000003', '32000000-0000-4000-8000-000000000004');
insert into public.platform_administrators (user_id) values ('32000000-0000-4000-8000-000000000005');

insert into public.protected_persons (id, owner_id, first_name, last_name) values
  ('32000000-0000-4000-8000-000000000101', '32000000-0000-4000-8000-000000000001', 'Dossier', 'RAPP6'),
  ('32000000-0000-4000-8000-000000000102', '32000000-0000-4000-8000-000000000004', 'Autre', 'Dossier');
insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by) values
  ('32000000-0000-4000-8000-000000000201', '32000000-0000-4000-8000-000000000101', '32000000-0000-4000-8000-000000000002', 'manager', '32000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000202', '32000000-0000-4000-8000-000000000101', '32000000-0000-4000-8000-000000000003', 'read_only', '32000000-0000-4000-8000-000000000001');

insert into public.financial_accounts (id, protected_person_id, account_type, institution_name, account_name, initial_balance, initial_balance_date, status) values
  ('32000000-0000-4000-8000-000000000301', '32000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Principal', 100, '2026-01-01', 'active'),
  ('32000000-0000-4000-8000-000000000302', '32000000-0000-4000-8000-000000000101', 'checking', 'Banque', 'Secondaire', 50, '2026-01-01', 'active'),
  ('32000000-0000-4000-8000-000000000303', '32000000-0000-4000-8000-000000000102', 'checking', 'Banque', 'Étranger', 20, '2026-01-01', 'active');

insert into public.transfers (id, protected_person_id, source_account_id, destination_account_id, transfer_date, amount) values
  ('32000000-0000-4000-8000-000000000701', '32000000-0000-4000-8000-000000000101', '32000000-0000-4000-8000-000000000301', '32000000-0000-4000-8000-000000000302', '2026-01-08', 4),
  ('32000000-0000-4000-8000-000000000702', '32000000-0000-4000-8000-000000000101', '32000000-0000-4000-8000-000000000302', '32000000-0000-4000-8000-000000000301', '2026-01-09', 20);

insert into public.transactions (id, financial_account_id, transaction_date, transaction_type, label, amount, transfer_id) values
  ('32000000-0000-4000-8000-000000000401', '32000000-0000-4000-8000-000000000301', '2026-01-05', 'expense', 'Ancienne dépense', 3, null),
  ('32000000-0000-4000-8000-000000000402', '32000000-0000-4000-8000-000000000301', '2026-01-06', 'income', 'Recette', 10, null),
  ('32000000-0000-4000-8000-000000000403', '32000000-0000-4000-8000-000000000301', '2026-01-08', 'transfer_out', 'Virement sortant', 4, '32000000-0000-4000-8000-000000000701'),
  ('32000000-0000-4000-8000-000000000404', '32000000-0000-4000-8000-000000000301', '2026-01-09', 'transfer_in', 'Virement entrant', 20, '32000000-0000-4000-8000-000000000702'),
  ('32000000-0000-4000-8000-000000000405', '32000000-0000-4000-8000-000000000301', '2026-02-02', 'expense', 'Future', 7, null),
  ('32000000-0000-4000-8000-000000000406', '32000000-0000-4000-8000-000000000302', '2026-01-10', 'expense', 'Autre compte', 2, null);

insert into public.bank_statements (id, financial_account_id, statement_start_date, statement_end_date, statement_balance, storage_path, created_by) values
  ('32000000-0000-4000-8000-000000000501', '32000000-0000-4000-8000-000000000301', '2026-01-10', '2026-01-31', 100, 'rapp6-1', '32000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000502', '32000000-0000-4000-8000-000000000301', '2026-02-01', '2026-02-28', 93, 'rapp6-2', '32000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000503', '32000000-0000-4000-8000-000000000301', null, '2026-03-31', 116, 'rapp6-3', '32000000-0000-4000-8000-000000000001');
insert into public.bank_reconciliations (id, bank_statement_id, created_by) values
  ('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000501', '32000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000602', '32000000-0000-4000-8000-000000000502', '32000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000603', '32000000-0000-4000-8000-000000000503', '32000000-0000-4000-8000-000000000001');

select extensions.is((select reconciliation_mode from public.bank_reconciliations where id = '32000000-0000-4000-8000-000000000601'), 'simple', 'existing and new controls default to simple');
select extensions.ok(not has_table_privilege('authenticated', 'public.bank_reconciliation_outstanding_transactions', 'INSERT'), 'authenticated has no direct insert privilege');
select extensions.ok(has_table_privilege('authenticated', 'public.bank_reconciliation_outstanding_transactions', 'SELECT'), 'authenticated receives read access through RLS');

set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select extensions.lives_ok($$ select public.activate_complete_bank_reconciliation('32000000-0000-4000-8000-000000000601') $$, 'owner activates complete mode');
select extensions.is((select reconciliation_mode from public.bank_reconciliations where id = '32000000-0000-4000-8000-000000000601'), 'complete', 'complete mode is persisted');
select extensions.lives_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000401') $$, 'old operation before statement start remains eligible');
select extensions.lives_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000402') $$, 'income can be outstanding');
select extensions.lives_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000403') $$, 'transfer out can be outstanding');
select extensions.lives_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000404') $$, 'transfer in can be outstanding');
select extensions.throws_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000401') $$, '23505', null, 'duplicate on one reconciliation is refused');
select extensions.throws_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000406') $$, 'P0001', 'L''opération n''appartient pas au compte du relevé.', 'different account is refused');
select extensions.throws_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000601', '32000000-0000-4000-8000-000000000405') $$, 'P0001', 'L''opération est postérieure au relevé.', 'operation after statement end is refused');
select extensions.results_eq($$ select calculated_balance, outstanding_debits, outstanding_credits, explained_bank_balance, residual_difference from public.get_bank_reconciliation_detailed_summary('32000000-0000-4000-8000-000000000601') $$, $$ values (123::numeric, 7::numeric, 30::numeric, 100::numeric, 0::numeric) $$, 'all four signs produce the exact explained balance');
select extensions.lives_ok($$ select public.validate_bank_reconciliation('32000000-0000-4000-8000-000000000601') $$, 'owner validates complete reconciliation atomically');
select extensions.results_eq($$ select calculated_balance, difference, outstanding_debits, outstanding_credits, explained_bank_balance, residual_difference from public.bank_reconciliations where id = '32000000-0000-4000-8000-000000000601' $$, $$ values (123::numeric, -23::numeric, 7::numeric, 30::numeric, 100::numeric, 0::numeric) $$, 'complete validation preserves simple snapshots and freezes detailed snapshots');
select extensions.ok((select bool_and(transaction_date_snapshot is not null and transaction_type_snapshot is not null and amount_snapshot is not null and label_snapshot is not null) from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601'), 'validation freezes every line snapshot');
select extensions.throws_ok($$ delete from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601' $$, '42501', null, 'validated lines cannot be changed directly');

reset role;
set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select extensions.lives_ok($$ select public.activate_complete_bank_reconciliation('32000000-0000-4000-8000-000000000602') $$, 'manager activates complete mode');
select extensions.lives_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000602', '32000000-0000-4000-8000-000000000401') $$, 'same transaction can remain outstanding on a successive reconciliation');
select extensions.is((select carried_from_previous from public.list_bank_reconciliation_candidate_transactions('32000000-0000-4000-8000-000000000602') where transaction_id = '32000000-0000-4000-8000-000000000401'), true, 'previous outstanding operation is proposed explicitly');

reset role;
set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601'), 4::bigint, 'read only can inspect accessible outstanding history');
select extensions.throws_ok($$ select public.add_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000602', '32000000-0000-4000-8000-000000000402') $$, 'P0001', 'Rapprochement introuvable.', 'read only cannot write pointing');

reset role;
set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;
select extensions.throws_ok($$ select public.activate_complete_bank_reconciliation('32000000-0000-4000-8000-000000000603') $$, 'P0001', 'Rapprochement introuvable.', 'no access user cannot activate complete mode');
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions), 0::bigint, 'no access user cannot read pointing rows');

reset role;
set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000005';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000005","role":"authenticated"}';
set local role authenticated;
select extensions.throws_ok($$ select public.activate_complete_bank_reconciliation('32000000-0000-4000-8000-000000000603') $$, 'P0001', 'Rapprochement introuvable.', 'platform administrator receives no implicit financial access');
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions), 0::bigint, 'platform administrator receives no implicit read access');

reset role;
set local "request.jwt.claim.sub" = '32000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"32000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
update public.transactions set amount = 8, label = 'Dépense corrigée' where id = '32000000-0000-4000-8000-000000000401';
select extensions.results_eq($$ select amount_snapshot, label_snapshot from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601' and transaction_id_snapshot = '32000000-0000-4000-8000-000000000401' $$, $$ values (3::numeric, 'Ancienne dépense'::text) $$, 'source update never rewrites validated snapshot');
delete from public.transactions where id = '32000000-0000-4000-8000-000000000402';
select extensions.results_eq($$ select transaction_id is null, amount_snapshot, label_snapshot from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601' and transaction_id_snapshot = '32000000-0000-4000-8000-000000000402' $$, $$ values (true, 10::numeric, 'Recette'::text) $$, 'source deletion preserves historical id and snapshots');
select extensions.results_eq($$ select transaction_id, transaction_date, transaction_type, label, amount from public.list_bank_reconciliation_candidate_transactions('32000000-0000-4000-8000-000000000601') where transaction_id = '32000000-0000-4000-8000-000000000402' $$, $$ values ('32000000-0000-4000-8000-000000000402'::uuid, '2026-01-06'::date, 'income'::text, 'Recette'::text, 10::numeric) $$, 'deleted source remains consultable through its validated snapshots');
select extensions.lives_ok($$ select public.remove_bank_reconciliation_outstanding_transaction('32000000-0000-4000-8000-000000000602', '32000000-0000-4000-8000-000000000401') $$, 'manager-created draft line remains removable by owner');
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000602'), 0::bigint, 'draft removal is effective');
select extensions.lives_ok($$ select public.validate_bank_reconciliation('32000000-0000-4000-8000-000000000603') $$, 'simple RAPP-05 validation remains available');
select extensions.results_eq($$ select reconciliation_mode, calculated_balance, difference, outstanding_debits, outstanding_credits, explained_bank_balance, residual_difference from public.bank_reconciliations where id = '32000000-0000-4000-8000-000000000603' $$, $$ values ('simple'::text, 101::numeric, 15::numeric, null::numeric, null::numeric, null::numeric, null::numeric) $$, 'simple mode keeps RAPP-05 semantics and detailed snapshots null');
select extensions.throws_ok($$ select public.activate_complete_bank_reconciliation('32000000-0000-4000-8000-000000000603') $$, 'P0001', 'Seul un rapprochement en brouillon peut devenir détaillé.', 'validated simple reconciliation cannot convert to complete');
select extensions.ok(position('lock table public.bank_reconciliation_outstanding_transactions in share mode' in lower(pg_get_functiondef('public.validate_bank_reconciliation(uuid)'::regprocedure))) > 0, 'validation locks pointing writers');
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id = '32000000-0000-4000-8000-000000000601'), 4::bigint, 'validated history remains complete after source changes');

select * from extensions.finish();
rollback;
