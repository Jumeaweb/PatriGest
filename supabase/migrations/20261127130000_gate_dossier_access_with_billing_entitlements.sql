-- PAT-STRIPE-02D. Preserve existing application functions and RLS entry points.
create or replace function public.has_application_business_access(
  p_user_id uuid, p_at timestamptz default clock_timestamp()
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.platform_administrators admin where admin.user_id = p_user_id)
  or exists (
    select 1 from public.application_user_authorizations subject
    cross join public.account_trial_runtime_config trial
    cross join public.billing_runtime_config billing
    where subject.user_id = p_user_id and subject.status = 'active'
    and case
      when subject.account_mode = 'collaborator' then true
      when billing.commercial_access_enabled and subject.account_mode = 'autonomous' then exists (
        select 1 from public.billing_resolve_entitlements_at(p_user_id, clock_timestamp()) decision
        where decision.access_source <> 'none'
      )
      else not trial.enforcement_enabled or exists (
        select 1 from public.resolve_effective_account_entitlements(p_user_id, p_at) entitlement
        where entitlement.access_source <> 'none'
      )
    end
  );
$$;

create or replace function public.can_read_protected_person(person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_application_user_active() and exists (
    select 1 from public.protected_persons person cross join public.billing_runtime_config config
    where person.id = person_id and (
      person.owner_id = auth.uid() or (
        exists (select 1 from public.protected_person_access access
                where access.protected_person_id = person.id and access.user_id = auth.uid())
        and (not config.shared_access_enforcement_enabled or exists (
          select 1 from public.billing_resolve_entitlements_at(person.owner_id, clock_timestamp()) decision
          where decision.access_source in ('trial', 'commercial', 'administrative', 'legacy', 'development')
        ))
      )
    )
  );
$$;

create function public.current_commercial_access_restricted()
returns boolean language sql stable security definer set search_path = '' as $$
  select not public.has_application_business_access(subject.user_id)
  from public.application_user_authorizations subject
  cross join public.billing_runtime_config config
  where subject.user_id = auth.uid() and subject.account_mode = 'autonomous'
    and config.commercial_access_enabled;
$$;
revoke all on function public.current_commercial_access_restricted() from public, anon, authenticated, service_role;
grant execute on function public.current_commercial_access_restricted() to authenticated;

create or replace function public.can_manage_protected_person(person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.can_read_protected_person(person_id) and exists (
    select 1 from public.protected_persons person where person.id = person_id and (
      person.owner_id = auth.uid() or exists (
        select 1 from public.protected_person_access access
        where access.protected_person_id = person.id and access.user_id = auth.uid() and access.role = 'manager'
      )
    )
  );
$$;

-- NULL means the applicable commercial flag is off. This internal projection
-- is evaluated only after the caller's rights on the dossier are checked.
create function public.get_enabled_dossier_billing_features(p_protected_person_id uuid)
returns text[] language sql stable set search_path = '' as $$
  select decision.features
  from public.protected_persons person cross join public.billing_runtime_config config
  cross join lateral public.billing_resolve_entitlements_at(person.owner_id, clock_timestamp()) decision
  where person.id = p_protected_person_id
    and case when person.owner_id = auth.uid() then config.commercial_access_enabled
             else config.shared_access_enforcement_enabled end;
$$;

create function public.get_management_report_commercial_capabilities(p_protected_person_id uuid)
returns table (can_generate boolean, can_finalize boolean, can_print boolean)
language plpgsql stable security definer set search_path = '' as $$
declare features text[];
begin
  if not public.can_read_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Dossier introuvable.';
  end if;
  features := public.get_enabled_dossier_billing_features(p_protected_person_id);
  return query select coalesce('application_pdf_generate' = any(features), true),
    coalesce('management_report_finalize' = any(features), true),
    coalesce('management_report_print' = any(features), true);
end;
$$;

create function public.can_write_management_report_pdf(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select capabilities.can_generate and (file.parts[3] = 'management-report-draft.pdf' or capabilities.can_finalize)
    from regexp_match(p_path, '^protected-persons/([0-9a-f-]{36})/management-reports/([0-9a-f-]{36})/(management-report(?:-draft)?\.pdf)$') file(parts)
    join public.management_reports report on report.id::text = file.parts[2]
      and report.protected_person_id::text = file.parts[1]
    cross join lateral public.get_management_report_commercial_capabilities(report.protected_person_id) capabilities
    where public.can_manage_protected_person(report.protected_person_id)
  ), false);
$$;

create policy management_reports_storage_require_pdf_capability
on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'management-reports' or public.can_write_management_report_pdf(name));

create function public.assert_management_report_pdf_capability()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  dossier_id uuid;
  capabilities record;
begin
  if auth.uid() is null then return new; end if;
  select report.protected_person_id into strict dossier_id
  from public.management_reports report where report.id = new.management_report_id;
  if public.get_enabled_dossier_billing_features(dossier_id) is null then return new; end if;
  select * into strict capabilities from public.get_management_report_commercial_capabilities(dossier_id);
  if not capabilities.can_generate or (new.document_type = 'management_report' and not capabilities.can_finalize) then
    raise exception using errcode = '42501', message = 'La génération et la finalisation du PDF nécessitent un abonnement.';
  end if;
  return new;
end;
$$;

create trigger management_report_documents_05_require_pdf_capability
before insert on public.management_report_documents for each row
execute function public.assert_management_report_pdf_capability();

revoke all on function public.get_enabled_dossier_billing_features(uuid),
  public.get_management_report_commercial_capabilities(uuid),
  public.can_write_management_report_pdf(text), public.assert_management_report_pdf_capability()
from public, anon, authenticated, service_role;
grant execute on function public.get_management_report_commercial_capabilities(uuid),
  public.can_write_management_report_pdf(text) to authenticated;


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
  billing_features text[];
begin
  if auth.uid() is null or not public.can_read_protected_person(p_protected_person_id) then
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

  billing_features := public.get_enabled_dossier_billing_features(p_protected_person_id);

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
             when billing_features is not null and not (context.feature_key = any(billing_features)) then 'not_in_plan'
             when billing_features is null and context.entitlement_source = 'none' then 'subscription_missing'
             when billing_features is null and owner_entitlement.effective_plan_key is not null and not context.plan_included then 'not_in_plan'
             when context.feature_key in ('data_export', 'bank_operation_automation') and caller_role = 'read_only' then 'role_forbidden'
             else null
           end as read_denial_reason,
           case
             when context.implementation_status = 'upcoming' then 'feature_upcoming'
             when billing_features is not null and not (context.feature_key = any(billing_features)) then 'not_in_plan'
             when billing_features is null and context.entitlement_source = 'none' then 'subscription_missing'
             when billing_features is null and owner_entitlement.effective_plan_key is not null and not context.plan_included then 'not_in_plan'
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
