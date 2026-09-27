create or replace function public.lock_patrigest_email(p_email text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(coalesce(p_email, '')));
begin
  if normalized_email = ''
     or length(normalized_email) > 320
     or normalized_email ~ '[[:space:]]'
     or normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'Adresse e-mail invalide.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('patrigest-email:' || normalized_email, 0)
  );

  return normalized_email;
end;
$$;

create or replace function public.assert_email_change_target_available(
  p_user_id uuid,
  p_new_email text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text;
begin
  normalized_email := public.lock_patrigest_email(p_new_email);

  if exists (
    select 1
    from auth.users users
    where users.id is distinct from p_user_id
      and (
        lower(trim(coalesce(users.email, ''))) = normalized_email
        or lower(trim(coalesce(users.email_change, ''))) = normalized_email
      )
  ) or exists (
    select 1
    from public.protected_person_invitations invitations
    where lower(trim(invitations.email)) = normalized_email
      and invitations.accepted_at is null
      and invitations.revoked_at is null
      and invitations.expires_at > now()
  ) or exists (
    select 1
    from public.account_requests requests
    where lower(trim(requests.email)) = normalized_email
      and (
        requests.status = 'pending'
        or (
          requests.status = 'approved'
          and requests.invitation_used_at is null
          and requests.invitation_expires_at > now()
        )
      )
  ) then
    raise exception 'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.';
  end if;
end;
$$;

create or replace function public.check_own_email_change_availability(p_new_email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentification requise.';
  end if;

  perform public.assert_email_change_target_available(auth.uid(), p_new_email);
  return true;
end;
$$;

create or replace function public.enforce_auth_user_email_change_exclusivity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_email text;
begin
  if new.email_change is distinct from old.email_change
     and trim(coalesce(new.email_change, '')) <> '' then
    target_email := new.email_change;
  elsif new.email is distinct from old.email
        and trim(coalesce(new.email, '')) <> '' then
    target_email := new.email;
  end if;

  if target_email is not null then
    perform public.assert_email_change_target_available(new.id, target_email);
  end if;

  return new;
end;
$$;

create trigger auth_users_enforce_email_change_exclusivity
before update of email, email_change on auth.users
for each row execute function public.enforce_auth_user_email_change_exclusivity();

create or replace function public.enforce_active_invitation_email_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text;
begin
  if new.accepted_at is not null
     or new.revoked_at is not null
     or new.expires_at <= now() then
    return new;
  end if;

  normalized_email := public.lock_patrigest_email(new.email);

  if exists (
    select 1
    from auth.users users
    where lower(trim(coalesce(users.email_change, ''))) = normalized_email
  ) or exists (
    select 1
    from public.account_requests requests
    where lower(trim(requests.email)) = normalized_email
      and (
        requests.status = 'pending'
        or (
          requests.status = 'approved'
          and requests.invitation_used_at is null
          and requests.invitation_expires_at > now()
        )
      )
  ) then
    raise exception 'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.';
  end if;

  if tg_op = 'INSERT' then
    new.email := normalized_email;
  end if;
  return new;
end;
$$;

create trigger protected_person_invitations_enforce_email_reservation
before insert or update of email, accepted_at, revoked_at, expires_at
on public.protected_person_invitations
for each row execute function public.enforce_active_invitation_email_reservation();

create or replace function public.enforce_active_account_request_email_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text;
begin
  if not (
    new.status = 'pending'
    or (
      new.status = 'approved'
      and new.invitation_used_at is null
      and new.invitation_expires_at > now()
    )
  ) then
    return new;
  end if;

  normalized_email := public.lock_patrigest_email(new.email);

  if exists (
    select 1
    from auth.users users
    where lower(trim(coalesce(users.email, ''))) = normalized_email
       or lower(trim(coalesce(users.email_change, ''))) = normalized_email
  ) or exists (
    select 1
    from public.protected_person_invitations invitations
    where lower(trim(invitations.email)) = normalized_email
      and invitations.accepted_at is null
      and invitations.revoked_at is null
      and invitations.expires_at > now()
  ) or exists (
    select 1
    from public.account_requests requests
    where requests.id is distinct from new.id
      and lower(trim(requests.email)) = normalized_email
      and (
        requests.status = 'pending'
        or (
          requests.status = 'approved'
          and requests.invitation_used_at is null
          and requests.invitation_expires_at > now()
        )
      )
  ) then
    raise exception 'Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.';
  end if;

  new.email := normalized_email;
  return new;
end;
$$;

create trigger account_requests_enforce_email_reservation
before insert or update of email, status, invitation_used_at, invitation_expires_at
on public.account_requests
for each row execute function public.enforce_active_account_request_email_reservation();

do $$
begin
  if exists (
    select 1
    from auth.users users
    where trim(coalesce(users.email_change, '')) <> ''
      and (
        exists (
          select 1
          from auth.users other_users
          where other_users.id is distinct from users.id
            and (
              lower(trim(coalesce(other_users.email, ''))) = lower(trim(users.email_change))
              or lower(trim(coalesce(other_users.email_change, ''))) = lower(trim(users.email_change))
            )
        )
        or exists (
          select 1
          from public.protected_person_invitations invitations
          where lower(trim(invitations.email)) = lower(trim(users.email_change))
            and invitations.accepted_at is null
            and invitations.revoked_at is null
            and invitations.expires_at > now()
        )
        or exists (
          select 1
          from public.account_requests requests
          where lower(trim(requests.email)) = lower(trim(users.email_change))
            and (
              requests.status = 'pending'
              or (
                requests.status = 'approved'
                and requests.invitation_used_at is null
                and requests.invitation_expires_at > now()
              )
            )
        )
      )
  ) then
    raise exception 'Migration impossible : un changement d’adresse en attente entre en collision avec une adresse active.';
  end if;

  if exists (
    select 1
    from public.protected_person_invitations invitations
    join public.account_requests requests
      on lower(trim(requests.email)) = lower(trim(invitations.email))
    where invitations.accepted_at is null
      and invitations.revoked_at is null
      and invitations.expires_at > now()
      and (
        requests.status = 'pending'
        or (
          requests.status = 'approved'
          and requests.invitation_used_at is null
          and requests.invitation_expires_at > now()
        )
      )
  ) then
    raise exception 'Migration impossible : une adresse possède plusieurs réservations métier actives.';
  end if;
end;
$$;

revoke all on function public.lock_patrigest_email(text)
from public, anon, authenticated, service_role;
revoke all on function public.assert_email_change_target_available(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.check_own_email_change_availability(text)
from public, anon, authenticated, service_role;
revoke all on function public.enforce_auth_user_email_change_exclusivity()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_active_invitation_email_reservation()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_active_account_request_email_reservation()
from public, anon, authenticated, service_role;

grant execute on function public.check_own_email_change_availability(text)
to authenticated;
