alter table public.management_reports
  drop constraint management_reports_same_calendar_year,
  drop constraint management_reports_period_ends_on_december_31;

create function public.protect_linked_management_period_dates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.start_date, new.end_date) is distinct from (old.start_date, old.end_date)
     and exists (
       select 1
       from public.management_reports report
       where report.management_period_id = old.id
     ) then
    raise exception using
      errcode = 'P4R02',
      message = 'Les dates de cet exercice sont verrouillées car un compte de gestion y est déjà rattaché.';
  end if;

  return new;
end;
$$;

create trigger management_periods_protect_linked_dates
before update of start_date, end_date on public.management_periods
for each row execute function public.protect_linked_management_period_dates();

revoke all on function public.protect_linked_management_period_dates()
from public, anon, authenticated, service_role;
