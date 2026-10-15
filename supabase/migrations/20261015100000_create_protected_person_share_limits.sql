-- PAT-PARTAGE-01B-1
-- Centralise les limites de partage et sérialise toutes les mutations qui
-- modifient l'occupation d'un dossier.

alter table public.protected_person_invitations
  add column declined_at timestamptz,
  add column declined_by uuid references auth.users(id) on delete set null;

alter table public.protected_person_invitations
  drop constraint protected_person_invitations_not_accepted_and_revoked;

alter table public.protected_person_invitations
  add constraint protected_person_invitations_single_terminal_state
  check (num_nonnulls(accepted_at, revoked_at, declined_at) <= 1),
  add constraint protected_person_invitations_decliner_requires_decline
  check (declined_by is null or declined_at is not null);

drop index public.protected_person_invitations_active_email_idx;

create unique index protected_person_invitations_active_email_idx
on public.protected_person_invitations (protected_person_id, lower(trim(email)))
where accepted_at is null and revoked_at is null and declined_at is null;

create table public.protected_person_share_limit_configuration (
  configuration_key text primary key,
  manager_limit smallint not null check (manager_limit > 0),
  read_only_limit smallint not null check (read_only_limit > 0),
  updated_at timestamptz not null default now(),
  constraint protected_person_share_limit_configuration_singleton
    check (configuration_key = 'default')
);

insert into public.protected_person_share_limit_configuration (
  configuration_key,
  manager_limit,
  read_only_limit
) values ('default', 5, 5);

alter table public.protected_person_share_limit_configuration enable row level security;

revoke all on table public.protected_person_share_limit_configuration
from public, anon, authenticated, service_role;

create or replace function public.get_protected_person_share_occupancy(
  p_protected_person_id uuid
)
returns table (
  share_role text,
  role_limit integer,
  active_access_count bigint,
  pending_invitation_count bigint,
  used_count bigint,
  remaining_count bigint,
  exceeded_by bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with configured_roles as (
    select
      'manager'::text as share_role,
      configuration.manager_limit::integer as role_limit
    from public.protected_person_share_limit_configuration configuration
    where configuration.configuration_key = 'default'
    union all
    select
      'read_only'::text,
      configuration.read_only_limit::integer
    from public.protected_person_share_limit_configuration configuration
    where configuration.configuration_key = 'default'
  ),
  access_counts as (
    select access.role as share_role, count(*)::bigint as access_count
    from public.protected_person_access access
    where access.protected_person_id = p_protected_person_id
    group by access.role
  ),
  pending_counts as (
    select invitation.role as share_role, count(*)::bigint as invitation_count
    from public.protected_person_invitations invitation
    where invitation.protected_person_id = p_protected_person_id
      and invitation.accepted_at is null
      and invitation.revoked_at is null
      and invitation.declined_at is null
      and invitation.expires_at > now()
      and not exists (
        select 1
        from auth.users users
        join public.protected_person_access access
          on access.user_id = users.id
         and access.protected_person_id = invitation.protected_person_id
        where lower(trim(coalesce(users.email, ''))) = lower(trim(invitation.email))
      )
    group by invitation.role
  ),
  occupation as (
    select
      roles.share_role,
      roles.role_limit,
      coalesce(accesses.access_count, 0::bigint) as active_access_count,
      coalesce(invitations.invitation_count, 0::bigint) as pending_invitation_count
    from configured_roles roles
    left join access_counts accesses using (share_role)
    left join pending_counts invitations using (share_role)
  )
  select
    occupation.share_role,
    occupation.role_limit,
    occupation.active_access_count,
    occupation.pending_invitation_count,
    occupation.active_access_count + occupation.pending_invitation_count as used_count,
    greatest(
      occupation.role_limit::bigint
        - occupation.active_access_count
        - occupation.pending_invitation_count,
      0::bigint
    ) as remaining_count,
    greatest(
      occupation.active_access_count
        + occupation.pending_invitation_count
        - occupation.role_limit::bigint,
      0::bigint
    ) as exceeded_by
  from occupation
  order by case occupation.share_role when 'manager' then 1 else 2 end
$$;

create or replace function public.lock_protected_person_sharing(
  p_protected_person_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.protected_persons person
  where person.id = p_protected_person_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Dossier introuvable.';
  end if;
end;
$$;

create or replace function public.assert_protected_person_share_capacity(
  p_protected_person_id uuid,
  p_role text,
  p_additional_slots integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  occupancy record;
begin
  if p_role not in ('manager', 'read_only') then
    raise exception using errcode = '23514', message = 'Rôle invalide.';
  end if;
  if p_additional_slots is null or p_additional_slots < 0 then
    raise exception using errcode = '23514', message = 'Variation de quota invalide.';
  end if;

  select * into occupancy
  from public.get_protected_person_share_occupancy(p_protected_person_id) current_occupancy
  where current_occupancy.share_role = p_role;

  if not found then
    raise exception using errcode = '23514', message = 'Configuration des limites indisponible.';
  end if;

  if p_additional_slots > 0
     and occupancy.used_count + p_additional_slots > occupancy.role_limit then
    raise exception using
      errcode = '23514',
      message = case p_role
        when 'manager' then 'La limite de gestionnaires partagés est atteinte.'
        else 'La limite de collaborateurs en lecture seule est atteinte.'
      end;
  end if;
end;
$$;

create or replace function public.email_has_protected_person_access(
  p_protected_person_id uuid,
  p_email text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users users
    join public.protected_person_access access
      on access.user_id = users.id
    where access.protected_person_id = p_protected_person_id
      and lower(trim(coalesce(users.email, ''))) = lower(trim(coalesce(p_email, '')))
  )
$$;

create or replace function public.get_protected_person_share_capacity(
  p_protected_person_id uuid
)
returns table (
  share_role text,
  role_limit integer,
  active_access_count bigint,
  pending_invitation_count bigint,
  used_count bigint,
  remaining_count bigint,
  exceeded_by bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentification requise.';
  end if;
  if not public.is_protected_person_owner(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Accès propriétaire requis.';
  end if;

  return query
  select occupancy.*
  from public.get_protected_person_share_occupancy(p_protected_person_id) occupancy;
end;
$$;

create or replace function public.issue_protected_person_invitation(
  p_protected_person_id uuid,
  p_email text,
  p_role text,
  p_token_hash text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(p_email));
  invitation_id uuid;
  caller_is_owner boolean;
  active_invitation public.protected_person_invitations%rowtype;
  active_invitation_found boolean;
  additional_slots integer := 1;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not public.is_application_user_active() then raise exception 'Compte utilisateur inactif.'; end if;
  if not public.can_manage_protected_person(p_protected_person_id) then raise exception 'Dossier introuvable.'; end if;

  if p_role not in ('manager', 'read_only') then raise exception 'Rôle invalide.'; end if;
  if normalized_email is null
     or normalized_email = ''
     or length(normalized_email) > 320
     or normalized_email ~ '[[:space:]]'
     or normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'Adresse email invalide.';
  end if;
  if p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'Jeton invalide.'; end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '8 days' then raise exception 'Expiration invalide.'; end if;

  perform public.lock_protected_person_sharing(p_protected_person_id);

  select exists (
    select 1 from public.protected_persons
    where id = p_protected_person_id and owner_id = auth.uid()
  ) into caller_is_owner;

  if not caller_is_owner then
    perform 1
    from public.protected_person_access
    where protected_person_id = p_protected_person_id
      and user_id = auth.uid()
      and role = 'manager'
    for update;

    if not found then raise exception 'Dossier introuvable.'; end if;
    if p_role <> 'read_only' then raise exception 'Un gestionnaire ne peut inviter qu''en lecture seule.'; end if;
  end if;

  if public.email_has_protected_person_access(p_protected_person_id, normalized_email) then
    raise exception using errcode = '23505', message = 'Cette personne dispose déjà d''un accès au dossier.';
  end if;

  select * into active_invitation
  from public.protected_person_invitations
  where protected_person_id = p_protected_person_id
    and lower(trim(email)) = normalized_email
    and accepted_at is null
    and revoked_at is null
    and declined_at is null
  for update;
  active_invitation_found := found;

  if not caller_is_owner
     and active_invitation_found
     and (active_invitation.role <> 'read_only'
          or active_invitation.invited_by is distinct from auth.uid()) then
    raise exception 'Cette invitation est gérée par un autre responsable du dossier.';
  end if;

  if active_invitation_found
     and active_invitation.expires_at > now()
     and active_invitation.role = p_role then
    additional_slots := 0;
  end if;

  perform public.assert_protected_person_share_capacity(
    p_protected_person_id,
    p_role,
    additional_slots
  );

  update public.protected_person_invitations
  set revoked_at = now()
  where protected_person_id = p_protected_person_id
    and lower(trim(email)) = normalized_email
    and accepted_at is null
    and revoked_at is null
    and declined_at is null;

  insert into public.protected_person_invitations (
    protected_person_id, email, role, token_hash, expires_at, invited_by
  ) values (
    p_protected_person_id, normalized_email, p_role, p_token_hash, p_expires_at, auth.uid()
  ) returning id into invitation_id;

  return invitation_id;
end;
$$;

create or replace function public.reissue_protected_person_invitation(
  p_invitation_id uuid,
  p_token_hash text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_protected_person_id uuid;
  source_normalized_email text;
  source_invitation public.protected_person_invitations%rowtype;
  invitation_id uuid;
  caller_is_owner boolean;
  additional_slots integer := 1;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not public.is_application_user_active() then raise exception 'Compte utilisateur inactif.'; end if;

  select protected_person_id, lower(trim(email))
  into source_protected_person_id, source_normalized_email
  from public.protected_person_invitations
  where id = p_invitation_id;

  if not found or not public.can_manage_protected_person(source_protected_person_id) then
    raise exception 'Invitation indisponible.';
  end if;

  perform public.lock_protected_person_sharing(source_protected_person_id);

  select * into source_invitation
  from public.protected_person_invitations
  where id = p_invitation_id
  for update;

  if not found
     or source_invitation.protected_person_id <> source_protected_person_id
     or lower(trim(source_invitation.email)) <> source_normalized_email
     or source_invitation.accepted_at is not null
     or source_invitation.revoked_at is not null
     or source_invitation.declined_at is not null then
    raise exception 'Invitation indisponible.';
  end if;

  select exists (
    select 1 from public.protected_persons
    where id = source_protected_person_id and owner_id = auth.uid()
  ) into caller_is_owner;

  if not caller_is_owner then
    perform 1
    from public.protected_person_access
    where protected_person_id = source_protected_person_id
      and user_id = auth.uid()
      and role = 'manager'
    for update;

    if not found
       or source_invitation.role <> 'read_only'
       or source_invitation.invited_by is distinct from auth.uid() then
      raise exception 'Invitation indisponible.';
    end if;
  end if;

  if public.email_has_protected_person_access(source_protected_person_id, source_normalized_email) then
    raise exception using errcode = '23505', message = 'Cette personne dispose déjà d''un accès au dossier.';
  end if;
  if p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'Jeton invalide.'; end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '8 days' then raise exception 'Expiration invalide.'; end if;

  if source_invitation.expires_at > now() then additional_slots := 0; end if;
  perform public.assert_protected_person_share_capacity(
    source_protected_person_id,
    source_invitation.role,
    additional_slots
  );

  update public.protected_person_invitations
  set revoked_at = now()
  where protected_person_id = source_protected_person_id
    and lower(trim(email)) = source_normalized_email
    and accepted_at is null
    and revoked_at is null
    and declined_at is null;

  insert into public.protected_person_invitations (
    protected_person_id, email, role, token_hash, expires_at, invited_by
  ) values (
    source_protected_person_id,
    source_normalized_email,
    source_invitation.role,
    p_token_hash,
    p_expires_at,
    auth.uid()
  ) returning id into invitation_id;

  return invitation_id;
end;
$$;

create or replace function public.revoke_protected_person_invitation(
  p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_protected_person_id uuid;
  invitation public.protected_person_invitations%rowtype;
  caller_is_owner boolean;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not public.is_application_user_active() then raise exception 'Compte utilisateur inactif.'; end if;

  select protected_person_id into invitation_protected_person_id
  from public.protected_person_invitations
  where id = p_invitation_id;

  if not found or not public.can_manage_protected_person(invitation_protected_person_id) then
    raise exception 'Invitation indisponible.';
  end if;

  perform public.lock_protected_person_sharing(invitation_protected_person_id);

  select * into invitation
  from public.protected_person_invitations
  where id = p_invitation_id
  for update;

  if not found
     or invitation.protected_person_id <> invitation_protected_person_id
     or invitation.accepted_at is not null
     or invitation.revoked_at is not null
     or invitation.declined_at is not null then
    raise exception 'Invitation indisponible.';
  end if;

  select exists (
    select 1 from public.protected_persons
    where id = invitation_protected_person_id and owner_id = auth.uid()
  ) into caller_is_owner;

  if not caller_is_owner then
    perform 1
    from public.protected_person_access
    where protected_person_id = invitation_protected_person_id
      and user_id = auth.uid()
      and role = 'manager'
    for update;

    if not found
       or invitation.role <> 'read_only'
       or invitation.invited_by is distinct from auth.uid() then
      raise exception 'Invitation indisponible.';
    end if;
  end if;

  update public.protected_person_invitations
  set revoked_at = now()
  where id = invitation.id;
end;
$$;

create or replace function public.accept_protected_person_invitation(
  p_token_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_id uuid;
  invitation_protected_person_id uuid;
  invitation_normalized_email text;
  invitation public.protected_person_invitations%rowtype;
  caller_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;

  select id, protected_person_id, lower(trim(email))
  into invitation_id, invitation_protected_person_id, invitation_normalized_email
  from public.protected_person_invitations
  where token_hash = p_token_hash
    and accepted_at is null
    and revoked_at is null
    and declined_at is null
    and expires_at > now();

  if not found then raise exception 'Invitation invalide ou expirée.'; end if;

  perform public.lock_protected_person_sharing(invitation_protected_person_id);

  select * into invitation
  from public.protected_person_invitations
  where id = invitation_id
    and token_hash = p_token_hash
    and accepted_at is null
    and revoked_at is null
    and declined_at is null
    and expires_at > now()
  for update;

  if not found
     or invitation.protected_person_id <> invitation_protected_person_id
     or lower(trim(invitation.email)) <> invitation_normalized_email
     or invitation_normalized_email <> caller_email then
    raise exception 'Invitation invalide ou expirée.';
  end if;

  update public.application_user_authorizations
  set status = 'active',
      status_changed_at = now(),
      status_changed_by = invitation.invited_by
  where user_id = auth.uid()
    and status = 'pending';

  if not found and not public.is_application_user_active() then
    raise exception 'Autorisation utilisateur indisponible.';
  end if;

  update public.protected_person_invitations
  set accepted_at = now()
  where id = invitation.id;

  insert into public.protected_person_access(protected_person_id, user_id, role, invited_by)
  values (invitation.protected_person_id, auth.uid(), invitation.role, invitation.invited_by)
  on conflict (protected_person_id, user_id) do nothing;

  return invitation.protected_person_id;
end;
$$;

create or replace function public.decline_protected_person_invitation(
  p_token_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_id uuid;
  invitation_protected_person_id uuid;
  invitation_normalized_email text;
  invitation public.protected_person_invitations%rowtype;
  caller_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentification requise.';
  end if;

  select id, protected_person_id, lower(trim(email))
  into invitation_id, invitation_protected_person_id, invitation_normalized_email
  from public.protected_person_invitations
  where token_hash = p_token_hash
    and accepted_at is null
    and revoked_at is null
    and declined_at is null
    and expires_at > now();

  if not found then raise exception 'Invitation invalide ou expirée.'; end if;

  perform public.lock_protected_person_sharing(invitation_protected_person_id);

  select * into invitation
  from public.protected_person_invitations
  where id = invitation_id
    and token_hash = p_token_hash
    and accepted_at is null
    and revoked_at is null
    and declined_at is null
    and expires_at > now()
  for update;

  if not found
     or invitation.protected_person_id <> invitation_protected_person_id
     or lower(trim(invitation.email)) <> invitation_normalized_email
     or invitation_normalized_email <> caller_email then
    raise exception 'Invitation invalide ou expirée.';
  end if;

  update public.protected_person_invitations
  set declined_at = now(), declined_by = auth.uid()
  where id = invitation.id;

  return invitation.protected_person_id;
end;
$$;

create or replace function public.change_protected_person_access_role(
  p_protected_person_id uuid,
  p_access_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  access_row public.protected_person_access%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not public.is_application_user_active() then raise exception 'Compte utilisateur inactif.'; end if;
  if not public.is_protected_person_owner(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Accès propriétaire requis.';
  end if;
  if p_role not in ('manager', 'read_only') then
    raise exception using errcode = '23514', message = 'Rôle invalide.';
  end if;

  perform public.lock_protected_person_sharing(p_protected_person_id);

  if not public.is_protected_person_owner(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Accès propriétaire requis.';
  end if;

  select * into access_row
  from public.protected_person_access
  where id = p_access_id
    and protected_person_id = p_protected_person_id
  for update;

  if not found then raise exception 'Accès collaborateur introuvable.'; end if;
  if access_row.role = p_role then return; end if;

  perform public.assert_protected_person_share_capacity(
    p_protected_person_id,
    p_role,
    1
  );

  update public.protected_person_access
  set role = p_role
  where id = access_row.id
    and protected_person_id = p_protected_person_id;

  update public.protected_person_invitations invitation
  set revoked_at = now()
  where invitation.protected_person_id = p_protected_person_id
    and invitation.accepted_at is null
    and invitation.revoked_at is null
    and invitation.declined_at is null
    and invitation.expires_at > now()
    and exists (
      select 1 from auth.users users
      where users.id = access_row.user_id
        and lower(trim(coalesce(users.email, ''))) = lower(trim(invitation.email))
    );
end;
$$;

create or replace function public.remove_protected_person_access(
  p_protected_person_id uuid,
  p_access_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  access_row public.protected_person_access%rowtype;
  deleted_count integer;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not public.is_application_user_active() then raise exception 'Compte utilisateur inactif.'; end if;
  if not public.is_protected_person_owner(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Accès propriétaire requis.';
  end if;

  perform public.lock_protected_person_sharing(p_protected_person_id);

  if not public.is_protected_person_owner(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Accès propriétaire requis.';
  end if;

  select * into access_row
  from public.protected_person_access
  where id = p_access_id
    and protected_person_id = p_protected_person_id
  for update;

  if not found then raise exception 'Accès collaborateur introuvable.'; end if;

  update public.protected_person_invitations invitation
  set revoked_at = now()
  where invitation.protected_person_id = p_protected_person_id
    and invitation.accepted_at is null
    and invitation.revoked_at is null
    and invitation.declined_at is null
    and invitation.expires_at > now()
    and exists (
      select 1 from auth.users users
      where users.id = access_row.user_id
        and lower(trim(coalesce(users.email, ''))) = lower(trim(invitation.email))
    );

  delete from public.protected_person_access
  where id = access_row.id
    and protected_person_id = p_protected_person_id;

  get diagnostics deleted_count = row_count;
  if deleted_count <> 1 then raise exception 'Impossible de retirer cet accès.'; end if;
end;
$$;

-- Une invitation refusée ne réserve plus une adresse e-mail PatriGest.
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
      and invitations.declined_at is null
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
     or new.declined_at is not null
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

  if tg_op = 'INSERT' then new.email := normalized_email; end if;
  return new;
end;
$$;

drop trigger protected_person_invitations_enforce_email_reservation
on public.protected_person_invitations;

create trigger protected_person_invitations_enforce_email_reservation
before insert or update of email, accepted_at, revoked_at, declined_at, expires_at
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
      and invitations.declined_at is null
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

revoke update on public.protected_person_access from authenticated;

grant select (declined_at, declined_by)
on public.protected_person_invitations to authenticated;

revoke all on function public.get_protected_person_share_occupancy(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.lock_protected_person_sharing(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.assert_protected_person_share_capacity(uuid, text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.email_has_protected_person_access(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_protected_person_share_capacity(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.issue_protected_person_invitation(uuid, text, text, text, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.reissue_protected_person_invitation(uuid, text, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_protected_person_invitation(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.accept_protected_person_invitation(text)
from public, anon, authenticated, service_role;
revoke all on function public.decline_protected_person_invitation(text)
from public, anon, authenticated, service_role;
revoke all on function public.change_protected_person_access_role(uuid, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.remove_protected_person_access(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_protected_person_share_capacity(uuid) to authenticated;
grant execute on function public.issue_protected_person_invitation(uuid, text, text, text, timestamptz) to authenticated;
grant execute on function public.reissue_protected_person_invitation(uuid, text, timestamptz) to authenticated;
grant execute on function public.revoke_protected_person_invitation(uuid) to authenticated;
grant execute on function public.accept_protected_person_invitation(text) to authenticated;
grant execute on function public.decline_protected_person_invitation(text) to authenticated;
grant execute on function public.change_protected_person_access_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_protected_person_access(uuid, uuid) to authenticated;
