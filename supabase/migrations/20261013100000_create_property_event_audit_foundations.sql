alter table public.property_events
  add column revision bigint not null default 1,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid,
  add column cancellation_reason text,
  add constraint property_events_revision_positive check (revision > 0),
  add constraint property_events_cancellation_consistency check (
    (cancelled_at is null and cancelled_by is null and cancellation_reason is null)
    or (
      cancelled_at is not null
      and cancelled_by is not null
      and char_length(btrim(cancellation_reason)) between 1 and 2000
    )
  ),
  add constraint property_events_sale_price_positive check (
    event_type <> 'sale' or (amount is not null and amount > 0)
  );

create table public.property_event_changes (
  id uuid primary key default gen_random_uuid(),
  property_event_id uuid not null references public.property_events(id) on delete restrict,
  property_id uuid not null references public.real_estate_properties(id) on delete restrict,
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  change_type text not null check (
    change_type in ('correction', 'sale_date_correction', 'cancellation', 'restoration')
  ),
  old_values jsonb not null check (jsonb_typeof(old_values) = 'object'),
  new_values jsonb not null check (jsonb_typeof(new_values) = 'object'),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  changed_by uuid not null,
  changed_by_name text not null check (char_length(btrim(changed_by_name)) between 1 and 300),
  changed_at timestamptz not null default now()
);

create index property_event_changes_event_date_idx
on public.property_event_changes(property_event_id, changed_at, id);

create index property_event_changes_property_date_idx
on public.property_event_changes(property_id, changed_at, id);

alter table public.property_event_changes enable row level security;

create policy "property_event_changes_select_accessible"
on public.property_event_changes
for select to authenticated
using (public.can_read_protected_person(protected_person_id));

revoke all on public.property_event_changes from anon, authenticated;
grant select on public.property_event_changes to authenticated;

create or replace function public.prevent_property_event_change_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'Une trace de modification d’événement immobilier est immuable.';
end;
$$;

create trigger property_event_changes_immutable
before update or delete on public.property_event_changes
for each row execute function public.prevent_property_event_change_mutation();

create or replace function public.validate_property_event_change_links()
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
    select 1
    from public.property_events event
    where event.id = new.property_event_id
      and event.property_id = new.property_id
      and event.protected_person_id = new.protected_person_id
  ) then
    raise exception 'La trace ne correspond pas à l’événement immobilier indiqué.';
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

create trigger property_event_changes_validate_links
before insert on public.property_event_changes
for each row execute function public.validate_property_event_change_links();

create or replace function public.protect_closed_period_property_event()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  closed_period_message constant text :=
    'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.';
begin
  if tg_op in ('UPDATE', 'DELETE') and exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = old.protected_person_id
      and period.status = 'closed'
      and old.event_date between period.start_date and period.end_date
  ) then
    raise exception '%', closed_period_message;
  end if;

  if tg_op in ('INSERT', 'UPDATE') and exists (
    select 1
    from public.management_periods period
    where period.protected_person_id = new.protected_person_id
      and period.status = 'closed'
      and new.event_date between period.start_date and period.end_date
  ) then
    raise exception '%', closed_period_message;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger property_events_protect_closed_period
before insert or update or delete on public.property_events
for each row execute function public.protect_closed_period_property_event();

create or replace function public.protect_property_event_lifecycle_foundations()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
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

create trigger property_events_protect_lifecycle_foundations
before insert or update on public.property_events
for each row execute function public.protect_property_event_lifecycle_foundations();

-- Les utilisateurs conservent uniquement les colonnes déjà modifiables. Les
-- fondations de révision et d'annulation restent inaccessibles jusqu'au lot 3B-2.
revoke update on public.property_events from authenticated;
revoke insert on public.property_events from authenticated;
grant insert (
  id,
  property_id,
  protected_person_id,
  event_type,
  event_date,
  description,
  amount,
  document_reference,
  created_at
) on public.property_events to authenticated;
grant update (
  event_type,
  event_date,
  description,
  amount,
  document_reference
) on public.property_events to authenticated;
revoke delete on public.property_events from authenticated;

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

  if new.amount <= 0 then
    raise exception using
      errcode = '23514',
      message = 'Le prix de vente doit être strictement positif.';
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

revoke all on function public.prevent_property_event_change_mutation() from public, anon, authenticated;
revoke all on function public.validate_property_event_change_links() from public, anon, authenticated;
revoke all on function public.protect_closed_period_property_event() from public, anon, authenticated;
revoke all on function public.protect_property_event_lifecycle_foundations() from public, anon, authenticated;

comment on table public.property_event_changes is
  'Journal append-only préparé pour les futures corrections, annulations et restaurations d’événements immobiliers.';

comment on column public.property_events.revision is
  'Révision technique incrémentée automatiquement à chaque modification réussie.';

comment on column public.property_events.cancelled_at is
  'Fondation inactive en 3B-1. L’activation métier de l’annulation logique appartient au lot 3B-2.';

-- Stratégie 3B-2 : les événements d'entrée (acquisition, inheritance,
-- donation) restent indépendants de entry_date et entry_mode. Une future
-- correction devra arbitrer explicitement la source de vérité et ne doit pas
-- modifier automatiquement ces champs dans cette migration de fondation.
