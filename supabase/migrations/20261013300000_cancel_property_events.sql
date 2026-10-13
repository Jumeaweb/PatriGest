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
    if new.cancelled_at is not null or new.cancelled_by is not null or new.cancellation_reason is not null then
      raise exception 'Un nouvel événement immobilier ne peut pas être créé comme annulé.';
    end if;
    return new;
  end if;

  select pg_catalog.pg_get_userbyid(class.relowner)
  into event_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.property_events'::regclass;

  authorized_sale_price_update := coalesce(
    old.event_type = 'sale' and new.event_type = 'sale'
    and new.amount is distinct from old.amount
    and new.event_date is not distinct from old.event_date
    and new.description is not distinct from old.description
    and new.document_reference is not distinct from old.document_reference
    and new.property_id = old.property_id
    and new.protected_person_id = old.protected_person_id
    and new.created_at = old.created_at
    and new.revision = old.revision
    and old.cancelled_at is null and new.cancelled_at is null
    and current_setting('patrigest.sale_price_correction_event_id', true) = old.id::text,
    false
  );

  if current_user <> event_table_owner and not authorized_sale_price_update then
    raise exception using errcode = '42501', message = 'La correction d’un événement immobilier doit utiliser le parcours dédié.';
  end if;
  if old.cancelled_at is not null then
    raise exception using errcode = '23514', message = 'Un événement annulé ne peut plus être modifié.';
  end if;
  if new.revision is distinct from old.revision then
    raise exception 'La révision d’un événement immobilier est gérée automatiquement.';
  end if;
  if current_user <> event_table_owner
     and (new.cancelled_at, new.cancelled_by, new.cancellation_reason)
       is distinct from (old.cancelled_at, old.cancelled_by, old.cancellation_reason) then
    raise exception 'L’annulation d’un événement immobilier nécessite le parcours dédié.';
  end if;
  new.revision := old.revision + 1;
  return new;
end;
$$;

create or replace function public.synchronize_property_sale()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  property_row public.real_estate_properties%rowtype;
begin
  if new.event_type <> 'sale' then return new; end if;
  select property.* into property_row
  from public.real_estate_properties property
  where property.id = new.property_id and property.protected_person_id = new.protected_person_id
  for update;
  if not found then return new; end if;
  if exists (
    select 1 from public.property_events event
    where event.property_id = new.property_id and event.event_type = 'sale' and event.cancelled_at is null
  ) then
    raise exception using errcode = '23505', message = 'Une vente est déjà enregistrée pour ce bien.';
  end if;
  if property_row.status <> 'active' then raise exception 'Seul un bien actif peut être vendu.'; end if;
  if new.amount is null then
    raise exception using errcode = '23514', message = 'Le prix de vente doit être renseigné.';
  end if;
  if new.amount <= 0 then
    raise exception using errcode = '23514', message = 'Le prix de vente doit être strictement positif.';
  end if;
  if property_row.entry_date is not null and new.event_date < property_row.entry_date then
    raise exception 'La date de vente ne peut pas précéder l’entrée du bien dans le patrimoine.';
  end if;
  if new.event_date > current_date then raise exception 'La date de vente ne peut pas être future.'; end if;
  update public.real_estate_properties set status = 'disposed', disposal_date = new.event_date where id = property_row.id;
  if not found then raise exception 'La fiche immobilière n’a pas pu être synchronisée.'; end if;
  return new;
end;
$$;

create or replace function public.protect_sold_property_consistency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare sale_count bigint; sale_date date;
begin
  if (new.status, new.disposal_date) is not distinct from (old.status, old.disposal_date) then return new; end if;
  select count(*), min(event.event_date) into sale_count, sale_date
  from public.property_events event
  where event.property_id = old.id and event.event_type = 'sale' and event.cancelled_at is null;
  if sale_count = 0 then return new; end if;
  if sale_count > 1 then raise exception 'Plusieurs ventes actives empêchent la modification du statut de ce bien.'; end if;
  if new.status <> 'disposed' or new.disposal_date is distinct from sale_date then
    raise exception 'Le statut et la date de cession doivent correspondre à l’événement de vente.';
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
declare entry_event_count bigint; entry_event_date date; entry_event_type text;
begin
  if (new.entry_date, new.entry_mode) is not distinct from (old.entry_date, old.entry_mode) then return new; end if;
  select count(*), min(event.event_date), min(event.event_type)
  into entry_event_count, entry_event_date, entry_event_type
  from public.property_events event
  where event.property_id = old.id and event.protected_person_id = old.protected_person_id
    and event.event_type in ('acquisition', 'inheritance', 'donation') and event.cancelled_at is null;
  if entry_event_count > 1 then raise exception 'Plusieurs événements d’entrée empêchent la modification de la fiche du bien.'; end if;
  if entry_event_count = 1 and (new.entry_date is distinct from entry_event_date or new.entry_mode is distinct from entry_event_type) then
    raise exception 'La date et le mode d’entrée doivent correspondre à l’événement d’entrée du bien.';
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
      select pg_catalog.pg_get_userbyid(class.relowner) into event_table_owner
      from pg_catalog.pg_class class where class.oid = 'public.property_events'::regclass;
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
      if old.amount is distinct from nullif(current_setting('patrigest.sale_price_correction_expected_price', true), '')::numeric then
        raise exception using errcode = '40001', message = 'Le prix de vente a été modifié par une autre opération.';
      end if;
      correction_reason := btrim(current_setting('patrigest.sale_price_correction_reason', true));
      if correction_reason is null or char_length(correction_reason) not between 1 and 2000 then
        raise exception using errcode = '23514', message = 'Le motif de la correction est obligatoire.';
      end if;
      select count(*) into sale_count
      from public.property_events event
      where event.property_id = old.property_id
        and event.protected_person_id = old.protected_person_id
        and event.event_type = 'sale' and event.cancelled_at is null;
      if sale_count <> 1 then raise exception 'La correction exige une unique vente pour ce bien.'; end if;
      if exists (
        select 1 from public.management_periods period
        where period.protected_person_id = old.protected_person_id and period.status = 'closed'
          and old.event_date between period.start_date and period.end_date
      ) then raise exception 'Cette vente appartient à un exercice clôturé.'; end if;
      if not exists (
        select 1 from public.real_estate_properties property
        where property.id = old.property_id and property.protected_person_id = old.protected_person_id
          and property.status = 'disposed' and property.disposal_date is not distinct from old.event_date
      ) then raise exception 'Le bien et son événement de vente sont incohérents.'; end if;
    end if;
  end if;
  return new;
end;
$$;

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
  select event.* into sale_row
  from public.property_events event
  where event.id = p_event_id and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
    and event.event_type = 'sale' and event.cancelled_at is null
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Événement de vente actif introuvable.'; end if;
  select count(*) into sale_count
  from public.property_events event
  where event.property_id = p_property_id and event.protected_person_id = p_protected_person_id
    and event.event_type = 'sale' and event.cancelled_at is null;
  if sale_count <> 1 then raise exception 'La correction exige une unique vente pour ce bien.'; end if;
  if exists (
    select 1 from public.management_periods period
    where period.protected_person_id = p_protected_person_id and period.status = 'closed'
      and sale_row.event_date between period.start_date and period.end_date
  ) then raise exception 'Cette vente appartient à un exercice clôturé.'; end if;
  if sale_row.amount is distinct from p_expected_price then
    raise exception using errcode = '40001', message = 'Le prix de vente a été modifié par une autre opération.';
  end if;
  if sale_row.amount is not distinct from p_new_price then
    raise exception using errcode = '23514', message = 'Le nouveau prix doit être différent du prix actuel.';
  end if;
  select property.* into property_row
  from public.real_estate_properties property
  where property.id = p_property_id and property.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.'; end if;
  if property_row.status <> 'disposed' or property_row.disposal_date is distinct from sale_row.event_date then
    raise exception 'Le bien et son événement de vente sont incohérents.';
  end if;
  perform set_config('patrigest.sale_price_correction_id', correction_id::text, true);
  perform set_config('patrigest.sale_price_correction_event_id', sale_row.id::text, true);
  perform set_config('patrigest.sale_price_correction_expected_price', p_expected_price::text, true);
  perform set_config('patrigest.sale_price_correction_reason', correction_reason, true);
  update public.property_events set amount = p_new_price
  where id = sale_row.id and property_id = sale_row.property_id
    and protected_person_id = sale_row.protected_person_id and event_type = 'sale'
    and cancelled_at is null and amount is not distinct from p_expected_price;
  get diagnostics updated_event_count = row_count;
  if updated_event_count <> 1 then
    raise exception using errcode = '40001', message = 'Le prix de vente a été modifié par une autre opération.';
  end if;
  if not exists (
    select 1 from public.property_sale_price_corrections correction
    where correction.id = correction_id and correction.property_event_id = sale_row.id
      and correction.old_price is not distinct from p_expected_price
      and correction.new_price is not distinct from p_new_price and correction.corrected_by = auth.uid()
  ) then raise exception 'La trace de correction n’a pas été enregistrée.'; end if;
  perform set_config('patrigest.sale_price_correction_id', '', true);
  perform set_config('patrigest.sale_price_correction_event_id', '', true);
  perform set_config('patrigest.sale_price_correction_expected_price', '', true);
  perform set_config('patrigest.sale_price_correction_reason', '', true);
  return correction_id;
end;
$$;

alter function public.correct_property_event(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) rename to correct_property_event_before_cancellation;

revoke all on function public.correct_property_event_before_cancellation(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) from public, anon, authenticated;

create function public.correct_property_event(
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
  active_sale_count bigint;
  correction_reason text := btrim(p_reason);
  normalized_description text := btrim(p_description);
  normalized_reference text := nullif(btrim(p_document_reference), '');
  old_values jsonb;
  new_values jsonb;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  select event.* into old_event
  from public.property_events event
  where event.id = p_event_id and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id;

  if not found or old_event.event_type <> 'sale' or not exists (
    select 1 from public.property_events historical_sale
    where historical_sale.property_id = p_property_id
      and historical_sale.protected_person_id = p_protected_person_id
      and historical_sale.event_type = 'sale' and historical_sale.cancelled_at is not null
  ) then
    return public.correct_property_event_before_cancellation(
      p_protected_person_id, p_property_id, p_event_id, p_expected_revision,
      p_event_type, p_event_date, p_description, p_amount, p_document_reference, p_reason
    );
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using errcode = '23514', message = 'La révision attendue est invalide.';
  end if;
  if p_event_type <> 'sale' then
    raise exception using errcode = '23514', message = 'Cette transition de type d’événement n’est pas autorisée.';
  end if;
  if p_event_date is null or normalized_description is null
     or char_length(normalized_description) not between 1 and 2000
     or (normalized_reference is not null and char_length(normalized_reference) > 300)
     or correction_reason is null or char_length(correction_reason) not between 1 and 2000
     or p_amount = 'NaN'::numeric or p_amount < 0
     or p_amount > 9999999999999.99 or p_amount <> round(p_amount, 2) then
    raise exception using errcode = '23514', message = 'Les informations de correction sont invalides.';
  end if;

  select event.* into old_event
  from public.property_events event
  where event.id = p_event_id and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
  for update;
  if old_event.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'L’événement a été corrigé par une autre opération.';
  end if;
  if old_event.cancelled_at is not null then
    raise exception using errcode = '23514', message = 'Un événement annulé ne peut plus être modifié.';
  end if;
  if p_amount is distinct from old_event.amount then
    raise exception using errcode = '23514', message = 'Le prix de vente doit être corrigé par le parcours dédié.';
  end if;

  select property.* into property_row
  from public.real_estate_properties property
  where property.id = p_property_id and property.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.'; end if;
  select count(*) into active_sale_count
  from public.property_events event
  where event.property_id = p_property_id and event.protected_person_id = p_protected_person_id
    and event.event_type = 'sale' and event.cancelled_at is null;
  if active_sale_count <> 1 then raise exception 'La correction exige une unique vente pour ce bien.'; end if;
  if property_row.status <> 'disposed' or property_row.disposal_date is distinct from old_event.event_date then
    raise exception 'Le bien et son événement de vente sont incohérents.';
  end if;
  if p_event_date > current_date then raise exception using errcode = '23514', message = 'La date de vente ne peut pas être future.'; end if;
  if property_row.entry_date is not null and p_event_date < property_row.entry_date then
    raise exception using errcode = '23514', message = 'La date de vente ne peut pas précéder l’entrée du bien dans le patrimoine.';
  end if;
  if old_event.event_date is not distinct from p_event_date
     and old_event.description is not distinct from normalized_description
     and old_event.document_reference is not distinct from normalized_reference then
    raise exception using errcode = '23514', message = 'Aucune modification n’a été détectée.';
  end if;

  old_values := to_jsonb(old_event) || jsonb_build_object(
    'property_entry_date', property_row.entry_date, 'property_entry_mode', property_row.entry_mode,
    'property_disposal_date', property_row.disposal_date
  );
  update public.property_events
  set event_date = p_event_date, description = normalized_description, document_reference = normalized_reference
  where id = old_event.id and revision = p_expected_revision and cancelled_at is null
  returning * into new_event;
  if not found then raise exception using errcode = '40001', message = 'L’événement a été corrigé par une autre opération.'; end if;
  update public.real_estate_properties set disposal_date = new_event.event_date where id = property_row.id;
  property_row.disposal_date := new_event.event_date;
  new_values := to_jsonb(new_event) || jsonb_build_object(
    'property_entry_date', property_row.entry_date, 'property_entry_mode', property_row.entry_mode,
    'property_disposal_date', property_row.disposal_date
  );
  insert into public.property_event_changes(
    property_event_id,property_id,protected_person_id,change_type,old_values,new_values,
    reason,changed_by,changed_by_name,changed_at
  ) values (
    old_event.id,old_event.property_id,old_event.protected_person_id,
    case when old_event.event_date is distinct from new_event.event_date then 'sale_date_correction' else 'correction' end,
    old_values,new_values,correction_reason,auth.uid(),'Utilisateur PatriGest',clock_timestamp()
  );
  update public.management_reports report set refresh_required_at=clock_timestamp()
  where report.protected_person_id=old_event.protected_person_id and report.status::text='generated'
    and (old_event.event_date between report.period_start and report.period_end
      or new_event.event_date between report.period_start and report.period_end
      or report.period_start <= greatest(old_event.event_date,new_event.event_date));
  return new_event.revision;
end;
$$;

revoke all on function public.correct_property_event(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) from public, anon;
grant execute on function public.correct_property_event(
  uuid, uuid, uuid, bigint, text, date, text, numeric, text, text
) to authenticated;

create or replace function public.cancel_property_event(
  p_protected_person_id uuid,
  p_property_id uuid,
  p_event_id uuid,
  p_expected_revision bigint,
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
  normalized_reason text := btrim(p_reason);
  active_sale_count bigint;
  old_values jsonb;
  new_values jsonb;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using errcode = '23514', message = 'La révision attendue est invalide.';
  end if;
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '23514', message = 'Le motif de l’annulation est obligatoire.';
  end if;

  select event.* into old_event
  from public.property_events event
  where event.id = p_event_id and event.property_id = p_property_id
    and event.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Événement immobilier introuvable.'; end if;
  if old_event.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'L’événement a été modifié par une autre opération.';
  end if;
  if old_event.cancelled_at is not null then
    raise exception using errcode = '23514', message = 'Cet événement est déjà annulé.';
  end if;

  select property.* into property_row
  from public.real_estate_properties property
  where property.id = p_property_id and property.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.'; end if;

  if old_event.event_type in ('acquisition', 'inheritance', 'donation') then
    raise exception using errcode = '23514',
      message = 'L’annulation d’un événement d’entrée nécessite de définir une origine patrimoniale de remplacement.';
  end if;

  if old_event.event_type = 'sale' then
    select count(*) into active_sale_count
    from public.property_events event
    where event.property_id = p_property_id and event.protected_person_id = p_protected_person_id
      and event.event_type = 'sale' and event.cancelled_at is null;
    if active_sale_count <> 1 or property_row.status <> 'disposed'
       or property_row.disposal_date is distinct from old_event.event_date then
      raise exception 'Le bien et sa vente active sont incohérents. L’annulation est refusée.';
    end if;
  end if;

  old_values := to_jsonb(old_event) || jsonb_build_object(
    'property_status', property_row.status,
    'property_disposal_date', property_row.disposal_date,
    'property_entry_date', property_row.entry_date,
    'property_entry_mode', property_row.entry_mode
  );

  update public.property_events
  set cancelled_at = clock_timestamp(), cancelled_by = auth.uid(), cancellation_reason = normalized_reason
  where id = old_event.id and revision = p_expected_revision and cancelled_at is null
  returning * into new_event;
  if not found then raise exception using errcode = '40001', message = 'L’événement a été modifié par une autre opération.'; end if;

  if old_event.event_type = 'sale' then
    update public.real_estate_properties set status = 'active', disposal_date = null where id = property_row.id;
    property_row.status := 'active';
    property_row.disposal_date := null;
  end if;

  new_values := to_jsonb(new_event) || jsonb_build_object(
    'property_status', property_row.status,
    'property_disposal_date', property_row.disposal_date,
    'property_entry_date', property_row.entry_date,
    'property_entry_mode', property_row.entry_mode
  );
  insert into public.property_event_changes (
    property_event_id, property_id, protected_person_id, change_type,
    old_values, new_values, reason, changed_by, changed_by_name, changed_at
  ) values (
    old_event.id, old_event.property_id, old_event.protected_person_id, 'cancellation',
    old_values, new_values, normalized_reason, auth.uid(), 'Utilisateur PatriGest', clock_timestamp()
  );

  update public.management_reports report set refresh_required_at = clock_timestamp()
  where report.protected_person_id = old_event.protected_person_id
    and report.status::text = 'generated'
    and (
      old_event.event_date between report.period_start and report.period_end
      or (old_event.event_type = 'sale' and report.period_end >= old_event.event_date)
    );
  return new_event.revision;
end;
$$;

revoke all on function public.cancel_property_event(uuid, uuid, uuid, bigint, text) from public, anon;
grant execute on function public.cancel_property_event(uuid, uuid, uuid, bigint, text) to authenticated;

comment on function public.cancel_property_event(uuid, uuid, uuid, bigint, text) is
  'Annule atomiquement un événement immobilier, journalise l’opération et synchronise les effets courants déterministes.';
