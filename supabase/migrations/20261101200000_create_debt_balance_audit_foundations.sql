-- PAT-DETTES-04A
-- Corrections et annulations auditees des situations de dette.

alter table public.debt_balances
  add column revision bigint not null default 1,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid,
  add column cancellation_reason text;

alter table public.debt_balances
  add constraint debt_balances_revision_positive check (revision > 0),
  add constraint debt_balances_cancellation_consistency check (
    (cancelled_at is null and cancelled_by is null and cancellation_reason is null)
    or (
      cancelled_at is not null
      and cancelled_by is not null
      and char_length(btrim(cancellation_reason)) between 1 and 2000
    )
  );

alter table public.debt_balances
  drop constraint debt_balances_debt_id_balance_date_key;

create unique index debt_balances_active_debt_date_uidx
on public.debt_balances(debt_id, balance_date)
where cancelled_at is null;

comment on column public.debt_balances.revision is
  'Revision technique incrementee automatiquement a chaque correction ou annulation.';
comment on column public.debt_balances.cancelled_at is
  'Date d annulation logique ; une situation annulee reste consultable mais est exclue des calculs.';

create table public.debt_balance_changes (
  id uuid primary key default gen_random_uuid(),
  debt_balance_id uuid not null references public.debt_balances(id) on delete restrict,
  debt_id uuid not null references public.debts(id) on delete restrict,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  change_type text not null check (change_type in ('correction', 'cancellation')),
  old_values jsonb not null check (jsonb_typeof(old_values) = 'object'),
  new_values jsonb not null check (jsonb_typeof(new_values) = 'object'),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  revision_from bigint not null check (revision_from > 0),
  revision_to bigint not null check (revision_to = revision_from + 1),
  changed_by uuid not null,
  changed_by_name text not null check (char_length(btrim(changed_by_name)) between 1 and 300),
  changed_at timestamptz not null default clock_timestamp()
);

create index debt_balance_changes_balance_date_idx
on public.debt_balance_changes(debt_balance_id, changed_at, id);

create index debt_balance_changes_debt_date_idx
on public.debt_balance_changes(debt_id, changed_at, id);

alter table public.debt_balance_changes enable row level security;

create policy "debt_balance_changes_select_accessible"
on public.debt_balance_changes
for select to authenticated
using (public.can_read_protected_person(protected_person_id));

revoke all on table public.debt_balance_changes
from anon, authenticated, service_role;
grant select on table public.debt_balance_changes to authenticated;

create function public.prevent_debt_balance_change_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'Une trace de correction de situation de dette est immuable.';
end;
$$;

create trigger debt_balance_changes_immutable
before update or delete on public.debt_balance_changes
for each row execute function public.prevent_debt_balance_change_mutation();

create function public.validate_debt_balance_change_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
begin
  if actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'L auteur authentifie de la trace est introuvable.';
  end if;

  if not exists (
    select 1
    from public.debt_balances balance
    join public.debts debt on debt.id = balance.debt_id
    where balance.id = new.debt_balance_id
      and balance.debt_id = new.debt_id
      and debt.protected_person_id = new.protected_person_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'La trace ne correspond pas a la situation de dette indiquee.';
  end if;

  select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  into actor_name
  from public.profiles profile
  where profile.id = actor_id;

  new.changed_by := actor_id;
  new.changed_by_name := coalesce(actor_name, 'Utilisateur PatriGest');

  return new;
end;
$$;

create trigger debt_balance_changes_validate_links
before insert on public.debt_balance_changes
for each row execute function public.validate_debt_balance_change_links();

create function public.protect_debt_balance_audit_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  balance_table_owner name;
  change_permit text := current_setting('patrigest.debt_balance_change_id', true);
begin
  if tg_op = 'INSERT' then
    if new.revision <> 1 then
      raise exception using
        errcode = '23514',
        message = 'La revision initiale d une situation de dette doit etre egale a 1.';
    end if;

    if new.cancelled_at is not null
       or new.cancelled_by is not null
       or new.cancellation_reason is not null then
      raise exception using
        errcode = '23514',
        message = 'Une nouvelle situation de dette ne peut pas etre creee comme annulee.';
    end if;

    return new;
  end if;

  if tg_op = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Une situation de dette ne peut pas etre supprimee physiquement.';
  end if;

  select pg_catalog.pg_get_userbyid(class.relowner)
  into balance_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.debt_balances'::regclass;

  if current_user <> balance_table_owner
     or change_permit is distinct from old.id::text then
    raise exception using
      errcode = '42501',
      message = 'La correction ou l annulation doit utiliser le parcours dedie.';
  end if;

  if old.cancelled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Une situation de dette annulee ne peut plus etre modifiee.';
  end if;

  if new.revision is distinct from old.revision then
    raise exception using
      errcode = '42501',
      message = 'La revision de la situation de dette est geree automatiquement.';
  end if;

  if (new.cancelled_at, new.cancelled_by, new.cancellation_reason)
     is distinct from
       (old.cancelled_at, old.cancelled_by, old.cancellation_reason)
     and (
       new.cancelled_at is null
       or new.cancelled_by is null
       or new.cancellation_reason is null
     ) then
    raise exception using
      errcode = '23514',
      message = 'Les informations d annulation de la situation sont incompletes.';
  end if;

  new.revision := old.revision + 1;
  return new;
end;
$$;

create trigger debt_balances_protect_audit_lifecycle
before insert or update or delete on public.debt_balances
for each row execute function public.protect_debt_balance_audit_lifecycle();

revoke update, delete on table public.debt_balances
from anon, authenticated, service_role;

create or replace function public.sync_debt_current_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  latest_balance public.debt_balances%rowtype;
begin
  select balance.*
  into latest_balance
  from public.debt_balances balance
  where balance.debt_id = new.debt_id
    and balance.cancelled_at is null
  order by balance.balance_date desc, balance.created_at desc, balance.id desc
  limit 1;

  update public.debts
  set current_balance = latest_balance.remaining_balance,
      current_balance_date = latest_balance.balance_date,
      remaining_duration_months = latest_balance.remaining_duration_months
  where id = new.debt_id;

  return new;
end;
$$;

create function public.correct_debt_balance(
  p_protected_person_id uuid,
  p_debt_id uuid,
  p_debt_balance_id uuid,
  p_expected_revision bigint,
  p_balance_date date,
  p_remaining_balance numeric,
  p_remaining_duration_months integer,
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
  debt_row public.debts%rowtype;
  old_balance public.debt_balances%rowtype;
  new_balance public.debt_balances%rowtype;
begin
  if caller_id is null
     or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using
      errcode = '42501',
      message = 'Droits insuffisants pour corriger cette situation de dette.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  if normalized_reason is null
     or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using
      errcode = '23514',
      message = 'Le motif de la correction est obligatoire.';
  end if;

  if p_balance_date is null
     or p_remaining_balance is null
     or p_remaining_balance = 'NaN'::numeric
     or p_remaining_balance < 0
     or p_remaining_balance > 9999999999999.99
     or p_remaining_balance <> round(p_remaining_balance, 2)
     or p_remaining_duration_months < 0 then
    raise exception using
      errcode = '23514',
      message = 'Les informations de correction sont invalides.';
  end if;

  perform public.assert_protected_person_active_for_write(p_protected_person_id);

  select debt.*
  into debt_row
  from public.debts debt
  where debt.id = p_debt_id
    and debt.protected_person_id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Dette introuvable.';
  end if;

  if debt_row.status <> 'active' or debt_row.settled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Une dette soldee ne peut pas etre corrigee.';
  end if;

  select balance.*
  into old_balance
  from public.debt_balances balance
  where balance.id = p_debt_balance_id
    and balance.debt_id = p_debt_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Situation de dette introuvable.';
  end if;

  if old_balance.revision <> p_expected_revision then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  if old_balance.cancelled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Une situation de dette annulee ne peut plus etre corrigee.';
  end if;

  if exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = p_protected_person_id
      and period.status = 'closed'
      and old_balance.balance_date between period.start_date and period.end_date
  ) or exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = p_protected_person_id
      and period.status = 'closed'
      and p_balance_date between period.start_date and period.end_date
  ) then
    raise exception using
      errcode = '23514',
      message = 'Cette situation appartient a un exercice cloture. Elle ne peut plus etre corrigee ni annulee.';
  end if;

  if exists (
    select 1
    from public.debt_balances balance
    where balance.debt_id = p_debt_id
      and balance.id <> p_debt_balance_id
      and balance.cancelled_at is null
      and balance.balance_date = p_balance_date
  ) then
    raise exception using
      errcode = '23505',
      message = 'Une situation active existe deja a cette date.';
  end if;

  if old_balance.balance_date is not distinct from p_balance_date
     and old_balance.remaining_balance is not distinct from p_remaining_balance
     and old_balance.remaining_duration_months is not distinct from p_remaining_duration_months then
    raise exception using
      errcode = '23514',
      message = 'Aucune modification n a ete detectee.';
  end if;

  perform set_config('patrigest.debt_balance_change_id', old_balance.id::text, true);

  update public.debt_balances
  set balance_date = p_balance_date,
      remaining_balance = p_remaining_balance,
      remaining_duration_months = p_remaining_duration_months
  where id = old_balance.id
    and debt_id = old_balance.debt_id
    and revision = p_expected_revision
    and cancelled_at is null
  returning * into new_balance;

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  insert into public.debt_balance_changes(
    debt_balance_id,
    debt_id,
    protected_person_id,
    change_type,
    old_values,
    new_values,
    reason,
    revision_from,
    revision_to,
    changed_by,
    changed_by_name
  ) values (
    old_balance.id,
    old_balance.debt_id,
    p_protected_person_id,
    'correction',
    jsonb_build_object(
      'balance_date', old_balance.balance_date,
      'remaining_balance', old_balance.remaining_balance,
      'remaining_duration_months', old_balance.remaining_duration_months,
      'revision', old_balance.revision,
      'cancelled_at', old_balance.cancelled_at
    ),
    jsonb_build_object(
      'balance_date', new_balance.balance_date,
      'remaining_balance', new_balance.remaining_balance,
      'remaining_duration_months', new_balance.remaining_duration_months,
      'revision', new_balance.revision,
      'cancelled_at', new_balance.cancelled_at
    ),
    normalized_reason,
    old_balance.revision,
    new_balance.revision,
    caller_id,
    'Utilisateur PatriGest'
  );

  perform set_config('patrigest.debt_balance_change_id', '', true);
  return new_balance.revision;
end;
$$;

create function public.cancel_debt_balance(
  p_protected_person_id uuid,
  p_debt_id uuid,
  p_debt_balance_id uuid,
  p_expected_revision bigint,
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
  debt_row public.debts%rowtype;
  old_balance public.debt_balances%rowtype;
  new_balance public.debt_balances%rowtype;
begin
  if caller_id is null
     or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using
      errcode = '42501',
      message = 'Droits insuffisants pour annuler cette situation de dette.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  if normalized_reason is null
     or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using
      errcode = '23514',
      message = 'Le motif de l annulation est obligatoire.';
  end if;

  perform public.assert_protected_person_active_for_write(p_protected_person_id);

  select debt.*
  into debt_row
  from public.debts debt
  where debt.id = p_debt_id
    and debt.protected_person_id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Dette introuvable.';
  end if;

  if debt_row.status <> 'active' or debt_row.settled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Une dette soldee ne peut pas etre corrigee.';
  end if;

  select balance.*
  into old_balance
  from public.debt_balances balance
  where balance.id = p_debt_balance_id
    and balance.debt_id = p_debt_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Situation de dette introuvable.';
  end if;

  if old_balance.revision <> p_expected_revision then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  if old_balance.cancelled_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Cette situation de dette est deja annulee.';
  end if;

  if exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = p_protected_person_id
      and period.status = 'closed'
      and old_balance.balance_date between period.start_date and period.end_date
  ) then
    raise exception using
      errcode = '23514',
      message = 'Cette situation appartient a un exercice cloture. Elle ne peut plus etre corrigee ni annulee.';
  end if;

  perform set_config('patrigest.debt_balance_change_id', old_balance.id::text, true);

  update public.debt_balances
  set cancelled_at = clock_timestamp(),
      cancelled_by = caller_id,
      cancellation_reason = normalized_reason
  where id = old_balance.id
    and debt_id = old_balance.debt_id
    and revision = p_expected_revision
    and cancelled_at is null
  returning * into new_balance;

  if not found then
    raise exception using
      errcode = '40001',
      message = 'La situation de dette a ete modifiee par une autre operation.';
  end if;

  insert into public.debt_balance_changes(
    debt_balance_id,
    debt_id,
    protected_person_id,
    change_type,
    old_values,
    new_values,
    reason,
    revision_from,
    revision_to,
    changed_by,
    changed_by_name
  ) values (
    old_balance.id,
    old_balance.debt_id,
    p_protected_person_id,
    'cancellation',
    jsonb_build_object(
      'balance_date', old_balance.balance_date,
      'remaining_balance', old_balance.remaining_balance,
      'remaining_duration_months', old_balance.remaining_duration_months,
      'revision', old_balance.revision,
      'cancelled_at', old_balance.cancelled_at
    ),
    jsonb_build_object(
      'balance_date', new_balance.balance_date,
      'remaining_balance', new_balance.remaining_balance,
      'remaining_duration_months', new_balance.remaining_duration_months,
      'revision', new_balance.revision,
      'cancelled_at', new_balance.cancelled_at
    ),
    normalized_reason,
    old_balance.revision,
    new_balance.revision,
    caller_id,
    'Utilisateur PatriGest'
  );

  perform set_config('patrigest.debt_balance_change_id', '', true);
  return new_balance.revision;
end;
$$;

create or replace function public.settle_debt(
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
    and balance.cancelled_at is null
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
      and balance.cancelled_at is null
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
    debt_id, protected_person_id, change_type, old_status, new_status,
    old_settled_at, new_settled_at, balance_id, old_values, new_values,
    reason, revision_from, revision_to, changed_by, changed_by_name
  ) values (
    debt_row.id, debt_row.protected_person_id, 'settlement', debt_row.status,
    settled_debt.status, debt_row.settled_at, settled_debt.settled_at,
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
    normalized_reason, debt_row.revision, settled_debt.revision,
    caller_id, coalesce(actor_name, 'Utilisateur PatriGest')
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

revoke all on function public.prevent_debt_balance_change_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.validate_debt_balance_change_links()
from public, anon, authenticated, service_role;
revoke all on function public.protect_debt_balance_audit_lifecycle()
from public, anon, authenticated, service_role;
revoke all on function public.correct_debt_balance(
  uuid, uuid, uuid, bigint, date, numeric, integer, text
) from public, anon, authenticated, service_role;
revoke all on function public.cancel_debt_balance(
  uuid, uuid, uuid, bigint, text
) from public, anon, authenticated, service_role;
revoke all on function public.settle_debt(uuid, uuid, bigint, date, text)
from public, anon, authenticated, service_role;

grant execute on function public.correct_debt_balance(
  uuid, uuid, uuid, bigint, date, numeric, integer, text
) to authenticated;
grant execute on function public.cancel_debt_balance(
  uuid, uuid, uuid, bigint, text
) to authenticated;
grant execute on function public.settle_debt(uuid, uuid, bigint, date, text)
to authenticated;

comment on table public.debt_balance_changes is
  'Journal append-only des corrections et annulations logiques des situations de dette.';
comment on function public.correct_debt_balance(
  uuid, uuid, uuid, bigint, date, numeric, integer, text
) is 'Corrige atomiquement une situation de dette active et conserve ses anciennes valeurs.';
comment on function public.cancel_debt_balance(
  uuid, uuid, uuid, bigint, text
) is 'Annule logiquement une situation de dette active et recalcule le CRD courant.';
