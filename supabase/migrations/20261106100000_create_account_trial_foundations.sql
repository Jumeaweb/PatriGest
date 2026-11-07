-- PAT-TRIAL-01
-- Fondations du cycle d'essai 30 + 30 jours. L'application de la barriere
-- metier reste explicitement desactivee tant que le lot n'a pas ete valide
-- sur une pile locale isolee puis active par une migration ulterieure.

create table public.account_trial_runtime_config (
  singleton boolean primary key default true check (singleton),
  enforcement_enabled boolean not null default false,
  current_terms_version text not null check (length(trim(current_terms_version)) > 0),
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.account_trial_runtime_config(singleton, enforcement_enabled, current_terms_version)
values (true, false, 'trial-30-plus-30-v1');

create table public.account_trials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms_version text not null check (length(trim(terms_version)) > 0),
  terms_accepted_at timestamptz not null,
  started_at timestamptz,
  ends_at timestamptz,
  deletion_eligible_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint account_trials_timeline_consistency check (
    (started_at is null and ends_at is null and deletion_eligible_at is null)
    or (
      started_at is not null
      and ends_at = started_at + interval '30 days'
      and deletion_eligible_at = started_at + interval '60 days'
      and terms_accepted_at <= started_at
    )
  )
);

create table public.account_trial_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in (
    'terms_accepted', 'trial_started', 'purge_prepared'
  )),
  occurred_at timestamptz not null default clock_timestamp(),
  terms_version text,
  request_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  constraint account_trial_events_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create index account_trial_events_user_occurred_idx
on public.account_trial_events(user_id, occurred_at desc);

-- Les comptes deja actifs avant cette migration restent accessibles sans
-- qu'un consentement d'essai fictif leur soit attribue. Cette exemption est
-- explicite, figee et distincte du cycle d'essai des nouvelles inscriptions.
create table public.account_trial_legacy_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null check (reason = 'active_before_trial_cutover'),
  recorded_at timestamptz not null default clock_timestamp()
);

insert into public.account_trial_legacy_access(user_id, reason)
select user_authorization.user_id, 'active_before_trial_cutover'
from public.application_user_authorizations user_authorization
join auth.users existing_user on existing_user.id = user_authorization.user_id
where user_authorization.status = 'active';

create table public.account_trial_purge_requests (
  request_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  state text not null default 'prepared' check (state in (
    'prepared', 'running', 'attention_required', 'completed', 'cancelled'
  )),
  eligibility_observed_at timestamptz not null,
  trial_deletion_eligible_at timestamptz not null,
  checkpoints jsonb not null default '{}'::jsonb,
  error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint account_trial_purge_checkpoints_object check (jsonb_typeof(checkpoints) = 'object'),
  constraint account_trial_purge_completion_consistency check (
    (state = 'completed' and completed_at is not null)
    or (state <> 'completed' and completed_at is null)
  )
);

create unique index account_trial_one_open_purge_per_user_idx
on public.account_trial_purge_requests(user_id)
where state in ('prepared', 'running', 'attention_required');

alter table public.account_trial_runtime_config enable row level security;
alter table public.account_trials enable row level security;
alter table public.account_trial_events enable row level security;
alter table public.account_trial_legacy_access enable row level security;
alter table public.account_trial_purge_requests enable row level security;

revoke all on table public.account_trial_runtime_config from public, anon, authenticated, service_role;
revoke all on table public.account_trials from public, anon, authenticated, service_role;
revoke all on table public.account_trial_events from public, anon, authenticated, service_role;
revoke all on table public.account_trial_legacy_access from public, anon, authenticated, service_role;
revoke all on table public.account_trial_purge_requests from public, anon, authenticated, service_role;

create function public.has_current_commercial_subscription(
  p_user_id uuid,
  p_at timestamptz default clock_timestamp()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.account_subscriptions subscription
    join public.subscription_plans plan on plan.plan_key = subscription.plan_key
    where subscription.owner_id = p_user_id
      and subscription.status in ('active', 'past_due', 'canceled')
      and subscription.ended_at is null
      and plan.active
      and (
        subscription.current_period_ends_at is null
        or p_at < subscription.current_period_ends_at
      )
  )
$$;

create function public.compute_account_trial_state(
  p_user_id uuid,
  p_at timestamptz default clock_timestamp()
)
returns table (
  state text,
  terms_version text,
  terms_accepted_at timestamptz,
  started_at timestamptz,
  ends_at timestamptz,
  deletion_eligible_at timestamptz,
  remaining_days integer,
  active_dossier_limit integer,
  active_dossier_count bigint,
  enforcement_enabled boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with context as (
    select
      trial.terms_version,
      trial.terms_accepted_at,
      trial.started_at,
      trial.ends_at,
      trial.deletion_eligible_at,
      config.enforcement_enabled,
      exists (
        select 1
        from public.application_user_authorizations user_authorization
        where user_authorization.user_id = p_user_id
          and user_authorization.status = 'active'
      ) as authorization_active,
      exists (
        select 1
        from public.account_trial_legacy_access legacy
        where legacy.user_id = p_user_id
      ) as legacy_access,
      public.has_current_commercial_subscription(p_user_id, p_at) as commercial_access,
      coalesce((
        select capacity.active_dossier_limit
        from public.subscription_dossier_capacities capacity
        where capacity.capacity_key = 'included'
      ), 2) as active_dossier_limit,
      (select count(*) from public.protected_persons person
       where person.owner_id = p_user_id and person.status = 'active') as active_dossier_count
    from public.account_trial_runtime_config config
    left join public.account_trials trial on trial.user_id = p_user_id
    where config.singleton
  )
  select
    case
      when not context.authorization_active then 'not_authorized'
      when context.commercial_access then 'subscribed'
      when context.legacy_access then 'legacy_access'
      when context.terms_accepted_at is null then 'terms_required'
      when context.started_at is null then 'awaiting_activation'
      when p_at < context.ends_at then 'active'
      when p_at < context.deletion_eligible_at then 'suspended'
      else 'deletion_due'
    end,
    context.terms_version,
    context.terms_accepted_at,
    context.started_at,
    context.ends_at,
    context.deletion_eligible_at,
    case
      when context.started_at is not null and p_at < context.ends_at
        then greatest(ceil(extract(epoch from (context.ends_at - p_at)) / 86400)::integer, 0)
      else 0
    end,
    context.active_dossier_limit,
    context.active_dossier_count,
    context.enforcement_enabled
  from context
$$;

create function public.has_application_business_access(
  p_user_id uuid,
  p_at timestamptz default clock_timestamp()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_platform_admin()
    or exists (
      select 1
      from public.application_user_authorizations user_authorization
      cross join public.account_trial_runtime_config config
      where user_authorization.user_id = p_user_id
        and user_authorization.status = 'active'
        and (
          not config.enforcement_enabled
          or exists (
            select 1 from public.account_trial_legacy_access legacy
            where legacy.user_id = p_user_id
          )
          or public.has_current_commercial_subscription(p_user_id, p_at)
          or exists (
            select 1 from public.account_trials trial
            where trial.user_id = p_user_id
              and trial.started_at is not null
              and p_at >= trial.started_at
              and p_at < trial.ends_at
          )
        )
    )
$$;

create or replace function public.is_application_user_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.has_application_business_access(auth.uid(), clock_timestamp())
$$;

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
begin
  if auth.uid() is null or not public.is_application_user_active() then
    raise exception using errcode = '42501', message = 'Dossier introuvable.';
  end if;

  select persons.owner_id,
         case when persons.owner_id = auth.uid() then 'owner' else access.role end
  into dossier_owner_id, caller_role
  from public.protected_persons persons
  left join public.protected_person_access access
    on access.protected_person_id = persons.id and access.user_id = auth.uid()
  where persons.id = p_protected_person_id
    and (persons.owner_id = auth.uid() or access.user_id is not null);

  if not found or caller_role not in ('owner', 'manager', 'read_only') then
    raise exception using errcode = '42501', message = 'Dossier introuvable.';
  end if;

  return query
  with feature_context as (
    select
      features.feature_key,
      features.implementation_status,
      subscriptions.id as subscription_id,
      subscriptions.status as subscription_status,
      coalesce(plans.active, false) as plan_active,
      coalesce(plan_features.included, false) as plan_included,
      (
        exists (
          select 1 from public.account_trials caller_trial
          where caller_trial.user_id = auth.uid()
            and caller_trial.started_at is not null
            and statement_timestamp() >= caller_trial.started_at
            and statement_timestamp() < caller_trial.ends_at
        )
        and not public.has_current_commercial_subscription(auth.uid(), statement_timestamp())
      ) or (
      exists (
        select 1 from public.account_trials trial
        where trial.user_id = dossier_owner_id
          and trial.started_at is not null
          and statement_timestamp() >= trial.started_at
          and statement_timestamp() < trial.ends_at
      ) and not public.has_current_commercial_subscription(dossier_owner_id, statement_timestamp())
      )
        as trial_export_restricted
    from public.subscription_features features
    left join public.account_subscriptions subscriptions
      on subscriptions.owner_id = dossier_owner_id and subscriptions.ended_at is null
    left join public.subscription_plans plans on plans.plan_key = subscriptions.plan_key
    left join public.subscription_plan_features plan_features
      on plan_features.plan_key = subscriptions.plan_key
     and plan_features.feature_key = features.feature_key
  ), decisions as (
    select
      context.feature_key,
      context.implementation_status,
      case
        when context.implementation_status = 'upcoming' then 'feature_upcoming'
        when context.subscription_id is null then 'subscription_missing'
        when context.feature_key = 'data_export' and context.trial_export_restricted then 'trial_export_unavailable'
        when context.subscription_status <> 'development' and not context.plan_active then 'plan_unavailable'
        when context.subscription_status <> 'development' and not context.plan_included then 'not_in_plan'
        when context.feature_key in ('data_export', 'bank_operation_automation') and caller_role = 'read_only' then 'role_forbidden'
        else null
      end as read_denial_reason,
      case
        when context.implementation_status = 'upcoming' then 'feature_upcoming'
        when context.subscription_id is null then 'subscription_missing'
        when context.feature_key = 'data_export' and context.trial_export_restricted then 'trial_export_unavailable'
        when context.subscription_status <> 'development' and not context.plan_active then 'plan_unavailable'
        when context.subscription_status <> 'development' and not context.plan_included then 'not_in_plan'
        when context.feature_key = 'data_export' then 'operation_not_supported'
        when caller_role = 'read_only' then 'role_forbidden'
        else null
      end as write_denial_reason
    from feature_context context
  )
  select
    decisions.feature_key,
    decisions.implementation_status,
    decisions.read_denial_reason is null,
    decisions.write_denial_reason is null,
    decisions.read_denial_reason,
    decisions.write_denial_reason
  from decisions
  order by case decisions.feature_key
    when 'core_management' then 1
    when 'existing_accounting_documents' then 2
    when 'data_export' then 3
    when 'bank_operation_automation' then 4
    when 'central_document_management' then 5
  end;
end;
$$;

create function public.start_account_trial_if_eligible(p_user_id uuid)
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
      select 1 from public.application_user_authorizations user_authorization
      where user_authorization.user_id = p_user_id and user_authorization.status = 'active'
    );

  started := found;
  if started then
    insert into public.account_trial_events(user_id, event_type, occurred_at)
    values (p_user_id, 'trial_started', started_time);
  end if;
  return started;
end;
$$;

create function public.start_account_trial_on_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform public.start_account_trial_if_eligible(new.user_id);
  end if;
  return new;
end;
$$;

create trigger application_authorization_start_account_trial
after insert or update of status on public.application_user_authorizations
for each row execute function public.start_account_trial_on_authorization();

create function public.record_account_trial_terms_acceptance(
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

create function public.get_current_account_trial_state()
returns table (
  state text,
  terms_version text,
  terms_accepted_at timestamptz,
  started_at timestamptz,
  ends_at timestamptz,
  deletion_eligible_at timestamptz,
  remaining_days integer,
  active_dossier_limit integer,
  active_dossier_count bigint,
  enforcement_enabled boolean
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
  return query select * from public.compute_account_trial_state(auth.uid(), statement_timestamp());
end;
$$;

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
  v_current_status text;
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

  select status into v_current_status
  from public.application_user_authorizations
  where user_id = p_user_id
  for update;
  if not found then
    raise exception 'Autorisation utilisateur introuvable.';
  end if;
  if v_current_status <> 'pending' then
    raise exception 'Cette inscription a déjà été traitée.';
  end if;
  if p_decision = 'active' and not exists (
    select 1 from public.account_trials trial
    join public.account_trial_runtime_config config
      on config.current_terms_version = trial.terms_version
    where trial.user_id = p_user_id
      and trial.terms_accepted_at is not null
  ) then
    raise exception using
      errcode = 'P4T07',
      message = 'Les conditions de l''essai doivent etre acceptees avant activation.';
  end if;

  update public.application_user_authorizations
  set status = p_decision,
      status_changed_at = clock_timestamp(),
      status_changed_by = auth.uid()
  where user_id = p_user_id;
  return p_decision;
end;
$$;

create function public.prepare_account_trial_purge(
  p_user_id uuid,
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  trial_record public.account_trials%rowtype;
  current_state text;
  observed_at timestamptz := clock_timestamp();
begin
  if p_user_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'Parametres de purge invalides.';
  end if;

  select * into trial_record from public.account_trials
  where user_id = p_user_id for update;
  if not found then
    raise exception using errcode = 'P4T04', message = 'Essai introuvable.';
  end if;

  select state into current_state
  from public.compute_account_trial_state(p_user_id, observed_at);
  if current_state <> 'deletion_due' then
    raise exception using errcode = 'P4T05', message = 'Compte non eligible a la purge.';
  end if;

  insert into public.account_trial_purge_requests(
    request_id, user_id, eligibility_observed_at, trial_deletion_eligible_at
  ) values (
    p_request_id, p_user_id, observed_at, trial_record.deletion_eligible_at
  )
  on conflict (request_id) do nothing;

  if not exists (
    select 1 from public.account_trial_purge_requests request
    where request.request_id = p_request_id and request.user_id = p_user_id
  ) then
    raise exception using errcode = 'P4T06', message = 'Cle de reprise deja utilisee.';
  end if;

  insert into public.account_trial_events(user_id, event_type, request_id)
  select p_user_id, 'purge_prepared', p_request_id
  where not exists (
    select 1 from public.account_trial_events event
    where event.request_id = p_request_id and event.event_type = 'purge_prepared'
  );
  return p_request_id;
end;
$$;

revoke all on function public.has_current_commercial_subscription(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.compute_account_trial_state(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.has_application_business_access(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.start_account_trial_if_eligible(uuid) from public, anon, authenticated, service_role;
revoke all on function public.start_account_trial_on_authorization() from public, anon, authenticated, service_role;
revoke all on function public.record_account_trial_terms_acceptance(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.get_current_account_trial_state() from public, anon, authenticated, service_role;
revoke all on function public.prepare_account_trial_purge(uuid, uuid) from public, anon, authenticated, service_role;

grant execute on function public.record_account_trial_terms_acceptance(uuid, text) to service_role;
grant execute on function public.get_current_account_trial_state() to authenticated;
grant execute on function public.prepare_account_trial_purge(uuid, uuid) to service_role;

comment on table public.account_trials is
  'Consentement et chronologie serveur de l''unique essai 30 + 30 jours d''un compte.';
comment on table public.account_trial_legacy_access is
  'Exemptions figees des comptes actifs avant le basculement, sans consentement d''essai fabrique.';
comment on table public.account_trial_purge_requests is
  'Contrat de reprise de purge uniquement; aucune suppression n''est executee par PAT-TRIAL-01.';
comment on function public.is_application_user_active() is
  'Barriere metier centrale. Le mode trial reste inactif tant que account_trial_runtime_config.enforcement_enabled est false.';
