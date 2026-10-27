-- PAT-ABONNEMENT-01
-- Les comptes propriétaires sans forfait commercial utilisent la capacité
-- incluse de deux dossiers actifs. Le catalogue PostgreSQL reste la source de
-- vérité du plafond et les dépassements historiques ne sont jamais modifiés.

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
  subscription_status text;
  capacity_key text;
  configured_limit integer;
  custom_limit integer;
  owned_active_count bigint;
begin
  select
    subscriptions.status,
    subscriptions.dossier_capacity_key,
    capacities.active_dossier_limit,
    subscriptions.custom_active_dossier_limit
  into
    subscription_status,
    capacity_key,
    configured_limit,
    custom_limit
  from public.account_subscriptions subscriptions
  left join public.subscription_dossier_capacities capacities
    on capacities.capacity_key = subscriptions.dossier_capacity_key
  where subscriptions.owner_id = p_owner_id
    and subscriptions.ended_at is null;

  if not found then
    raise exception using
      errcode = 'P4D02',
      message = 'Capacité de dossiers indisponible.';
  end if;

  select count(*)
  into owned_active_count
  from public.protected_persons persons
  where persons.owner_id = p_owner_id
    and persons.status = 'active';

  if subscription_status = 'development' then
    select capacities.active_dossier_limit
    into configured_limit
    from public.subscription_dossier_capacities capacities
    where capacities.capacity_key = 'included';

    if configured_limit is null or configured_limit <= 0 then
      raise exception using
        errcode = 'P4D03',
        message = 'Configuration de capacité indisponible.';
    end if;

    return query
    select
      false,
      configured_limit,
      owned_active_count,
      greatest(configured_limit::bigint - owned_active_count, 0::bigint),
      greatest(owned_active_count - configured_limit::bigint, 0::bigint);
    return;
  end if;

  if subscription_status not in ('active', 'past_due', 'canceled') then
    raise exception using
      errcode = 'P4D03',
      message = 'Configuration de capacité indisponible.';
  end if;

  if capacity_key = 'custom' then
    configured_limit := custom_limit;
  end if;

  if configured_limit is null or configured_limit <= 0 then
    raise exception using
      errcode = 'P4D03',
      message = 'Configuration de capacité indisponible.';
  end if;

  return query
  select
    false,
    configured_limit,
    owned_active_count,
    greatest(configured_limit::bigint - owned_active_count, 0::bigint),
    greatest(owned_active_count - configured_limit::bigint, 0::bigint);
end;
$$;

comment on function public.resolve_owner_dossier_capacity(uuid) is
  'Résout le plafond courant ; development utilise la capacité included. Codes stables : P4D02 abonnement courant absent ou terminé ; P4D03 configuration invalide.';
