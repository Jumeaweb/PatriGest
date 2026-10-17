-- PAT-ABONNEMENT-02B-1
-- Prépare le catalogue des forfaits, leur matrice fonctionnelle et les
-- abonnements propriétaires sans activer de restriction commerciale.

create table public.subscription_plans (
  plan_key text primary key,
  display_name text not null check (length(trim(display_name)) > 0),
  monthly_price_cents integer not null check (monthly_price_cents > 0),
  annual_price_cents integer not null check (annual_price_cents > 0),
  sort_order smallint not null unique check (sort_order > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_plans_known_key
    check (plan_key in ('essential', 'comfort', 'premium'))
);

create table public.subscription_features (
  feature_key text primary key,
  display_name text not null check (length(trim(display_name)) > 0),
  implementation_status text not null
    check (implementation_status in ('available', 'upcoming')),
  sort_order smallint not null unique check (sort_order > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_features_known_key check (feature_key in (
    'core_management',
    'existing_accounting_documents',
    'data_export',
    'bank_operation_automation',
    'central_document_management'
  ))
);

create table public.subscription_plan_features (
  plan_key text not null
    references public.subscription_plans(plan_key) on delete restrict,
  feature_key text not null
    references public.subscription_features(feature_key) on delete restrict,
  included boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (plan_key, feature_key)
);

create index subscription_plan_features_feature_key_idx
on public.subscription_plan_features(feature_key);

create table public.subscription_dossier_capacities (
  capacity_key text primary key,
  display_name text not null check (length(trim(display_name)) > 0),
  active_dossier_limit integer,
  sort_order smallint not null unique check (sort_order > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_dossier_capacities_known_key
    check (capacity_key in ('included', 'five', 'ten', 'custom')),
  constraint subscription_dossier_capacities_limit_consistency check (
    (capacity_key = 'included' and active_dossier_limit = 2)
    or (capacity_key = 'five' and active_dossier_limit = 5)
    or (capacity_key = 'ten' and active_dossier_limit = 10)
    or (capacity_key = 'custom' and active_dossier_limit is null)
  )
);

create table public.account_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  plan_key text references public.subscription_plans(plan_key) on delete restrict,
  dossier_capacity_key text
    references public.subscription_dossier_capacities(capacity_key) on delete restrict,
  custom_active_dossier_limit integer,
  status text not null default 'development'
    check (status in ('development', 'active', 'past_due', 'canceled', 'ended')),
  started_at timestamptz not null default now(),
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  canceled_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint account_subscriptions_development_consistency check (
    (
      status = 'development'
      and plan_key is null
      and dossier_capacity_key is null
      and custom_active_dossier_limit is null
      and current_period_started_at is null
      and current_period_ends_at is null
      and canceled_at is null
    )
    or (
      status <> 'development'
      and plan_key is not null
      and dossier_capacity_key is not null
    )
  ),
  constraint account_subscriptions_custom_capacity_consistency check (
    (dossier_capacity_key = 'custom' and custom_active_dossier_limit > 10)
    or (
      dossier_capacity_key is distinct from 'custom'
      and custom_active_dossier_limit is null
    )
  ),
  constraint account_subscriptions_period_consistency check (
    (current_period_started_at is null and current_period_ends_at is null)
    or (
      current_period_started_at is not null
      and current_period_ends_at is not null
      and current_period_ends_at > current_period_started_at
    )
  ),
  constraint account_subscriptions_cancellation_consistency check (
    canceled_at is null
    or (status in ('canceled', 'ended') and canceled_at >= started_at)
  ),
  constraint account_subscriptions_end_consistency check (
    (status = 'ended' and ended_at is not null and ended_at >= started_at)
    or (status in ('active', 'past_due', 'canceled') and ended_at is null)
    or (
      status = 'development'
      and (ended_at is null or ended_at >= started_at)
    )
  )
);

create unique index account_subscriptions_one_current_per_owner_idx
on public.account_subscriptions(owner_id)
where ended_at is null;

create index account_subscriptions_plan_key_idx
on public.account_subscriptions(plan_key)
where plan_key is not null;

create index account_subscriptions_status_idx
on public.account_subscriptions(status);

create trigger subscription_plans_set_updated_at
before update on public.subscription_plans
for each row execute function public.set_updated_at();

create trigger subscription_features_set_updated_at
before update on public.subscription_features
for each row execute function public.set_updated_at();

create trigger subscription_plan_features_set_updated_at
before update on public.subscription_plan_features
for each row execute function public.set_updated_at();

create trigger subscription_dossier_capacities_set_updated_at
before update on public.subscription_dossier_capacities
for each row execute function public.set_updated_at();

create trigger account_subscriptions_set_updated_at
before update on public.account_subscriptions
for each row execute function public.set_updated_at();

create function public.validate_account_subscription_owner()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.application_user_authorizations authorizations
    where authorizations.user_id = new.owner_id
      and authorizations.account_mode = 'autonomous'
  ) then
    raise exception using
      errcode = '23514',
      message = 'Un abonnement ne peut être associé qu’à un compte propriétaire.';
  end if;

  return new;
end;
$$;

create trigger account_subscriptions_validate_owner
before insert or update of owner_id on public.account_subscriptions
for each row execute function public.validate_account_subscription_owner();

insert into public.subscription_plans (
  plan_key,
  display_name,
  monthly_price_cents,
  annual_price_cents,
  sort_order
) values
  ('essential', 'Essentiel', 300, 3000, 1),
  ('comfort', 'Confort', 500, 5000, 2),
  ('premium', 'Premium', 600, 6000, 3);

insert into public.subscription_features (
  feature_key,
  display_name,
  implementation_status,
  sort_order
) values
  ('core_management', 'Gestion comptable et patrimoniale', 'available', 1),
  ('existing_accounting_documents', 'Documents comptables existants', 'available', 2),
  ('data_export', 'Export des données', 'available', 3),
  ('bank_operation_automation', 'Automatisation des opérations bancaires', 'upcoming', 4),
  ('central_document_management', 'Gestion documentaire centralisée', 'upcoming', 5);

insert into public.subscription_plan_features (plan_key, feature_key, included)
select plans.plan_key, features.feature_key,
  case
    when features.feature_key in (
      'core_management',
      'existing_accounting_documents',
      'data_export'
    ) then true
    when features.feature_key = 'bank_operation_automation'
      then plans.plan_key in ('comfort', 'premium')
    when features.feature_key = 'central_document_management'
      then plans.plan_key = 'premium'
    else false
  end
from public.subscription_plans plans
cross join public.subscription_features features;

insert into public.subscription_dossier_capacities (
  capacity_key,
  display_name,
  active_dossier_limit,
  sort_order
) values
  ('included', '2 dossiers', 2, 1),
  ('five', 'Jusqu’à 5 dossiers', 5, 2),
  ('ten', 'Jusqu’à 10 dossiers', 10, 3),
  ('custom', 'Plus de 10 dossiers', null, 4);

alter table public.subscription_plans enable row level security;
alter table public.subscription_features enable row level security;
alter table public.subscription_plan_features enable row level security;
alter table public.subscription_dossier_capacities enable row level security;
alter table public.account_subscriptions enable row level security;

create policy "subscription_plans_select_authenticated"
on public.subscription_plans
for select to authenticated
using (true);

create policy "subscription_features_select_authenticated"
on public.subscription_features
for select to authenticated
using (true);

create policy "subscription_plan_features_select_authenticated"
on public.subscription_plan_features
for select to authenticated
using (true);

create policy "subscription_dossier_capacities_select_authenticated"
on public.subscription_dossier_capacities
for select to authenticated
using (true);

create policy "account_subscriptions_select_own"
on public.account_subscriptions
for select to authenticated
using (owner_id = (select auth.uid()));

create policy "account_subscriptions_admin_select"
on public.account_subscriptions
for select to authenticated
using (public.is_platform_admin());

revoke all on table public.subscription_plans
from public, anon, authenticated, service_role;
revoke all on table public.subscription_features
from public, anon, authenticated, service_role;
revoke all on table public.subscription_plan_features
from public, anon, authenticated, service_role;
revoke all on table public.subscription_dossier_capacities
from public, anon, authenticated, service_role;
revoke all on table public.account_subscriptions
from public, anon, authenticated, service_role;
revoke all on function public.validate_account_subscription_owner()
from public, anon, authenticated, service_role;

grant select on table public.subscription_plans to authenticated;
grant select on table public.subscription_features to authenticated;
grant select on table public.subscription_plan_features to authenticated;
grant select on table public.subscription_dossier_capacities to authenticated;
grant select on table public.account_subscriptions to authenticated;

-- Tous les propriétaires déjà présents conservent le comportement antérieur.
-- Le mode Développement n'attribue ni forfait payant ni capacité commerciale.
with existing_owners as (
  select persons.owner_id
  from public.protected_persons persons
  union
  select authorizations.user_id
  from public.application_user_authorizations authorizations
  where authorizations.account_mode = 'autonomous'
)
insert into public.account_subscriptions (owner_id, status)
select owners.owner_id, 'development'
from existing_owners owners
where not exists (
  select 1
  from public.account_subscriptions subscriptions
  where subscriptions.owner_id = owners.owner_id
    and subscriptions.ended_at is null
);

comment on table public.subscription_plans is
  'Catalogue commercial stable des forfaits PatriGest. Aucun paiement n’est géré dans cette table.';
comment on table public.subscription_features is
  'Catalogue stable des capacités fonctionnelles, y compris celles encore à venir.';
comment on table public.subscription_plan_features is
  'Matrice explicite des capacités incluses ou non dans chaque forfait.';
comment on table public.subscription_dossier_capacities is
  'Paliers non cumulatifs de dossiers actifs ; la capacité personnalisée est portée par l’abonnement.';
comment on table public.account_subscriptions is
  'État commercial d’un propriétaire, distinct de son autorisation administrative et de son mode de compte.';
