-- PAT-STRIPE-02E. Slot increases use the same owner lock as rights transitions.
create or replace function public.lock_owner_dossier_capacity(p_owner_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Acquiring a row lock does not refresh a transaction-wide snapshot.
  if current_setting('transaction_isolation') not in ('read committed', 'read uncommitted')
     and exists (select 1 from public.billing_runtime_config where commercial_access_enabled) then
    raise exception using errcode = '25000',
      message = 'Le contrôle de capacité nécessite une transaction READ COMMITTED.';
  end if;

  perform 1 from public.application_user_authorizations authorization_row
  where authorization_row.user_id = p_owner_id for update;
  if not found then
    raise exception using errcode = 'P4D03', message = 'Configuration de capacité indisponible.';
  end if;
end;
$$;

-- Do not expose billing identifiers, features or a caller-supplied time/owner.
create function public.get_owned_dossier_quota_gate()
returns table (active_dossier_limit integer, active_dossier_count bigint,
               remaining_dossier_count bigint, block_reason text)
language sql stable security definer set search_path = '' as $$
  select decision.active_dossier_limit, decision.active_dossier_count,
    case when decision.active_dossier_limit is not null then
      greatest(decision.active_dossier_limit::bigint - decision.active_dossier_count, 0::bigint)
    end,
    case
      when decision.access_source = 'none' then 'account_suspended'
      when decision.active_dossier_limit is null then 'configuration_unavailable'
      when decision.active_dossier_count >= decision.active_dossier_limit then 'quota_reached'
    end
  from public.application_user_authorizations subject
  join public.billing_runtime_config config on config.singleton and config.commercial_access_enabled
  cross join lateral public.billing_resolve_entitlements_at(subject.user_id, clock_timestamp()) decision
  where subject.user_id = auth.uid()
    and subject.status = 'active' and subject.account_mode = 'autonomous'
    and not public.is_platform_admin();
$$;

-- Advisory Checkout preflight for a future trusted caller. The initial
-- verified-invoice acceptance still rechecks the same count under the owner lock.
create function billing_internal.check_essential_dossier_capacity(p_owner uuid)
returns table (active_dossier_count bigint, essential_limit integer, exceeded_by bigint, compatible boolean)
language sql stable set search_path = '' as $$
  select decision.active_dossier_count, 2, greatest(decision.active_dossier_count - 2, 0::bigint),
    decision.active_dossier_count <= 2
  from public.application_user_authorizations subject
  cross join lateral public.billing_resolve_entitlements_at(subject.user_id, clock_timestamp()) decision
  where subject.user_id = p_owner and subject.account_mode = 'autonomous'
    and subject.status = 'active'
    and not exists (select 1 from public.platform_administrators admin where admin.user_id = subject.user_id);
$$;

revoke all on function public.get_owned_dossier_quota_gate() from public, anon, authenticated, service_role;
grant execute on function public.get_owned_dossier_quota_gate() to authenticated;
revoke all on function billing_internal.check_essential_dossier_capacity(uuid)
from public, anon, authenticated, service_role;

create or replace function public.resolve_owner_dossier_capacity(p_owner_id uuid)
returns table (
  unlimited boolean,
  active_dossier_limit integer,
  active_dossier_count bigint,
  remaining_dossier_count bigint,
  exceeded_by bigint
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  entitlement record;
  decision record;
begin
  if exists (select 1 from public.billing_runtime_config where commercial_access_enabled) then
    select * into decision from public.billing_resolve_entitlements_at(p_owner_id, clock_timestamp());
    if decision.access_source = 'shared_access' then
      raise exception using errcode = 'P4D02', message = 'Capacité de dossiers indisponible.';
    elsif decision.access_source = 'none' then
      raise exception using errcode = 'P4D04',
        message = 'Vos droits sont suspendus. Consultez Mon compte > Abonnement.';
    elsif decision.active_dossier_limit is null then
      raise exception using errcode = 'P4D03', message = 'Configuration de capacité indisponible.';
    end if;
    return query select false, decision.active_dossier_limit, decision.active_dossier_count,
      greatest(decision.active_dossier_limit::bigint - decision.active_dossier_count, 0::bigint),
      greatest(decision.active_dossier_count - decision.active_dossier_limit::bigint, 0::bigint);
    return;
  end if;
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
create or replace function public.enforce_protected_person_dossier_capacity()
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
  if exists (select 1 from public.billing_runtime_config where commercial_access_enabled) then
    -- Archives release a slot via the existing owner-locked RPC. A direct
    -- deletion can only release a slot. Do not acquire owner after dossier.
    if tg_op = 'DELETE' then
      return old;
    end if;
    if tg_op = 'UPDATE' then
      if new.owner_id is distinct from old.owner_id then
        raise exception using errcode = '42501', message = 'Le propriétaire du dossier ne peut pas être modifié.';
      end if;
      if old.status = 'active' or new.status <> 'active' then
        return new;
      end if;
    end if;

    if caller_id is distinct from new.owner_id or caller_id is null
       or current_setting('role', true) is distinct from 'authenticated'
       or public.is_platform_admin()
       or not exists (
         select 1 from public.application_user_authorizations subject
         where subject.user_id = caller_id and subject.account_mode = 'autonomous'
           and subject.status = 'active'
       ) then
      raise exception using errcode = '42501', message = 'Opération sur le dossier non autorisée.';
    end if;

    perform public.lock_owner_dossier_capacity(new.owner_id);
    perform public.assert_owner_dossier_capacity(new.owner_id);
    return new;
  end if;
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
create or replace function public.restore_protected_person(p_protected_person_id uuid,p_expected_revision bigint,p_reason text)
returns bigint language plpgsql security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); dossier_owner_id uuid; person_row public.protected_persons%rowtype; restored_person public.protected_persons%rowtype; normalized_reason text:=btrim(p_reason);
begin
  if exists (select 1 from public.get_owned_dossier_quota_gate() where block_reason = 'account_suspended') then
    raise exception using errcode = 'P4D04',
      message = 'Vos droits sont suspendus. Consultez Mon compte > Abonnement.';
  end if;
  if caller_id is null or not public.is_application_user_active() or public.is_platform_admin() then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.assert_protected_person_archive_lifecycle_enabled();
  if normalized_reason is null or char_length(normalized_reason) not between 1 and 2000 then raise exception using errcode='P4A03',message='Le motif de la restauration est invalide.'; end if;
  if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  select owner_id into dossier_owner_id from public.protected_persons where id=p_protected_person_id;
  if not found then raise exception using errcode='P4A02',message='Dossier introuvable.'; end if;
  if dossier_owner_id<>caller_id then raise exception using errcode='P4A01',message='Accès à la transition du dossier refusé.'; end if;
  perform public.lock_owner_dossier_capacity(dossier_owner_id);
  select * into person_row from public.protected_persons where id=p_protected_person_id for update;
  if person_row.archive_revision<>p_expected_revision then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  if person_row.status<>'archived' or person_row.archived_at is null then raise exception using errcode='P4A04',message='Le dossier ne peut pas être restauré dans son état actuel.'; end if;
  if exists(select 1 from public.document_operations where protected_person_id=p_protected_person_id and workflow='administrative_repair' and state in ('reserved','executing','compensating','attention_required')) then
    raise exception using errcode='P4A06',message='Une réparation documentaire en cours bloque la restauration.';
  end if;
  update public.protected_persons set status='active',archived_at=null
  where id=person_row.id and status='archived' and archived_at is not null and archive_revision=p_expected_revision returning * into restored_person;
  if not found then raise exception using errcode='P4A05',message='La révision du dossier est obsolète.'; end if;
  insert into public.protected_person_archive_changes(protected_person_id,old_status,new_status,changed_by,changed_at,reason)
  values(person_row.id,person_row.status,restored_person.status,caller_id,clock_timestamp(),normalized_reason);
  return restored_person.archive_revision;
end; $$;
