-- PAT-DOSSIERS-ARCHIVAGE-01B-2A
-- Fondation transactionnelle du cycle de vie des dossiers. La lecture seule
-- globale des dossiers archivés sera activée dans un lot ultérieur.

alter table public.protected_persons
  add column archive_revision bigint not null default 1,
  add constraint protected_persons_archive_revision_positive
    check (archive_revision > 0);

create table public.protected_person_archive_changes (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null
    references public.protected_persons(id) on delete restrict,
  old_status text not null check (old_status in ('active', 'archived')),
  new_status text not null check (new_status in ('active', 'archived')),
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default clock_timestamp(),
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  constraint protected_person_archive_changes_transition_check check (
    (old_status = 'active' and new_status = 'archived')
    or (old_status = 'archived' and new_status = 'active')
  )
);

create index protected_person_archive_changes_person_date_idx
on public.protected_person_archive_changes(protected_person_id, changed_at, id);

alter table public.protected_person_archive_changes enable row level security;

create policy "protected_person_archive_changes_select_accessible"
on public.protected_person_archive_changes
for select to authenticated
using (public.can_read_protected_person(protected_person_id));

revoke all on table public.protected_person_archive_changes
from public, anon, authenticated, service_role;
grant select on table public.protected_person_archive_changes to authenticated;

create function public.protect_protected_person_archive_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  history_table_owner name;
begin
  select pg_catalog.pg_get_userbyid(class.relowner)
  into history_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.protected_person_archive_changes'::regclass;

  if current_user <> history_table_owner then
    raise exception using
      errcode = '42501',
      message = 'L’historique d’archivage des dossiers est immuable.';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger protected_person_archive_changes_immutable
before update or delete on public.protected_person_archive_changes
for each row execute function public.protect_protected_person_archive_change();

create function public.validate_protected_person_archive_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise exception using
      errcode = 'P4A01',
      message = 'Accès à la transition du dossier refusé.';
  end if;

  if not exists (
    select 1
    from public.protected_persons person
    where person.id = new.protected_person_id
      and person.status = new.new_status
  ) then
    raise exception using
      errcode = '23514',
      message = 'La trace ne correspond pas à l’état courant du dossier.';
  end if;

  new.changed_by := actor_id;
  new.changed_at := clock_timestamp();
  new.reason := btrim(new.reason);
  return new;
end;
$$;

create trigger protected_person_archive_changes_validate
before insert on public.protected_person_archive_changes
for each row execute function public.validate_protected_person_archive_change();

create function public.protect_protected_person_archive_state()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  person_table_owner name;
  lifecycle_changed boolean;
begin
  select pg_catalog.pg_get_userbyid(class.relowner)
  into person_table_owner
  from pg_catalog.pg_class class
  where class.oid = 'public.protected_persons'::regclass;

  if tg_op = 'INSERT' then
    if current_user <> person_table_owner
       and (new.status <> 'active'
            or new.archived_at is not null
            or new.archive_revision <> 1) then
      raise exception using
        errcode = '42501',
        message = 'Le cycle de vie du dossier nécessite le parcours dédié.';
    end if;
    return new;
  end if;

  lifecycle_changed := (new.status, new.archived_at)
    is distinct from (old.status, old.archived_at);

  if new.archive_revision is distinct from old.archive_revision then
    raise exception using
      errcode = '42501',
      message = 'La révision d’archivage du dossier est gérée automatiquement.';
  end if;

  if lifecycle_changed and current_user <> person_table_owner then
    raise exception using
      errcode = '42501',
      message = 'Le cycle de vie du dossier nécessite le parcours dédié.';
  end if;

  if lifecycle_changed then
    new.archive_revision := old.archive_revision + 1;
  end if;

  return new;
end;
$$;

create trigger protected_persons_protect_archive_state
before insert or update on public.protected_persons
for each row execute function public.protect_protected_person_archive_state();

create function public.archive_protected_person(
  p_protected_person_id uuid,
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
  dossier_owner_id uuid;
  person_row public.protected_persons%rowtype;
  archived_person public.protected_persons%rowtype;
  normalized_reason text := btrim(p_reason);
begin
  if caller_id is null
     or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using
      errcode = 'P4A01',
      message = 'Accès à la transition du dossier refusé.';
  end if;

  if normalized_reason is null
     or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using
      errcode = 'P4A03',
      message = 'Le motif de l’archivage est invalide.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  select person.owner_id
  into dossier_owner_id
  from public.protected_persons person
  where person.id = p_protected_person_id;

  if not found then
    raise exception using
      errcode = 'P4A02',
      message = 'Dossier introuvable.';
  end if;

  if dossier_owner_id <> caller_id then
    raise exception using
      errcode = 'P4A01',
      message = 'Accès à la transition du dossier refusé.';
  end if;

  perform public.lock_owner_dossier_capacity(dossier_owner_id);

  select person.*
  into person_row
  from public.protected_persons person
  where person.id = p_protected_person_id
  for update;

  if person_row.archive_revision <> p_expected_revision then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  if person_row.status <> 'active' or person_row.archived_at is not null then
    raise exception using
      errcode = 'P4A04',
      message = 'Le dossier ne peut pas être archivé dans son état actuel.';
  end if;

  update public.protected_persons
  set status = 'archived', archived_at = clock_timestamp()
  where id = person_row.id
    and status = 'active'
    and archived_at is null
    and archive_revision = p_expected_revision
  returning * into archived_person;

  if not found then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  insert into public.protected_person_archive_changes(
    protected_person_id, old_status, new_status, changed_by, changed_at, reason
  ) values (
    person_row.id, person_row.status, archived_person.status,
    caller_id, clock_timestamp(), normalized_reason
  );

  return archived_person.archive_revision;
end;
$$;

create function public.restore_protected_person(
  p_protected_person_id uuid,
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
  dossier_owner_id uuid;
  person_row public.protected_persons%rowtype;
  restored_person public.protected_persons%rowtype;
  normalized_reason text := btrim(p_reason);
begin
  if caller_id is null
     or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using
      errcode = 'P4A01',
      message = 'Accès à la transition du dossier refusé.';
  end if;

  if normalized_reason is null
     or char_length(normalized_reason) not between 1 and 2000 then
    raise exception using
      errcode = 'P4A03',
      message = 'Le motif de la restauration est invalide.';
  end if;

  if p_expected_revision is null or p_expected_revision <= 0 then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  select person.owner_id
  into dossier_owner_id
  from public.protected_persons person
  where person.id = p_protected_person_id;

  if not found then
    raise exception using
      errcode = 'P4A02',
      message = 'Dossier introuvable.';
  end if;

  if dossier_owner_id <> caller_id then
    raise exception using
      errcode = 'P4A01',
      message = 'Accès à la transition du dossier refusé.';
  end if;

  perform public.lock_owner_dossier_capacity(dossier_owner_id);

  select person.*
  into person_row
  from public.protected_persons person
  where person.id = p_protected_person_id
  for update;

  if person_row.archive_revision <> p_expected_revision then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  if person_row.status <> 'archived' or person_row.archived_at is null then
    raise exception using
      errcode = 'P4A04',
      message = 'Le dossier ne peut pas être restauré dans son état actuel.';
  end if;

  update public.protected_persons
  set status = 'active', archived_at = null
  where id = person_row.id
    and status = 'archived'
    and archived_at is not null
    and archive_revision = p_expected_revision
  returning * into restored_person;

  if not found then
    raise exception using
      errcode = 'P4A05',
      message = 'La révision du dossier est obsolète.';
  end if;

  insert into public.protected_person_archive_changes(
    protected_person_id, old_status, new_status, changed_by, changed_at, reason
  ) values (
    person_row.id, person_row.status, restored_person.status,
    caller_id, clock_timestamp(), normalized_reason
  );

  return restored_person.archive_revision;
end;
$$;

-- La suppression contrôlée d’un dossier vide reste possible, quel que soit
-- son statut. Son journal de cycle de vie est supprimé dans la même transaction.
create or replace function public.delete_empty_protected_person(
  p_protected_person_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select owner_id
  into v_owner_id
  from public.protected_persons
  where id = p_protected_person_id
    and owner_id = auth.uid()
  for update;

  if v_owner_id is null then
    raise exception 'Dossier introuvable ou suppression non autorisée.';
  end if;

  if exists (select 1 from public.financial_accounts where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.protection_measures where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.management_periods where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.protected_person_access where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.protected_person_invitations where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.transfers where protected_person_id = p_protected_person_id)
     or exists (select 1 from public.proof_reference_assignments where protected_person_id = p_protected_person_id) then
    raise exception 'Ce dossier ne peut pas être supprimé tant qu''il contient des comptes ou d''autres données associées.';
  end if;

  delete from public.protected_person_archive_changes
  where protected_person_id = p_protected_person_id;

  delete from public.proof_reference_counters
  where protected_person_id = p_protected_person_id;

  delete from public.protected_persons
  where id = p_protected_person_id;
end;
$$;

revoke all on function public.archive_protected_person(uuid,bigint,text)
from public, anon, authenticated, service_role;
revoke all on function public.restore_protected_person(uuid,bigint,text)
from public, anon, authenticated, service_role;
revoke all on function public.protect_protected_person_archive_change()
from public, anon, authenticated, service_role;
revoke all on function public.validate_protected_person_archive_change()
from public, anon, authenticated, service_role;
revoke all on function public.protect_protected_person_archive_state()
from public, anon, authenticated, service_role;

grant execute on function public.archive_protected_person(uuid,bigint,text)
to authenticated;
grant execute on function public.restore_protected_person(uuid,bigint,text)
to authenticated;

comment on table public.protected_person_archive_changes is
  'Journal append-only des archivages et restaurations de dossiers.';
comment on column public.protected_persons.archive_revision is
  'Révision optimiste du cycle de vie, incrémentée par les RPC dédiées.';
comment on function public.archive_protected_person(uuid,bigint,text) is
  'Archive atomiquement un dossier possédé. Codes : P4A01 accès, P4A02 introuvable, P4A03 motif, P4A04 état, P4A05 révision ; P4D01/P4D02/P4D03 quotas.';
comment on function public.restore_protected_person(uuid,bigint,text) is
  'Restaure atomiquement un dossier possédé. Codes : P4A01 accès, P4A02 introuvable, P4A03 motif, P4A04 état, P4A05 révision ; P4D01/P4D02/P4D03 quotas.';
