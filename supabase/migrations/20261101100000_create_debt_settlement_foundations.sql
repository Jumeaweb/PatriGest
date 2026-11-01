-- PAT-DETTES-03A
-- Fondations transactionnelles de la cloture explicite des dettes.

alter table public.debts
add column revision bigint not null default 1;

alter table public.debts
add constraint debts_revision_positive check (revision > 0);

comment on column public.debts.revision is
  'Revision technique incrementee automatiquement a chaque modification reussie.';

create table public.debt_status_changes (
  id uuid primary key default gen_random_uuid(),
  debt_id uuid not null references public.debts(id) on delete restrict,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  change_type text not null check (change_type = 'settlement'),
  old_status text not null check (old_status in ('active', 'settled')),
  new_status text not null check (new_status in ('active', 'settled')),
  old_settled_at date,
  new_settled_at date,
  balance_id uuid not null references public.debt_balances(id) on delete restrict,
  old_values jsonb not null check (jsonb_typeof(old_values) = 'object'),
  new_values jsonb not null check (jsonb_typeof(new_values) = 'object'),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  revision_from bigint not null check (revision_from > 0),
  revision_to bigint not null check (revision_to = revision_from + 1),
  changed_by uuid not null,
  changed_by_name text not null check (char_length(btrim(changed_by_name)) between 1 and 300),
  changed_at timestamptz not null default clock_timestamp(),
  constraint debt_status_changes_settlement_transition check (
    change_type <> 'settlement'
    or (
      old_status = 'active'
      and new_status = 'settled'
      and old_settled_at is null
      and new_settled_at is not null
    )
  )
);

create index debt_status_changes_debt_date_idx
on public.debt_status_changes(debt_id, changed_at, id);

alter table public.debt_status_changes enable row level security;

create policy "debt_status_changes_select_accessible"
on public.debt_status_changes
for select to authenticated
using (public.can_read_protected_person(protected_person_id));

revoke all on public.debt_status_changes from anon, authenticated, service_role;
grant select on public.debt_status_changes to authenticated;

create function public.prevent_debt_status_change_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'Une trace de changement de statut de dette est immuable.';
end;
$$;

create trigger debt_status_changes_immutable
before update or delete on public.debt_status_changes
for each row execute function public.prevent_debt_status_change_mutation();

create function public.protect_debt_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  debt_table_owner name;
  settlement_permit text := current_setting('patrigest.debt_settlement_id', true);
begin
  if tg_op = 'INSERT' then
    if new.revision <> 1 then
      raise exception using
        errcode = '23514',
        message = 'La revision initiale d''une dette doit etre egale a 1.';
    end if;

    if new.status <> 'active' or new.settled_at is not null then
      raise exception using
        errcode = '23514',
        message = 'Une nouvelle dette doit etre creee active et sans date de cloture.';
    end if;

    return new;
  end if;

  if new.revision is distinct from old.revision then
    raise exception using
      errcode = '42501',
      message = 'La revision de la dette est geree automatiquement.';
  end if;

  if (new.status, new.settled_at) is distinct from (old.status, old.settled_at) then
    select pg_catalog.pg_get_userbyid(class.relowner)
    into debt_table_owner
    from pg_catalog.pg_class class
    where class.oid = 'public.debts'::regclass;

    if current_user <> debt_table_owner
       or settlement_permit is distinct from old.id::text then
      raise exception using
        errcode = '42501',
        message = 'La cloture d''une dette doit utiliser le parcours dedie.';
    end if;

    if old.status <> 'active'
       or old.settled_at is not null
       or new.status <> 'settled'
       or new.settled_at is null then
      raise exception using
        errcode = '23514',
        message = 'Cette transition de statut de dette n''est pas autorisee.';
    end if;
  end if;

  new.revision := old.revision + 1;
  return new;
end;
$$;

create trigger debts_protect_lifecycle
before insert or update on public.debts
for each row execute function public.protect_debt_lifecycle();

create function public.protect_debt_balance_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  debt_row public.debts%rowtype;
  closed_period_message constant text :=
    'Cette situation appartient a un exercice cloture. Elle ne peut plus etre ajoutee ni modifiee.';
begin
  select debt.*
  into debt_row
  from public.debts debt
  where debt.id = new.debt_id
  for key share;

  if not found then
    return new;
  end if;

  if debt_row.status <> 'active' or debt_row.settled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Une dette soldee ne peut plus recevoir de nouvelle situation.';
  end if;

  if tg_op = 'UPDATE' and exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = debt_row.protected_person_id
      and period.status = 'closed'
      and old.balance_date between period.start_date and period.end_date
  ) then
    raise exception using errcode = '23514', message = closed_period_message;
  end if;

  if exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = debt_row.protected_person_id
      and period.status = 'closed'
      and new.balance_date between period.start_date and period.end_date
  ) then
    raise exception using errcode = '23514', message = closed_period_message;
  end if;

  return new;
end;
$$;

create trigger debt_balances_protect_lifecycle
before insert or update on public.debt_balances
for each row execute function public.protect_debt_balance_lifecycle();

create function public.invalidate_management_reports_after_debt_balance_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  debt_row public.debts%rowtype;
begin
  select debt.*
  into debt_row
  from public.debts debt
  where debt.id = new.debt_id;

  if not found then
    return new;
  end if;

  update public.management_reports report
  set refresh_required_at = clock_timestamp()
  where report.protected_person_id = debt_row.protected_person_id
    and report.status::text = 'generated'
    and (debt_row.start_date is null or debt_row.start_date <= report.period_end)
    and (
      new.balance_date <= report.period_end
      or (tg_op = 'UPDATE' and old.balance_date <= report.period_end)
    );

  return new;
end;
$$;

create trigger debt_balances_invalidate_generated_reports
after insert or update on public.debt_balances
for each row execute function public.invalidate_management_reports_after_debt_balance_change();

create function public.settle_debt(
  p_protected_person_id uuid,
  p_debt_id uuid,
  p_expected_revision bigint,
  p_settled_at date,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_reason text := btrim(p_reason);
  actor_name text;
  debt_row public.debts%rowtype;
  settled_debt public.debts%rowtype;
  zero_balance public.debt_balances%rowtype;
begin
  if caller_id is null
     or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using
      errcode = '42501',
      message = 'Droits insuffisants pour solder cette dette.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using
      errcode = '40001',
      message = 'La dette a ete modifiee par une autre operation.';
  end if;

  if normalized_reason is null
     or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using
      errcode = '23514',
      message = 'Le motif de la cloture est obligatoire.';
  end if;

  if p_settled_at is null then
    raise exception using
      errcode = '23514',
      message = 'La date de cloture est obligatoire.';
  end if;

  select debt.*
  into debt_row
  from public.debts debt
  where debt.id = p_debt_id
    and debt.protected_person_id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Dette introuvable.';
  end if;

  if debt_row.revision <> p_expected_revision then
    raise exception using
      errcode = '40001',
      message = 'La dette a ete modifiee par une autre operation.';
  end if;

  if debt_row.status <> 'active' or debt_row.settled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Seule une dette active peut etre soldee.';
  end if;

  if debt_row.start_date is null then
    raise exception using
      errcode = '23514',
      message = 'La date de debut de la dette doit etre renseignee avant sa cloture.';
  end if;

  if p_settled_at < debt_row.start_date or p_settled_at > current_date then
    raise exception using
      errcode = '23514',
      message = 'La date de cloture doit etre comprise entre le debut de la dette et la date du jour.';
  end if;

  if exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = debt_row.protected_person_id
      and period.status = 'closed'
      and p_settled_at between period.start_date and period.end_date
  ) then
    raise exception using
      errcode = '23514',
      message = 'La dette ne peut pas etre soldee dans un exercice cloture.';
  end if;

  select balance.*
  into zero_balance
  from public.debt_balances balance
  where balance.debt_id = debt_row.id
    and balance.balance_date = p_settled_at
    and balance.remaining_balance = 0
  for key share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Une situation a 0 EUR doit exister a la date de cloture.';
  end if;

  if exists (
    select 1
    from public.debt_balances balance
    where balance.debt_id = debt_row.id
      and balance.balance_date > p_settled_at
  ) then
    raise exception using
      errcode = '23514',
      message = 'Une situation plus recente empeche la cloture a cette date.';
  end if;

  if debt_row.current_balance is distinct from 0::numeric
     or debt_row.current_balance_date is distinct from p_settled_at then
    raise exception using
      errcode = '23514',
      message = 'La situation courante de la dette est incoherente avec sa cloture.';
  end if;

  perform set_config('patrigest.debt_settlement_id', debt_row.id::text, true);

  update public.debts
  set status = 'settled',
      settled_at = p_settled_at
  where id = debt_row.id
    and protected_person_id = debt_row.protected_person_id
    and revision = p_expected_revision
    and status = 'active'
    and settled_at is null
  returning * into settled_debt;

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La dette a ete modifiee par une autre operation.';
  end if;

  select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  into actor_name
  from public.profiles profile
  where profile.id = caller_id;

  insert into public.debt_status_changes(
    debt_id,
    protected_person_id,
    change_type,
    old_status,
    new_status,
    old_settled_at,
    new_settled_at,
    balance_id,
    old_values,
    new_values,
    reason,
    revision_from,
    revision_to,
    changed_by,
    changed_by_name
  ) values (
    debt_row.id,
    debt_row.protected_person_id,
    'settlement',
    debt_row.status,
    settled_debt.status,
    debt_row.settled_at,
    settled_debt.settled_at,
    zero_balance.id,
    jsonb_build_object(
      'status', debt_row.status,
      'settled_at', debt_row.settled_at,
      'current_balance', debt_row.current_balance,
      'current_balance_date', debt_row.current_balance_date,
      'revision', debt_row.revision
    ),
    jsonb_build_object(
      'status', settled_debt.status,
      'settled_at', settled_debt.settled_at,
      'current_balance', settled_debt.current_balance,
      'current_balance_date', settled_debt.current_balance_date,
      'revision', settled_debt.revision
    ),
    normalized_reason,
    debt_row.revision,
    settled_debt.revision,
    caller_id,
    coalesce(actor_name, 'Utilisateur PatriGest')
  );

  update public.management_reports report
  set refresh_required_at = clock_timestamp()
  where report.protected_person_id = debt_row.protected_person_id
    and report.status::text = 'generated'
    and (debt_row.start_date is null or debt_row.start_date <= report.period_end)
    and p_settled_at <= report.period_end;

  perform set_config('patrigest.debt_settlement_id', '', true);

  return settled_debt.revision;
end;
$$;

revoke all on function public.prevent_debt_status_change_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.protect_debt_lifecycle()
from public, anon, authenticated, service_role;
revoke all on function public.protect_debt_balance_lifecycle()
from public, anon, authenticated, service_role;
revoke all on function public.invalidate_management_reports_after_debt_balance_change()
from public, anon, authenticated, service_role;
revoke all on function public.settle_debt(uuid, uuid, bigint, date, text)
from public, anon, authenticated, service_role;
grant execute on function public.settle_debt(uuid, uuid, bigint, date, text)
to authenticated;

comment on table public.debt_status_changes is
  'Journal append-only des transitions explicites de statut des dettes.';
comment on function public.settle_debt(uuid, uuid, bigint, date, text) is
  'Solde atomiquement une dette active a partir d une situation courante nulle et audite la transition.';
