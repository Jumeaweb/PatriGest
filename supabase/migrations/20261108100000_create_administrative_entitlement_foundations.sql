-- PAT-ADMIN-USERS-05C
-- Fondations distinctes pour les attributions administratives gratuites et
-- les derogations de droits. Les abonnements commerciaux, essais et acces
-- historiques restent inchanges.

create table public.account_administrative_plan_assignments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  plan_key text not null references public.subscription_plans(plan_key) on delete restrict,
  billing_period text not null check (billing_period in ('monthly', 'annual')),
  dossier_capacity_key text not null
    references public.subscription_dossier_capacities(capacity_key) on delete restrict,
  status text not null default 'active'
    check (status in ('active', 'revoked', 'superseded')),
  revision bigint not null default 1 check (revision > 0),
  reason text not null check (length(trim(reason)) > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  superseded_at timestamptz,
  constraint account_administrative_plan_assignment_capacity check (
    (plan_key = 'essential' and dossier_capacity_key = 'included')
    or (
      plan_key in ('comfort', 'premium')
      and dossier_capacity_key in ('included', 'five', 'ten')
    )
  ),
  constraint account_administrative_plan_assignment_terminal check (
    (status = 'active' and revoked_at is null and revoked_by is null and superseded_at is null)
    or (status = 'revoked' and revoked_at is not null and revoked_by is not null and superseded_at is null)
    or (status = 'superseded' and superseded_at is not null and revoked_at is null and revoked_by is null)
  )
);

create unique index account_administrative_plan_assignment_one_active_idx
on public.account_administrative_plan_assignments(owner_id)
where status = 'active';

create index account_administrative_plan_assignment_owner_history_idx
on public.account_administrative_plan_assignments(owner_id, created_at desc);

create table public.account_administrative_entitlement_overrides (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  base_source text not null check (base_source in ('commercial', 'administrative')),
  base_reference_id uuid not null,
  feature_plan_key text references public.subscription_plans(plan_key) on delete restrict,
  dossier_capacity_key text
    references public.subscription_dossier_capacities(capacity_key) on delete restrict,
  status text not null default 'active'
    check (status in ('active', 'revoked', 'superseded')),
  revision bigint not null default 1 check (revision > 0),
  reason text not null check (length(trim(reason)) > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  superseded_at timestamptz,
  constraint account_administrative_override_nonempty check (
    feature_plan_key is not null or dossier_capacity_key is not null
  ),
  constraint account_administrative_override_capacity check (
    dossier_capacity_key is null or dossier_capacity_key in ('five', 'ten')
  ),
  constraint account_administrative_override_terminal check (
    (status = 'active' and revoked_at is null and revoked_by is null and superseded_at is null)
    or (status = 'revoked' and revoked_at is not null and revoked_by is not null and superseded_at is null)
    or (status = 'superseded' and superseded_at is not null and revoked_at is null and revoked_by is null)
  )
);

create unique index account_administrative_entitlement_override_one_active_idx
on public.account_administrative_entitlement_overrides(owner_id)
where status = 'active';

create index account_administrative_entitlement_override_owner_history_idx
on public.account_administrative_entitlement_overrides(owner_id, created_at desc);

create table public.account_administrative_entitlement_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  owner_id uuid not null references auth.users(id) on delete restrict,
  entity_type text not null check (entity_type in ('plan_assignment', 'entitlement_override')),
  entity_id uuid not null,
  action text not null check (action in ('assigned', 'replaced', 'revoked', 'superseded')),
  actor_kind text not null check (actor_kind in ('administrator', 'system')),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (length(trim(reason)) > 0),
  before_state jsonb,
  after_state jsonb,
  request_payload jsonb not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  result_revision bigint not null check (result_revision > 0),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint account_administrative_event_actor check (
    (actor_kind = 'administrator' and actor_id is not null)
    or (actor_kind = 'system' and actor_id is null)
  ),
  constraint account_administrative_event_states check (
    before_state is not null or after_state is not null
  )
);

create index account_administrative_entitlement_events_owner_idx
on public.account_administrative_entitlement_events(owner_id, occurred_at desc);

alter table public.account_administrative_plan_assignments enable row level security;
alter table public.account_administrative_entitlement_overrides enable row level security;
alter table public.account_administrative_entitlement_events enable row level security;

revoke all on table public.account_administrative_plan_assignments
from public, anon, authenticated, service_role;
revoke all on table public.account_administrative_entitlement_overrides
from public, anon, authenticated, service_role;
revoke all on table public.account_administrative_entitlement_events
from public, anon, authenticated, service_role;

create function public.administrative_entitlement_payload_hash(p_payload jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256'), 'hex')
$$;

create function public.prevent_administrative_entitlement_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P5A20',
    message = 'L historique administratif est immuable.';
end;
$$;

create trigger account_administrative_entitlement_events_immutable
before update or delete on public.account_administrative_entitlement_events
for each row execute function public.prevent_administrative_entitlement_event_mutation();

create function public.validate_active_administrative_plan_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active' and not exists (
    select 1
    from public.application_user_authorizations user_authorization
    where user_authorization.user_id = new.owner_id
      and user_authorization.status = 'active'
      and user_authorization.account_mode = 'autonomous'
  ) then
    raise exception using errcode = 'P5A04', message = 'Compte non eligible a une attribution administrative.';
  end if;

  if new.status = 'active' and exists (
    select 1 from public.platform_administrators administrator
    where administrator.user_id = new.owner_id
  ) then
    raise exception using errcode = 'P5A04', message = 'Compte non eligible a une attribution administrative.';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger account_administrative_plan_assignments_validate
before insert or update on public.account_administrative_plan_assignments
for each row execute function public.validate_active_administrative_plan_assignment();

create function public.resolve_effective_account_entitlements(
  p_owner_id uuid,
  p_at timestamptz default statement_timestamp()
)
returns table (
  authorization_active boolean,
  account_mode text,
  access_source text,
  commercial_subscription_id uuid,
  administrative_assignment_id uuid,
  base_plan_key text,
  effective_plan_key text,
  base_active_dossier_limit integer,
  effective_active_dossier_limit integer,
  administrative_override_id uuid,
  active_dossier_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  authorization_record record;
  commercial_record record;
  assignment_record record;
  override_record record;
  included_limit integer;
  resolved_source text := 'none';
  resolved_base_id uuid;
  resolved_plan text;
  resolved_base_limit integer;
  resolved_effective_plan text;
  resolved_effective_limit integer;
  resolved_override_id uuid;
  dossier_count bigint;
  trial_active boolean := false;
  legacy_active boolean := false;
  enforcement_active boolean := false;
begin
  select user_authorization.status = 'active' as is_active,
         user_authorization.account_mode
  into authorization_record
  from public.application_user_authorizations user_authorization
  where user_authorization.user_id = p_owner_id;

  select capacity.active_dossier_limit
  into included_limit
  from public.subscription_dossier_capacities capacity
  where capacity.capacity_key = 'included';

  select count(*) into dossier_count
  from public.protected_persons person
  where person.owner_id = p_owner_id and person.status = 'active';

  if coalesce(authorization_record.is_active, false)
     and authorization_record.account_mode = 'autonomous' then
    select subscription.id,
           subscription.plan_key,
           case when subscription.dossier_capacity_key = 'custom'
             then subscription.custom_active_dossier_limit
             else capacity.active_dossier_limit
           end as active_limit
    into commercial_record
    from public.account_subscriptions subscription
    join public.subscription_plans plan
      on plan.plan_key = subscription.plan_key and plan.active
    join public.subscription_dossier_capacities capacity
      on capacity.capacity_key = subscription.dossier_capacity_key
    where subscription.owner_id = p_owner_id
      and subscription.status in ('active', 'past_due', 'canceled')
      and subscription.ended_at is null
      and (subscription.current_period_ends_at is null or p_at < subscription.current_period_ends_at)
    order by subscription.started_at desc
    limit 1;

    if found then
      resolved_source := 'commercial';
      resolved_base_id := commercial_record.id;
      resolved_plan := commercial_record.plan_key;
      resolved_base_limit := commercial_record.active_limit;
    else
      select assignment.id, assignment.plan_key, capacity.active_dossier_limit
      into assignment_record
      from public.account_administrative_plan_assignments assignment
      join public.subscription_dossier_capacities capacity
        on capacity.capacity_key = assignment.dossier_capacity_key
      where assignment.owner_id = p_owner_id and assignment.status = 'active'
      limit 1;

      if found then
        resolved_source := 'administrative';
        resolved_base_id := assignment_record.id;
        resolved_plan := assignment_record.plan_key;
        resolved_base_limit := assignment_record.active_dossier_limit;
      else
        select exists (
          select 1 from public.account_trials trial
          where trial.user_id = p_owner_id
            and trial.started_at is not null
            and p_at >= trial.started_at and p_at < trial.ends_at
        ) into trial_active;

        select exists (
          select 1 from public.account_trial_legacy_access legacy
          where legacy.user_id = p_owner_id
        ) into legacy_active;

        select config.enforcement_enabled into enforcement_active
        from public.account_trial_runtime_config config where config.singleton;

        if trial_active then
          resolved_source := 'trial';
          resolved_base_limit := included_limit;
        elsif legacy_active then
          resolved_source := 'legacy';
          resolved_base_limit := included_limit;
        elsif not coalesce(enforcement_active, false) then
          resolved_source := 'development';
          resolved_base_limit := included_limit;
        end if;
      end if;
    end if;
  elsif coalesce(authorization_record.is_active, false)
        and authorization_record.account_mode = 'collaborator' then
    resolved_source := 'shared_access';
  end if;

  resolved_effective_plan := resolved_plan;
  resolved_effective_limit := resolved_base_limit;

  if resolved_source in ('commercial', 'administrative') then
    select entitlement_override.id,
           entitlement_override.feature_plan_key,
           capacity.active_dossier_limit
    into override_record
    from public.account_administrative_entitlement_overrides entitlement_override
    left join public.subscription_dossier_capacities capacity
      on capacity.capacity_key = entitlement_override.dossier_capacity_key
    where entitlement_override.owner_id = p_owner_id
      and entitlement_override.status = 'active'
      and entitlement_override.base_source = resolved_source
      and entitlement_override.base_reference_id = resolved_base_id
    limit 1;

    if found then
      resolved_override_id := override_record.id;
      if override_record.feature_plan_key is not null then
        resolved_effective_plan := override_record.feature_plan_key;
      end if;
      if override_record.active_dossier_limit is not null then
        resolved_effective_limit := greatest(resolved_base_limit, override_record.active_dossier_limit);
      end if;
    end if;
  end if;

  return query select
    coalesce(authorization_record.is_active, false),
    authorization_record.account_mode,
    resolved_source,
    case when resolved_source = 'commercial' then resolved_base_id end,
    case when resolved_source = 'administrative' then resolved_base_id end,
    resolved_plan,
    resolved_effective_plan,
    resolved_base_limit,
    resolved_effective_limit,
    resolved_override_id,
    dossier_count;
end;
$$;

create function public.validate_active_administrative_entitlement_override()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitlement record;
  base_rank smallint;
  override_rank smallint;
  override_limit integer;
begin
  if new.status <> 'active' then
    new.updated_at := clock_timestamp();
    return new;
  end if;

  select * into entitlement
  from public.resolve_effective_account_entitlements(new.owner_id, statement_timestamp());

  if entitlement.access_source is distinct from new.base_source
     or coalesce(entitlement.commercial_subscription_id, entitlement.administrative_assignment_id)
        is distinct from new.base_reference_id then
    raise exception using errcode = 'P5A10', message = 'Base de derogation invalide.';
  end if;

  select plan.sort_order into base_rank
  from public.subscription_plans plan where plan.plan_key = entitlement.base_plan_key;
  select plan.sort_order into override_rank
  from public.subscription_plans plan where plan.plan_key = new.feature_plan_key;
  select capacity.active_dossier_limit into override_limit
  from public.subscription_dossier_capacities capacity
  where capacity.capacity_key = new.dossier_capacity_key;

  if new.feature_plan_key is not null and override_rank <= base_rank then
    raise exception using errcode = 'P5A11', message = 'La derogation fonctionnelle doit augmenter les droits.';
  end if;
  if new.dossier_capacity_key is not null
     and override_limit <= entitlement.base_active_dossier_limit then
    raise exception using errcode = 'P5A12', message = 'La derogation de capacite doit augmenter le plafond.';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger account_administrative_entitlement_overrides_validate
before insert or update on public.account_administrative_entitlement_overrides
for each row execute function public.validate_active_administrative_entitlement_override();

create or replace function public.has_application_business_access(
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
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_user_id
  ) or exists (
    select 1
    from public.resolve_effective_account_entitlements(p_user_id, p_at) entitlement
    where entitlement.authorization_active
      and entitlement.access_source <> 'none'
  )
$$;

create or replace function public.resolve_owner_dossier_capacity(p_owner_id uuid)
returns table (
  unlimited boolean,
  active_dossier_limit integer,
  active_dossier_count bigint,
  remaining_dossier_count bigint,
  exceeded_by bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  entitlement record;
begin
  select * into entitlement
  from public.resolve_effective_account_entitlements(p_owner_id, statement_timestamp());

  if entitlement.account_mode is distinct from 'autonomous'
     or entitlement.effective_active_dossier_limit is null then
    raise exception using errcode = 'P4D02', message = 'Capacité de dossiers indisponible.';
  end if;

  return query select
    false,
    entitlement.effective_active_dossier_limit,
    entitlement.active_dossier_count,
    greatest(entitlement.effective_active_dossier_limit::bigint - entitlement.active_dossier_count, 0::bigint),
    greatest(entitlement.active_dossier_count - entitlement.effective_active_dossier_limit::bigint, 0::bigint);
end;
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
  owner_entitlement record;
  caller_entitlement record;
  trial_export_restricted boolean := false;
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

  select * into owner_entitlement
  from public.resolve_effective_account_entitlements(dossier_owner_id, statement_timestamp());
  select * into caller_entitlement
  from public.resolve_effective_account_entitlements(auth.uid(), statement_timestamp());
  trial_export_restricted := owner_entitlement.access_source = 'trial'
    or caller_entitlement.access_source = 'trial';

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
             when context.feature_key = 'data_export' and trial_export_restricted then 'trial_export_unavailable'
             when owner_entitlement.effective_plan_key is not null and not context.plan_included then 'not_in_plan'
             when context.feature_key in ('data_export', 'bank_operation_automation') and caller_role = 'read_only' then 'role_forbidden'
             else null
           end as read_denial_reason,
           case
             when context.implementation_status = 'upcoming' then 'feature_upcoming'
             when context.entitlement_source = 'none' then 'subscription_missing'
             when context.feature_key = 'data_export' and trial_export_restricted then 'trial_export_unavailable'
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

create function public.apply_administrative_plan_assignment(
  p_action text,
  p_owner_id uuid,
  p_assignment_id uuid,
  p_plan_key text,
  p_billing_period text,
  p_dossier_capacity_key text,
  p_reason text,
  p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  current_assignment public.account_administrative_plan_assignments%rowtype;
  result_assignment public.account_administrative_plan_assignments%rowtype;
  existing_event public.account_administrative_entitlement_events%rowtype;
  request_payload jsonb;
  before_state jsonb;
  fallback_limit integer := 0;
  active_count bigint := 0;
begin
  if actor_id is null or not exists (
    select 1 from public.platform_administrators administrator where administrator.user_id = actor_id
  ) then
    raise exception using errcode = '42501', message = 'Acces administrateur requis.';
  end if;
  if p_action not in ('assign', 'replace', 'revoke') or p_owner_id is null
     or p_request_id is null or p_expected_revision is null
     or length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception using errcode = '22023', message = 'Demande administrative invalide.';
  end if;

  request_payload := jsonb_build_object(
    'action', p_action, 'ownerId', p_owner_id, 'assignmentId', p_assignment_id,
    'planKey', p_plan_key, 'billingPeriod', p_billing_period,
    'capacityKey', p_dossier_capacity_key, 'reason', trim(p_reason),
    'expectedRevision', p_expected_revision
  );

  select * into existing_event
  from public.account_administrative_entitlement_events event
  where event.request_id = p_request_id;
  if found then
    if existing_event.owner_id is distinct from p_owner_id
       or existing_event.entity_type <> 'plan_assignment'
       or existing_event.request_payload is distinct from request_payload then
      raise exception using errcode = 'P5A02', message = 'Identifiant de requete deja utilise.';
    end if;
    return query select existing_event.entity_id, existing_event.result_revision,
      coalesce(existing_event.after_state->>'status', 'revoked');
    return;
  end if;

  perform public.lock_owner_dossier_capacity(p_owner_id);
  perform 1 from public.account_subscriptions subscription
  where subscription.owner_id = p_owner_id for update;

  if not exists (
    select 1 from public.application_user_authorizations user_authorization
    where user_authorization.user_id = p_owner_id
      and user_authorization.status = 'active'
      and user_authorization.account_mode = 'autonomous'
  ) or exists (
    select 1 from public.platform_administrators administrator where administrator.user_id = p_owner_id
  ) then
    raise exception using errcode = 'P5A04', message = 'Compte non eligible a une attribution administrative.';
  end if;

  if exists (
    select 1 from public.account_trial_purge_requests purge_request
    where purge_request.user_id = p_owner_id
      and purge_request.state in ('prepared', 'running', 'attention_required')
  ) then
    raise exception using errcode = 'P5A17', message = 'Une purge de compte non terminale interdit cette attribution.';
  end if;

  if public.has_current_commercial_subscription(p_owner_id, statement_timestamp()) then
    raise exception using errcode = 'P5A05', message = 'Un abonnement commercial courant interdit cette attribution.';
  end if;

  if p_action in ('replace', 'revoke') then
    select * into current_assignment
    from public.account_administrative_plan_assignments assignment
    where assignment.id = p_assignment_id and assignment.owner_id = p_owner_id
    for update;
    if not found or current_assignment.status <> 'active' then
      raise exception using errcode = 'P5A06', message = 'Attribution administrative active introuvable.';
    end if;
    if current_assignment.revision <> p_expected_revision then
      raise exception using errcode = '40001', message = 'Revision administrative obsolete.';
    end if;
    if exists (
      select 1 from public.account_administrative_entitlement_overrides entitlement_override
      where entitlement_override.owner_id = p_owner_id and entitlement_override.status = 'active'
    ) then
      raise exception using errcode = 'P5A07', message = 'La derogation active doit etre revoquee auparavant.';
    end if;
    before_state := to_jsonb(current_assignment);
  elsif p_expected_revision <> 0 or p_assignment_id is not null then
    raise exception using errcode = '22023', message = 'Revision initiale invalide.';
  elsif exists (
    select 1 from public.account_administrative_plan_assignments assignment
    where assignment.owner_id = p_owner_id and assignment.status = 'active'
  ) then
    raise exception using errcode = 'P5A08', message = 'Une attribution administrative est deja active.';
  end if;

  select count(*) into active_count
  from public.protected_persons person
  where person.owner_id = p_owner_id and person.status = 'active';

  if p_action in ('assign', 'replace') then
    if p_plan_key is null or p_plan_key not in ('essential', 'comfort', 'premium')
       or p_billing_period is null or p_billing_period not in ('monthly', 'annual')
       or p_dossier_capacity_key is null or p_dossier_capacity_key not in ('included', 'five', 'ten')
       or (p_plan_key = 'essential' and p_dossier_capacity_key <> 'included') then
      raise exception using errcode = 'P5A09', message = 'Formule ou capacite administrative invalide.';
    end if;
    select capacity.active_dossier_limit into fallback_limit
    from public.subscription_dossier_capacities capacity
    where capacity.capacity_key = p_dossier_capacity_key;
    if active_count > fallback_limit then
      raise exception using errcode = 'P5A13', message = 'La capacite est inferieure au nombre de dossiers actifs.';
    end if;
  else
    select case
      when exists (
        select 1 from public.account_trials trial
        where trial.user_id = p_owner_id and trial.started_at is not null
          and statement_timestamp() >= trial.started_at and statement_timestamp() < trial.ends_at
      ) or exists (
        select 1 from public.account_trial_legacy_access legacy where legacy.user_id = p_owner_id
      ) or not (select config.enforcement_enabled from public.account_trial_runtime_config config where config.singleton)
      then capacity.active_dossier_limit else 0 end
    into fallback_limit
    from public.subscription_dossier_capacities capacity where capacity.capacity_key = 'included';
    if active_count > fallback_limit then
      raise exception using errcode = 'P5A13', message = 'La revocation placerait le compte au-dessus de son quota.';
    end if;
  end if;

  if p_action = 'assign' then
    insert into public.account_administrative_plan_assignments(
      owner_id, plan_key, billing_period, dossier_capacity_key, reason, created_by
    ) values (
      p_owner_id, p_plan_key, p_billing_period, p_dossier_capacity_key, trim(p_reason), actor_id
    ) returning * into result_assignment;
  elsif p_action = 'replace' then
    update public.account_administrative_plan_assignments assignment
    set plan_key = p_plan_key,
        billing_period = p_billing_period,
        dossier_capacity_key = p_dossier_capacity_key,
        reason = trim(p_reason),
        revision = assignment.revision + 1
    where assignment.id = current_assignment.id
    returning * into result_assignment;
  else
    update public.account_administrative_plan_assignments assignment
    set status = 'revoked', revoked_at = clock_timestamp(), revoked_by = actor_id,
        reason = trim(p_reason), revision = assignment.revision + 1
    where assignment.id = current_assignment.id
    returning * into result_assignment;
  end if;

  insert into public.account_administrative_entitlement_events(
    request_id, owner_id, entity_type, entity_id, action, actor_kind, actor_id,
    reason, before_state, after_state, request_payload, payload_sha256, result_revision
  ) values (
    p_request_id, p_owner_id, 'plan_assignment', result_assignment.id,
    case p_action when 'assign' then 'assigned' when 'replace' then 'replaced' else 'revoked' end,
    'administrator', actor_id, trim(p_reason), before_state, to_jsonb(result_assignment),
    request_payload, public.administrative_entitlement_payload_hash(request_payload), result_assignment.revision
  );

  return query select result_assignment.id, result_assignment.revision, result_assignment.status;
end;
$$;

create function public.apply_administrative_entitlement_override(
  p_action text,
  p_owner_id uuid,
  p_override_id uuid,
  p_feature_plan_key text,
  p_dossier_capacity_key text,
  p_reason text,
  p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  entitlement record;
  current_override public.account_administrative_entitlement_overrides%rowtype;
  result_override public.account_administrative_entitlement_overrides%rowtype;
  existing_event public.account_administrative_entitlement_events%rowtype;
  request_payload jsonb;
  before_state jsonb;
begin
  if actor_id is null or not exists (
    select 1 from public.platform_administrators administrator where administrator.user_id = actor_id
  ) then
    raise exception using errcode = '42501', message = 'Acces administrateur requis.';
  end if;
  if p_action not in ('assign', 'replace', 'revoke') or p_owner_id is null
     or p_request_id is null or p_expected_revision is null
     or length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception using errcode = '22023', message = 'Demande administrative invalide.';
  end if;

  request_payload := jsonb_build_object(
    'action', p_action, 'ownerId', p_owner_id, 'overrideId', p_override_id,
    'featurePlanKey', p_feature_plan_key, 'capacityKey', p_dossier_capacity_key,
    'reason', trim(p_reason), 'expectedRevision', p_expected_revision
  );
  select * into existing_event from public.account_administrative_entitlement_events event
  where event.request_id = p_request_id;
  if found then
    if existing_event.owner_id is distinct from p_owner_id
       or existing_event.entity_type <> 'entitlement_override'
       or existing_event.request_payload is distinct from request_payload then
      raise exception using errcode = 'P5A02', message = 'Identifiant de requete deja utilise.';
    end if;
    return query select existing_event.entity_id, existing_event.result_revision,
      coalesce(existing_event.after_state->>'status', 'revoked');
    return;
  end if;

  perform public.lock_owner_dossier_capacity(p_owner_id);
  perform 1 from public.account_subscriptions subscription
  where subscription.owner_id = p_owner_id for update;
  perform 1 from public.account_administrative_plan_assignments assignment
  where assignment.owner_id = p_owner_id for update;

  select * into entitlement
  from public.resolve_effective_account_entitlements(p_owner_id, statement_timestamp());
  if entitlement.access_source not in ('commercial', 'administrative') then
    raise exception using errcode = 'P5A10', message = 'Une base commerciale ou administrative active est requise.';
  end if;

  if p_action in ('replace', 'revoke') then
    select * into current_override
    from public.account_administrative_entitlement_overrides entitlement_override
    where entitlement_override.id = p_override_id and entitlement_override.owner_id = p_owner_id
    for update;
    if not found or current_override.status <> 'active' then
      raise exception using errcode = 'P5A14', message = 'Derogation active introuvable.';
    end if;
    if current_override.revision <> p_expected_revision then
      raise exception using errcode = '40001', message = 'Revision administrative obsolete.';
    end if;
    if current_override.base_source is distinct from entitlement.access_source
       or current_override.base_reference_id is distinct from
          coalesce(entitlement.commercial_subscription_id, entitlement.administrative_assignment_id) then
      raise exception using errcode = 'P5A10', message = 'Base de derogation invalide.';
    end if;
    before_state := to_jsonb(current_override);
  elsif p_expected_revision <> 0 or p_override_id is not null then
    raise exception using errcode = '22023', message = 'Revision initiale invalide.';
  elsif exists (
    select 1 from public.account_administrative_entitlement_overrides entitlement_override
    where entitlement_override.owner_id = p_owner_id and entitlement_override.status = 'active'
  ) then
    raise exception using errcode = 'P5A15', message = 'Une derogation administrative est deja active.';
  end if;

  if p_action in ('assign', 'replace') then
    if p_feature_plan_key is null and p_dossier_capacity_key is null then
      raise exception using errcode = 'P5A16', message = 'La derogation doit augmenter au moins un droit.';
    end if;
    if p_feature_plan_key is not null and p_feature_plan_key not in ('comfort', 'premium') then
      raise exception using errcode = 'P5A11', message = 'Niveau fonctionnel de derogation invalide.';
    end if;
    if p_dossier_capacity_key is not null and p_dossier_capacity_key not in ('five', 'ten') then
      raise exception using errcode = 'P5A12', message = 'Capacite de derogation invalide.';
    end if;
  elsif entitlement.active_dossier_count > entitlement.base_active_dossier_limit then
    raise exception using errcode = 'P5A13', message = 'La revocation placerait le compte au-dessus de son quota.';
  end if;

  if p_action = 'assign' then
    insert into public.account_administrative_entitlement_overrides(
      owner_id, base_source, base_reference_id, feature_plan_key,
      dossier_capacity_key, reason, created_by
    ) values (
      p_owner_id, entitlement.access_source,
      coalesce(entitlement.commercial_subscription_id, entitlement.administrative_assignment_id),
      p_feature_plan_key, p_dossier_capacity_key, trim(p_reason), actor_id
    ) returning * into result_override;
  elsif p_action = 'replace' then
    update public.account_administrative_entitlement_overrides entitlement_override
    set feature_plan_key = p_feature_plan_key,
        dossier_capacity_key = p_dossier_capacity_key,
        reason = trim(p_reason),
        revision = entitlement_override.revision + 1
    where entitlement_override.id = current_override.id
    returning * into result_override;
  else
    update public.account_administrative_entitlement_overrides entitlement_override
    set status = 'revoked', revoked_at = clock_timestamp(), revoked_by = actor_id,
        reason = trim(p_reason), revision = entitlement_override.revision + 1
    where entitlement_override.id = current_override.id
    returning * into result_override;
  end if;

  insert into public.account_administrative_entitlement_events(
    request_id, owner_id, entity_type, entity_id, action, actor_kind, actor_id,
    reason, before_state, after_state, request_payload, payload_sha256, result_revision
  ) values (
    p_request_id, p_owner_id, 'entitlement_override', result_override.id,
    case p_action when 'assign' then 'assigned' when 'replace' then 'replaced' else 'revoked' end,
    'administrator', actor_id, trim(p_reason), before_state, to_jsonb(result_override),
    request_payload, public.administrative_entitlement_payload_hash(request_payload), result_override.revision
  );

  return query select result_override.id, result_override.revision, result_override.status;
end;
$$;

create function public.assign_administrative_plan(
  p_owner_id uuid, p_plan_key text, p_billing_period text,
  p_dossier_capacity_key text, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_plan_assignment(
  'assign', p_owner_id, null, p_plan_key, p_billing_period,
  p_dossier_capacity_key, p_reason, p_request_id, p_expected_revision) $$;

create function public.replace_administrative_plan(
  p_owner_id uuid, p_assignment_id uuid, p_plan_key text, p_billing_period text,
  p_dossier_capacity_key text, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_plan_assignment(
  'replace', p_owner_id, p_assignment_id, p_plan_key, p_billing_period,
  p_dossier_capacity_key, p_reason, p_request_id, p_expected_revision) $$;

create function public.revoke_administrative_plan(
  p_owner_id uuid, p_assignment_id uuid, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_plan_assignment(
  'revoke', p_owner_id, p_assignment_id, null, null, null,
  p_reason, p_request_id, p_expected_revision) $$;

create function public.assign_administrative_entitlement_override(
  p_owner_id uuid, p_feature_plan_key text, p_dossier_capacity_key text,
  p_reason text, p_request_id uuid, p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_entitlement_override(
  'assign', p_owner_id, null, p_feature_plan_key, p_dossier_capacity_key,
  p_reason, p_request_id, p_expected_revision) $$;

create function public.replace_administrative_entitlement_override(
  p_owner_id uuid, p_override_id uuid, p_feature_plan_key text,
  p_dossier_capacity_key text, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_entitlement_override(
  'replace', p_owner_id, p_override_id, p_feature_plan_key, p_dossier_capacity_key,
  p_reason, p_request_id, p_expected_revision) $$;

create function public.revoke_administrative_entitlement_override(
  p_owner_id uuid, p_override_id uuid, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language sql security definer set search_path = ''
as $$ select * from public.apply_administrative_entitlement_override(
  'revoke', p_owner_id, p_override_id, null, null,
  p_reason, p_request_id, p_expected_revision) $$;

create function public.supersede_administrative_entitlements_for_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_assignment public.account_administrative_plan_assignments%rowtype;
  affected_override public.account_administrative_entitlement_overrides%rowtype;
  event_payload jsonb;
  previous_state jsonb;
  commercial_is_current boolean := false;
  commercial_stopped boolean := false;
begin
  if tg_op <> 'DELETE' then
    commercial_is_current := new.status in ('active', 'past_due', 'canceled')
      and new.ended_at is null and new.plan_key is not null
      and (new.current_period_ends_at is null or statement_timestamp() < new.current_period_ends_at);
  end if;
  if tg_op <> 'INSERT' then
    commercial_stopped := old.status in ('active', 'past_due', 'canceled')
      and old.ended_at is null and old.plan_key is not null
      and (old.current_period_ends_at is null or statement_timestamp() < old.current_period_ends_at)
      and (tg_op = 'DELETE' or not commercial_is_current);
  end if;

  if commercial_is_current then
    for affected_override in
      select * from public.account_administrative_entitlement_overrides entitlement_override
      where entitlement_override.owner_id = new.owner_id
        and entitlement_override.status = 'active'
        and entitlement_override.base_source = 'administrative'
      for update
    loop
      previous_state := to_jsonb(affected_override);
      update public.account_administrative_entitlement_overrides entitlement_override
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = entitlement_override.revision + 1,
          reason = 'Remplacement automatique par un abonnement commercial.'
      where entitlement_override.id = affected_override.id
      returning * into affected_override;
      event_payload := jsonb_build_object('cause', 'commercial_subscription_started', 'subscriptionId', new.id);
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), new.owner_id, 'entitlement_override', affected_override.id,
        'superseded', 'system', 'Remplacement automatique par un abonnement commercial.',
        previous_state, to_jsonb(affected_override), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_override.revision
      );
    end loop;

    for affected_assignment in
      select * from public.account_administrative_plan_assignments assignment
      where assignment.owner_id = new.owner_id and assignment.status = 'active'
      for update
    loop
      previous_state := to_jsonb(affected_assignment);
      update public.account_administrative_plan_assignments assignment
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = assignment.revision + 1,
          reason = 'Remplacement automatique par un abonnement commercial.'
      where assignment.id = affected_assignment.id
      returning * into affected_assignment;
      event_payload := jsonb_build_object('cause', 'commercial_subscription_started', 'subscriptionId', new.id);
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), new.owner_id, 'plan_assignment', affected_assignment.id,
        'superseded', 'system', 'Remplacement automatique par un abonnement commercial.',
        previous_state, to_jsonb(affected_assignment), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_assignment.revision
      );
    end loop;
  end if;

  if commercial_stopped then
    for affected_override in
      select * from public.account_administrative_entitlement_overrides entitlement_override
      where entitlement_override.owner_id = old.owner_id
        and entitlement_override.status = 'active'
        and entitlement_override.base_source = 'commercial'
        and entitlement_override.base_reference_id = old.id
      for update
    loop
      previous_state := to_jsonb(affected_override);
      update public.account_administrative_entitlement_overrides entitlement_override
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = entitlement_override.revision + 1,
          reason = 'Fin de la base commerciale de la derogation.'
      where entitlement_override.id = affected_override.id
      returning * into affected_override;
      event_payload := jsonb_build_object('cause', 'commercial_subscription_ended', 'subscriptionId', old.id);
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), old.owner_id, 'entitlement_override', affected_override.id,
        'superseded', 'system', 'Fin de la base commerciale de la derogation.',
        previous_state, to_jsonb(affected_override), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_override.revision
      );
    end loop;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger account_subscriptions_supersede_administrative_entitlements
after insert or update or delete on public.account_subscriptions
for each row execute function public.supersede_administrative_entitlements_for_subscription();

revoke all on function public.administrative_entitlement_payload_hash(jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.prevent_administrative_entitlement_event_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.validate_active_administrative_plan_assignment()
from public, anon, authenticated, service_role;
revoke all on function public.validate_active_administrative_entitlement_override()
from public, anon, authenticated, service_role;
revoke all on function public.resolve_effective_account_entitlements(uuid, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.apply_administrative_plan_assignment(text, uuid, uuid, text, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.apply_administrative_entitlement_override(text, uuid, uuid, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.supersede_administrative_entitlements_for_subscription()
from public, anon, authenticated, service_role;

revoke all on function public.assign_administrative_plan(uuid, text, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.replace_administrative_plan(uuid, uuid, text, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_administrative_plan(uuid, uuid, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.assign_administrative_entitlement_override(uuid, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.replace_administrative_entitlement_override(uuid, uuid, text, text, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_administrative_entitlement_override(uuid, uuid, text, uuid, bigint)
from public, anon, authenticated, service_role;

grant execute on function public.assign_administrative_plan(uuid, text, text, text, text, uuid, bigint)
to authenticated;
grant execute on function public.replace_administrative_plan(uuid, uuid, text, text, text, text, uuid, bigint)
to authenticated;
grant execute on function public.revoke_administrative_plan(uuid, uuid, text, uuid, bigint)
to authenticated;
grant execute on function public.assign_administrative_entitlement_override(uuid, text, text, text, uuid, bigint)
to authenticated;
grant execute on function public.replace_administrative_entitlement_override(uuid, uuid, text, text, text, uuid, bigint)
to authenticated;
grant execute on function public.revoke_administrative_entitlement_override(uuid, uuid, text, uuid, bigint)
to authenticated;

comment on table public.account_administrative_plan_assignments is
  'Formules gratuites attribuees par un administrateur, distinctes des abonnements commerciaux.';
comment on table public.account_administrative_entitlement_overrides is
  'Derogations augmentant les droits sans modifier la formule ni le tarif de leur base.';
comment on table public.account_administrative_entitlement_events is
  'Historique immuable et idempotent des decisions administratives de droits.';
comment on function public.resolve_effective_account_entitlements(uuid, timestamptz) is
  'Resout la priorite commercial, attribution administrative, essai, acces historique puis developpement, avant derogation.';

-- PAT-ADMIN-USERS-05C
-- Durcissements additifs validables sans reinitialiser la pile locale :
-- blocage des purges non terminales, validation explicite des champs requis
-- et etats avant/apres complets pour les supersessions automatiques.

create function public.prevent_active_assignment_during_account_purge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active' and exists (
    select 1 from public.account_trial_purge_requests purge_request
    where purge_request.user_id = new.owner_id
      and purge_request.state in ('prepared', 'running', 'attention_required')
  ) then
    raise exception using
      errcode = 'P5A17',
      message = 'Une purge de compte non terminale interdit cette attribution.';
  end if;
  return new;
end;
$$;

create trigger account_administrative_plan_assignments_block_open_purge
before insert or update of owner_id, status
on public.account_administrative_plan_assignments
for each row execute function public.prevent_active_assignment_during_account_purge();

create or replace function public.assign_administrative_plan(
  p_owner_id uuid, p_plan_key text, p_billing_period text,
  p_dossier_capacity_key text, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_plan_key is null or p_billing_period is null or p_dossier_capacity_key is null then
    raise exception using errcode = 'P5A09', message = 'Formule ou capacite administrative invalide.';
  end if;
  return query select * from public.apply_administrative_plan_assignment(
    'assign', p_owner_id, null, p_plan_key, p_billing_period,
    p_dossier_capacity_key, p_reason, p_request_id, p_expected_revision);
end;
$$;

create or replace function public.replace_administrative_plan(
  p_owner_id uuid, p_assignment_id uuid, p_plan_key text, p_billing_period text,
  p_dossier_capacity_key text, p_reason text, p_request_id uuid,
  p_expected_revision bigint
)
returns table (entity_id uuid, revision bigint, status text)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_plan_key is null or p_billing_period is null or p_dossier_capacity_key is null then
    raise exception using errcode = 'P5A09', message = 'Formule ou capacite administrative invalide.';
  end if;
  return query select * from public.apply_administrative_plan_assignment(
    'replace', p_owner_id, p_assignment_id, p_plan_key, p_billing_period,
    p_dossier_capacity_key, p_reason, p_request_id, p_expected_revision);
end;
$$;

create or replace function public.supersede_administrative_entitlements_for_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_assignment public.account_administrative_plan_assignments%rowtype;
  affected_override public.account_administrative_entitlement_overrides%rowtype;
  event_payload jsonb;
  previous_state jsonb;
  commercial_is_current boolean := false;
  commercial_stopped boolean := false;
begin
  if tg_op <> 'DELETE' then
    commercial_is_current := new.status in ('active', 'past_due', 'canceled')
      and new.ended_at is null and new.plan_key is not null
      and (new.current_period_ends_at is null or statement_timestamp() < new.current_period_ends_at);
  end if;
  if tg_op <> 'INSERT' then
    commercial_stopped := old.status in ('active', 'past_due', 'canceled')
      and old.ended_at is null and old.plan_key is not null
      and (old.current_period_ends_at is null or statement_timestamp() < old.current_period_ends_at)
      and (tg_op = 'DELETE' or not commercial_is_current);
  end if;

  if commercial_is_current then
    for affected_override in
      select * from public.account_administrative_entitlement_overrides entitlement_override
      where entitlement_override.owner_id = new.owner_id
        and entitlement_override.status = 'active'
        and entitlement_override.base_source = 'administrative'
      for update
    loop
      previous_state := to_jsonb(affected_override);
      update public.account_administrative_entitlement_overrides entitlement_override
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = entitlement_override.revision + 1,
          reason = 'Remplacement automatique par un abonnement commercial.'
      where entitlement_override.id = affected_override.id
      returning * into affected_override;
      event_payload := jsonb_build_object(
        'cause', 'commercial_subscription_started', 'subscriptionId', new.id
      );
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), new.owner_id, 'entitlement_override', affected_override.id,
        'superseded', 'system', 'Remplacement automatique par un abonnement commercial.',
        previous_state, to_jsonb(affected_override), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_override.revision
      );
    end loop;

    for affected_assignment in
      select * from public.account_administrative_plan_assignments assignment
      where assignment.owner_id = new.owner_id and assignment.status = 'active'
      for update
    loop
      previous_state := to_jsonb(affected_assignment);
      update public.account_administrative_plan_assignments assignment
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = assignment.revision + 1,
          reason = 'Remplacement automatique par un abonnement commercial.'
      where assignment.id = affected_assignment.id
      returning * into affected_assignment;
      event_payload := jsonb_build_object(
        'cause', 'commercial_subscription_started', 'subscriptionId', new.id
      );
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), new.owner_id, 'plan_assignment', affected_assignment.id,
        'superseded', 'system', 'Remplacement automatique par un abonnement commercial.',
        previous_state, to_jsonb(affected_assignment), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_assignment.revision
      );
    end loop;
  end if;

  if commercial_stopped then
    for affected_override in
      select * from public.account_administrative_entitlement_overrides entitlement_override
      where entitlement_override.owner_id = old.owner_id
        and entitlement_override.status = 'active'
        and entitlement_override.base_source = 'commercial'
        and entitlement_override.base_reference_id = old.id
      for update
    loop
      previous_state := to_jsonb(affected_override);
      update public.account_administrative_entitlement_overrides entitlement_override
      set status = 'superseded', superseded_at = clock_timestamp(),
          revision = entitlement_override.revision + 1,
          reason = 'Fin de la base commerciale de la derogation.'
      where entitlement_override.id = affected_override.id
      returning * into affected_override;
      event_payload := jsonb_build_object(
        'cause', 'commercial_subscription_ended', 'subscriptionId', old.id
      );
      insert into public.account_administrative_entitlement_events(
        request_id, owner_id, entity_type, entity_id, action, actor_kind, reason,
        before_state, after_state, request_payload, payload_sha256, result_revision
      ) values (
        gen_random_uuid(), old.owner_id, 'entitlement_override', affected_override.id,
        'superseded', 'system', 'Fin de la base commerciale de la derogation.',
        previous_state, to_jsonb(affected_override), event_payload,
        public.administrative_entitlement_payload_hash(event_payload), affected_override.revision
      );
    end loop;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.prevent_active_assignment_during_account_purge()
from public, anon, authenticated, service_role;

-- PAT-ADMIN-USERS-05C
-- Preserve la distinction historique entre une ligne development et une
-- absence totale d'abonnement, tout en laissant un compte actif sans mode
-- choisir son premier parcours lorsque l'enforcement des essais est desactive.

alter function public.resolve_effective_account_entitlements(uuid, timestamptz)
rename to resolve_effective_account_entitlements_unchecked;

create function public.resolve_effective_account_entitlements(
  p_owner_id uuid,
  p_at timestamptz default statement_timestamp()
)
returns table (
  authorization_active boolean,
  account_mode text,
  access_source text,
  commercial_subscription_id uuid,
  administrative_assignment_id uuid,
  base_plan_key text,
  effective_plan_key text,
  base_active_dossier_limit integer,
  effective_active_dossier_limit integer,
  administrative_override_id uuid,
  active_dossier_count bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    entitlement.authorization_active,
    entitlement.account_mode,
    case
      when entitlement.access_source = 'development' and not exists (
        select 1 from public.account_subscriptions subscription
        where subscription.owner_id = p_owner_id
          and subscription.status = 'development'
          and subscription.ended_at is null
      ) then 'none'
      else entitlement.access_source
    end,
    entitlement.commercial_subscription_id,
    entitlement.administrative_assignment_id,
    entitlement.base_plan_key,
    entitlement.effective_plan_key,
    case
      when entitlement.access_source = 'development' and not exists (
        select 1 from public.account_subscriptions subscription
        where subscription.owner_id = p_owner_id
          and subscription.status = 'development'
          and subscription.ended_at is null
      ) then null
      else entitlement.base_active_dossier_limit
    end,
    case
      when entitlement.access_source = 'development' and not exists (
        select 1 from public.account_subscriptions subscription
        where subscription.owner_id = p_owner_id
          and subscription.status = 'development'
          and subscription.ended_at is null
      ) then null
      else entitlement.effective_active_dossier_limit
    end,
    entitlement.administrative_override_id,
    entitlement.active_dossier_count
  from public.resolve_effective_account_entitlements_unchecked(p_owner_id, p_at) entitlement
$$;

create or replace function public.has_application_business_access(
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
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_user_id
  ) or exists (
    select 1
    from public.application_user_authorizations user_authorization
    cross join public.account_trial_runtime_config config
    where user_authorization.user_id = p_user_id
      and user_authorization.status = 'active'
      and user_authorization.account_mode is null
      and not config.enforcement_enabled
  ) or exists (
    select 1
    from public.resolve_effective_account_entitlements(p_user_id, p_at) entitlement
    where entitlement.authorization_active
      and entitlement.access_source <> 'none'
  )
$$;

revoke all on function public.resolve_effective_account_entitlements_unchecked(uuid, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_effective_account_entitlements(uuid, timestamptz)
from public, anon, authenticated, service_role;

comment on function public.resolve_effective_account_entitlements_unchecked(uuid, timestamptz) is
  'Implementation interne brute. Utiliser exclusivement le resolveur public homonyme securise.';

-- PAT-ADMIN-USERS-05C
-- Lorsque l'enforcement J30/J60 est desactive, tous les comptes actifs
-- conservent exactement l'acces applicatif historique. Le resolveur de
-- fonctionnalites et de quotas continue toutefois a distinguer l'absence
-- d'abonnement development.

create or replace function public.has_application_business_access(
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
    select 1 from public.platform_administrators administrator
    where administrator.user_id = p_user_id
  ) or exists (
    select 1
    from public.application_user_authorizations user_authorization
    cross join public.account_trial_runtime_config config
    where user_authorization.user_id = p_user_id
      and user_authorization.status = 'active'
      and (
        not config.enforcement_enabled
        or user_authorization.account_mode = 'collaborator'
        or exists (
          select 1
          from public.resolve_effective_account_entitlements(p_user_id, p_at) entitlement
          where entitlement.access_source <> 'none'
        )
      )
  )
$$;

-- PAT-ADMIN-USERS-05C
-- Preserve le message fonctionnel stable du moteur de quotas apres sa
-- centralisation sur les droits effectifs.

create or replace function public.resolve_owner_dossier_capacity(p_owner_id uuid)
returns table (
  unlimited boolean,
  active_dossier_limit integer,
  active_dossier_count bigint,
  remaining_dossier_count bigint,
  exceeded_by bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  entitlement record;
begin
  select * into entitlement
  from public.resolve_effective_account_entitlements(p_owner_id, statement_timestamp());

  if entitlement.account_mode is distinct from 'autonomous'
     or entitlement.effective_active_dossier_limit is null then
    raise exception using
      errcode = 'P4D02',
      message = 'Capacité de dossiers indisponible.';
  end if;

  return query select
    false,
    entitlement.effective_active_dossier_limit,
    entitlement.active_dossier_count,
    greatest(entitlement.effective_active_dossier_limit::bigint - entitlement.active_dossier_count, 0::bigint),
    greatest(entitlement.active_dossier_count - entitlement.effective_active_dossier_limit::bigint, 0::bigint);
end;
$$;

-- PAT-ADMIN-USERS-05C
-- Les nouvelles fondations ne doivent pas bloquer les suppressions de comptes.
-- Les decisions restent conservees, mais les identifiants Auth sont anonymises
-- par les seules actions referentielles PostgreSQL autorisees.

alter table public.account_administrative_plan_assignments
  drop constraint account_administrative_plan_assignment_terminal,
  add constraint account_administrative_plan_assignment_terminal check (
    (status = 'active' and revoked_at is null and revoked_by is null and superseded_at is null)
    or (status = 'revoked' and revoked_at is not null and superseded_at is null)
    or (status = 'superseded' and superseded_at is not null and revoked_at is null and revoked_by is null)
  ),
  drop constraint account_administrative_plan_assignments_owner_id_fkey,
  add constraint account_administrative_plan_assignments_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete cascade,
  drop constraint account_administrative_plan_assignments_created_by_fkey,
  alter column created_by drop not null,
  add constraint account_administrative_plan_assignments_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null,
  drop constraint account_administrative_plan_assignments_revoked_by_fkey,
  add constraint account_administrative_plan_assignments_revoked_by_fkey
    foreign key (revoked_by) references auth.users(id) on delete set null;

alter table public.account_administrative_entitlement_overrides
  drop constraint account_administrative_override_terminal,
  add constraint account_administrative_override_terminal check (
    (status = 'active' and revoked_at is null and revoked_by is null and superseded_at is null)
    or (status = 'revoked' and revoked_at is not null and superseded_at is null)
    or (status = 'superseded' and superseded_at is not null and revoked_at is null and revoked_by is null)
  ),
  drop constraint account_administrative_entitlement_overrides_owner_id_fkey,
  add constraint account_administrative_entitlement_overrides_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete cascade,
  drop constraint account_administrative_entitlement_overrides_created_by_fkey,
  alter column created_by drop not null,
  add constraint account_administrative_entitlement_overrides_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null,
  drop constraint account_administrative_entitlement_overrides_revoked_by_fkey,
  add constraint account_administrative_entitlement_overrides_revoked_by_fkey
    foreign key (revoked_by) references auth.users(id) on delete set null;

alter table public.account_administrative_entitlement_events
  drop constraint account_administrative_entitlement_events_owner_id_fkey,
  alter column owner_id drop not null,
  add constraint account_administrative_entitlement_events_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete set null,
  drop constraint account_administrative_entitlement_events_actor_id_fkey,
  add constraint account_administrative_entitlement_events_actor_id_fkey
    foreign key (actor_id) references auth.users(id) on delete set null,
  drop constraint account_administrative_event_actor,
  add constraint account_administrative_event_actor check (
    actor_kind = 'administrator'
    or (actor_kind = 'system' and actor_id is null)
  );

create or replace function public.prevent_administrative_entitlement_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'owner_id' - 'actor_id') =
         (to_jsonb(old) - 'owner_id' - 'actor_id')
     and (new.owner_id is null or new.owner_id is not distinct from old.owner_id)
     and (new.actor_id is null or new.actor_id is not distinct from old.actor_id) then
    return new;
  end if;

  raise exception using
    errcode = 'P5A20',
    message = 'L historique administratif est immuable.';
end;
$$;

comment on function public.prevent_administrative_entitlement_event_mutation() is
  'Interdit toute mutation du journal, sauf anonymisation referentielle des identifiants Auth lors d une suppression de compte.';

-- La suppression definitive d'un compte Auth conserve les decisions metier,
-- mais retire l'identifiant supprime de toutes les structures d'audit. Cette
-- operation est uniquement declenchee par DELETE sur auth.users.
alter table public.account_administrative_entitlement_events
  add column identifiers_anonymized_at timestamptz;

create function public.scrub_deleted_account_identifier(
  p_value jsonb,
  p_deleted_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  value_type text;
  deleted_identifier text := p_deleted_user_id::text;
  result jsonb;
begin
  if p_value is null then
    return null;
  end if;

  value_type := jsonb_typeof(p_value);
  if value_type = 'object' then
    select coalesce(
      jsonb_object_agg(
        replace(entry.key, deleted_identifier, '[deleted-account]'),
        public.scrub_deleted_account_identifier(entry.value, p_deleted_user_id)
      ),
      '{}'::jsonb
    )
    into result
    from jsonb_each(p_value) entry;
    return result;
  elsif value_type = 'array' then
    select coalesce(
      jsonb_agg(public.scrub_deleted_account_identifier(item.value, p_deleted_user_id)
        order by item.ordinality),
      '[]'::jsonb
    )
    into result
    from jsonb_array_elements(p_value) with ordinality item(value, ordinality);
    return result;
  elsif value_type = 'string' then
    return to_jsonb(replace(p_value #>> '{}', deleted_identifier, '[deleted-account]'));
  end if;

  return p_value;
end;
$$;

create or replace function public.prevent_administrative_entitlement_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_user_id uuid;
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    begin
      deleted_user_id := nullif(
        current_setting('patrigest.deleted_auth_user_id', true),
        ''
      )::uuid;
    exception when invalid_text_representation then
      deleted_user_id := null;
    end;

    if deleted_user_id is not null
       and (to_jsonb(new)
              - 'owner_id' - 'actor_id'
              - 'before_state' - 'after_state' - 'request_payload'
              - 'payload_sha256' - 'identifiers_anonymized_at') =
           (to_jsonb(old)
              - 'owner_id' - 'actor_id'
              - 'before_state' - 'after_state' - 'request_payload'
              - 'payload_sha256' - 'identifiers_anonymized_at')
       and new.owner_id is not distinct from (
         case when old.owner_id = deleted_user_id then null else old.owner_id end
       )
       and new.actor_id is not distinct from (
         case when old.actor_id = deleted_user_id then null else old.actor_id end
       )
       and new.before_state is not distinct from
         public.scrub_deleted_account_identifier(old.before_state, deleted_user_id)
       and new.after_state is not distinct from
         public.scrub_deleted_account_identifier(old.after_state, deleted_user_id)
       and new.request_payload =
         public.scrub_deleted_account_identifier(old.request_payload, deleted_user_id)
       and new.payload_sha256 =
         public.administrative_entitlement_payload_hash(new.request_payload)
       and new.identifiers_anonymized_at is not null
       and (
         old.identifiers_anonymized_at is null
         or new.identifiers_anonymized_at >= old.identifiers_anonymized_at
       ) then
      return new;
    end if;
  end if;

  raise exception using
    errcode = 'P5A20',
    message = 'L historique administratif est immuable.';
end;
$$;

create function public.anonymize_administrative_entitlement_history_on_auth_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('patrigest.deleted_auth_user_id', old.id::text, true);

  update public.account_administrative_entitlement_events event
  set owner_id = case when event.owner_id = old.id then null else event.owner_id end,
      actor_id = case when event.actor_id = old.id then null else event.actor_id end,
      before_state = public.scrub_deleted_account_identifier(event.before_state, old.id),
      after_state = public.scrub_deleted_account_identifier(event.after_state, old.id),
      request_payload = public.scrub_deleted_account_identifier(event.request_payload, old.id),
      payload_sha256 = public.administrative_entitlement_payload_hash(
        public.scrub_deleted_account_identifier(event.request_payload, old.id)
      ),
      identifiers_anonymized_at = clock_timestamp()
  where event.owner_id = old.id
     or event.actor_id = old.id
     or event.before_state::text like '%' || old.id::text || '%'
     or event.after_state::text like '%' || old.id::text || '%'
     or event.request_payload::text like '%' || old.id::text || '%';

  return old;
end;
$$;

create trigger auth_users_anonymize_administrative_entitlement_history
before delete on auth.users
for each row execute function
  public.anonymize_administrative_entitlement_history_on_auth_delete();

revoke all on function public.scrub_deleted_account_identifier(jsonb,uuid)
from public, anon, authenticated, service_role;
revoke all on function public.anonymize_administrative_entitlement_history_on_auth_delete()
from public, anon, authenticated, service_role;

comment on column public.account_administrative_entitlement_events.identifiers_anonymized_at is
  'Date du retrait des identifiants Auth lors de la suppression definitive du compte concerne.';
comment on function public.scrub_deleted_account_identifier(jsonb,uuid) is
  'Retire recursivement un identifiant Auth des cles et valeurs JSON sans produire de pseudonyme reversible.';
comment on function public.anonymize_administrative_entitlement_history_on_auth_delete() is
  'Trigger interne : conserve les decisions administratives et retire l identifiant du compte supprime.';
comment on function public.prevent_administrative_entitlement_event_mutation() is
  'Rend le journal immuable, hors retrait strictement borne des identifiants lors de DELETE sur auth.users.';
