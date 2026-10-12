create or replace function public.synchronize_property_sale()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  property_row public.real_estate_properties%rowtype;
  updated_property_count integer;
begin
  if new.event_type <> 'sale' then
    return new;
  end if;

  select property.*
  into property_row
  from public.real_estate_properties property
  where property.id = new.property_id
    and property.protected_person_id = new.protected_person_id
  for update;

  if not found then
    return new;
  end if;

  if exists (
    select 1
    from public.property_events event
    where event.property_id = new.property_id
      and event.event_type = 'sale'
  ) then
    raise exception using
      errcode = '23505',
      message = 'Une vente est déjà enregistrée pour ce bien.';
  end if;

  if property_row.status <> 'active' then
    raise exception 'Seul un bien actif peut être vendu.';
  end if;

  if new.amount is null then
    raise exception using
      errcode = '23514',
      message = 'Le prix de vente doit être renseigné.';
  end if;

  if property_row.entry_date is not null and new.event_date < property_row.entry_date then
    raise exception 'La date de vente ne peut pas précéder l’entrée du bien dans le patrimoine.';
  end if;

  if new.event_date > current_date then
    raise exception 'La date de vente ne peut pas être future.';
  end if;

  update public.real_estate_properties
  set status = 'disposed',
      disposal_date = new.event_date
  where id = property_row.id;

  get diagnostics updated_property_count = row_count;
  if updated_property_count <> 1 then
    raise exception 'La fiche immobilière n’a pas pu être synchronisée.';
  end if;

  return new;
end;
$$;

create or replace function public.protect_property_sale_event()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
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
  end if;

  return new;
end;
$$;

create or replace function public.protect_sold_property_consistency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  sale_count bigint;
  sale_date date;
begin
  if (new.status, new.disposal_date) is not distinct from (old.status, old.disposal_date) then
    return new;
  end if;

  select count(*), min(event.event_date)
  into sale_count, sale_date
  from public.property_events event
  where event.property_id = old.id
    and event.event_type = 'sale';

  if sale_count = 0 then
    return new;
  end if;

  if sale_count > 1 then
    raise exception 'Plusieurs ventes historiques empêchent la modification du statut de ce bien.';
  end if;

  if new.status <> 'disposed' or new.disposal_date is distinct from sale_date then
    raise exception 'Le statut et la date de cession doivent correspondre à l’événement de vente.';
  end if;

  return new;
end;
$$;

drop trigger if exists property_events_validate_sale on public.property_events;
create trigger property_events_validate_sale
before insert on public.property_events
for each row execute function public.synchronize_property_sale();

drop trigger if exists property_events_protect_sale on public.property_events;
create trigger property_events_protect_sale
before update on public.property_events
for each row execute function public.protect_property_sale_event();

drop trigger if exists real_estate_properties_protect_sale on public.real_estate_properties;
create trigger real_estate_properties_protect_sale
before update on public.real_estate_properties
for each row execute function public.protect_sold_property_consistency();
