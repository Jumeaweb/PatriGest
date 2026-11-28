-- Reuse the same dossier access rules for the signed-in user and the
-- administrative projection, without changing or impersonating the session.
create function billing_internal.can_read_dossier_as(p_user_id uuid, p_person_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select p_user_id is not null
    and public.has_application_business_access(p_user_id, clock_timestamp())
    and exists (
      select 1 from public.protected_persons person cross join public.billing_runtime_config config
      where person.id = p_person_id and (
        person.owner_id = p_user_id or (
          exists (select 1 from public.protected_person_access access
                  where access.protected_person_id = person.id and access.user_id = p_user_id)
          and (not config.shared_access_enforcement_enabled or exists (
            select 1 from public.billing_resolve_entitlements_at(person.owner_id, clock_timestamp()) decision
            where decision.access_source in ('trial', 'commercial', 'administrative', 'legacy', 'development')
          ))
        )
      )
    );
$$;

create function billing_internal.can_manage_dossier_as(p_user_id uuid, p_person_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select billing_internal.can_read_dossier_as(p_user_id, p_person_id) and exists (
    select 1 from public.protected_persons person where person.id = p_person_id and (
      person.owner_id = p_user_id or exists (
        select 1 from public.protected_person_access access
        where access.protected_person_id = person.id and access.user_id = p_user_id and access.role = 'manager'
      )
    )
  );
$$;

revoke all on function billing_internal.can_read_dossier_as(uuid, uuid),
  billing_internal.can_manage_dossier_as(uuid, uuid) from public, anon, authenticated, service_role;

create or replace function public.can_read_protected_person(person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select billing_internal.can_read_dossier_as(auth.uid(), person_id);
$$;

create or replace function public.can_manage_protected_person(person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select billing_internal.can_manage_dossier_as(auth.uid(), person_id);
$$;

create function public.list_administrative_collaborator_access_counts(p_user_ids uuid[])
returns table (user_id uuid, total_count bigint, manager_count bigint, read_only_count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.platform_administrators administrator where administrator.user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'Accès administrateur requis.';
  end if;

  if p_user_ids is null or cardinality(p_user_ids) > 25 or array_position(p_user_ids, null) is not null then
    raise exception using errcode = '22023', message = 'Liste de comptes invalide.';
  end if;

  return query
  with requested as (
    select distinct existing_user.id
    from unnest(p_user_ids) as input(id)
    join auth.users existing_user on existing_user.id = input.id
  ), readable_dossiers as (
    select requested.id as collaborator_id, person.id as dossier_id,
      bool_or(person.status = 'active' and billing_internal.can_manage_dossier_as(requested.id, person.id)) as can_manage
    from requested
    join public.application_user_authorizations authorization_row
      on authorization_row.user_id = requested.id and authorization_row.account_mode = 'collaborator'
    join public.protected_person_access access on access.user_id = requested.id
    join public.protected_persons person on person.id = access.protected_person_id
    where billing_internal.can_read_dossier_as(requested.id, person.id)
    group by requested.id, person.id
  )
  select requested.id,
    count(readable.dossier_id),
    count(readable.dossier_id) filter (where readable.can_manage),
    count(readable.dossier_id) filter (where not readable.can_manage)
  from requested
  left join readable_dossiers readable on readable.collaborator_id = requested.id
  group by requested.id
  order by requested.id;
end;
$$;

revoke all on function public.list_administrative_collaborator_access_counts(uuid[])
from public, anon, authenticated, service_role;
grant execute on function public.list_administrative_collaborator_access_counts(uuid[]) to authenticated;
