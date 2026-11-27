begin;
create extension if not exists pgtap with schema extensions;
\if :{?debt_sheet_concurrency}
select extensions.plan(26);
\else
select extensions.plan(25);
\endif

select extensions.ok(
  not has_function_privilege('authenticated', 'public.guard_management_report_document_debt_sheet()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.invalidate_management_reports_after_debt_sheet_change()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.management_report_debt_sheet_lock_key(uuid)', 'EXECUTE'),
  'Les fonctions internes ne sont pas ouvertes à la Data API');

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '99500000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'report-debt-sheet-owner@example.test',
  'test', now(), '{}', '{}', now(), now()
);
update public.application_user_authorizations
set status = 'active', status_changed_at = now(),
    account_mode = 'autonomous', registration_intent = 'autonomous'
where user_id = '99500000-0000-4000-8000-000000000001';

insert into public.protected_persons(id, owner_id, first_name, last_name) values
  ('99500000-0000-4000-8100-000000000001', '99500000-0000-4000-8000-000000000001', 'Dossier', 'Principal'),
  ('99500000-0000-4000-8100-000000000002', '99500000-0000-4000-8000-000000000001', 'Dossier', 'Distinct');

insert into public.debts(id, protected_person_id, creditor, debt_type, designation, start_date)
values ('99500000-0000-4000-8200-000000000001', '99500000-0000-4000-8100-000000000001',
  'Banque A', 'bank_loan', 'Prêt de test', '2024-07-01');

insert into public.management_reports(
  id, protected_person_id, report_year, period_start, period_end, status, generated_at, finalized_at, created_by
) values
  ('99500000-0000-4000-8300-000000000001', '99500000-0000-4000-8100-000000000001', 2025,
   '2024-07-01', '2025-06-30', 'generated', now(), null, '99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8300-000000000002', '99500000-0000-4000-8100-000000000001', 2026,
   '2025-07-01', '2026-06-30', 'generated', now(), null, '99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8300-000000000003', '99500000-0000-4000-8100-000000000001', 2024,
   '2024-01-01', '2024-06-30', 'generated', now(), null, '99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8300-000000000004', '99500000-0000-4000-8100-000000000002', 2025,
   '2024-07-01', '2025-06-30', 'generated', now(), null, '99500000-0000-4000-8000-000000000001'),
  ('99500000-0000-4000-8300-000000000005', '99500000-0000-4000-8100-000000000001', 2027,
   '2026-07-01', '2027-06-30', 'finalized', now(), now(), '99500000-0000-4000-8000-000000000001');

create function pg_temp.refresh_ids() returns uuid[] language sql as $$
  select coalesce(array_agg(id order by id), array[]::uuid[])
  from public.management_reports where refresh_required_at is not null
    and id::text like '99500000-0000-4000-8300-%';
$$;

create function pg_temp.expect_debt_edit(change_sql text, expected integer[], description text)
returns text language plpgsql as $$
declare
  actual uuid[];
begin
  -- Roll back each edit so that the next case starts with clean reports.
  begin
    execute 'update public.debts set ' || change_sql ||
      ' where id = ''99500000-0000-4000-8200-000000000001''';
    actual := pg_temp.refresh_ids();
    raise exception using errcode = 'PT001', message = 'rollback fixture';
  exception when sqlstate 'PT001' then null;
  end;
  return extensions.is(actual, array(
    select ('99500000-0000-4000-8300-' || lpad(n::text, 12, '0'))::uuid
    from unnest(expected) as numbers(n) order by n
  ), description);
end;
$$;

select pg_temp.expect_debt_edit(change_sql, array[1, 2], description)
from (values
  ('monthly_payment = 25', 'La mensualité invalide les deux projets concernés'),
  ('creditor = ''Banque B''', 'Le créancier invalide les deux projets concernés'),
  ('designation = ''Autre prêt''', 'La désignation invalide les deux projets concernés'),
  ('debt_type = ''personal_debt''', 'Le type invalide les deux projets concernés'),
  ('initial_amount = 500', 'Le montant initial invalide les deux projets concernés'),
  ('initial_duration_months = 18', 'La durée initiale invalide les deux projets concernés'),
  ('start_date = ''2024-08-01''', 'Un début modifié dans le même exercice invalide le projet')
) as cases(change_sql, description);
select pg_temp.expect_debt_edit('creditor = creditor', array[]::integer[], 'Réécrire la même valeur est sans effet');
select pg_temp.expect_debt_edit('notes = ''Note'', interest_rate = 2', array[]::integer[], 'Les notes et le taux ne sont pas restitués');
select pg_temp.expect_debt_edit('start_date = ''2024-06-30''', array[1,2,3], 'Entrée le dernier jour de l’exercice et invalidation des exercices suivants');
select pg_temp.expect_debt_edit('start_date = ''2025-07-01''', array[1,2], 'Sortie de l’exercice non civil, maintien dans le suivant');
select pg_temp.expect_debt_edit('start_date = null', array[1,2,3], 'Date de début inconnue prise en compte dans le périmètre');

insert into public.debt_balances(debt_id, balance_date, remaining_balance)
values ('99500000-0000-4000-8200-000000000001', '2025-06-30', 0);
select extensions.is(pg_temp.refresh_ids(), array[
  '99500000-0000-4000-8300-000000000001'::uuid,
  '99500000-0000-4000-8300-000000000002'::uuid
], 'Le trigger des situations reste opérationnel');
update public.management_reports set refresh_required_at = null
where id::text like '99500000-0000-4000-8300-%' and refresh_required_at is not null;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true);
select extensions.lives_ok($$select public.settle_debt(
  '99500000-0000-4000-8100-000000000001', '99500000-0000-4000-8200-000000000001',
  (select revision from public.debts where id = '99500000-0000-4000-8200-000000000001'),
  '2025-06-30', 'Clôture de test'
)$$, 'La clôture reste disponible via la RPC');
reset role;
select extensions.is(cardinality(pg_temp.refresh_ids()), 2, 'La clôture conserve son invalidation existante');
update public.management_reports set refresh_required_at = null
where id::text like '99500000-0000-4000-8300-%' and refresh_required_at is not null;
select pg_temp.expect_debt_edit('designation = ''Prêt soldé corrigé''', array[1], 'Une dette soldée ne concerne que les exercices où elle figure');

create function pg_temp.project_snapshot(creditor text, report_status text default 'generated')
returns jsonb language sql as $$
  select jsonb_build_object(
    'report', jsonb_build_object(
      'id', '99500000-0000-4000-8300-000000000001',
      'protected_person_id', '99500000-0000-4000-8100-000000000001',
      'report_year', 2025, 'period_start', '2024-07-01', 'period_end', '2025-06-30',
      'status', report_status
    ),
    'person', jsonb_build_object('id', '99500000-0000-4000-8100-000000000001'),
    'debts', jsonb_build_array(jsonb_build_object(
      'id', '99500000-0000-4000-8200-000000000001', 'startDate', '2024-07-01',
      'monthlyPayment', null, 'creditor', creditor, 'designation', 'Prêt de test',
      'type', 'Prêt bancaire', 'initialAmount', null, 'initialDurationMonths', null
    ))
  );
$$;

insert into public.management_report_documents(
  management_report_id, document_type, storage_path, file_name, mime_type,
  file_size, preview_snapshot, snapshot_schema_version, generated_by
) values (
  '99500000-0000-4000-8300-000000000001', 'management_report_draft',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report-draft.pdf',
  'projet.pdf', 'application/pdf', 100, pg_temp.project_snapshot('Banque A'), 1,
  '99500000-0000-4000-8000-000000000001'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true);
update public.debts set creditor = 'Banque B' where id = '99500000-0000-4000-8200-000000000001';
reset role;
select extensions.is(
  (select preview_snapshot from public.management_report_documents
    where management_report_id = '99500000-0000-4000-8300-000000000001'),
  pg_temp.project_snapshot('Banque A'), 'L’instantané du PDF projet reste identique après invalidation');
select extensions.ok(
  (select status = 'finalized' and finalized_at is not null and refresh_required_at is null
    from public.management_reports where id = '99500000-0000-4000-8300-000000000005'),
  'Le CRG définitif reste figé');

insert into storage.objects(bucket_id, name, owner, owner_id, metadata, version) values (
  'management-reports',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report.pdf',
  '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001',
  '{"size":100,"mimetype":"application/pdf"}', 'fixture'
);
insert into public.management_report_final_verifications(storage_object_id, report_id, storage_version, byte_count, sha256)
select object.id, '99500000-0000-4000-8300-000000000001', object.version, 100, repeat('a',64)
from storage.objects object where object.bucket_id = 'management-reports'
  and object.name = 'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report.pdf';

set local role authenticated;
select extensions.throws_ok($$select public.finalize_management_report(
  '99500000-0000-4000-8300-000000000001',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report.pdf',
  'definitif.pdf', 'application/pdf', 100, pg_temp.project_snapshot('Banque A', 'finalized'), 1
)$$, 'P0001', 'Le compte de gestion doit être actualisé et son projet régénéré avant finalisation.',
  'La finalisation d’un projet obsolète est bloquée en base');
select extensions.lives_ok($$select public.resume_management_report_preparation(
  '99500000-0000-4000-8300-000000000001'
)$$, 'Le parcours de reprise reste disponible');
update public.management_reports set status = 'ready' where id = '99500000-0000-4000-8300-000000000001';
reset role;

insert into storage.objects(bucket_id, name, owner, owner_id, metadata) values (
  'management-reports',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report-draft.pdf',
  '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001',
  '{"size":100,"mimetype":"application/pdf"}'
);

set local role authenticated;
select extensions.throws_ok($$select public.finalize_management_report_draft_generation(
  '99500000-0000-4000-8300-000000000001',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report-draft.pdf',
  'projet.pdf', 'application/pdf', 100, pg_temp.project_snapshot('Banque A'), 1
)$$, '40001', 'Les fiches Dette ont changé depuis la préparation du projet. Actualisez puis réessayez.',
  'Une génération ayant lu les fiches avant la modification ne peut pas publier son instantané');
select extensions.lives_ok($$select public.finalize_management_report_draft_generation(
  '99500000-0000-4000-8300-000000000001',
  'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/99500000-0000-4000-8300-000000000001/management-report-draft.pdf',
  'projet.pdf', 'application/pdf', 100, pg_temp.project_snapshot('Banque B'), 1
)$$, 'La régénération avec les données à jour réussit');
reset role;

select extensions.ok(
  (select status = 'generated' and refresh_required_at is null
    from public.management_reports where id = '99500000-0000-4000-8300-000000000001'),
  'Le projet régénéré n’est plus marqué obsolète');
select extensions.is(
  (select count(*) from storage.objects where bucket_id = 'management-reports'
    and name like 'protected-persons/99500000-0000-4000-8100-000000000001/management-reports/%'),
  2::bigint, 'Les objets Storage de test n’ont subi aucune suppression SQL');

\if :{?debt_sheet_concurrency}
-- Run this branch while another local psql session holds the advisory lock
-- for dossier 99500000-0000-4000-8100-000000000002.
insert into public.management_reports(
  id, protected_person_id, report_year, period_start, period_end, status, created_by
) values ('99500000-0000-4000-8300-000000000006', '99500000-0000-4000-8100-000000000002',
  2028, '2028-01-01', '2028-12-31', 'ready', '99500000-0000-4000-8000-000000000001');

insert into storage.objects(bucket_id, name, owner, owner_id, metadata) values (
  'management-reports',
  'protected-persons/99500000-0000-4000-8100-000000000002/management-reports/99500000-0000-4000-8300-000000000006/management-report-draft.pdf',
  '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001',
  '{"size":100,"mimetype":"application/pdf"}'
);
set local role authenticated;
select extensions.throws_ok($$select public.finalize_management_report_draft_generation(
  '99500000-0000-4000-8300-000000000006',
  'protected-persons/99500000-0000-4000-8100-000000000002/management-reports/99500000-0000-4000-8300-000000000006/management-report-draft.pdf',
  'projet.pdf', 'application/pdf', 100,
  '{"report":{"id":"99500000-0000-4000-8300-000000000006","protected_person_id":"99500000-0000-4000-8100-000000000002","report_year":2028,"period_start":"2028-01-01","period_end":"2028-12-31","status":"generated"},"person":{"id":"99500000-0000-4000-8100-000000000002"},"debts":[]}'::jsonb,
  1
)$$, '40001', 'Une fiche Dette de ce dossier est en cours de modification. Réessayez.',
  'Une deuxième session qui détient le verrou empêche la génération sans attente');
reset role;
\endif

select * from extensions.finish();
rollback;
