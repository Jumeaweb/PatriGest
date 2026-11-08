-- PAT-INSCRIPTION-01B
-- Separe l'inscription autonome de l'acces obtenu par invitation, autorise les
-- exports pendant l'essai et rend l'enregistrement du consentement recuperable
-- apres la confirmation de l'adresse e-mail.

alter table public.application_user_authorizations
  add column registration_intent text
    check (registration_intent in ('autonomous', 'collaborator')),
  add column autonomous_registration_status text
    check (autonomous_registration_status in ('pending', 'active', 'rejected'));

-- Les modes metier deja etablis restent l'autorite du backfill. Pour les
-- inscriptions encore sans mode, une invitation active identifie le parcours
-- collaborateur ; un consentement d'essai identifie sinon le parcours autonome.
update public.application_user_authorizations user_authorization
set registration_intent = case
      when user_authorization.account_mode = 'autonomous' then 'autonomous'
      when user_authorization.account_mode = 'collaborator' then 'collaborator'
      when exists (
        select 1
        from auth.users auth_user
        join public.protected_person_invitations invitation
          on lower(trim(invitation.email)) = lower(trim(auth_user.email))
        where auth_user.id = user_authorization.user_id
          and invitation.accepted_at is null
          and invitation.revoked_at is null
          and invitation.declined_at is null
          and invitation.expires_at > statement_timestamp()
      ) then 'collaborator'
      when exists (
        select 1 from public.account_trials trial
        where trial.user_id = user_authorization.user_id
      ) then 'autonomous'
      else null
    end;

update public.application_user_authorizations user_authorization
set autonomous_registration_status = case
      when user_authorization.registration_intent = 'autonomous'
        then user_authorization.status
      else null
    end;

grant select (registration_intent, autonomous_registration_status)
on public.application_user_authorizations to authenticated;

create or replace function public.initialize_application_user_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(coalesce(new.email, '')));
  requested_intent text := case
    when new.raw_user_meta_data ->> 'patrigest_registration_intent' = 'collaborator'
      then 'collaborator'
    else 'autonomous'
  end;
  initial_status text := 'pending';
  initial_autonomous_status text;
  initial_account_mode text;
begin
  if exists (
    select 1
    from public.account_requests request
    where lower(trim(request.email)) = normalized_email
      and request.status = 'approved'
      and request.invitation_used_at is null
      and request.invitation_expires_at > now()
  ) then
    initial_status := 'active';
  end if;

  if requested_intent = 'autonomous' then
    initial_autonomous_status := case when initial_status = 'active' then 'active' else 'pending' end;
    initial_account_mode := case when initial_status = 'active' then 'autonomous' else null end;
  end if;

  insert into public.application_user_authorizations (
    user_id, status, account_mode, registration_intent, autonomous_registration_status
  ) values (
    new.id, initial_status, initial_account_mode, requested_intent, initial_autonomous_status
  ) on conflict (user_id) do nothing;

  return new;
end;
$$;

create or replace function public.start_account_trial_if_eligible(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  started boolean := false;
  started_time timestamptz := clock_timestamp();
begin
  update public.account_trials trial
  set started_at = started_time,
      ends_at = started_time + interval '30 days',
      deletion_eligible_at = started_time + interval '60 days',
      updated_at = started_time
  where trial.user_id = p_user_id
    and trial.started_at is null
    and exists (
      select 1
      from public.application_user_authorizations user_authorization
      where user_authorization.user_id = p_user_id
        and user_authorization.status = 'active'
        and user_authorization.registration_intent = 'autonomous'
        and user_authorization.autonomous_registration_status = 'active'
    );

  started := found;
  if started then
    insert into public.account_trial_events(user_id, event_type, occurred_at)
    values (p_user_id, 'trial_started', started_time);
  end if;
  return started;
end;
$$;

create or replace function public.start_account_trial_on_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
     and new.registration_intent = 'autonomous'
     and new.autonomous_registration_status = 'active'
     and (
       tg_op = 'INSERT'
       or old.autonomous_registration_status is distinct from new.autonomous_registration_status
       or old.status is distinct from new.status
     ) then
    perform public.start_account_trial_if_eligible(new.user_id);
  end if;
  return new;
end;
$$;

drop trigger application_authorization_start_account_trial
on public.application_user_authorizations;
create trigger application_authorization_start_account_trial
after insert or update of status, autonomous_registration_status
on public.application_user_authorizations
for each row execute function public.start_account_trial_on_authorization();

create or replace function public.provision_new_development_owner_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
     and new.account_mode = 'autonomous'
     and new.registration_intent = 'autonomous'
     and new.autonomous_registration_status = 'active'
     and (
       tg_op = 'INSERT'
       or old.account_mode is distinct from new.account_mode
       or old.status is distinct from new.status
       or old.autonomous_registration_status is distinct from new.autonomous_registration_status
     )
     and not exists (
       select 1 from public.platform_administrators administrator
       where administrator.user_id = new.user_id
     )
     and not exists (
       select 1 from public.account_subscriptions subscription
       where subscription.owner_id = new.user_id
     ) then
    insert into public.account_subscriptions(owner_id, status)
    values (new.user_id, 'development')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger application_user_authorizations_provision_development_subscription
on public.application_user_authorizations;
create trigger application_user_authorizations_provision_development_subscription
after insert or update of status, account_mode, autonomous_registration_status
on public.application_user_authorizations
for each row execute function public.provision_new_development_owner_subscription();

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
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_user_id
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
    set account_mode = p_account_mode,
        registration_intent = coalesce(registration_intent, p_account_mode)
    where user_id = p_user_id;
  elsif current_mode = 'autonomous' and p_account_mode = 'collaborator' then
    -- Un titulaire autonome peut aussi recevoir des acces partages. Son mode
    -- principal reste autonome et ses droits de collaboration sont portes par
    -- protected_person_access.
    return;
  elsif current_mode is distinct from p_account_mode then
    raise exception 'Un compte collaborateur ne peut pas créer ou posséder de dossier.';
  end if;
end;
$$;

create or replace function public.reject_autonomous_protected_person_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Les titulaires autonomes peuvent desormais cumuler des acces partages.
  -- Les administrateurs de plateforme restent proteges par le trigger dedie.
  if tg_op = 'INSERT' then
    new.email := lower(trim(new.email));
  end if;
  return new;
end;
$$;

create or replace function public.record_account_trial_terms_acceptance(
  p_user_id uuid,
  p_terms_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  accepted_time timestamptz := clock_timestamp();
  expected_version text;
  existing_trial public.account_trials%rowtype;
  inserted_count integer := 0;
begin
  select current_terms_version into expected_version
  from public.account_trial_runtime_config where singleton;

  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception using errcode = 'P4T01', message = 'Compte introuvable.';
  end if;
  if not exists (
    select 1 from public.application_user_authorizations user_authorization
    where user_authorization.user_id = p_user_id
      and user_authorization.registration_intent = 'autonomous'
      and user_authorization.autonomous_registration_status in ('pending', 'active')
  ) then
    raise exception using errcode = 'P4T08', message = 'Inscription autonome requise.';
  end if;
  if p_terms_version is distinct from expected_version then
    raise exception using errcode = 'P4T02', message = 'Version des conditions invalide.';
  end if;

  insert into public.account_trials(user_id, terms_version, terms_accepted_at)
  values (p_user_id, expected_version, accepted_time)
  on conflict (user_id) do nothing;
  get diagnostics inserted_count = row_count;

  select * into existing_trial from public.account_trials where user_id = p_user_id;
  if existing_trial.terms_version is distinct from expected_version then
    raise exception using errcode = 'P4T03', message = 'Une periode d''essai existe deja.';
  end if;
  if inserted_count = 1 then
    insert into public.account_trial_events(user_id, event_type, occurred_at, terms_version)
    select p_user_id, 'terms_accepted', existing_trial.terms_accepted_at, expected_version
    where not exists (
      select 1 from public.account_trial_events event
      where event.user_id = p_user_id and event.event_type = 'terms_accepted'
    );
  end if;
  perform public.start_account_trial_if_eligible(p_user_id);
end;
$$;

create function public.complete_own_autonomous_trial_registration()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  expected_version text;
  auth_user auth.users%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentification requise.';
  end if;
  select * into auth_user from auth.users where id = caller_id;
  if not found or auth_user.email_confirmed_at is null then
    raise exception using errcode = 'P4T09', message = 'Adresse e-mail non confirmee.';
  end if;
  if not exists (
    select 1 from public.application_user_authorizations user_authorization
    where user_authorization.user_id = caller_id
      and user_authorization.registration_intent = 'autonomous'
      and user_authorization.autonomous_registration_status in ('pending', 'active')
  ) then
    raise exception using errcode = 'P4T08', message = 'Inscription autonome requise.';
  end if;

  select current_terms_version into expected_version
  from public.account_trial_runtime_config where singleton;
  if auth_user.raw_user_meta_data ->> 'patrigest_registration_intent' is distinct from 'autonomous'
     or auth_user.raw_user_meta_data ->> 'patrigest_trial_terms_version' is distinct from expected_version
     or auth_user.raw_user_meta_data ->> 'patrigest_trial_terms_accepted' is distinct from 'true' then
    raise exception using errcode = 'P4T10', message = 'Consentement explicite introuvable.';
  end if;

  perform public.record_account_trial_terms_acceptance(caller_id, expected_version);
end;
$$;

revoke all on function public.complete_own_autonomous_trial_registration()
from public, anon, authenticated, service_role;
grant execute on function public.complete_own_autonomous_trial_registration()
to authenticated;

create or replace function public.review_application_user_registration(
  p_user_id uuid,
  p_decision text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_autonomous_status text;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'Acces administrateur requis.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Vous ne pouvez pas modifier votre propre autorisation.';
  end if;
  if p_decision not in ('active', 'rejected') then
    raise exception 'Decision invalide.';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Utilisateur introuvable.';
  end if;

  select user_authorization.autonomous_registration_status
  into current_autonomous_status
  from public.application_user_authorizations user_authorization
  where user_authorization.user_id = p_user_id
    and user_authorization.registration_intent = 'autonomous'
  for update;
  if not found then
    raise exception 'Inscription autonome introuvable.';
  end if;
  if current_autonomous_status <> 'pending' then
    raise exception 'Cette inscription a déjà été traitée.';
  end if;
  if p_decision = 'active' and not exists (
    select 1 from public.account_trials trial
    join public.account_trial_runtime_config config
      on config.current_terms_version = trial.terms_version
    where trial.user_id = p_user_id and trial.terms_accepted_at is not null
  ) then
    raise exception using errcode = 'P4T07',
      message = 'Les conditions de l''essai doivent etre acceptees avant activation.';
  end if;

  update public.application_user_authorizations user_authorization
  set autonomous_registration_status = p_decision,
      status = case
        when p_decision = 'active' then 'active'
        when exists (
          select 1 from public.protected_person_access access
          where access.user_id = p_user_id
        ) then 'active'
        else 'rejected'
      end,
      account_mode = case
        when p_decision = 'active' then 'autonomous'
        else user_authorization.account_mode
      end,
      status_changed_at = clock_timestamp(),
      status_changed_by = auth.uid()
  where user_authorization.user_id = p_user_id;
  return p_decision;
end;
$$;

-- L'essai donne acces aux exports ordinaires. Les restrictions de role sur les
-- dossiers partages et les fonctionnalites non encore implementees restent en place.
create or replace function public.get_protected_person_feature_capabilities(
  p_protected_person_id uuid
)
returns table (
  feature_key text,
  implementation_status text,
  can_read boolean,
  can_write boolean,
  read_denial_reason text,
  write_denial_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_role text;
  dossier_owner_id uuid;
  owner_entitlement record;
begin
  if auth.uid() is null or not public.is_application_user_active() then
    raise exception using errcode = '42501', message = 'Dossier introuvable.';
  end if;

  select person.owner_id,
         case when person.owner_id = auth.uid() then 'owner' else access.role end
  into dossier_owner_id, caller_role
  from public.protected_persons person
  left join public.protected_person_access access
    on access.protected_person_id = person.id and access.user_id = auth.uid()
  where person.id = p_protected_person_id
    and (person.owner_id = auth.uid() or access.user_id is not null);
  if not found or caller_role not in ('owner', 'manager', 'read_only') then
    raise exception using errcode = '42501', message = 'Dossier introuvable.';
  end if;

  select * into owner_entitlement
  from public.resolve_effective_account_entitlements(dossier_owner_id, statement_timestamp());

  return query
  with feature_context as (
    select feature.feature_key,
           feature.implementation_status,
           owner_entitlement.access_source as entitlement_source,
           coalesce(plan_feature.included, false) as plan_included
    from public.subscription_features feature
    left join public.subscription_plan_features plan_feature
      on plan_feature.plan_key = owner_entitlement.effective_plan_key
     and plan_feature.feature_key = feature.feature_key
  ), decisions as (
    select context.feature_key,
           context.implementation_status,
           case
             when context.implementation_status = 'upcoming' then 'feature_upcoming'
             when context.entitlement_source = 'none' then 'subscription_missing'
             when owner_entitlement.effective_plan_key is not null and not context.plan_included then 'not_in_plan'
             when context.feature_key in ('data_export', 'bank_operation_automation') and caller_role = 'read_only' then 'role_forbidden'
             else null
           end as read_denial_reason,
           case
             when context.implementation_status = 'upcoming' then 'feature_upcoming'
             when context.entitlement_source = 'none' then 'subscription_missing'
             when owner_entitlement.effective_plan_key is not null and not context.plan_included then 'not_in_plan'
             when context.feature_key = 'data_export' then 'operation_not_supported'
             when caller_role = 'read_only' then 'role_forbidden'
             else null
           end as write_denial_reason
    from feature_context context
  )
  select decision.feature_key,
         decision.implementation_status,
         decision.read_denial_reason is null,
         decision.write_denial_reason is null,
         decision.read_denial_reason,
         decision.write_denial_reason
  from decisions decision
  order by case decision.feature_key
    when 'core_management' then 1
    when 'existing_accounting_documents' then 2
    when 'data_export' then 3
    when 'bank_operation_automation' then 4
    when 'central_document_management' then 5
  end;
end;
$$;

comment on column public.application_user_authorizations.registration_intent is
  'Intention explicite du parcours initial : titulaire autonome ou collaborateur invite.';
comment on column public.application_user_authorizations.autonomous_registration_status is
  'Decision Jumeaweb propre au parcours autonome, distincte de l acces applicatif obtenu par invitation.';
comment on function public.complete_own_autonomous_trial_registration() is
  'Reprise authentifiee du consentement explicite apres confirmation de l adresse e-mail ; ne demarre pas l essai avant validation administrative.';
