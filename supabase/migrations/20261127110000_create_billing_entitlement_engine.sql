-- PAT-STRIPE-02C. Internal decisions and recorded transitions only.
-- No application caller or external writer is enabled in this migration.

create schema billing_internal;
revoke all on schema billing_internal from public, anon, authenticated, service_role;

create table billing_internal.accepted_invoice_periods (
  invoice_id uuid primary key,
  context_id uuid not null,
  subscription_id uuid not null,
  applied_at timestamptz not null,
  billed_from timestamptz not null,
  paid_until timestamptz not null,
  plan_key text not null references public.subscription_plans(plan_key),
  superseded_assignment_id uuid references public.account_administrative_plan_assignments(id),
  consent_attempt_id uuid references public.billing_checkout_attempts(id),
  foreign key (context_id, subscription_id, invoice_id)
    references public.billing_invoice_periods(context_id, billing_subscription_id, id),
  check (paid_until > billed_from and paid_until > applied_at),
  check (superseded_assignment_id is null or consent_attempt_id is not null)
);
create index billing_accepted_invoice_subscription_idx
on billing_internal.accepted_invoice_periods(subscription_id, applied_at);

-- An explicit administrative replacement, recorded separately from the old
-- resolver so the same assignment can be audited during the transition.
create table billing_internal.transition_access_replacements (
  assignment_id uuid primary key references public.account_administrative_plan_assignments(id),
  effective_at timestamptz not null
);

alter table billing_internal.accepted_invoice_periods enable row level security;
alter table billing_internal.transition_access_replacements enable row level security;
revoke all on billing_internal.accepted_invoice_periods, billing_internal.transition_access_replacements
from public, anon, authenticated, service_role;

create function public.billing_retention_deadline(p_start timestamptz)
returns timestamptz
language sql immutable strict set search_path = '' as $$
  -- Civil arithmetic clamps leap day. PostgreSQL chooses the standard-time
  -- offset for ambiguous or nonexistent times (a spring gap shifts forward).
  select ((p_start at time zone 'Europe/Paris') + interval '12 months')
    at time zone 'Europe/Paris';
$$;

create function public.billing_administrative_periods(p_owner uuid)
returns table (assignment_id uuid, starts_at timestamptz, ends_at timestamptz,
               plan_key text, capacity integer)
language sql stable set search_path = '' as $$
  select assignment.id, coalesce(assignment.valid_from, assignment.created_at),
    least(assignment.valid_until, assignment.revoked_at, assignment.superseded_at,
      (select min(payment.applied_at) from billing_internal.accepted_invoice_periods payment
       where payment.superseded_assignment_id = assignment.id)),
    assignment.plan_key, capacity.active_dossier_limit
  from public.account_administrative_plan_assignments assignment
  join public.subscription_dossier_capacities capacity
    on capacity.capacity_key = assignment.dossier_capacity_key
  where assignment.owner_id = p_owner;
$$;

create function public.billing_resolve_entitlements_at(p_owner uuid, p_at timestamptz)
returns table (
  access_source text, base_plan_key text, effective_plan_key text,
  active_dossier_limit integer, active_dossier_count bigint, features text[],
  commercial_state text, stripe_status text, lifecycle_state text,
  rights_end_at timestamptz, grace_ends_at timestamptz,
  retention_started_at timestamptz, retention_until timestamptz,
  purge_eligible boolean, payment_uncertain boolean,
  subscription_id uuid, administrative_assignment_id uuid, administrative_override_id uuid
)
language plpgsql stable set search_path = '' as $$
declare
  subject record;
  contract record;
  paid record;
  assignment record;
  trial public.account_trials%rowtype;
  paid_end timestamptz;
  last_admin_end timestamptz;
  fallback_replaced boolean;
  irreversible boolean;
  feature_keys text[];
  base_limit integer;
begin
  if p_at is null then
    raise exception using errcode = '22004', message = 'Instant de référence obligatoire.';
  end if;

  select mode.account_mode, mode.status into subject
  from public.application_user_authorizations mode where mode.user_id = p_owner;

  access_source := 'none';
  commercial_state := 'none';
  lifecycle_state := 'unavailable';
  features := array[]::text[];
  purge_eligible := false;
  payment_uncertain := false;
  select count(*) into active_dossier_count from public.protected_persons person
  where person.owner_id = p_owner and person.status = 'active';

  if subject.status is distinct from 'active' then
    return next;
    return;
  end if;
  if subject.account_mode = 'collaborator' then
    access_source := 'shared_access';
    lifecycle_state := 'shared_access';
    return next;
    return;
  end if;
  if subject.account_mode is distinct from 'autonomous' then
    return next;
    return;
  end if;

  select exists (
    select 1 from public.billing_purge_jobs job
    where job.owner_id = p_owner and job.irreversible_at <= p_at
  ) into irreversible;
  if irreversible then
    lifecycle_state := 'purge_irreversible';
    return next;
    return;
  end if;

  -- A later accepted contract permanently replaces the preceding one. A
  -- subsequent renewal of the old contract cannot change this ordering.
  select subscription.* into contract
  from public.billing_subscriptions subscription
  join public.billing_customers customer on customer.context_id = subscription.context_id
    and customer.id = subscription.billing_customer_id
  join lateral (
    select min(payment.applied_at) as first_applied_at
    from billing_internal.accepted_invoice_periods payment
    where payment.subscription_id = subscription.id and payment.applied_at <= p_at
  ) activation on activation.first_applied_at is not null
  where customer.owner_id = p_owner
  order by activation.first_applied_at desc, subscription.started_at desc, subscription.id
  limit 1;

  if contract.id is not null then
    subscription_id := contract.id;
    stripe_status := contract.stripe_status;
    select payment.* into strict paid
    from billing_internal.accepted_invoice_periods payment
    where payment.subscription_id = contract.id and payment.applied_at <= p_at
    order by payment.paid_until desc, payment.applied_at desc, payment.invoice_id
    limit 1;

    paid_end := paid.paid_until;
    if contract.end_reason = 'administrative' then
      paid_end := least(paid_end, contract.stripe_ended_at);
    end if;
    if p_at >= paid_end and contract.cancel_effective_at is null and
        (contract.end_reason is null or contract.end_reason = 'nonpayment') then
      grace_ends_at := paid_end + interval '336 hours';
    end if;

    if p_at < paid_end then
      commercial_state := 'paid';
      rights_end_at := paid_end;
    elsif p_at < grace_ends_at then
      commercial_state := 'grace';
      rights_end_at := grace_ends_at;
    else
      commercial_state := 'ended';
      retention_started_at := coalesce(grace_ends_at, paid_end);
    end if;
    if commercial_state in ('paid', 'grace') then
      access_source := 'commercial';
      base_plan_key := paid.plan_key;
      active_dossier_limit := 2;
    end if;
  end if;

  if access_source = 'none' then
    select period.* into assignment
    from public.billing_administrative_periods(p_owner) period
    where period.starts_at <= p_at and (period.ends_at is null or p_at < period.ends_at)
    order by period.starts_at desc, period.assignment_id limit 1;
    if found then
      access_source := 'administrative';
      administrative_assignment_id := assignment.assignment_id;
      base_plan_key := assignment.plan_key;
      active_dossier_limit := assignment.capacity;
      rights_end_at := assignment.ends_at;
      retention_started_at := null;
    end if;
  end if;

  if access_source = 'none' then
    fallback_replaced := contract.id is not null or exists (
      select 1 from billing_internal.transition_access_replacements replacement
      join public.billing_administrative_periods(p_owner) period
        on period.assignment_id = replacement.assignment_id
      where replacement.effective_at <= p_at
    );
    select * into trial from public.account_trials entry where entry.user_id = p_owner;

    if not fallback_replaced then
      if p_at >= trial.started_at and p_at < trial.ends_at then
        access_source := 'trial';
        active_dossier_limit := 2;
        rights_end_at := trial.ends_at;
      elsif exists (select 1 from public.account_trial_legacy_access legacy
                    where legacy.user_id = p_owner and legacy.recorded_at <= p_at) then
        access_source := 'legacy';
        active_dossier_limit := 2;
      elsif trial.started_at is null and exists (
        select 1 from public.account_subscriptions existing
        where existing.owner_id = p_owner and existing.status = 'development'
          and existing.started_at <= p_at and (existing.ended_at is null or p_at < existing.ended_at)
      ) then
        access_source := 'development';
        active_dossier_limit := 2;
      end if;
    end if;

    if access_source = 'none' then
      select max(period.ends_at) into last_admin_end
      from public.billing_administrative_periods(p_owner) period
      where period.ends_at <= p_at and period.ends_at > period.starts_at;
      retention_started_at := greatest(retention_started_at, last_admin_end);
      if retention_started_at is not null then
        retention_until := public.billing_retention_deadline(retention_started_at);
        lifecycle_state := 'retention';
      elsif not fallback_replaced and p_at >= trial.ends_at then
        retention_started_at := trial.ends_at;
        retention_until := trial.deletion_eligible_at;
        lifecycle_state := 'trial_suspended';
      end if;
    end if;
  end if;

  -- Only evidence that requires investigation holds a purge. An ordinary
  -- failed or open invoice is insufficient. A terminal/replaced contract
  -- cannot benefit from or delay the lifecycle through an old invoice.
  select exists (
    select 1 from public.billing_customers customer
    join public.billing_stripe_contexts context on context.id = customer.context_id and context.mode = 'live'
    join public.billing_subscriptions candidate on candidate.context_id = customer.context_id
      and candidate.billing_customer_id = customer.id
    join public.billing_invoice_periods invoice on invoice.billing_subscription_id = candidate.id
    where customer.owner_id = p_owner and invoice.stripe_reported_paid_at <= p_at
      and candidate.started_at <= p_at
      and (candidate.stripe_ended_at is null or p_at < candidate.stripe_ended_at)
      and candidate.stripe_status not in ('canceled', 'incomplete_expired')
      and (candidate.cancel_effective_at is null or p_at < candidate.cancel_effective_at)
      and (contract.id is null or candidate.id = contract.id or candidate.started_at > contract.started_at)
      and not exists (select 1 from billing_internal.accepted_invoice_periods payment
                      where payment.invoice_id = invoice.id and payment.applied_at <= p_at)
  ) into payment_uncertain;

  if access_source = 'none' then
    purge_eligible := coalesce(p_at >= retention_until, false) and not payment_uncertain;
    if purge_eligible then lifecycle_state := 'purge_eligible'; end if;
    return next;
    return;
  end if;

  lifecycle_state := case when commercial_state = 'grace' then 'grace' else 'active' end;
  effective_plan_key := base_plan_key;
  if access_source in ('commercial', 'administrative') then
    base_limit := active_dossier_limit;
    select entry.id, coalesce(entry.feature_plan_key, base_plan_key),
      greatest(base_limit, capacity.active_dossier_limit)
    into administrative_override_id, effective_plan_key, active_dossier_limit
    from public.account_administrative_entitlement_overrides entry
    left join public.subscription_dossier_capacities capacity
      on capacity.capacity_key = entry.dossier_capacity_key
    where entry.owner_id = p_owner and entry.base_source = access_source
      and entry.base_reference_id = case when access_source = 'commercial'
        then contract.account_subscription_id else administrative_assignment_id end
      and entry.created_at <= p_at
      and (least(entry.revoked_at, entry.superseded_at) is null
        or p_at < least(entry.revoked_at, entry.superseded_at))
    order by entry.created_at desc, entry.id limit 1;
    if not found then
      effective_plan_key := base_plan_key;
      active_dossier_limit := base_limit;
    end if;
  end if;

  select coalesce(array_agg(feature.feature_key order by feature.sort_order), array[]::text[])
  into feature_keys
  from public.subscription_features feature
  left join public.subscription_plan_features plan_feature
    on plan_feature.feature_key = feature.feature_key and plan_feature.plan_key = effective_plan_key
  where feature.implementation_status = 'available'
    and (effective_plan_key is null or plan_feature.included)
    and (access_source <> 'trial' or feature.feature_key <> 'data_export');

  features := feature_keys;
  if 'core_management' = any(feature_keys) then
    features := features || array['bank_reconciliation','uploaded_document_upload',
      'uploaded_document_read','uploaded_document_download','management_report_prepare','management_report_screen_preview'];
    if access_source <> 'trial' then
      features := features || array['application_pdf_generate','management_report_finalize','management_report_print'];
    end if;
  end if;
  if 'data_export' = any(feature_keys) then
    features := features || array['csv_export','excel_export','dossier_export','global_zip_export'];
  end if;
  return next;
end;
$$;

-- Future authorization callers can only obtain the server-time decision.
-- Returning zero rows when disabled prevents switching existing behavior.
create function public.billing_resolve_current_entitlements(p_owner uuid)
returns setof jsonb
language sql stable set search_path = '' as $$
  select to_jsonb(decision) from public.billing_runtime_config config
  cross join lateral public.billing_resolve_entitlements_at(p_owner, statement_timestamp()) decision
  where config.singleton and config.commercial_access_enabled;
$$;

-- Only trusted database owners can call this simulation/materialization
-- boundary. Future ingestion must call it under the same owner lock.
create function public.billing_record_lifecycle_at(p_owner uuid, p_at timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  decision record;
  episode record;
  due_at timestamptz;
begin
  perform public.lock_owner_dossier_capacity(p_owner);
  select * into strict decision from public.billing_resolve_entitlements_at(p_owner, p_at);

  if decision.grace_ends_at is not null then
    due_at := decision.grace_ends_at - interval '336 hours';
    if due_at <= p_at then
      insert into public.billing_lifecycle_episodes(
        owner_id, kind, episode_key, context_id, billing_customer_id, billing_subscription_id,
        renewal_due_at, grace_ends_at, starts_at
      ) select p_owner, 'renewal_arrears', gen_random_uuid(), subscription.context_id,
        subscription.billing_customer_id, subscription.id, due_at, decision.grace_ends_at, due_at
      from public.billing_subscriptions subscription where subscription.id = decision.subscription_id
      on conflict do nothing returning id, episode_key into episode;

      if found then
        insert into public.billing_lifecycle_events(episode_id, transition_key, transition_code, source, occurred_at)
        values (episode.id, episode.episode_key, 'renewal_due', 'system', due_at);
      end if;
    end if;
  end if;

  if decision.access_source in ('commercial', 'administrative') then
    update public.billing_purge_jobs set state = 'canceled', canceled_at = p_at
    where owner_id = p_owner and irreversible_at is null
      and state in ('reserved', 'eligible', 'attention_required');
  end if;

  with closed as (
    update public.billing_lifecycle_episodes entry set closed_at = p_at
    where entry.owner_id = p_owner and entry.closed_at is null and entry.starts_at <= p_at
      and ((entry.kind = 'retention' and decision.lifecycle_state <> 'purge_irreversible'
            and (decision.retention_started_at is distinct from entry.starts_at
                 or decision.retention_until is distinct from entry.retention_until))
        or (entry.kind = 'renewal_arrears'
            and (entry.billing_subscription_id is distinct from decision.subscription_id
              or entry.grace_ends_at is distinct from decision.grace_ends_at)))
    returning entry.id
  )
  insert into public.billing_lifecycle_events(episode_id, transition_key, transition_code, source, occurred_at)
  select id, gen_random_uuid(), 'episode_closed', 'system', p_at from closed;

  -- The existing trial dates are authoritative and remain in account_trials.
  if decision.retention_until is not null and decision.lifecycle_state <> 'trial_suspended'
     and decision.retention_until = public.billing_retention_deadline(decision.retention_started_at) then
    insert into public.billing_lifecycle_episodes(
      owner_id, kind, episode_key, access_ended_at, retention_until, starts_at
    ) values (p_owner, 'retention', gen_random_uuid(), decision.retention_started_at,
      decision.retention_until, decision.retention_started_at)
    on conflict do nothing returning id, episode_key into episode;

    if found then
      insert into public.billing_lifecycle_events(episode_id, transition_key, transition_code, source, occurred_at)
      values (episode.id, episode.episode_key, 'retention_started', 'system', decision.retention_started_at);
    end if;
  end if;
end;
$$;

create function public.billing_record_transition_replacement_at(p_assignment uuid, p_at timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  owner_id uuid;
begin
  select assignment.owner_id into strict owner_id
  from public.account_administrative_plan_assignments assignment where assignment.id = p_assignment;
  perform public.lock_owner_dossier_capacity(owner_id);
  if not exists (
    select 1 from public.billing_administrative_periods(owner_id) period
    where period.assignment_id = p_assignment and period.starts_at <= p_at
      and (period.ends_at is null or p_at < period.ends_at)
  ) then
    raise exception using errcode = '22023', message = 'Attribution administrative inactive.';
  end if;
  insert into billing_internal.transition_access_replacements(assignment_id, effective_at)
  values (p_assignment, p_at) on conflict (assignment_id) do nothing;
  perform public.billing_record_lifecycle_at(owner_id, p_at);
end;
$$;

create function public.billing_accept_verified_invoice_at(p_invoice uuid, p_at timestamptz)
returns text language plpgsql set search_path = '' as $$
declare
  proof record;
  decision record;
  prior_until timestamptz;
  assignment_id uuid;
  consent_id uuid;
begin
  select customer.owner_id into strict proof
  from public.billing_invoice_periods invoice
  join public.billing_subscriptions subscription on subscription.context_id = invoice.context_id
    and subscription.id = invoice.billing_subscription_id
  join public.billing_customers customer on customer.context_id = subscription.context_id
    and customer.id = subscription.billing_customer_id
  where invoice.id = p_invoice;
  if proof.owner_id is null then return 'owner_ineligible'; end if;
  perform public.lock_owner_dossier_capacity(proof.owner_id);

  if exists (select 1 from billing_internal.accepted_invoice_periods payment where payment.invoice_id = p_invoice) then
    return 'already_applied';
  end if;

  select invoice.*, subscription.stripe_ended_at, subscription.cancel_effective_at,
    subscription.started_at, subscription.checkout_attempt_id,
    subscription.stripe_status as contract_status, subscription.price_mapping_id as contract_price,
    customer.owner_id, context.mode as stripe_mode, price.plan_key, price.amount_cents, price.currency as price_currency
  into strict proof
  from public.billing_invoice_periods invoice
  join public.billing_subscriptions subscription on subscription.context_id = invoice.context_id
    and subscription.id = invoice.billing_subscription_id
  join public.billing_customers customer on customer.context_id = subscription.context_id
    and customer.id = subscription.billing_customer_id
  join public.billing_stripe_contexts context on context.id = subscription.context_id
  join public.billing_price_mappings price on price.context_id = invoice.context_id
    and price.id = invoice.price_mapping_id
  where invoice.id = p_invoice;

  if p_at is null or proof.stripe_mode <> 'live'
     or proof.payment_evidence <> 'stripe_verified' or proof.payment_verified_at > p_at
     or proof.stripe_status <> 'paid' or proof.stripe_payment_intent_id is null
     or proof.amount_due_cents <> proof.amount_cents or proof.price_mapping_id <> proof.contract_price
     or proof.plan_key <> 'essential' or proof.currency <> proof.price_currency or proof.currency <> 'eur'
     or proof.billing_reason not in ('initial', 'renewal') then
    return 'payment_not_verified';
  end if;
  if not exists (select 1 from public.application_user_authorizations subject
                 where subject.user_id = proof.owner_id and subject.account_mode = 'autonomous'
                   and subject.status = 'active') then
    return 'owner_ineligible';
  end if;
  if proof.billed_from > p_at or proof.started_at > p_at then return 'period_not_started'; end if;
  if proof.billed_until <= p_at then return 'period_expired'; end if;
  if proof.stripe_ended_at <= p_at or proof.cancel_effective_at <= p_at
     or proof.contract_status in ('canceled', 'incomplete_expired') then return 'contract_ended'; end if;
  if exists (select 1 from billing_internal.accepted_invoice_periods payment
    join public.billing_subscriptions subscription on subscription.id = payment.subscription_id
    join public.billing_customers customer on customer.id = subscription.billing_customer_id
    where customer.owner_id = proof.owner_id and payment.applied_at > p_at) then
    return 'out_of_order';
  end if;

  select * into strict decision from public.billing_resolve_entitlements_at(proof.owner_id, p_at);
  if decision.lifecycle_state = 'purge_irreversible' then return 'purge_irreversible'; end if;
  select max(payment.paid_until) into prior_until from billing_internal.accepted_invoice_periods payment
  where payment.subscription_id = proof.billing_subscription_id;

  if prior_until is not null then
    if decision.subscription_id is distinct from proof.billing_subscription_id then return 'contract_replaced'; end if;
    if proof.billing_reason <> 'renewal' or proof.billed_from <> prior_until then return 'period_not_contiguous'; end if;
  else
    if proof.billing_reason <> 'initial' then return 'initial_payment_missing'; end if;
    if exists (select 1 from public.billing_subscriptions current_contract
      where current_contract.id = decision.subscription_id and current_contract.started_at >= proof.started_at) then
      return 'contract_replaced';
    end if;
    if decision.active_dossier_count > 2 then return 'active_dossier_limit_exceeded'; end if;
    if exists (select 1 from public.account_trials trial where trial.user_id = proof.owner_id
               and trial.ends_at > proof.stripe_reported_paid_at) then return 'trial_not_finished'; end if;

    select period.assignment_id into assignment_id
    from public.billing_administrative_periods(proof.owner_id) period
    where period.starts_at <= p_at and (period.ends_at is null or p_at < period.ends_at)
    order by period.starts_at desc, period.assignment_id limit 1;
    if assignment_id is not null then
      -- Only an explicitly versioned conversion consent qualifies. An ordinary
      -- checkout or a payment alone can never displace an administrative grant.
      select attempt.id into consent_id from public.billing_checkout_attempts attempt
      join public.account_administrative_plan_assignments assigned on assigned.id = assignment_id
      where attempt.id = proof.checkout_attempt_id and attempt.price_mapping_id = proof.price_mapping_id
        and attempt.intent = 'subscribe_now' and attempt.state = 'completed'
        and attempt.consented_at <= proof.stripe_reported_paid_at
        and assigned.updated_at <= attempt.consented_at
        and proof.stripe_reported_paid_at < attempt.expires_at
        and attempt.consent_version = 'administrative-to-essential-v1'
        and not exists (select 1 from public.account_administrative_entitlement_overrides entry
          where entry.owner_id = proof.owner_id and entry.base_source = 'administrative'
            and entry.base_reference_id = assignment_id and entry.updated_at > attempt.consented_at);
      if consent_id is null then return 'administrative_consent_required'; end if;
    end if;
  end if;

  perform public.billing_record_lifecycle_at(proof.owner_id, p_at);
  insert into billing_internal.accepted_invoice_periods(
    invoice_id, context_id, subscription_id, applied_at, billed_from, paid_until,
    plan_key, superseded_assignment_id, consent_attempt_id
  ) values (p_invoice, proof.context_id, proof.billing_subscription_id, p_at, proof.billed_from,
    proof.billed_until, proof.plan_key, assignment_id, consent_id);

  insert into public.billing_account_lifecycle(owner_id, first_paid_at, paid_through, trial_converted_at)
  values (proof.owner_id, proof.stripe_reported_paid_at, proof.billed_until, case when exists (
    select 1 from public.account_trials trial where trial.user_id = proof.owner_id and trial.started_at is not null
  ) then p_at end)
  on conflict (owner_id) do update set paid_through = excluded.paid_through,
    revision = billing_account_lifecycle.revision + 1;

  perform public.billing_record_lifecycle_at(proof.owner_id, p_at);
  return 'applied';
end;
$$;

revoke all on function public.billing_retention_deadline(timestamptz),
  public.billing_administrative_periods(uuid), public.billing_resolve_entitlements_at(uuid, timestamptz),
  public.billing_resolve_current_entitlements(uuid), public.billing_record_lifecycle_at(uuid, timestamptz),
  public.billing_record_transition_replacement_at(uuid, timestamptz),
  public.billing_accept_verified_invoice_at(uuid, timestamptz)
from public, anon, authenticated, service_role;
