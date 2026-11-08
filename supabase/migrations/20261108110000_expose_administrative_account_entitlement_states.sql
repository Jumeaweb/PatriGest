-- PAT-ADMIN-USERS-05D-02
-- Projection paginee et strictement administrative des droits des comptes.
-- Les tables techniques restent fermees et aucune mutation n'est introduite.

create function public.list_administrative_account_entitlement_states(
  p_user_ids uuid[]
)
returns table (
  user_id uuid,
  access_source text,
  commercial_subscription_id uuid,
  base_plan_key text,
  effective_plan_key text,
  base_active_dossier_limit integer,
  effective_active_dossier_limit integer,
  active_dossier_count bigint,
  administrative_assignment_id uuid,
  administrative_assignment_revision bigint,
  administrative_plan_key text,
  administrative_billing_period text,
  administrative_dossier_capacity_key text,
  administrative_override_id uuid,
  administrative_override_revision bigint,
  administrative_override_base_source text,
  administrative_override_feature_plan_key text,
  administrative_override_dossier_capacity_key text,
  plan_assignment_block_code text,
  entitlement_override_block_code text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.platform_administrators administrator
    where administrator.user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'Acces administrateur requis.';
  end if;

  if p_user_ids is null
     or cardinality(p_user_ids) > 25
     or array_position(p_user_ids, null) is not null then
    raise exception using errcode = '22023', message = 'Liste de comptes invalide.';
  end if;

  return query
  select
    requested.user_id,
    entitlement.access_source,
    entitlement.commercial_subscription_id,
    entitlement.base_plan_key,
    entitlement.effective_plan_key,
    entitlement.base_active_dossier_limit,
    entitlement.effective_active_dossier_limit,
    entitlement.active_dossier_count,
    assignment.id,
    assignment.revision,
    assignment.plan_key,
    assignment.billing_period,
    assignment.dossier_capacity_key,
    entitlement_override.id,
    entitlement_override.revision,
    entitlement_override.base_source,
    entitlement_override.feature_plan_key,
    entitlement_override.dossier_capacity_key,
    case
      when target_administrator.user_id is not null then 'platform_administrator'
      when user_authorization.status is distinct from 'active' then 'authorization_inactive'
      when user_authorization.account_mode is distinct from 'autonomous' then 'account_not_autonomous'
      when purge_request.user_id is not null then 'purge_in_progress'
      when entitlement.commercial_subscription_id is not null then 'commercial_subscription_active'
      when entitlement_override.id is not null then 'active_override_must_be_revoked'
      else null
    end,
    case
      when target_administrator.user_id is not null then 'platform_administrator'
      when user_authorization.status is distinct from 'active' then 'authorization_inactive'
      when user_authorization.account_mode is distinct from 'autonomous' then 'account_not_autonomous'
      when purge_request.user_id is not null then 'purge_in_progress'
      when entitlement.access_source not in ('commercial', 'administrative') then 'entitlement_base_required'
      else null
    end
  from (
    select distinct requested_id as user_id
    from unnest(p_user_ids) requested_id
  ) requested
  join auth.users existing_user on existing_user.id = requested.user_id
  left join public.application_user_authorizations user_authorization
    on user_authorization.user_id = requested.user_id
  left join public.platform_administrators target_administrator
    on target_administrator.user_id = requested.user_id
  cross join lateral public.resolve_effective_account_entitlements(
    requested.user_id,
    statement_timestamp()
  ) entitlement
  left join public.account_administrative_plan_assignments assignment
    on assignment.id = entitlement.administrative_assignment_id
   and assignment.owner_id = requested.user_id
   and assignment.status = 'active'
  left join public.account_administrative_entitlement_overrides entitlement_override
    on entitlement_override.id = entitlement.administrative_override_id
   and entitlement_override.owner_id = requested.user_id
   and entitlement_override.status = 'active'
  left join lateral (
    select open_purge.user_id
    from public.account_trial_purge_requests open_purge
    where open_purge.user_id = requested.user_id
      and open_purge.state in ('prepared', 'running', 'attention_required')
    limit 1
  ) purge_request on true
  order by requested.user_id;
end;
$$;

revoke all on function public.list_administrative_account_entitlement_states(uuid[])
from public, anon, authenticated, service_role;

grant execute on function public.list_administrative_account_entitlement_states(uuid[])
to authenticated;

comment on function public.list_administrative_account_entitlement_states(uuid[]) is
  'Projection paginee des attributions, derogations et droits effectifs, reservee aux administrateurs PatriGest authentifies.';
