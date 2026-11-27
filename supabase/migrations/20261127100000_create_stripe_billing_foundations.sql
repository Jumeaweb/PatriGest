-- PAT-STRIPE-02B. Private foundation only. Existing access functions and
-- policies do not consult these tables.

create table public.billing_runtime_config (
  singleton boolean primary key default true check (singleton),
  stripe_sales_enabled boolean not null default false,
  commercial_access_enabled boolean not null default false,
  shared_access_enforcement_enabled boolean not null default false,
  notifications_enabled boolean not null default false,
  purges_enabled boolean not null default false
);
insert into public.billing_runtime_config default values;

create table public.billing_stripe_contexts (
  id uuid primary key default gen_random_uuid(),
  stripe_account_id text not null check (stripe_account_id ~ '^acct_[A-Za-z0-9]+$'),
  mode text not null check (mode in ('test', 'live')),
  created_at timestamptz not null default now(),
  unique (stripe_account_id, mode)
);

create table public.billing_customers (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null references public.billing_stripe_contexts(id),
  -- Keep the financial entity when the operational Auth account is removed.
  owner_id uuid references auth.users(id) on delete set null,
  stripe_customer_id text not null check (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  created_at timestamptz not null default now(),
  unique (context_id, owner_id),
  unique (context_id, stripe_customer_id),
  unique (context_id, id),
  unique (context_id, id, owner_id)
);

create function public.validate_billing_customer_owner()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.owner_id is null then
    if tg_op = 'INSERT' then
      raise exception using errcode = '23514', message = 'Un client Stripe doit être associé à un compte autonome.';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.owner_id is distinct from old.owner_id then
    raise exception using errcode = '23514', message = 'Le propriétaire du client Stripe ne peut pas être remplacé.';
  end if;
  if not exists (
    select 1 from public.application_user_authorizations authorization_row
    where authorization_row.user_id = new.owner_id and authorization_row.account_mode = 'autonomous'
  ) then
    raise exception using errcode = '23514', message = 'Un client Stripe doit être associé à un compte autonome.';
  end if;
  return new;
end;
$$;
create trigger billing_customers_validate_owner
before insert or update of owner_id on public.billing_customers
for each row execute function public.validate_billing_customer_owner();

create table public.billing_price_mappings (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null references public.billing_stripe_contexts(id),
  stripe_price_id text not null check (stripe_price_id ~ '^price_[A-Za-z0-9]+$'),
  plan_key text not null references public.subscription_plans(plan_key),
  billing_cycle text not null check (billing_cycle in ('monthly', 'annual')),
  currency text not null check (currency ~ '^[a-z]{3}$'),
  amount_cents integer not null check (amount_cents > 0),
  sale_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (context_id, id),
  unique (context_id, stripe_price_id),
  constraint billing_prices_launch_offer check (
    not sale_enabled or (
      retired_at is null and plan_key = 'essential' and currency = 'eur'
      and amount_cents = case billing_cycle when 'monthly' then 300 else 3000 end
    )
  ),
  check (retired_at is null or retired_at >= created_at)
);
create unique index billing_prices_one_on_sale_idx
on public.billing_price_mappings(context_id, plan_key, billing_cycle, currency)
where sale_enabled;

create table public.billing_checkout_attempts (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null,
  billing_customer_id uuid not null,
  price_mapping_id uuid not null,
  intent text not null check (intent in ('setup_trial', 'subscribe_now')),
  state text not null default 'reserved' check (state in (
    'reserved', 'session_open', 'scheduled', 'awaiting_payment', 'cancel_pending',
    'completed', 'canceled', 'expired', 'failed'
  )),
  consent_version text not null check (consent_version ~ '^[A-Za-z0-9._-]{1,80}$'),
  consented_at timestamptz not null,
  scheduled_for timestamptz,
  expires_at timestamptz not null,
  idempotency_key uuid not null default gen_random_uuid() unique,
  stripe_checkout_session_id text check (stripe_checkout_session_id ~ '^cs_(test|live)_[A-Za-z0-9]+$'),
  stripe_setup_intent_id text check (stripe_setup_intent_id ~ '^seti_[A-Za-z0-9]+$'),
  stripe_schedule_id text check (stripe_schedule_id ~ '^sub_sched_[A-Za-z0-9]+$'),
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  foreign key (context_id, billing_customer_id) references public.billing_customers(context_id, id),
  foreign key (context_id, price_mapping_id) references public.billing_price_mappings(context_id, id),
  unique (context_id, id, billing_customer_id),
  unique (context_id, stripe_checkout_session_id),
  unique (context_id, stripe_setup_intent_id),
  unique (context_id, stripe_schedule_id),
  check (expires_at > consented_at),
  check ((intent = 'setup_trial') = (scheduled_for is not null)),
  check (scheduled_for is null or scheduled_for > consented_at),
  check (stripe_schedule_id is null or intent = 'setup_trial'),
  check (state <> 'scheduled' or stripe_schedule_id is not null),
  check ((state in ('completed', 'canceled', 'expired', 'failed')) = (finished_at is not null)),
  check (finished_at is null or finished_at >= consented_at)
);
create unique index billing_checkout_one_open_idx
on public.billing_checkout_attempts(context_id, billing_customer_id)
where finished_at is null;
create function public.validate_billing_checkout_context()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.stripe_checkout_session_id is not null and not exists (
    select 1 from public.billing_stripe_contexts context
    where context.id = new.context_id
      and split_part(new.stripe_checkout_session_id, '_', 2) = context.mode
  ) then
    raise exception using errcode = '23514', message = 'Le mode de la session Checkout ne correspond pas au contexte Stripe.';
  end if;
  return new;
end;
$$;
create trigger billing_checkout_validate_context
before insert or update of context_id, stripe_checkout_session_id on public.billing_checkout_attempts
for each row execute function public.validate_billing_checkout_context();

create table public.billing_subscriptions (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null,
  billing_customer_id uuid not null,
  price_mapping_id uuid not null,
  checkout_attempt_id uuid,
  -- Future projection link. Auth deletion may remove the operational row,
  -- never the provider subscription or invoices.
  account_subscription_id uuid unique references public.account_subscriptions(id) on delete set null,
  stripe_subscription_id text not null check (stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$'),
  stripe_status text not null check (stripe_status in (
    'incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'paused'
  )),
  started_at timestamptz not null,
  cancel_effective_at timestamptz,
  stripe_ended_at timestamptz,
  end_reason text check (end_reason in ('voluntary', 'nonpayment', 'administrative', 'other', 'unknown')),
  last_synced_at timestamptz,
  foreign key (context_id, billing_customer_id) references public.billing_customers(context_id, id),
  foreign key (context_id, price_mapping_id) references public.billing_price_mappings(context_id, id),
  foreign key (context_id, checkout_attempt_id, billing_customer_id)
    references public.billing_checkout_attempts(context_id, id, billing_customer_id),
  unique (context_id, stripe_subscription_id),
  unique (context_id, id),
  unique (context_id, id, billing_customer_id),
  check ((stripe_ended_at is null) = (end_reason is null)),
  check (stripe_ended_at is null or stripe_ended_at >= started_at),
  check (cancel_effective_at is null or cancel_effective_at >= started_at)
);
create index billing_subscriptions_history_idx
on public.billing_subscriptions(context_id, billing_customer_id, started_at desc);

create table public.billing_invoice_periods (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null,
  billing_subscription_id uuid not null,
  price_mapping_id uuid not null,
  stripe_invoice_id text not null check (stripe_invoice_id ~ '^in_[A-Za-z0-9]+$'),
  billing_reason text not null check (billing_reason in ('initial', 'renewal', 'adjustment', 'other')),
  stripe_status text not null check (stripe_status in ('draft', 'open', 'paid', 'void', 'uncollectible')),
  billed_from timestamptz not null,
  billed_until timestamptz not null,
  currency text not null check (currency ~ '^[a-z]{3}$'),
  amount_due_cents bigint not null check (amount_due_cents >= 0),
  stripe_reported_paid_at timestamptz,
  payment_evidence text not null default 'unverified'
    check (payment_evidence in ('unverified', 'stripe_verified', 'out_of_band_unverified')),
  payment_verified_at timestamptz,
  stripe_payment_intent_id text check (stripe_payment_intent_id ~ '^pi_[A-Za-z0-9]+$'),
  foreign key (context_id, billing_subscription_id) references public.billing_subscriptions(context_id, id),
  foreign key (context_id, price_mapping_id) references public.billing_price_mappings(context_id, id),
  unique (context_id, stripe_invoice_id),
  unique (context_id, billing_subscription_id, id),
  check (billed_until > billed_from),
  check ((payment_evidence = 'stripe_verified') = (payment_verified_at is not null)),
  check (payment_verified_at is null or (
    stripe_status = 'paid' and stripe_reported_paid_at is not null
    and payment_verified_at >= stripe_reported_paid_at
  ))
);
create index billing_invoice_periods_history_idx
on public.billing_invoice_periods(context_id, billing_subscription_id, billed_from desc);

create function public.validate_billing_subscription_projection()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.account_subscription_id is not null and not exists (
    select 1 from public.account_subscriptions projection
    join public.billing_customers customer on customer.context_id = new.context_id
      and customer.id = new.billing_customer_id and customer.owner_id = projection.owner_id
    join public.billing_price_mappings price on price.context_id = new.context_id
      and price.id = new.price_mapping_id and price.plan_key = projection.plan_key
    where projection.id = new.account_subscription_id and projection.status <> 'development'
      and exists (
        select 1 from public.billing_invoice_periods invoice
        where invoice.context_id = new.context_id and invoice.billing_subscription_id = new.id
          and invoice.payment_evidence = 'stripe_verified'
      )
  ) then
    raise exception using errcode = '23514', message = 'Projection commerciale incompatible ou paiement non vérifié.';
  end if;
  return new;
end;
$$;
create trigger billing_subscriptions_validate_projection
before insert or update of account_subscription_id, context_id, billing_customer_id, price_mapping_id
on public.billing_subscriptions for each row execute function public.validate_billing_subscription_projection();

-- A prospective operational projection; it is not read by the existing resolver.
create table public.billing_account_lifecycle (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  first_paid_at timestamptz,
  paid_through timestamptz,
  trial_converted_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  check (paid_through is null or (first_paid_at is not null and paid_through > first_paid_at)),
  check (trial_converted_at is null or (first_paid_at is not null and trial_converted_at >= first_paid_at))
);
create function public.protect_billing_conversion_history()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (old.first_paid_at is not null and new.first_paid_at is distinct from old.first_paid_at)
     or (old.trial_converted_at is not null and new.trial_converted_at is distinct from old.trial_converted_at) then
    raise exception using errcode = '23514', message = 'Les dates historiques de conversion sont immuables.';
  end if;
  return new;
end;
$$;
create trigger billing_account_lifecycle_protect_conversion
before update of first_paid_at, trial_converted_at on public.billing_account_lifecycle
for each row execute function public.protect_billing_conversion_history();

create table public.billing_lifecycle_episodes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('trial', 'renewal_arrears', 'retention', 'administrative')),
  episode_key uuid not null unique,
  context_id uuid,
  billing_customer_id uuid,
  billing_subscription_id uuid,
  renewal_due_at timestamptz,
  grace_ends_at timestamptz,
  access_ended_at timestamptz,
  retention_until timestamptz,
  starts_at timestamptz not null,
  closed_at timestamptz,
  foreign key (context_id, billing_customer_id, owner_id)
    references public.billing_customers(context_id, id, owner_id) deferrable initially deferred,
  foreign key (context_id, billing_subscription_id, billing_customer_id)
    references public.billing_subscriptions(context_id, id, billing_customer_id),
  unique (id, owner_id, kind),
  unique (owner_id, kind, starts_at),
  check ((context_id is null) = (billing_subscription_id is null)),
  check ((context_id is null) = (billing_customer_id is null)),
  check (closed_at is null or closed_at >= starts_at),
  check (
    (kind = 'renewal_arrears' and billing_subscription_id is not null
      and renewal_due_at is not null and grace_ends_at is not null
      and starts_at = renewal_due_at and grace_ends_at = renewal_due_at + interval '336 hours')
    or (kind <> 'renewal_arrears' and renewal_due_at is null and grace_ends_at is null)
  ),
  check (
    (kind = 'retention' and access_ended_at is not null and access_ended_at = starts_at
      and retention_until is not null and retention_until > access_ended_at)
    or (kind <> 'retention' and access_ended_at is null and retention_until is null)
  )
);
create unique index billing_episodes_one_renewal_arrears_idx
on public.billing_lifecycle_episodes(context_id, billing_subscription_id, renewal_due_at)
where kind = 'renewal_arrears';
create unique index billing_episodes_one_open_retention_idx
on public.billing_lifecycle_episodes(owner_id) where kind = 'retention' and closed_at is null;

create table public.billing_lifecycle_events (
  id bigint generated always as identity primary key,
  episode_id uuid not null references public.billing_lifecycle_episodes(id) on delete cascade,
  transition_key uuid not null unique,
  transition_code text not null check (transition_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  source text not null check (source in ('stripe', 'system', 'administrative')),
  occurred_at timestamptz not null default now()
);
create index billing_lifecycle_events_episode_idx on public.billing_lifecycle_events(episode_id, occurred_at);

-- Nullable dates preserve all existing (indefinite) assignments without a backfill.
alter table public.account_administrative_plan_assignments
  add column valid_from timestamptz,
  add column valid_until timestamptz,
  add constraint administrative_assignment_valid_dates check (
    valid_until is null or (valid_from is not null and valid_until > valid_from)
  );
comment on column public.account_administrative_plan_assignments.valid_from is
  'Future effective start. NULL preserves existing behavior; use created_at for historical display.';
comment on column public.account_administrative_plan_assignments.valid_until is
  'Future optional end. This foundation does not enforce the administrative dates.';

create table public.billing_stripe_events (
  context_id uuid not null references public.billing_stripe_contexts(id),
  stripe_event_id text not null check (stripe_event_id ~ '^evt_[A-Za-z0-9]+$'),
  event_type text not null check (event_type ~ '^[a-z0-9_.]{3,120}$'),
  stripe_object_id text check (stripe_object_id ~ '^[a-z]+_[A-Za-z0-9_]{1,120}$'),
  stripe_customer_id text check (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  stripe_subscription_id text check (stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$'),
  stripe_invoice_id text check (stripe_invoice_id ~ '^in_[A-Za-z0-9]+$'),
  state text not null default 'pending' check (state in ('pending', 'processing', 'processed', 'retry', 'dead_letter', 'ignored')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  stripe_created_at timestamptz not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_code text check (error_code ~ '^[A-Z][A-Z0-9_]{0,63}$'),
  primary key (context_id, stripe_event_id),
  check ((lease_token is null) = (lease_until is null)),
  check ((state = 'processing') = (lease_token is not null)),
  check ((state in ('processed', 'ignored')) = (processed_at is not null)),
  check (processed_at is null or processed_at >= received_at)
);
create index billing_stripe_events_available_idx on public.billing_stripe_events(available_at, received_at)
where state in ('pending', 'retry');
create index billing_stripe_events_expired_lease_idx on public.billing_stripe_events(lease_until)
where state = 'processing';

create table public.billing_notification_jobs (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references public.billing_lifecycle_episodes(id) on delete cascade,
  notification_code text not null check (notification_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  idempotency_key uuid not null default gen_random_uuid() unique,
  due_at timestamptz not null,
  state text not null default 'pending' check (state in ('pending', 'reserved', 'sent', 'retry', 'canceled', 'dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  lease_token uuid,
  lease_until timestamptz,
  sent_at timestamptz,
  canceled_at timestamptz,
  unique (episode_id, notification_code),
  check ((lease_token is null) = (lease_until is null)),
  check ((state = 'reserved') = (lease_token is not null)),
  check ((state = 'sent') = (sent_at is not null)),
  check ((state = 'canceled') = (canceled_at is not null))
);
create index billing_notification_jobs_due_idx on public.billing_notification_jobs(due_at)
where state in ('pending', 'retry');

create table public.billing_purge_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  episode_id uuid unique references public.billing_lifecycle_episodes(id) on delete set null,
  kind text not null check (kind in ('trial', 'retention')),
  request_key uuid not null unique,
  state text not null default 'eligible'
    check (state in ('eligible', 'reserved', 'irreversible', 'completed', 'attention_required', 'canceled')),
  eligible_at timestamptz not null,
  reserved_at timestamptz,
  irreversible_at timestamptz,
  completed_at timestamptz,
  canceled_at timestamptz,
  foreign key (episode_id, owner_id, kind)
    references public.billing_lifecycle_episodes(id, owner_id, kind) deferrable initially deferred,
  check (reserved_at is null or reserved_at >= eligible_at),
  check (irreversible_at is null or (reserved_at is not null and irreversible_at >= reserved_at)),
  check ((state = 'completed') = (completed_at is not null)),
  check ((state = 'canceled') = (canceled_at is not null)),
  check (state <> 'reserved' or reserved_at is not null),
  check (state <> 'irreversible' or irreversible_at is not null),
  check (completed_at is null or (irreversible_at is not null and completed_at >= irreversible_at)),
  check (canceled_at is null or irreversible_at is null)
);
create unique index billing_purge_jobs_one_open_idx
on public.billing_purge_jobs(owner_id)
where owner_id is not null and state in ('eligible', 'reserved', 'irreversible', 'attention_required');
create function public.validate_billing_purge_subject()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.owner_id is null or new.episode_id is null then
    raise exception using errcode = '23514', message = 'Une nouvelle demande de purge exige un propriétaire et un épisode.';
  end if;
  return new;
end;
$$;
create trigger billing_purge_jobs_validate_subject
before insert on public.billing_purge_jobs
for each row execute function public.validate_billing_purge_subject();

-- No runtime role can directly read or mutate the foundation. Future trusted
-- writers must recheck the owner, context and the existing owner-capacity lock.
do $$
declare relation_name text;
begin
  foreach relation_name in array array[
    'billing_runtime_config', 'billing_stripe_contexts', 'billing_customers',
    'billing_price_mappings', 'billing_checkout_attempts', 'billing_subscriptions',
    'billing_invoice_periods', 'billing_account_lifecycle', 'billing_lifecycle_episodes',
    'billing_lifecycle_events', 'billing_stripe_events', 'billing_notification_jobs',
    'billing_purge_jobs'
  ] loop
    execute format('alter table public.%I enable row level security', relation_name);
    execute format('revoke all on table public.%I from public, anon, authenticated, service_role', relation_name);
  end loop;
end;
$$;
revoke all on sequence public.billing_lifecycle_events_id_seq from public, anon, authenticated, service_role;
revoke all on function public.validate_billing_customer_owner(),
  public.validate_billing_checkout_context(),
  public.validate_billing_subscription_projection(),
  public.protect_billing_conversion_history(),
  public.validate_billing_purge_subject() from public, anon, authenticated, service_role;
