-- PAT-VERSION-093C
-- Restaure l'exclusivite stricte entre comptes autonomes et collaborateurs.
-- Cette migration refuse de s'appliquer si des donnees existantes necessitent
-- une decision humaine ; elle ne regularise ni ne supprime aucune donnee.

do $$
begin
  if exists (
    select 1
    from public.application_user_authorizations user_authorization
    join public.protected_person_access access
      on access.user_id = user_authorization.user_id
    where user_authorization.account_mode = 'autonomous'
  ) or exists (
    select 1
    from public.application_user_authorizations user_authorization
    join public.protected_persons person
      on person.owner_id = user_authorization.user_id
    where user_authorization.account_mode = 'collaborator'
  ) then
    raise exception using
      errcode = 'P4M10',
      message = 'Migration impossible : un compte utilise deja les deux modes metier.';
  end if;

  if exists (
    select 1
    from public.application_user_authorizations user_authorization
    where (user_authorization.account_mode = 'autonomous'
           and user_authorization.registration_intent = 'collaborator')
       or (user_authorization.account_mode = 'collaborator'
           and user_authorization.registration_intent = 'autonomous')
  ) then
    raise exception using
      errcode = 'P4M11',
      message = 'Migration impossible : le mode et l intention d inscription divergent.';
  end if;

  if exists (
    select 1
    from public.application_user_authorizations user_authorization
    join auth.users auth_user on auth_user.id = user_authorization.user_id
    join public.protected_person_invitations invitation
      on lower(trim(invitation.email)) = lower(trim(coalesce(auth_user.email, '')))
    where (user_authorization.account_mode = 'autonomous'
           or user_authorization.registration_intent = 'autonomous')
      and invitation.accepted_at is null
      and invitation.revoked_at is null
      and invitation.declined_at is null
      and invitation.expires_at > statement_timestamp()
  ) then
    raise exception using
      errcode = 'P4M12',
      message = 'Migration impossible : une inscription autonome possede une invitation collaborateur active.';
  end if;

  if exists (
    select 1
    from public.application_user_authorizations user_authorization
    join public.account_trials trial on trial.user_id = user_authorization.user_id
    where user_authorization.account_mode = 'collaborator'
       or user_authorization.registration_intent = 'collaborator'
  ) or exists (
    select 1
    from public.application_user_authorizations user_authorization
    join public.account_subscriptions subscription on subscription.owner_id = user_authorization.user_id
    where user_authorization.account_mode = 'collaborator'
       or user_authorization.registration_intent = 'collaborator'
  ) then
    raise exception using
      errcode = 'P4M13',
      message = 'Migration impossible : un compte collaborateur possede un essai ou un abonnement.';
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
  current_intent text;
  normalized_email text;
begin
  if p_account_mode not in ('autonomous', 'collaborator') then
    raise exception 'Mode de compte invalide.';
  end if;
  if exists (
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_user_id
  ) then
    raise exception 'Un administrateur de plateforme ne peut pas utiliser les fonctions métier.';
  end if;

  select user_authorization.account_mode, user_authorization.registration_intent
  into current_mode, current_intent
  from public.application_user_authorizations user_authorization
  where user_authorization.user_id = p_user_id
  for update;
  if not found then
    raise exception 'Autorisation utilisateur introuvable.';
  end if;

  if p_account_mode = 'collaborator' then
    if current_mode = 'autonomous' or current_intent = 'autonomous' then
      raise exception using
        errcode = 'P4M01',
        message = 'Un compte autonome ne peut pas devenir collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.';
    end if;
    if exists (
      select 1 from public.protected_persons person
      where person.owner_id = p_user_id
    ) then
      raise exception using
        errcode = 'P4M02',
        message = 'Un propriétaire de dossier ne peut pas devenir collaborateur. Utilisez une adresse électronique distincte.';
    end if;
  else
    if current_mode = 'collaborator' or current_intent = 'collaborator' then
      raise exception using
        errcode = 'P4M02',
        message = 'Un compte collaborateur ne peut pas créer ou posséder de dossier. Utilisez une adresse électronique distincte pour le compte autonome.';
    end if;
    if exists (
      select 1 from public.protected_person_access access
      where access.user_id = p_user_id
    ) then
      raise exception using
        errcode = 'P4M02',
        message = 'Un compte collaborateur ne peut pas créer ou posséder de dossier. Utilisez une adresse électronique distincte pour le compte autonome.';
    end if;

    select public.lock_patrigest_email(auth_user.email)
    into normalized_email
    from auth.users auth_user
    where auth_user.id = p_user_id;
    if normalized_email is null then
      raise exception 'Utilisateur introuvable.';
    end if;
    if exists (
      select 1
      from public.protected_person_invitations invitation
      where lower(trim(invitation.email)) = normalized_email
        and invitation.accepted_at is null
        and invitation.revoked_at is null
        and invitation.declined_at is null
        and invitation.expires_at > statement_timestamp()
    ) then
      raise exception using
        errcode = 'P4M03',
        message = 'L activation du compte autonome est impossible tant qu une invitation collaborateur est active pour cette adresse. Utilisez une adresse électronique distincte ou refusez l invitation.';
    end if;
  end if;

  if current_mode is null then
    update public.application_user_authorizations
    set account_mode = p_account_mode,
        registration_intent = coalesce(registration_intent, p_account_mode)
    where user_id = p_user_id;
  elsif current_mode is distinct from p_account_mode then
    if current_mode = 'autonomous' then
      raise exception using
        errcode = 'P4M01',
        message = 'Un compte autonome ne peut pas devenir collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.';
    end if;
    raise exception using
      errcode = 'P4M02',
      message = 'Un compte collaborateur ne peut pas créer ou posséder de dossier. Utilisez une adresse électronique distincte pour le compte autonome.';
  end if;
end;
$$;

create or replace function public.reject_autonomous_protected_person_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := public.lock_patrigest_email(new.email);
begin
  -- Le trigger specialise des administrateurs s'execute ensuite et conserve
  -- son code ainsi que son message metier historiques.
  if exists (
    select 1
    from auth.users auth_user
    join public.platform_administrators administrator
      on administrator.user_id = auth_user.id
    where lower(trim(coalesce(auth_user.email, ''))) = normalized_email
  ) then
    new.email := normalized_email;
    return new;
  end if;

  if exists (
    select 1
    from auth.users auth_user
    join public.application_user_authorizations user_authorization
      on user_authorization.user_id = auth_user.id
    where lower(trim(coalesce(auth_user.email, ''))) = normalized_email
      and (
        user_authorization.account_mode = 'autonomous'
        or user_authorization.registration_intent = 'autonomous'
      )
  ) then
    raise exception using
      errcode = 'P4M01',
      message = 'Un compte autonome ne peut pas être invité comme collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.';
  end if;

  new.email := normalized_email;
  return new;
end;
$$;

-- Les triggers PostgreSQL d'un même type s'executent par ordre alphabetique.
-- Le nouveau nom laisse les refus specialises (proprietaire et administrateur)
-- conserver leurs codes et messages avant le controle general de mode.
drop trigger protected_person_access_enforce_account_mode
on public.protected_person_access;
create trigger protected_person_access_require_exclusive_account_mode
before insert or update of user_id on public.protected_person_access
for each row execute function public.enforce_protected_person_access_account_mode();

create function public.enforce_application_user_account_mode_exclusivity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text;
begin
  if (new.account_mode = 'autonomous' and new.registration_intent = 'collaborator')
     or (new.account_mode = 'collaborator' and new.registration_intent = 'autonomous') then
    raise exception using
      errcode = 'P4M04',
      message = 'Le mode du compte ne correspond pas à son parcours d inscription.';
  end if;

  if new.account_mode = 'collaborator' then
    if exists (select 1 from public.protected_persons person where person.owner_id = new.user_id) then
      raise exception using
        errcode = 'P4M02',
        message = 'Un compte collaborateur ne peut pas créer ou posséder de dossier. Utilisez une adresse électronique distincte pour le compte autonome.';
    end if;
    if exists (select 1 from public.account_trials trial where trial.user_id = new.user_id)
       or exists (select 1 from public.account_subscriptions subscription where subscription.owner_id = new.user_id) then
      raise exception using
        errcode = 'P4M05',
        message = 'Un compte collaborateur ne peut pas posséder d essai gratuit ni d abonnement.';
    end if;
  end if;

  if new.account_mode = 'autonomous'
     or (new.registration_intent = 'autonomous'
         and new.autonomous_registration_status = 'active') then
    if exists (select 1 from public.protected_person_access access where access.user_id = new.user_id) then
      raise exception using
        errcode = 'P4M01',
        message = 'Un compte autonome ne peut pas devenir collaborateur. Utilisez une adresse électronique distincte pour les accès partagés.';
    end if;

    select public.lock_patrigest_email(auth_user.email)
    into normalized_email
    from auth.users auth_user
    where auth_user.id = new.user_id;
    if normalized_email is not null and exists (
      select 1
      from public.protected_person_invitations invitation
      where lower(trim(invitation.email)) = normalized_email
        and invitation.accepted_at is null
        and invitation.revoked_at is null
        and invitation.declined_at is null
        and invitation.expires_at > statement_timestamp()
    ) then
      raise exception using
        errcode = 'P4M03',
        message = 'L activation du compte autonome est impossible tant qu une invitation collaborateur est active pour cette adresse. Utilisez une adresse électronique distincte ou refusez l invitation.';
    end if;
  end if;

  return new;
end;
$$;

create trigger application_user_authorizations_enforce_mode_exclusivity
before insert or update of status, account_mode, registration_intent, autonomous_registration_status
on public.application_user_authorizations
for each row execute function public.enforce_application_user_account_mode_exclusivity();

create function public.enforce_collaborator_has_no_trial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.application_user_authorizations user_authorization
    where user_authorization.user_id = new.user_id
      and (
        user_authorization.account_mode = 'collaborator'
        or user_authorization.registration_intent = 'collaborator'
      )
  ) then
    raise exception using
      errcode = 'P4M05',
      message = 'Un compte collaborateur ne peut pas posséder d essai gratuit ni d abonnement.';
  end if;
  return new;
end;
$$;

create trigger account_trials_reject_collaborator
before insert or update of user_id on public.account_trials
for each row execute function public.enforce_collaborator_has_no_trial();

revoke all on function public.claim_application_user_account_mode(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.reject_autonomous_protected_person_invitation()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_application_user_account_mode_exclusivity()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_collaborator_has_no_trial()
from public, anon, authenticated, service_role;

comment on function public.claim_application_user_account_mode(uuid, text) is
  'Attribue une seule fois un mode autonome ou collaborateur et refuse tout cumul, y compris entre intention d inscription et relations metier.';
comment on function public.enforce_application_user_account_mode_exclusivity() is
  'Protege les changements directs d autorisation et bloque une activation autonome tant qu une invitation collaborateur est active.';
