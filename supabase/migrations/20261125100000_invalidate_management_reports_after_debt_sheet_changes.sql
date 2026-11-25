-- Keep the inclusion rule aligned with management-reports/debt-period.ts.
create function public.management_report_includes_debt(
  debt public.debts, period_start date, period_end date
) returns boolean
language sql immutable strict
set search_path = ''
as $$
  select ((debt).start_date is null or (debt).start_date <= period_end)
    and not (
      (debt).status = 'settled'
      and (debt).settled_at is not null
      and ((debt).start_date is null or (debt).settled_at >= (debt).start_date)
      and (debt).settled_at < period_start
    );
$$;

create function public.management_report_debt_sheet_lock_key(person_id uuid)
returns bigint
language sql immutable strict
set search_path = ''
as $$
  select pg_catalog.hashtextextended('management-report-debt-sheet:' || person_id::text, 0);
$$;

create function public.invalidate_management_reports_after_debt_sheet_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  -- The debt write and the refresh flag become visible together.
  perform pg_catalog.pg_advisory_xact_lock(
    public.management_report_debt_sheet_lock_key(new.protected_person_id)
  );

  update public.management_reports report
  set refresh_required_at = clock_timestamp()
  where report.protected_person_id = new.protected_person_id
    and report.status = 'generated'
    and report.refresh_required_at is null
    and (
      public.management_report_includes_debt(old, report.period_start, report.period_end)
      or public.management_report_includes_debt(new, report.period_start, report.period_end)
    );
  return new;
end;
$$;

create trigger debts_invalidate_generated_reports_after_sheet_change
after update on public.debts
for each row
when (
  (old.start_date, old.monthly_payment, old.creditor, old.designation,
   old.debt_type, old.initial_amount, old.initial_duration_months)
  is distinct from
  (new.start_date, new.monthly_payment, new.creditor, new.designation,
   new.debt_type, new.initial_amount, new.initial_duration_months)
)
execute function public.invalidate_management_reports_after_debt_sheet_change();

create function public.guard_management_report_document_debt_sheet()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  report public.management_reports%rowtype;
  snapshot_debts jsonb;
  current_sheets jsonb;
  snapshot_sheets jsonb;
begin
  -- Both document RPCs already lock this row before inserting metadata.
  select * into report
  from public.management_reports
  where id = new.management_report_id
  for update;

  if not (
    (new.document_type = 'management_report_draft' and report.status = 'ready')
    or (new.document_type = 'management_report' and report.status = 'generated')
  ) then
    return new;
  end if;

  -- Never wait while holding the report row: a debt writer may already
  -- hold the dossier lock and be waiting to mark that same report.
  if not pg_catalog.pg_try_advisory_xact_lock(
    public.management_report_debt_sheet_lock_key(report.protected_person_id)
  ) then
    raise exception using errcode = '40001',
      message = 'Une fiche Dette de ce dossier est en cours de modification. Réessayez.';
  end if;

  -- Finalization uses the frozen project and the existing refresh-required guard.
  if new.document_type = 'management_report' then
    return new;
  end if;

  -- A transaction-level snapshot could hide an edit committed before the lock.
  -- The application RPCs run in READ COMMITTED.
  if current_setting('transaction_isolation') not in ('read committed', 'read uncommitted') then
    raise exception using errcode = '40001',
      message = 'Relancez la génération du projet dans une nouvelle transaction en READ COMMITTED.';
  end if;

  -- A debt edit may have committed after the app read the debts and rendered
  -- the PDF, while the report was still ready. Compare the actual inputs here.
  snapshot_debts := coalesce(new.preview_snapshot -> 'debts', '[]'::jsonb);
  if jsonb_typeof(snapshot_debts) <> 'array' then
    raise exception using errcode = '40001',
      message = 'Les fiches Dette du projet sont indisponibles. Réessayez la génération.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(
    debt.id, debt.start_date, debt.monthly_payment, debt.creditor, debt.designation,
    case debt.debt_type
      when 'bank_loan' then 'Prêt bancaire'
      when 'tax_debt' then 'Dette fiscale'
      when 'institution_debt' then 'Dette envers un établissement'
      when 'personal_debt' then 'Dette personnelle'
      when 'other' then 'Autre'
    end,
    debt.initial_amount, debt.initial_duration_months
  ) order by debt.id::text collate "C"), '[]'::jsonb)
  into current_sheets
  from public.debts debt
  where debt.protected_person_id = report.protected_person_id
    and public.management_report_includes_debt(debt, report.period_start, report.period_end);

  select coalesce(jsonb_agg(jsonb_build_array(
    debt -> 'id', debt -> 'startDate', debt -> 'monthlyPayment', debt -> 'creditor',
    debt -> 'designation', debt -> 'type', debt -> 'initialAmount', debt -> 'initialDurationMonths'
  ) order by (debt ->> 'id') collate "C"), '[]'::jsonb)
  into snapshot_sheets
  from jsonb_array_elements(snapshot_debts) as entries(debt);

  if snapshot_sheets is distinct from current_sheets then
    raise exception using errcode = '40001',
      message = 'Les fiches Dette ont changé depuis la préparation du projet. Actualisez puis réessayez.';
  end if;
  return new;
end;
$$;

-- Shared by the current and durable RPCs. No new grant or public endpoint.
create trigger management_report_documents_20_guard_debt_sheet
before insert on public.management_report_documents
for each row execute function public.guard_management_report_document_debt_sheet();

revoke all on function public.management_report_includes_debt(public.debts, date, date),
  public.management_report_debt_sheet_lock_key(uuid),
  public.invalidate_management_reports_after_debt_sheet_change(),
  public.guard_management_report_document_debt_sheet()
from public, anon, authenticated, service_role;
