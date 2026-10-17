-- PAT-ABONNEMENT-02B-2
-- Résout les capacités d'un dossier depuis l'abonnement de son propriétaire,
-- sans activer ces contrôles dans les parcours métier existants.

create function public.get_protected_person_feature_capabilities(
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
  if auth.uid() is null
     or not public.is_application_user_active() then
    raise exception using
      errcode = '42501',
      message = 'Dossier introuvable.';
  end if;

  select
    persons.owner_id,
    case
      when persons.owner_id = auth.uid() then 'owner'
      else access.role
    end
  into dossier_owner_id, caller_role
  from public.protected_persons persons
  left join public.protected_person_access access
    on access.protected_person_id = persons.id
   and access.user_id = auth.uid()
  where persons.id = p_protected_person_id
    and (
      persons.owner_id = auth.uid()
      or access.user_id is not null
    );

  if not found or caller_role not in ('owner', 'manager', 'read_only') then
    raise exception using
      errcode = '42501',
      message = 'Dossier introuvable.';
  end if;

  return query
  with feature_context as (
    select
      features.feature_key,
      features.implementation_status,
      subscriptions.id as subscription_id,
      subscriptions.status as subscription_status,
      coalesce(plans.active, false) as plan_active,
      coalesce(plan_features.included, false) as plan_included
    from public.subscription_features features
    left join public.account_subscriptions subscriptions
      on subscriptions.owner_id = dossier_owner_id
     and subscriptions.ended_at is null
    left join public.subscription_plans plans
      on plans.plan_key = subscriptions.plan_key
    left join public.subscription_plan_features plan_features
      on plan_features.plan_key = subscriptions.plan_key
     and plan_features.feature_key = features.feature_key
  ),
  decisions as (
    select
      context.feature_key,
      context.implementation_status,
      case
        when context.implementation_status = 'upcoming' then 'feature_upcoming'
        when context.subscription_id is null then 'subscription_missing'
        when context.subscription_status <> 'development'
             and not context.plan_active then 'plan_unavailable'
        when context.subscription_status <> 'development'
             and not context.plan_included then 'not_in_plan'
        when context.feature_key in ('data_export', 'bank_operation_automation')
             and caller_role = 'read_only' then 'role_forbidden'
        else null
      end as read_denial_reason,
      case
        when context.implementation_status = 'upcoming' then 'feature_upcoming'
        when context.subscription_id is null then 'subscription_missing'
        when context.subscription_status <> 'development'
             and not context.plan_active then 'plan_unavailable'
        when context.subscription_status <> 'development'
             and not context.plan_included then 'not_in_plan'
        when context.feature_key = 'data_export' then 'operation_not_supported'
        when caller_role = 'read_only' then 'role_forbidden'
        else null
      end as write_denial_reason
    from feature_context context
  )
  select
    decisions.feature_key,
    decisions.implementation_status,
    decisions.read_denial_reason is null as can_read,
    decisions.write_denial_reason is null as can_write,
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

create function public.check_protected_person_feature_access(
  p_protected_person_id uuid,
  p_feature_key text,
  p_access_mode text
)
returns table (
  allowed boolean,
  denial_reason text
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_feature_key is null or p_feature_key not in (
    'core_management',
    'existing_accounting_documents',
    'data_export',
    'bank_operation_automation',
    'central_document_management'
  ) then
    raise exception using
      errcode = '23514',
      message = 'Fonctionnalité inconnue.';
  end if;

  if p_access_mode is null or p_access_mode not in ('read', 'write') then
    raise exception using
      errcode = '23514',
      message = 'Mode d’accès invalide.';
  end if;

  return query
  select
    case p_access_mode
      when 'read' then capabilities.can_read
      else capabilities.can_write
    end,
    case p_access_mode
      when 'read' then capabilities.read_denial_reason
      else capabilities.write_denial_reason
    end
  from public.get_protected_person_feature_capabilities(
    p_protected_person_id
  ) capabilities
  where capabilities.feature_key = p_feature_key;
end;
$$;

revoke all on function public.get_protected_person_feature_capabilities(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.check_protected_person_feature_access(uuid, text, text)
from public, anon, authenticated, service_role;

grant execute on function public.get_protected_person_feature_capabilities(uuid)
to authenticated;
grant execute on function public.check_protected_person_feature_access(uuid, text, text)
to authenticated;

comment on function public.get_protected_person_feature_capabilities(uuid) is
  'Retourne uniquement les capacités effectives sûres du dossier courant, sans exposer l’abonnement privé de son propriétaire.';
comment on function public.check_protected_person_feature_access(uuid, text, text) is
  'Vérifie un accès read/write à une capacité ; aucun parcours métier ne l’utilise encore comme restriction.';
