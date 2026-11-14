begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(17);

select extensions.ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.management_reports'::regclass
      and conname = 'management_reports_same_calendar_year'
  ),
  'la restriction à une seule année civile est supprimée'
);
select extensions.ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.management_reports'::regclass
      and conname = 'management_reports_period_ends_on_december_31'
  ),
  'la fin obligatoire au 31 décembre est supprimée'
);
select extensions.ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.management_reports'::regclass
      and conname = 'management_reports_period_order'
  ),
  'l’ordre des dates reste contrôlé'
);
select extensions.ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.management_reports'::regclass
      and conname = 'management_reports_year_matches_period'
  ),
  'l’année reste celle de la fin de l’exercice'
);
select extensions.ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.management_reports'::regclass
      and conname = 'management_reports_no_overlap'
  ),
  'la protection concurrente contre les chevauchements reste en place'
);
select extensions.has_trigger(
  'public', 'management_periods', 'management_periods_protect_linked_dates',
  'les dates d’un exercice rattaché sont protégées'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '99400000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'crg-owner@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '99400000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'crg-reader@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000002'
);

insert into public.protected_persons (
  id, owner_id, first_name, last_name, status, archived_at
) values
  ('99400000-0000-4000-8100-000000000001', '99400000-0000-4000-8000-000000000001', 'Dossier', 'CRG', 'active', null),
  ('99400000-0000-4000-8100-000000000002', '99400000-0000-4000-8000-000000000001', 'Dossier', 'Archivé', 'active', null);

insert into public.protected_person_access (
  protected_person_id, user_id, role, invited_by
) values (
  '99400000-0000-4000-8100-000000000001',
  '99400000-0000-4000-8000-000000000002',
  'read_only',
  '99400000-0000-4000-8000-000000000001'
);

insert into public.management_periods (
  id, protected_person_id, start_date, end_date, status, closed_at, notes
) values
  ('99400000-0000-4000-8200-000000000001', '99400000-0000-4000-8100-000000000001', '2023-03-15', '2023-12-31', 'closed', now(), 'Exercice incomplet'),
  ('99400000-0000-4000-8200-000000000002', '99400000-0000-4000-8100-000000000001', '2024-07-01', '2025-06-30', 'closed', now(), 'Exercice non civil'),
  ('99400000-0000-4000-8200-000000000003', '99400000-0000-4000-8100-000000000001', '2026-01-01', '2026-12-31', 'open', null, 'Exercice disponible'),
  ('99400000-0000-4000-8200-000000000004', '99400000-0000-4000-8100-000000000002', '2026-01-01', '2026-12-31', 'open', null, 'Exercice archivé');

set local session_replication_role = replica;
update public.protected_persons
set status = 'archived', archived_at = now()
where id = '99400000-0000-4000-8100-000000000002';
set local session_replication_role = origin;

select extensions.lives_ok(
  $$insert into public.management_reports(
      id, protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8300-000000000001',
      '99400000-0000-4000-8100-000000000001',
      '99400000-0000-4000-8200-000000000001',
      2023, '2023-03-15', '2023-12-31',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  'un exercice incomplet peut produire un compte de gestion'
);
select extensions.lives_ok(
  $$insert into public.management_reports(
      id, protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8300-000000000002',
      '99400000-0000-4000-8100-000000000001',
      '99400000-0000-4000-8200-000000000002',
      2025, '2024-07-01', '2025-06-30',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  'un exercice chevauchant deux années peut produire un compte de gestion'
);
select extensions.is(
  (select report_year from public.management_reports
   where id = '99400000-0000-4000-8300-000000000002'),
  2025,
  'l’année du CRG est celle de la fin de l’exercice'
);
select extensions.throws_ok(
  $$insert into public.management_reports(
      protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8100-000000000001',
      '99400000-0000-4000-8200-000000000003',
      2025, '2026-01-01', '2026-12-31',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  '23514',
  'new row for relation "management_reports" violates check constraint "management_reports_year_matches_period"',
  'une année manipulée reste refusée par PostgreSQL'
);
select extensions.throws_ok(
  $$insert into public.management_reports(
      protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8100-000000000001',
      '99400000-0000-4000-8200-000000000004',
      2026, '2026-01-01', '2026-12-31',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  'P0001', 'L''exercice ne correspond pas à la période du compte de gestion.',
  'un exercice d’un autre dossier ne peut pas être rattaché'
);
select extensions.throws_ok(
  $$insert into public.management_reports(
      protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8100-000000000001',
      null,
      2026, '2023-12-01', '2026-12-31',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  '23P01', null,
  'un chevauchement partiel ou concurrent reste refusé'
);
select extensions.throws_ok(
  $$update public.management_periods
    set start_date = '2023-03-16'
    where id = '99400000-0000-4000-8200-000000000001'$$,
  'P4R02',
  'Les dates de cet exercice sont verrouillées car un compte de gestion y est déjà rattaché.',
  'les dates d’un exercice lié ne peuvent plus être déplacées'
);
select extensions.lives_ok(
  $$update public.management_periods
    set notes = 'Note mise à jour'
    where id = '99400000-0000-4000-8200-000000000001'$$,
  'une modification sans rapport avec les dates reste possible'
);
select extensions.results_eq(
  $$select report_year, period_start, period_end
    from public.management_reports
    where id = '99400000-0000-4000-8300-000000000001'$$,
  $$values (2023, '2023-03-15'::date, '2023-12-31'::date)$$,
  'le CRG historique reste inchangé'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '99400000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"99400000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select extensions.throws_ok(
  $$insert into public.management_reports(
      protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8100-000000000001',
      '99400000-0000-4000-8200-000000000003',
      2026, '2026-01-01', '2026-12-31',
      '99400000-0000-4000-8000-000000000002'
    )$$,
  '42501', null,
  'un lecteur ne peut pas préparer un CRG'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '99400000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"99400000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select extensions.throws_ok(
  $$insert into public.management_reports(
      protected_person_id, management_period_id, report_year,
      period_start, period_end, created_by
    ) values (
      '99400000-0000-4000-8100-000000000002',
      '99400000-0000-4000-8200-000000000004',
      2026, '2026-01-01', '2026-12-31',
      '99400000-0000-4000-8000-000000000001'
    )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un dossier archivé reste protégé'
);

select * from extensions.finish();
rollback;
