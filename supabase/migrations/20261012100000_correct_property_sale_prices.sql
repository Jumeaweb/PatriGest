create table public.property_sale_price_corrections (
  id uuid primary key,
  property_event_id uuid not null references public.property_events(id) on delete restrict,
  property_id uuid not null references public.real_estate_properties(id) on delete restrict,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  old_price numeric(15,2) not null check (old_price >= 0),
  new_price numeric(15,2) not null check (new_price > 0),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  corrected_by uuid not null,
  corrected_by_name text not null check (char_length(btrim(corrected_by_name)) between 1 and 300),
  corrected_at timestamptz not null default now()
);

create index property_sale_price_corrections_event_date_idx
on public.property_sale_price_corrections(property_event_id, corrected_at, id);

alter table public.property_sale_price_corrections enable row level security;

create policy "property_sale_price_corrections_select_accessible"
on public.property_sale_price_corrections
for select to authenticated
using (public.can_read_protected_person(protected_person_id));

grant select on public.property_sale_price_corrections to authenticated;
revoke insert, update, delete on public.property_sale_price_corrections from authenticated;

create or replace function public.protect_property_sale_event()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  correction_reason text;
  sale_count bigint;
begin
  if old.event_type = 'sale' or new.event_type = 'sale' then
    if new.event_type is distinct from old.event_type then
      raise exception 'Le type d’un événement de vente ne peut pas être modifié.';
    end if;

    if new.event_date is distinct from old.event_date then
      raise exception 'La date d’un événement de vente ne peut pas être modifiée.';
    end if;

    if new.amount is null then
      raise exception using
        errcode = '23514',
        message = 'Le prix de vente doit être renseigné.';
    end if;

    if new.amount <= 0 then
      raise exception using
        errcode = '23514',
        message = 'Le prix de vente doit être strictement positif.';
    end if;

    if new.amount is distinct from old.amount then
      if current_setting('patrigest.sale_price_correction_event_id', true) is distinct from old.id::text then
        raise exception 'Le prix de vente doit être corrigé par le parcours dédié.';
      end if;

      -- Les paramètres de session transportent le contexte d'audit, mais ne
      -- constituent jamais une autorisation : chaque invariant est revérifié
      -- par le trigger pour qu'un appel SQL direct ne puisse pas les contourner.
      if auth.uid() is null or not public.can_manage_protected_person(old.protected_person_id) then
        raise exception using errcode = '42501', message = 'Droits insuffisants.';
      end if;

      if old.amount is distinct from nullif(
        current_setting('patrigest.sale_price_correction_expected_price', true), ''
      )::numeric then
        raise exception using
          errcode = '40001',
          message = 'Le prix de vente a été modifié par une autre opération.';
      end if;

      correction_reason := btrim(current_setting('patrigest.sale_price_correction_reason', true));
      if correction_reason is null or char_length(correction_reason) not between 1 and 2000 then
        raise exception using errcode = '23514', message = 'Le motif de la correction est obligatoire.';
      end if;

      select count(*)
      into sale_count
      from public.property_events event
      where event.property_id = old.property_id
        and event.protected_person_id = old.protected_person_id
        and event.event_type = 'sale';

      if sale_count <> 1 then
        raise exception 'La correction exige une unique vente pour ce bien.';
      end if;

      if exists (
        select 1
        from public.management_periods period
        where period.protected_person_id = old.protected_person_id
          and period.status = 'closed'
          and old.event_date between period.start_date and period.end_date
      ) then
        raise exception 'Cette vente appartient à un exercice clôturé.';
      end if;

      if not exists (
        select 1
        from public.real_estate_properties property
        where property.id = old.property_id
          and property.protected_person_id = old.protected_person_id
          and property.status = 'disposed'
          and property.disposal_date is not distinct from old.event_date
      ) then
        raise exception 'Le bien et son événement de vente sont incohérents.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.audit_property_sale_price_correction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  correction_id uuid;
  correction_reason text;
  actor_id uuid;
  actor_name text;
begin
  if new.event_type <> 'sale' or new.amount is not distinct from old.amount then
    return new;
  end if;

  if current_setting('patrigest.sale_price_correction_event_id', true) is distinct from old.id::text then
    raise exception 'Le contexte de correction du prix de vente est invalide.';
  end if;

  correction_id := nullif(current_setting('patrigest.sale_price_correction_id', true), '')::uuid;
  correction_reason := btrim(current_setting('patrigest.sale_price_correction_reason', true));
  actor_id := auth.uid();

  if correction_id is null or actor_id is null or correction_reason is null
     or char_length(correction_reason) not between 1 and 2000 then
    raise exception 'Le contexte d’audit de la correction est incomplet.';
  end if;

  select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  into actor_name
  from public.profiles profile
  where profile.id = actor_id;

  insert into public.property_sale_price_corrections (
    id, property_event_id, property_id, protected_person_id,
    old_price, new_price, reason, corrected_by, corrected_by_name, corrected_at
  ) values (
    correction_id, old.id, old.property_id, old.protected_person_id,
    old.amount, new.amount, correction_reason, actor_id,
    coalesce(actor_name, 'Utilisateur PatriGest'), clock_timestamp()
  );

  return new;
end;
$$;

create or replace function public.prevent_property_sale_price_correction_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'Une trace de correction de prix de vente est immuable.';
end;
$$;

create trigger property_events_audit_sale_price_correction
after update of amount on public.property_events
for each row execute function public.audit_property_sale_price_correction();

create trigger property_sale_price_corrections_immutable
before update or delete on public.property_sale_price_corrections
for each row execute function public.prevent_property_sale_price_correction_change();

create or replace function public.correct_property_sale_price(
  p_protected_person_id uuid,
  p_property_id uuid,
  p_event_id uuid,
  p_expected_price numeric,
  p_new_price numeric,
  p_reason text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  sale_row public.property_events%rowtype;
  property_row public.real_estate_properties%rowtype;
  correction_id uuid := gen_random_uuid();
  correction_reason text := btrim(p_reason);
  sale_count bigint;
  updated_event_count integer;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;

  if p_expected_price is null or p_expected_price = 'NaN'::numeric
     or p_expected_price < 0 or p_expected_price > 9999999999999.99
     or p_expected_price <> round(p_expected_price, 2)
     or p_new_price is null or p_new_price = 'NaN'::numeric
     or p_new_price <= 0 or p_new_price > 9999999999999.99
     or p_new_price <> round(p_new_price, 2) then
    raise exception using errcode = '23514', message = 'Le nouveau prix est invalide.';
  end if;

  if correction_reason is null or char_length(correction_reason) not between 1 and 2000 then
    raise exception using errcode = '23514', message = 'Le motif de la correction est obligatoire.';
  end if;

  select event.*
  into sale_row
  from public.property_events event
  where event.id = p_event_id
    and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
    and event.event_type = 'sale'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Événement de vente introuvable.';
  end if;

  select count(*)
  into sale_count
  from public.property_events event
  where event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
    and event.event_type = 'sale';

  if sale_count <> 1 then
    raise exception 'La correction exige une unique vente pour ce bien.';
  end if;

  if exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = p_protected_person_id
      and period.status = 'closed'
      and sale_row.event_date between period.start_date and period.end_date
  ) then
    raise exception 'Cette vente appartient à un exercice clôturé.';
  end if;

  if sale_row.amount is distinct from p_expected_price then
    raise exception using
      errcode = '40001',
      message = 'Le prix de vente a été modifié par une autre opération.';
  end if;

  if sale_row.amount is not distinct from p_new_price then
    raise exception using errcode = '23514', message = 'Le nouveau prix doit être différent du prix actuel.';
  end if;

  select property.*
  into property_row
  from public.real_estate_properties property
  where property.id = p_property_id
    and property.protected_person_id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.';
  end if;

  if property_row.status <> 'disposed'
     or property_row.disposal_date is distinct from sale_row.event_date then
    raise exception 'Le bien et son événement de vente sont incohérents.';
  end if;

  perform set_config('patrigest.sale_price_correction_id', correction_id::text, true);
  perform set_config('patrigest.sale_price_correction_event_id', sale_row.id::text, true);
  perform set_config('patrigest.sale_price_correction_expected_price', p_expected_price::text, true);
  perform set_config('patrigest.sale_price_correction_reason', correction_reason, true);

  update public.property_events
  set amount = p_new_price
  where id = sale_row.id
    and property_id = sale_row.property_id
    and protected_person_id = sale_row.protected_person_id
    and event_type = 'sale'
    and amount is not distinct from p_expected_price;

  get diagnostics updated_event_count = row_count;
  if updated_event_count <> 1 then
    raise exception using
      errcode = '40001',
      message = 'Le prix de vente a été modifié par une autre opération.';
  end if;

  if not exists (
    select 1
    from public.property_sale_price_corrections correction
    where correction.id = correction_id
      and correction.property_event_id = sale_row.id
      and correction.old_price is not distinct from p_expected_price
      and correction.new_price is not distinct from p_new_price
      and correction.corrected_by = auth.uid()
  ) then
    raise exception 'La trace de correction n’a pas été enregistrée.';
  end if;

  perform set_config('patrigest.sale_price_correction_id', '', true);
  perform set_config('patrigest.sale_price_correction_event_id', '', true);
  perform set_config('patrigest.sale_price_correction_expected_price', '', true);
  perform set_config('patrigest.sale_price_correction_reason', '', true);

  return correction_id;
end;
$$;

revoke all on function public.audit_property_sale_price_correction() from public;
revoke all on function public.prevent_property_sale_price_correction_change() from public;
revoke all on function public.correct_property_sale_price(uuid, uuid, uuid, numeric, numeric, text) from public;
grant execute on function public.correct_property_sale_price(uuid, uuid, uuid, numeric, numeric, text) to authenticated;
