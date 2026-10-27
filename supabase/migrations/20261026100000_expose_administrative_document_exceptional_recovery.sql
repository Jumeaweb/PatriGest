-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C5C2
-- Consultation applicative minimale des récupérations exceptionnelles.
-- Les registres restent privés : seules des DTO sûres et bornées sont exposées.

create or replace function public.get_administrative_document_exceptional_recovery(
  p_recovery_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  recovery_row public.document_repair_exceptional_recoveries%rowtype;
  effective_state text;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Consultation de récupération exceptionnelle non autorisée.';
  end if;
  select * into recovery_row
  from public.document_repair_exceptional_recoveries recovery
  where recovery.id = p_recovery_id;
  if not found then
    raise exception using errcode = 'P4X02',
      message = 'Récupération exceptionnelle introuvable.';
  end if;
  effective_state := case
    when recovery_row.state in ('rejected','consumed') then recovery_row.state
    when recovery_row.state = 'requested' then 'requested'
    when recovery_row.active_expires_at > statement_timestamp() then 'active'
    when recovery_row.activation_count > 0 then 'expired'
    else 'approved'
  end;
  return jsonb_build_object(
    'recoveryId', recovery_row.id,
    'authorizationId', recovery_row.authorization_id,
    'operationId', recovery_row.operation_id,
    'state', effective_state,
    'reason', recovery_row.reason,
    'decisionReason', recovery_row.decision_reason,
    'requestedAt', recovery_row.requested_at,
    'decidedAt', recovery_row.decided_at,
    'expiresAt', recovery_row.active_expires_at,
    'activationCount', recovery_row.activation_count,
    'maxActivations', recovery_row.max_activations,
    'revision', recovery_row.row_revision,
    'requesterIsCaller', recovery_row.requester_subject_id = caller_id,
    'approverIsCaller', recovery_row.approver_subject_id = caller_id,
    'canApprove', recovery_row.state = 'requested'
      and recovery_row.requester_subject_id <> caller_id,
    'activations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ordinal', activation.ordinal,
        'activatedAt', activation.activated_at,
        'expiresAt', activation.expires_at,
        'activatedByCaller', activation.activated_by = caller_id
      ) order by activation.ordinal)
      from public.document_repair_exceptional_activations activation
      where activation.recovery_id = recovery_row.id
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sequenceNumber', event.sequence_number,
        'eventType', event.event_type,
        'outcome', event.outcome,
        'safeCode', event.safe_code,
        'occurredAt', event.occurred_at,
        'actorIsCaller', event.actor_subject_id = caller_id
      ) order by event.sequence_number)
      from public.document_repair_exceptional_events event
      where event.recovery_id = recovery_row.id
    ), '[]'::jsonb)
  );
end;
$$;

create function public.get_administrative_document_exceptional_recovery_for_operation(
  p_operation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  recovery_id_value uuid;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Consultation de récupération exceptionnelle non autorisée.';
  end if;
  select recovery.id into recovery_id_value
  from public.document_repair_exceptional_recoveries recovery
  where recovery.operation_id = p_operation_id
  order by recovery.requested_at desc, recovery.id desc
  limit 1;
  if recovery_id_value is null then return null; end if;
  return public.get_administrative_document_exceptional_recovery(recovery_id_value);
end;
$$;

create function public.list_pending_administrative_document_exceptional_recoveries(
  p_limit integer default 20,
  p_after_requested_at timestamptz default null,
  p_after_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  bounded_limit integer;
  items_value jsonb;
  has_more_value boolean;
  next_requested_at_value timestamptz;
  next_id_value uuid;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Liste des récupérations exceptionnelles non autorisée.';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50
     or ((p_after_requested_at is null) <> (p_after_id is null)) then
    raise exception using errcode = 'P4X02',
      message = 'Pagination des récupérations exceptionnelles invalide.';
  end if;
  bounded_limit := p_limit;

  with eligible as (
    select recovery.*
    from public.document_repair_exceptional_recoveries recovery
    where recovery.state = 'requested'
      and recovery.requester_subject_id <> caller_id
      and (
        p_after_requested_at is null
        or (recovery.requested_at, recovery.id)
          < (p_after_requested_at, p_after_id)
      )
    order by recovery.requested_at desc, recovery.id desc
    limit bounded_limit + 1
  ), page as (
    select * from eligible
    order by requested_at desc, id desc
    limit bounded_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'recoveryId', page.id,
      'authorizationId', page.authorization_id,
      'operationId', page.operation_id,
      'state', 'requested',
      'reason', page.reason,
      'requestedAt', page.requested_at,
      'revision', page.row_revision,
      'requesterIsCaller', false,
      'canApprove', true
    ) order by page.requested_at desc, page.id desc), '[]'::jsonb),
    (select count(*) > bounded_limit from eligible)
  into items_value, has_more_value
  from page;

  if has_more_value and jsonb_array_length(items_value) > 0 then
    next_requested_at_value := (items_value -> -1 ->> 'requestedAt')::timestamptz;
    next_id_value := (items_value -> -1 ->> 'recoveryId')::uuid;
  end if;
  return jsonb_build_object(
    'items', items_value,
    'hasMore', has_more_value,
    'limit', bounded_limit,
    'nextRequestedAt', next_requested_at_value,
    'nextId', next_id_value
  );
end;
$$;

revoke all on function
  public.get_administrative_document_exceptional_recovery(uuid),
  public.get_administrative_document_exceptional_recovery_for_operation(uuid),
  public.list_pending_administrative_document_exceptional_recoveries(integer,timestamptz,uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_administrative_document_exceptional_recovery(uuid),
  public.get_administrative_document_exceptional_recovery_for_operation(uuid),
  public.list_pending_administrative_document_exceptional_recoveries(integer,timestamptz,uuid)
to authenticated;

comment on function public.list_pending_administrative_document_exceptional_recoveries(integer,timestamptz,uuid) is
  'Liste keyset bornée des demandes en attente d’un autre administrateur, sans identifiant personnel ni donnée Storage.';
