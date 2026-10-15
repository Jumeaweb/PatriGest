create table public.patrimony_absence_confirmations (
  protected_person_id uuid not null references public.protected_persons(id) on delete cascade,
  category text not null check (category in ('real_estate', 'active_debt')),
  confirmed_at timestamptz not null,
  confirmed_by uuid not null,
  confirmed_by_name text not null check (char_length(btrim(confirmed_by_name)) between 1 and 300),
  primary key (protected_person_id, category)
);

alter table public.patrimony_absence_confirmations enable row level security;

create policy "patrimony_absence_confirmations_select_accessible"
on public.patrimony_absence_confirmations for select to authenticated
using (public.can_read_protected_person(protected_person_id));

create policy "patrimony_absence_confirmations_insert_manage"
on public.patrimony_absence_confirmations for insert to authenticated
with check (public.can_manage_protected_person(protected_person_id));

create policy "patrimony_absence_confirmations_delete_manage"
on public.patrimony_absence_confirmations for delete to authenticated
using (public.can_manage_protected_person(protected_person_id));

revoke all on public.patrimony_absence_confirmations from anon, authenticated;
grant select, delete on public.patrimony_absence_confirmations to authenticated;
grant insert (protected_person_id, category)
on public.patrimony_absence_confirmations to authenticated;

create or replace function public.validate_patrimony_absence_confirmation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_name text;
begin
  if actor_id is null or not public.can_manage_protected_person(new.protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  if new.category not in ('real_estate', 'active_debt') then
    raise exception using errcode = '23514', message = 'La catégorie de confirmation est invalide.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'patrigest.patrimony_absence:' || new.protected_person_id::text || ':' || new.category,
      0
    )
  );

  if new.category = 'real_estate' and exists (
    select 1
    from public.real_estate_properties property
    where property.protected_person_id = new.protected_person_id
      and property.status = 'active'
      and property.archived_at is null
  ) then
    raise exception using errcode = '23514', message = 'L’absence de bien immobilier ne peut pas être confirmée tant qu’un bien actif existe.';
  end if;
  if new.category = 'active_debt' and exists (
    select 1
    from public.debts debt
    where debt.protected_person_id = new.protected_person_id
      and debt.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'L’absence de dette ne peut pas être confirmée tant qu’une dette active existe.';
  end if;

  select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  into actor_name
  from public.profiles profile
  where profile.id = actor_id;

  new.confirmed_at := clock_timestamp();
  new.confirmed_by := actor_id;
  new.confirmed_by_name := coalesce(actor_name, 'Utilisateur PatriGest');
  return new;
end;
$$;

create trigger patrimony_absence_confirmations_validate
before insert on public.patrimony_absence_confirmations
for each row execute function public.validate_patrimony_absence_confirmation();

create or replace function public.protect_patrimony_absence_confirmation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using errcode = '42501', message = 'Une confirmation d’absence doit être retirée puis recréée.';
end;
$$;

create trigger patrimony_absence_confirmations_no_update
before update on public.patrimony_absence_confirmations
for each row execute function public.protect_patrimony_absence_confirmation();

create or replace function public.set_patrimony_absence_confirmation(
  p_protected_person_id uuid,
  p_category text,
  p_confirmed boolean
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected_rows bigint;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  if p_category is null or p_category not in ('real_estate', 'active_debt') then
    raise exception using errcode = '23514', message = 'La catégorie de confirmation est invalide.';
  end if;
  if p_confirmed is null then
    raise exception using errcode = '23514', message = 'L’état de confirmation est obligatoire.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'patrigest.patrimony_absence:' || p_protected_person_id::text || ':' || p_category,
      0
    )
  );

  if p_confirmed then
    insert into public.patrimony_absence_confirmations(protected_person_id, category)
    values (p_protected_person_id, p_category)
    on conflict (protected_person_id, category) do nothing;
  else
    delete from public.patrimony_absence_confirmations
    where protected_person_id = p_protected_person_id
      and category = p_category;
  end if;

  get diagnostics affected_rows = row_count;
  return affected_rows > 0;
end;
$$;

create or replace function public.invalidate_patrimony_absence_confirmation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_category text;
  target_person_id uuid;
  is_current_element boolean;
begin
  if tg_table_name = 'real_estate_properties' then
    target_category := 'real_estate';
    target_person_id := new.protected_person_id;
    is_current_element := new.status = 'active' and new.archived_at is null;
  elsif tg_table_name = 'debts' then
    target_category := 'active_debt';
    target_person_id := new.protected_person_id;
    is_current_element := new.status = 'active';
  else
    raise exception 'Table non prise en charge pour l’invalidation patrimoniale.';
  end if;

  if not is_current_element then return new; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'patrigest.patrimony_absence:' || target_person_id::text || ':' || target_category,
      0
    )
  );

  delete from public.patrimony_absence_confirmations
  where protected_person_id = target_person_id
    and category = target_category;
  return new;
end;
$$;

create trigger real_estate_properties_invalidate_absence_confirmation
after insert or update of status, archived_at on public.real_estate_properties
for each row execute function public.invalidate_patrimony_absence_confirmation();

create trigger debts_invalidate_absence_confirmation
after insert or update of status on public.debts
for each row execute function public.invalidate_patrimony_absence_confirmation();

revoke all on function public.set_patrimony_absence_confirmation(uuid,text,boolean) from public, anon;
grant execute on function public.set_patrimony_absence_confirmation(uuid,text,boolean) to authenticated;
revoke all on function public.validate_patrimony_absence_confirmation() from public, anon, authenticated;
revoke all on function public.protect_patrimony_absence_confirmation() from public, anon, authenticated;
revoke all on function public.invalidate_patrimony_absence_confirmation() from public, anon, authenticated;

comment on table public.patrimony_absence_confirmations is
  'État courant des absences de biens immobiliers ou de dettes explicitement confirmées par dossier.';
comment on column public.patrimony_absence_confirmations.category is
  'real_estate : aucun bien actif non archivé ; active_debt : aucune dette active.';
comment on function public.set_patrimony_absence_confirmation(uuid,text,boolean) is
  'Confirme ou retire une absence patrimoniale pour un dossier gérable par l’utilisateur authentifié.';
