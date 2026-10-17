-- PAT-ABONNEMENT-02B-4B
-- Applique les capacités de dossiers actifs au niveau PostgreSQL sans modifier
-- les dossiers existants. Les écritures administratives sans identité JWT
-- restent possibles pour les migrations et les restaurations explicitement
-- privilégiées ; toutes les écritures applicatives authentifiées sont contrôlées.

create index protected_persons_owner_active_idx
on public.protected_persons(owner_id)
where status = 'active';

create function public.lock_owner_dossier_capacity(p_owner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.application_user_authorizations authorizations
  where authorizations.user_id = p_owner_id
  for update;

  if not found then
    raise exception using
      errcode = 'P4D03',
      message = 'Configuration de capacité indisponible.';
  end if;
end;
$$;

create function public.resolve_owner_dossier_capacity(p_owner_id uuid)
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
    return query
    select true, null::integer, owned_active_count, null::bigint, 0::bigint;
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

create function public.assert_owner_dossier_capacity(p_owner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  capacity record;
begin
  select *
  into capacity
  from public.resolve_owner_dossier_capacity(p_owner_id);

  if not capacity.unlimited
     and capacity.active_dossier_count >= capacity.active_dossier_limit then
    raise exception using
      errcode = 'P4D01',
      message = 'La capacité de dossiers actifs est atteinte.';
  end if;
end;
$$;

-- Tous les changements futurs de capacité utilisent le même verrou que les
-- créations et restaurations. Un changement de propriétaire, s'il est réalisé
-- administrativement, verrouille les deux propriétaires dans un ordre stable.
create function public.serialize_account_subscription_capacity_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  first_owner_id uuid;
  second_owner_id uuid;
begin
  if tg_op = 'INSERT' then
    perform public.lock_owner_dossier_capacity(new.owner_id);
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- Lors d'un DELETE CASCADE depuis auth.users, l'autorisation propriétaire
    -- peut déjà être invisible. Aucun nouveau dossier authentifié ne peut alors
    -- être créé ; la suppression terminale de l'abonnement doit rester possible.
    perform 1
    from public.application_user_authorizations authorizations
    where authorizations.user_id = old.owner_id
    for update;
    return old;
  end if;

  if old.owner_id = new.owner_id then
    perform public.lock_owner_dossier_capacity(new.owner_id);
  else
    first_owner_id := least(old.owner_id::text, new.owner_id::text)::uuid;
    second_owner_id := greatest(old.owner_id::text, new.owner_id::text)::uuid;
    perform public.lock_owner_dossier_capacity(first_owner_id);
    perform public.lock_owner_dossier_capacity(second_owner_id);
  end if;

  return new;
end;
$$;

create trigger account_subscriptions_serialize_dossier_capacity
before insert or update or delete on public.account_subscriptions
for each row execute function public.serialize_account_subscription_capacity_change();

-- Une transition réalisée par l'utilisateur lui-même vers le mode autonome,
-- sans aucun historique d'abonnement, identifie le parcours actuel d'un nouveau
-- propriétaire de développement. Un abonnement terminé interdit cette création.
create function public.provision_new_development_owner_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
     and new.account_mode = 'autonomous'
     and auth.uid() = new.user_id
     and (tg_op = 'INSERT'
          or old.account_mode is distinct from new.account_mode
          or old.status is distinct from new.status)
     and not exists (
       select 1
       from public.platform_administrators administrators
       where administrators.user_id = new.user_id
     )
     and not exists (
       select 1
       from public.account_subscriptions subscriptions
       where subscriptions.owner_id = new.user_id
     ) then
    insert into public.account_subscriptions(owner_id, status)
    values (new.user_id, 'development')
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create trigger application_user_authorizations_provision_development_subscription
after insert or update of status, account_mode
on public.application_user_authorizations
for each row execute function public.provision_new_development_owner_subscription();

create function public.enforce_protected_person_dossier_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  old_consumes_slot boolean := false;
  new_consumes_slot boolean := false;
begin
  -- Les migrations, pgTAP et restaurations administratives explicites n'ont
  -- pas d'identité JWT. Les parcours applicatifs et PostgREST en ont toujours une.
  if caller_id is null
     or current_setting('role', true) is distinct from 'authenticated' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  -- La politique RLS existante conserve son message et son autorité pour les
  -- comptes inactifs ; le quota ne doit pas divulguer l'état d'abonnement.
  if not public.is_application_user_active() then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op <> 'INSERT' then
    old_consumes_slot := old.status = 'active';
  end if;
  if tg_op <> 'DELETE' then
    new_consumes_slot := new.status = 'active';
  end if;

  if tg_op = 'UPDATE'
     and old.owner_id = new.owner_id
     and old_consumes_slot = new_consumes_slot then
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old_consumes_slot then
      perform public.lock_owner_dossier_capacity(old.owner_id);
    end if;
    return old;
  end if;

  if new.owner_id <> caller_id then
    raise exception using
      errcode = '42501',
      message = 'Opération sur le dossier non autorisée.';
  end if;

  if tg_op = 'UPDATE' and old.owner_id <> new.owner_id then
    perform public.lock_owner_dossier_capacity(
      least(old.owner_id::text, new.owner_id::text)::uuid
    );
    perform public.lock_owner_dossier_capacity(
      greatest(old.owner_id::text, new.owner_id::text)::uuid
    );
  else
    perform public.lock_owner_dossier_capacity(new.owner_id);
  end if;

  if new_consumes_slot
     and (tg_op = 'INSERT' or not old_consumes_slot or old.owner_id <> new.owner_id) then
    perform public.assert_owner_dossier_capacity(new.owner_id);
  end if;

  return new;
end;
$$;

-- Le nom place ce trigger après protected_persons_enforce_owner_account_mode :
-- le premier dossier crée ainsi le mode autonome et son abonnement development
-- avant la résolution du quota.
create trigger protected_persons_quota_guard
before insert or update of owner_id, status, archived_at or delete
on public.protected_persons
for each row execute function public.enforce_protected_person_dossier_capacity();

create function public.get_owned_dossier_capacity()
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
begin
  if auth.uid() is null
     or not public.is_application_user_active()
     or public.is_platform_admin()
     or not exists (
       select 1
       from public.application_user_authorizations authorizations
       where authorizations.user_id = auth.uid()
         and authorizations.account_mode = 'autonomous'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Accès propriétaire requis.';
  end if;

  return query
  select capacity.*
  from public.resolve_owner_dossier_capacity(auth.uid()) capacity;
end;
$$;

revoke all on function public.lock_owner_dossier_capacity(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_owner_dossier_capacity(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.assert_owner_dossier_capacity(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.serialize_account_subscription_capacity_change()
from public, anon, authenticated, service_role;
revoke all on function public.provision_new_development_owner_subscription()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_protected_person_dossier_capacity()
from public, anon, authenticated, service_role;
revoke all on function public.get_owned_dossier_capacity()
from public, anon, authenticated, service_role;

grant execute on function public.get_owned_dossier_capacity()
to authenticated;

comment on function public.get_owned_dossier_capacity() is
  'Retourne uniquement l’occupation et la capacité de dossiers actifs du propriétaire authentifié.';
comment on function public.lock_owner_dossier_capacity(uuid) is
  'Verrou transactionnel par propriétaire partagé par les mutations de dossiers et les changements futurs de capacité.';
comment on function public.resolve_owner_dossier_capacity(uuid) is
  'Codes stables : P4D02 abonnement courant absent ou terminé ; P4D03 configuration de capacité invalide.';
comment on function public.assert_owner_dossier_capacity(uuid) is
  'Code stable P4D01 lorsque la capacité de dossiers actifs est atteinte.';
