-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-2
-- Applique le cycle de vie des dossiers aux invitations et accès partagés.
-- Les réductions de droits restent possibles sur un dossier archivé.

create function public.lock_protected_person_sharing_lifecycle(
  p_protected_person_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  dossier_status text;
begin
  if p_protected_person_id is null then
    return null;
  end if;

  -- Le verrou est compatible avec les autres lectures métier mais se
  -- sérialise avec archive_protected_person/restore_protected_person et avec
  -- le verrou FOR UPDATE déjà pris par les RPC de partage.
  select person.status
  into dossier_status
  from public.protected_persons person
  where person.id = p_protected_person_id
  for key share;

  return dossier_status;
end;
$$;

create function public.enforce_archived_protected_person_access_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  dossier_status text;
  downgrade_allowed boolean := false;
begin
  if tg_op = 'UPDATE'
     and new.protected_person_id is distinct from old.protected_person_id then
    -- Conserve la protection d’identité historique et évite de verrouiller
    -- deux dossiers dans un ordre dépendant de la requête.
    return new;
  end if;

  dossier_status := public.lock_protected_person_sharing_lifecycle(
    case when tg_op = 'INSERT'
      then new.protected_person_id
      else old.protected_person_id
    end
  );

  if dossier_status is distinct from 'archived' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if tg_op = 'UPDATE' then
    downgrade_allowed :=
      old.role = 'manager'
      and new.role = 'read_only'
      and (to_jsonb(new) - array['role', 'updated_at'])
        is not distinct from
          (to_jsonb(old) - array['role', 'updated_at']);

    if downgrade_allowed then
      return new;
    end if;
  end if;

  perform public.assert_protected_person_active_for_write(
    case when tg_op = 'INSERT'
      then new.protected_person_id
      else old.protected_person_id
    end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function public.enforce_archived_protected_person_invitation_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  dossier_status text;
  revocation_allowed boolean := false;
  decline_allowed boolean := false;
begin
  if tg_op = 'UPDATE'
     and new.protected_person_id is distinct from old.protected_person_id then
    -- La garde d’identité existante reste responsable de ce refus absolu.
    return new;
  end if;

  dossier_status := public.lock_protected_person_sharing_lifecycle(
    case when tg_op = 'INSERT'
      then new.protected_person_id
      else old.protected_person_id
    end
  );

  if dossier_status is distinct from 'archived' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if tg_op = 'UPDATE' then
    revocation_allowed :=
      old.accepted_at is null
      and old.revoked_at is null
      and old.declined_at is null
      and new.accepted_at is null
      and new.revoked_at is not null
      and new.declined_at is null
      and (to_jsonb(new) - 'revoked_at')
        is not distinct from (to_jsonb(old) - 'revoked_at');

    decline_allowed :=
      old.accepted_at is null
      and old.revoked_at is null
      and old.declined_at is null
      and new.accepted_at is null
      and new.revoked_at is null
      and new.declined_at is not null
      and (to_jsonb(new) - array['declined_at', 'declined_by'])
        is not distinct from
          (to_jsonb(old) - array['declined_at', 'declined_by']);

    if revocation_allowed or decline_allowed then
      return new;
    end if;
  end if;

  perform public.assert_protected_person_active_for_write(
    case when tg_op = 'INSERT'
      then new.protected_person_id
      else old.protected_person_id
    end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger protected_person_access_00_enforce_archive_lifecycle
before insert or update or delete on public.protected_person_access
for each row execute function public.enforce_archived_protected_person_access_write();

create trigger protected_person_invitations_00_enforce_archive_lifecycle
before insert or update or delete on public.protected_person_invitations
for each row execute function public.enforce_archived_protected_person_invitation_write();

revoke all on function public.lock_protected_person_sharing_lifecycle(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.enforce_archived_protected_person_access_write()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_archived_protected_person_invitation_write()
from public, anon, authenticated, service_role;

comment on function public.lock_protected_person_sharing_lifecycle(uuid) is
  'Sérialise une mutation de partage avec le cycle de vie du dossier.';
comment on function public.enforce_archived_protected_person_access_write() is
  'Sur archive, autorise seulement le retrait d’un accès ou sa rétrogradation.';
comment on function public.enforce_archived_protected_person_invitation_write() is
  'Sur archive, autorise seulement le refus, la révocation ou la suppression d’une invitation.';
