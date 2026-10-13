alter table public.real_estate_properties
  add column archive_revision bigint not null default 1,
  add column archived_at timestamptz,
  add column archived_by uuid,
  add column archive_reason text,
  add constraint real_estate_properties_archive_revision_positive check (archive_revision > 0),
  add constraint real_estate_properties_archive_consistency check (
    (archived_at is null and archived_by is null and archive_reason is null)
    or (
      archived_at is not null
      and archived_by is not null
      and char_length(btrim(archive_reason)) between 1 and 2000
    )
  );

create table public.property_archive_changes (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.real_estate_properties(id) on delete restrict,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  operation text not null check (operation in ('archive', 'restore')),
  old_values jsonb not null check (jsonb_typeof(old_values) = 'object'),
  new_values jsonb not null check (jsonb_typeof(new_values) = 'object'),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  changed_by uuid not null,
  changed_by_name text not null check (char_length(btrim(changed_by_name)) between 1 and 300),
  changed_at timestamptz not null default now()
);

create index property_archive_changes_property_date_idx
on public.property_archive_changes(property_id, changed_at, id);

alter table public.property_archive_changes enable row level security;
create policy "property_archive_changes_select_accessible"
on public.property_archive_changes for select to authenticated
using (public.can_read_protected_person(protected_person_id));
revoke all on public.property_archive_changes from anon, authenticated;
grant select on public.property_archive_changes to authenticated;

create or replace function public.protect_property_archive_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'Une trace d’archivage immobilier est immuable.';
end;
$$;

create trigger property_archive_changes_immutable
before update or delete on public.property_archive_changes
for each row execute function public.protect_property_archive_change();

create or replace function public.validate_property_archive_change()
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
    raise exception using errcode = '42501', message = 'L’auteur authentifié de la trace est introuvable.';
  end if;
  if not exists (
    select 1 from public.real_estate_properties property
    where property.id = new.property_id
      and property.protected_person_id = new.protected_person_id
  ) then
    raise exception 'La trace ne correspond pas au bien immobilier indiqué.';
  end if;
  select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  into actor_name from public.profiles profile where profile.id = actor_id;
  new.changed_by := actor_id;
  new.changed_by_name := coalesce(actor_name, 'Utilisateur PatriGest');
  return new;
end;
$$;

create trigger property_archive_changes_validate
before insert on public.property_archive_changes
for each row execute function public.validate_property_archive_change();

create or replace function public.protect_property_archive_state()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  property_table_owner name;
  archive_changed boolean;
begin
  select pg_catalog.pg_get_userbyid(class.relowner) into property_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.real_estate_properties'::regclass;

  archive_changed := (new.archived_at, new.archived_by, new.archive_reason)
    is distinct from (old.archived_at, old.archived_by, old.archive_reason);

  if new.archive_revision is distinct from old.archive_revision then
    raise exception 'La révision d’archivage d’un bien immobilier est gérée automatiquement.';
  end if;
  if archive_changed and current_user <> property_table_owner then
    raise exception using errcode = '42501', message = 'L’archivage immobilier nécessite le parcours dédié.';
  end if;
  if old.archived_at is not null and not archive_changed then
    raise exception using errcode = '23514', message = 'Un bien archivé ne peut pas être modifié avant sa restauration.';
  end if;
  if archive_changed then new.archive_revision := old.archive_revision + 1; end if;
  return new;
end;
$$;

create trigger real_estate_properties_protect_archive_state
before update on public.real_estate_properties
for each row execute function public.protect_property_archive_state();

create or replace function public.protect_archived_property_events()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare target_property_id uuid; target_person_id uuid;
begin
  target_property_id := case when tg_op = 'DELETE' then old.property_id else new.property_id end;
  target_person_id := case when tg_op = 'DELETE' then old.protected_person_id else new.protected_person_id end;
  if exists (
    select 1 from public.real_estate_properties property
    where property.id = target_property_id
      and property.protected_person_id = target_person_id
      and property.archived_at is not null
  ) then
    raise exception using errcode = '23514', message = 'Les événements d’un bien archivé ne peuvent pas être modifiés.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger property_events_protect_archived_property
before insert or update or delete on public.property_events
for each row execute function public.protect_archived_property_events();

revoke insert, update on public.real_estate_properties from authenticated;
grant insert (
  id, protected_person_id, property_type, designation, address_line1, address_line2,
  postal_code, city, country, entry_date, entry_mode, estimated_value,
  valuation_date, status, disposal_date, notes, created_at, updated_at
) on public.real_estate_properties to authenticated;
grant update (
  protected_person_id, property_type, designation, address_line1, address_line2, postal_code, city,
  country, entry_date, entry_mode, estimated_value, valuation_date, status,
  disposal_date, notes
) on public.real_estate_properties to authenticated;

create or replace function public.archive_real_estate_property(
  p_protected_person_id uuid,
  p_property_id uuid,
  p_expected_revision bigint,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  property_row public.real_estate_properties%rowtype;
  archived_property public.real_estate_properties%rowtype;
  normalized_reason text := btrim(p_reason);
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using errcode = '23514', message = 'La révision attendue est invalide.';
  end if;
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '23514', message = 'Le motif de l’archivage est obligatoire.';
  end if;
  select property.* into property_row
  from public.real_estate_properties property
  where property.id = p_property_id and property.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.'; end if;
  if property_row.archive_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'Le bien immobilier a été modifié par une autre opération.';
  end if;
  if property_row.archived_at is not null then
    raise exception using errcode = '23514', message = 'Ce bien immobilier est déjà archivé.';
  end if;

  update public.real_estate_properties
  set archived_at = clock_timestamp(), archived_by = auth.uid(), archive_reason = normalized_reason
  where id = property_row.id and archive_revision = p_expected_revision and archived_at is null
  returning * into archived_property;
  if not found then raise exception using errcode = '40001', message = 'Le bien immobilier a été modifié par une autre opération.'; end if;

  insert into public.property_archive_changes(
    property_id,protected_person_id,operation,old_values,new_values,reason,
    changed_by,changed_by_name,changed_at
  ) values (
    property_row.id,property_row.protected_person_id,'archive',to_jsonb(property_row),
    to_jsonb(archived_property),normalized_reason,auth.uid(),'Utilisateur PatriGest',clock_timestamp()
  );

  update public.management_reports report set refresh_required_at = clock_timestamp()
  where report.protected_person_id = property_row.protected_person_id
    and report.status::text = 'generated'
    and (property_row.entry_date is null or property_row.entry_date <= report.period_end)
    and (property_row.disposal_date is null or property_row.disposal_date >= report.period_start);
  return archived_property.archive_revision;
end;
$$;

create or replace function public.restore_real_estate_property(
  p_protected_person_id uuid,
  p_property_id uuid,
  p_expected_revision bigint,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  property_row public.real_estate_properties%rowtype;
  restored_property public.real_estate_properties%rowtype;
  normalized_reason text := btrim(p_reason);
  active_sale_count bigint;
  active_sale_date date;
begin
  if auth.uid() is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Droits insuffisants.';
  end if;
  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using errcode = '23514', message = 'La révision attendue est invalide.';
  end if;
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using errcode = '23514', message = 'Le motif de la restauration est obligatoire.';
  end if;
  select property.* into property_row
  from public.real_estate_properties property
  where property.id = p_property_id and property.protected_person_id = p_protected_person_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Bien immobilier introuvable.'; end if;
  if property_row.archive_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'Le bien immobilier a été modifié par une autre opération.';
  end if;
  if property_row.archived_at is null then
    raise exception using errcode = '23514', message = 'Ce bien immobilier n’est pas archivé.';
  end if;

  select count(*), min(event.event_date) into active_sale_count, active_sale_date
  from public.property_events event
  where event.property_id = property_row.id and event.protected_person_id = property_row.protected_person_id
    and event.event_type = 'sale' and event.cancelled_at is null;
  if property_row.status = 'active'
     and (property_row.disposal_date is not null or active_sale_count <> 0) then
    raise exception 'Le statut actif du bien est incohérent avec son historique de cession.';
  end if;
  if property_row.status = 'disposed'
     and (active_sale_count <> 1 or property_row.disposal_date is distinct from active_sale_date) then
    raise exception 'Le statut cédé du bien est incohérent avec son événement de vente.';
  end if;

  update public.real_estate_properties
  set archived_at = null, archived_by = null, archive_reason = null
  where id = property_row.id and archive_revision = p_expected_revision and archived_at is not null
  returning * into restored_property;
  if not found then raise exception using errcode = '40001', message = 'Le bien immobilier a été modifié par une autre opération.'; end if;

  insert into public.property_archive_changes(
    property_id,protected_person_id,operation,old_values,new_values,reason,
    changed_by,changed_by_name,changed_at
  ) values (
    property_row.id,property_row.protected_person_id,'restore',to_jsonb(property_row),
    to_jsonb(restored_property),normalized_reason,auth.uid(),'Utilisateur PatriGest',clock_timestamp()
  );

  update public.management_reports report set refresh_required_at = clock_timestamp()
  where report.protected_person_id = property_row.protected_person_id
    and report.status::text = 'generated'
    and (property_row.entry_date is null or property_row.entry_date <= report.period_end)
    and (property_row.disposal_date is null or property_row.disposal_date >= report.period_start);
  return restored_property.archive_revision;
end;
$$;

revoke all on function public.archive_real_estate_property(uuid,uuid,bigint,text) from public,anon;
revoke all on function public.restore_real_estate_property(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.archive_real_estate_property(uuid,uuid,bigint,text) to authenticated;
grant execute on function public.restore_real_estate_property(uuid,uuid,bigint,text) to authenticated;
revoke all on function public.protect_property_archive_change() from public,anon,authenticated;
revoke all on function public.validate_property_archive_change() from public,anon,authenticated;
revoke all on function public.protect_property_archive_state() from public,anon,authenticated;
revoke all on function public.protect_archived_property_events() from public,anon,authenticated;

comment on table public.property_archive_changes is
  'Journal append-only des archivages et restaurations de biens immobiliers.';
comment on column public.real_estate_properties.archived_at is
  'État technique indépendant du statut métier. Non nul : bien exclu des lectures courantes.';
