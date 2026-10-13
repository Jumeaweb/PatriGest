alter table public.management_reports
add column refresh_required_at timestamptz;

comment on column public.management_reports.refresh_required_at is
  'Date d’une modification métier postérieure au projet PDF. Non nul : le projet doit être repris et régénéré avant finalisation.';

create or replace function public.protect_property_event_lifecycle_foundations()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  event_table_owner name;
  authorized_sale_price_update boolean;
begin
  if tg_op = 'INSERT' then
    if new.revision <> 1 then
      raise exception 'La révision initiale d’un événement immobilier doit être égale à 1.';
    end if;

    if new.cancelled_at is not null
       or new.cancelled_by is not null
       or new.cancellation_reason is not null then
      raise exception 'Un nouvel événement immobilier ne peut pas être créé comme annulé.';
    end if;

    return new;
  end if;

  select pg_catalog.pg_get_userbyid(class.relowner)
  into event_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.property_events'::regclass;

  authorized_sale_price_update := coalesce(
    old.event_type = 'sale'
    and new.event_type = 'sale'
    and new.amount is distinct from old.amount
    and new.event_date is not distinct from old.event_date
    and new.description is not distinct from old.description
    and new.document_reference is not distinct from old.document_reference
    and new.property_id = old.property_id
    and new.protected_person_id = old.protected_person_id
    and new.created_at = old.created_at
    and new.revision = old.revision
    and (new.cancelled_at, new.cancelled_by, new.cancellation_reason)
      is not distinct from
      (old.cancelled_at, old.cancelled_by, old.cancellation_reason)
    and current_setting('patrigest.sale_price_correction_event_id', true) = old.id::text,
    false
  );

  if current_user <> event_table_owner and not authorized_sale_price_update then
    raise exception using
      errcode = '42501',
      message = 'La correction d’un événement immobilier doit utiliser le parcours dédié.';
  end if;

  if new.revision is distinct from old.revision then
    raise exception 'La révision d’un événement immobilier est gérée automatiquement.';
  end if;

  if (new.cancelled_at, new.cancelled_by, new.cancellation_reason)
     is distinct from
     (old.cancelled_at, old.cancelled_by, old.cancellation_reason) then
    raise exception 'L’annulation d’un événement immobilier nécessite le parcours dédié.';
  end if;

  new.revision := old.revision + 1;
  return new;
end;
$$;

create or replace function public.protect_property_sale_event()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  correction_reason text;
  sale_count bigint;
  event_table_owner name;
begin
  if old.event_type = 'sale' or new.event_type = 'sale' then
    if new.event_type is distinct from old.event_type then
      raise exception 'Le type d’un événement de vente ne peut pas être modifié.';
    end if;

    if new.event_date is distinct from old.event_date then
      select pg_catalog.pg_get_userbyid(class.relowner)
      into event_table_owner
      from pg_catalog.pg_class class
      where class.oid = 'public.property_events'::regclass;

      if current_user <> event_table_owner then
        raise exception 'La date d’un événement de vente doit être corrigée par le parcours dédié.';
      end if;
    end if;

    if new.amount is null then
      raise exception using errcode = '23514', message = 'Le prix de vente doit être renseigné.';
    end if;

    if new.amount <= 0 then
      raise exception using errcode = '23514', message = 'Le prix de vente doit être strictement positif.';
    end if;

    if new.amount is distinct from old.amount then
      if current_setting('patrigest.sale_price_correction_event_id', true) is distinct from old.id::text then
        raise exception 'Le prix de vente doit être corrigé par le parcours dédié.';
      end if;

      if auth.uid() is null or not public.can_manage_protected_person(old.protected_person_id) then
        raise exception using errcode = '42501', message = 'Droits insuffisants.';
      end if;

      if old.amount is distinct from nullif(
        current_setting('patrigest.sale_price_correction_expected_price', true), ''
      )::numeric then
        raise exception using errcode = '40001', message = 'Le prix de vente a été modifié par une autre opération.';
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

create or replace function public.protect_management_report_refresh_requirement()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  report_table_owner name;
begin
  select pg_catalog.pg_get_userbyid(class.relowner)
  into report_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.management_reports'::regclass;

  if current_user <> report_table_owner
     and new.refresh_required_at is distinct from old.refresh_required_at then
    raise exception using
      errcode = '42501',
      message = 'Le signalement d’actualisation est géré automatiquement.';
  end if;

  if old.status::text = 'generated' and new.status::text = 'finalized'
     and old.refresh_required_at is not null then
    raise exception 'Le compte de gestion doit être actualisé et son projet régénéré avant finalisation.';
  end if;

  if (old.status::text = 'generated' and new.status::text = 'draft')
     or (old.status::text = 'ready' and new.status::text = 'generated') then
    new.refresh_required_at := null;
  end if;

  return new;
end;
$$;

create or replace function public.protect_property_entry_consistency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  entry_event_count bigint;
  entry_event_date date;
  entry_event_type text;
begin
  if (new.entry_date, new.entry_mode) is not distinct from (old.entry_date, old.entry_mode) then
    return new;
  end if;

  select count(*), min(event.event_date), min(event.event_type)
  into entry_event_count, entry_event_date, entry_event_type
  from public.property_events event
  where event.property_id = old.id
    and event.protected_person_id = old.protected_person_id
    and event.event_type in ('acquisition', 'inheritance', 'donation');

  if entry_event_count > 1 then
    raise exception 'Plusieurs événements d’entrée empêchent la modification de la fiche du bien.';
  end if;

  if entry_event_count = 1
     and (new.entry_date is distinct from entry_event_date
          or new.entry_mode is distinct from entry_event_type) then
    raise exception 'La date et le mode d’entrée doivent correspondre à l’événement d’entrée du bien.';
  end if;

  return new;
end;
$$;

create trigger real_estate_properties_protect_entry_consistency
before update on public.real_estate_properties
for each row execute function public.protect_property_entry_consistency();

create trigger management_reports_protect_refresh_requirement
before update on public.management_reports
for each row execute function public.protect_management_report_refresh_requirement();

create or replace function public.correct_property_event(
  p_protected_person_id uuid,
  p_property_id uuid,
  p_event_id uuid,
  p_expected_revision bigint,
  p_event_type text,
  p_event_date date,
  p_description text,
  p_amount numeric,
  p_document_reference text,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_event public.property_events%rowtype;
  new_event public.property_events%rowtype;
  property_row public.real_estate_properties%rowtype;
  entry_event_count bigint;
  sale_event_count bigint;
  sale_event_date date;
  correction_reason text := btrim(p_reason);
  normalized_description text := btrim(p_description);
  normalized_reference text := nullif(btrim(p_document_reference), '');
  old_values jsonb;
  new_values jsonb;
  is_old_entry boolean;
  is_new_entry boolean;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using errcode = '23514', message = 'La révision attendue est invalide.';
  end if;

  if p_event_type is null or p_event_type not in (
    'acquisition', 'sale', 'inheritance', 'donation', 'significant_change'
  ) then
    raise exception using errcode = '23514', message = 'Le type d’événement est invalide.';
  end if;

  if p_event_date is null or normalized_description is null
     or char_length(normalized_description) not between 1 and 2000
     or (normalized_reference is not null and char_length(normalized_reference) > 300)
     or correction_reason is null or char_length(correction_reason) not between 1 and 2000
     or p_amount = 'NaN'::numeric or p_amount < 0
     or p_amount > 9999999999999.99 or p_amount <> round(p_amount, 2) then
    raise exception using errcode = '23514', message = 'Les informations de correction sont invalides.';
  end if;

  select event.*
  into old_event
  from public.property_events event
  where event.id = p_event_id
    and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Événement immobilier introuvable.';
  end if;

  if old_event.revision <> p_expected_revision then
    raise exception using
      errcode = '40001',
      message = 'L’événement a été corrigé par une autre opération.';
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

  is_old_entry := old_event.event_type in ('acquisition', 'inheritance', 'donation');
  is_new_entry := p_event_type in ('acquisition', 'inheritance', 'donation');

  if (old_event.event_type = 'sale') is distinct from (p_event_type = 'sale')
     or is_old_entry is distinct from is_new_entry then
    raise exception using
      errcode = '23514',
      message = 'Cette transition de type d’événement n’est pas autorisée.';
  end if;

  if old_event.event_type = 'sale' then
    if p_amount is distinct from old_event.amount then
      raise exception using
        errcode = '23514',
        message = 'Le prix de vente doit être corrigé par le parcours dédié.';
    end if;

    select count(*)
    into sale_event_count
    from public.property_events event
    where event.property_id = p_property_id
      and event.protected_person_id = p_protected_person_id
      and event.event_type = 'sale';

    if sale_event_count <> 1 then
      raise exception 'La correction exige une unique vente pour ce bien.';
    end if;

    if property_row.status <> 'disposed'
       or property_row.disposal_date is distinct from old_event.event_date then
      raise exception 'Le bien et son événement de vente sont incohérents.';
    end if;

    if p_event_date > current_date then
      raise exception using errcode = '23514', message = 'La date de vente ne peut pas être future.';
    end if;

    if property_row.entry_date is not null and p_event_date < property_row.entry_date then
      raise exception using
        errcode = '23514',
        message = 'La date de vente ne peut pas précéder l’entrée du bien dans le patrimoine.';
    end if;
  end if;

  if is_old_entry then
    select count(*)
    into entry_event_count
    from public.property_events event
    where event.property_id = p_property_id
      and event.protected_person_id = p_protected_person_id
      and event.event_type in ('acquisition', 'inheritance', 'donation');

    if entry_event_count <> 1 then
      raise exception 'Plusieurs événements d’entrée empêchent une correction non ambiguë.';
    end if;

    if property_row.entry_date is distinct from old_event.event_date
       or property_row.entry_mode is distinct from old_event.event_type then
      raise exception 'La fiche du bien et son événement d’entrée sont incohérents.';
    end if;

    select count(*), min(event.event_date)
    into sale_event_count, sale_event_date
    from public.property_events event
    where event.property_id = p_property_id
      and event.protected_person_id = p_protected_person_id
      and event.event_type = 'sale';

    if sale_event_count > 1 then
      raise exception 'Plusieurs ventes historiques empêchent la correction de l’entrée.';
    end if;

    if sale_event_count = 1 and p_event_date > sale_event_date then
      raise exception using
        errcode = '23514',
        message = 'La date d’entrée ne peut pas être postérieure à la vente.';
    end if;
  end if;

  if old_event.event_type is not distinct from p_event_type
     and old_event.event_date is not distinct from p_event_date
     and old_event.description is not distinct from normalized_description
     and old_event.amount is not distinct from p_amount
     and old_event.document_reference is not distinct from normalized_reference then
    raise exception using errcode = '23514', message = 'Aucune modification n’a été détectée.';
  end if;

  old_values := to_jsonb(old_event) || jsonb_build_object(
    'property_entry_date', property_row.entry_date,
    'property_entry_mode', property_row.entry_mode,
    'property_disposal_date', property_row.disposal_date
  );

  update public.property_events
  set event_type = p_event_type,
      event_date = p_event_date,
      description = normalized_description,
      amount = p_amount,
      document_reference = normalized_reference
  where id = old_event.id
    and revision = p_expected_revision
  returning * into new_event;

  if not found then
    raise exception using
      errcode = '40001',
      message = 'L’événement a été corrigé par une autre opération.';
  end if;

  if is_old_entry then
    update public.real_estate_properties
    set entry_date = new_event.event_date,
        entry_mode = new_event.event_type
    where id = property_row.id;

    property_row.entry_date := new_event.event_date;
    property_row.entry_mode := new_event.event_type;
  elsif old_event.event_type = 'sale' then
    update public.real_estate_properties
    set disposal_date = new_event.event_date
    where id = property_row.id;

    property_row.disposal_date := new_event.event_date;
  end if;

  new_values := to_jsonb(new_event) || jsonb_build_object(
    'property_entry_date', property_row.entry_date,
    'property_entry_mode', property_row.entry_mode,
    'property_disposal_date', property_row.disposal_date
  );

  insert into public.property_event_changes (
    property_event_id,
    property_id,
    protected_person_id,
    change_type,
    old_values,
    new_values,
    reason,
    changed_by,
    changed_by_name,
    changed_at
  ) values (
    old_event.id,
    old_event.property_id,
    old_event.protected_person_id,
    case
      when old_event.event_type = 'sale'
           and old_event.event_date is distinct from new_event.event_date
        then 'sale_date_correction'
      else 'correction'
    end,
    old_values,
    new_values,
    correction_reason,
    auth.uid(),
    'Utilisateur PatriGest',
    clock_timestamp()
  );

  update public.management_reports report
  set refresh_required_at = clock_timestamp()
  where report.protected_person_id = old_event.protected_person_id
    and report.status::text = 'generated'
    and (
      old_event.event_date between report.period_start and report.period_end
      or new_event.event_date between report.period_start and report.period_end
      or (
        is_old_entry
        and report.period_end >= least(old_event.event_date, new_event.event_date)
      )
      or (
        old_event.event_type = 'sale'
        and report.period_start <= greatest(old_event.event_date, new_event.event_date)
      )
    );

  return new_event.revision;
end;
$$;

revoke all on function public.correct_property_event(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) from public, anon;
grant execute on function public.correct_property_event(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) to authenticated;

revoke all on function public.protect_management_report_refresh_requirement()
from public, anon, authenticated;
revoke all on function public.protect_property_entry_consistency()
from public, anon, authenticated;
