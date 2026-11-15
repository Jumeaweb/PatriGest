-- PAT-INVITATIONS-01
-- Un titulaire autonome peut collaborer sur d'autres dossiers, mais le
-- propriétaire d'un dossier ne doit jamais pouvoir s'inviter lui-même.

create function public.prevent_protected_person_owner_self_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_invitation_email text := lower(trim(coalesce(new.email, '')));
begin
  if exists (
    select 1
    from public.protected_persons person
    join auth.users owner_user on owner_user.id = person.owner_id
    where person.id = new.protected_person_id
      and lower(trim(coalesce(owner_user.email, ''))) = normalized_invitation_email
  ) then
    raise exception using
      errcode = 'P4I01',
      message = 'Le propriétaire du dossier ne peut pas être invité comme collaborateur.';
  end if;

  return new;
end;
$$;

create trigger protected_person_invitations_prevent_owner_self_invitation
before insert or update of protected_person_id, email
on public.protected_person_invitations
for each row execute function public.prevent_protected_person_owner_self_invitation();

revoke all on function public.prevent_protected_person_owner_self_invitation()
from public, anon, authenticated, service_role;

comment on function public.prevent_protected_person_owner_self_invitation() is
  'Refuse uniquement une invitation adressée au propriétaire du dossier concerné, après normalisation de l''adresse.';
