alter table public.application_user_authorizations
  add column account_mode text
  check (account_mode in ('autonomous', 'collaborator'));

do $$
begin
  if exists (
    select 1
    from auth.users users
    where exists (
      select 1 from public.protected_persons persons
      where persons.owner_id = users.id
    )
    and exists (
      select 1 from public.protected_person_access access
      where access.user_id = users.id
    )
  ) then
    raise exception 'Migration impossible : au moins un utilisateur est simultanément propriétaire et collaborateur.';
  end if;
end;
$$;

update public.application_user_authorizations as user_authorization
set account_mode = 'autonomous'
where exists (
  select 1 from public.protected_persons persons
  where persons.owner_id = user_authorization.user_id
);

update public.application_user_authorizations as user_authorization
set account_mode = 'collaborator'
where exists (
  select 1 from public.protected_person_access access
  where access.user_id = user_authorization.user_id
)
and not exists (
  select 1 from public.protected_persons persons
  where persons.owner_id = user_authorization.user_id
);

do $$
begin
  if exists (
    select 1
    from public.protected_persons persons
    left join public.application_user_authorizations user_authorization
      on user_authorization.user_id = persons.owner_id
    where user_authorization.account_mode is distinct from 'autonomous'
  ) or exists (
    select 1
    from public.protected_person_access access
    left join public.application_user_authorizations user_authorization
      on user_authorization.user_id = access.user_id
    where user_authorization.account_mode is distinct from 'collaborator'
  ) then
    raise exception 'Migration impossible : le mode de certains comptes métier reste incohérent.';
  end if;
end;
$$;

create or replace function public.claim_application_user_account_mode(
  p_user_id uuid,
  p_account_mode text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_mode text;
begin
  if p_account_mode not in ('autonomous', 'collaborator') then
    raise exception 'Mode de compte invalide.';
  end if;

  if exists (
    select 1 from public.platform_administrators administrators
    where administrators.user_id = p_user_id
  ) then
    raise exception 'Un administrateur de plateforme ne peut pas utiliser les fonctions métier.';
  end if;

  select user_authorization.account_mode
  into current_mode
  from public.application_user_authorizations user_authorization
  where user_authorization.user_id = p_user_id
  for update;

  if not found then
    raise exception 'Autorisation utilisateur introuvable.';
  end if;

  if current_mode is null then
    update public.application_user_authorizations
    set account_mode = p_account_mode
    where user_id = p_user_id;
  elsif current_mode is distinct from p_account_mode then
    if current_mode = 'autonomous' then
      raise exception 'Un compte autonome ne peut pas devenir collaborateur.';
    end if;
    raise exception 'Un compte collaborateur ne peut pas créer ou posséder de dossier.';
  end if;
end;
$$;

create or replace function public.enforce_protected_person_owner_account_mode()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.claim_application_user_account_mode(new.owner_id, 'autonomous');
  return new;
end;
$$;

create trigger protected_persons_enforce_owner_account_mode
before insert or update of owner_id on public.protected_persons
for each row execute function public.enforce_protected_person_owner_account_mode();

create or replace function public.enforce_protected_person_access_account_mode()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.claim_application_user_account_mode(new.user_id, 'collaborator');
  return new;
end;
$$;

create trigger protected_person_access_enforce_account_mode
before insert or update of user_id on public.protected_person_access
for each row execute function public.enforce_protected_person_access_account_mode();

create or replace function public.reject_autonomous_protected_person_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(new.email));
begin
  if exists (
    select 1
    from auth.users users
    join public.application_user_authorizations user_authorization
      on user_authorization.user_id = users.id
    where lower(trim(users.email)) = normalized_email
      and user_authorization.account_mode = 'autonomous'
  ) then
    raise exception 'Un compte autonome ne peut pas être invité comme collaborateur.';
  end if;

  if tg_op = 'INSERT' then
    new.email := normalized_email;
  end if;
  return new;
end;
$$;

create trigger protected_person_invitations_reject_autonomous_account
before insert or update of email on public.protected_person_invitations
for each row execute function public.reject_autonomous_protected_person_invitation();

revoke all on function public.claim_application_user_account_mode(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.enforce_protected_person_owner_account_mode()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_protected_person_access_account_mode()
from public, anon, authenticated, service_role;
revoke all on function public.reject_autonomous_protected_person_invitation()
from public, anon, authenticated, service_role;

grant select (account_mode)
on public.application_user_authorizations
to authenticated;
