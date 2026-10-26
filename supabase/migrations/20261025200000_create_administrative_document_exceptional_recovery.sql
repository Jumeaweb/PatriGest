-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C5C1
-- Récupération exceptionnelle d'une réparation administrative commencée après
-- épuisement des six renouvellements ordinaires. Ce contrat ne modifie aucun
-- octet Storage, aucun plan de réparation et aucun item existant.

create table public.document_repair_exceptional_recoveries (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null unique
    references public.document_repair_authorizations(id) on delete restrict,
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  original_attempt_id uuid not null,
  requester_subject_id uuid not null,
  approver_subject_id uuid,
  request_id uuid not null,
  decision_id uuid,
  reason text not null check (char_length(btrim(reason)) between 1 and 2000),
  decision_reason text check (
    decision_reason is null or char_length(btrim(decision_reason)) between 1 and 2000
  ),
  repair_plan_hash text not null check (repair_plan_hash ~ '^[0-9a-f]{64}$'),
  requested_authorization_revision bigint not null check (requested_authorization_revision >= 0),
  request_context_hash text not null check (request_context_hash ~ '^[0-9a-f]{64}$'),
  state text not null default 'requested'
    check (state in ('requested','approved','rejected','consumed')),
  max_activations smallint not null default 2 check (max_activations = 2),
  activation_count smallint not null default 0
    check (activation_count between 0 and 2 and activation_count <= max_activations),
  last_activation_id uuid,
  requested_at timestamptz not null default clock_timestamp(),
  decided_at timestamptz,
  last_activated_at timestamptz,
  active_expires_at timestamptz,
  consumed_at timestamptz,
  row_revision bigint not null default 0 check (row_revision >= 0),
  unique (requester_subject_id, request_id),
  unique (id, authorization_id),
  check (approver_subject_id is null or approver_subject_id <> requester_subject_id),
  check (
    (state = 'requested' and approver_subject_id is null and decision_id is null
      and decision_reason is null and decided_at is null)
    or
    (state in ('approved','rejected','consumed') and approver_subject_id is not null
      and decision_id is not null and decision_reason is not null and decided_at is not null)
  ),
  check ((state = 'consumed') = (consumed_at is not null)),
  check (
    (activation_count = 0 and last_activation_id is null
      and last_activated_at is null and active_expires_at is null)
    or
    (activation_count > 0 and last_activation_id is not null
      and last_activated_at is not null and active_expires_at is not null
      and active_expires_at > last_activated_at
      and active_expires_at <= last_activated_at + interval '5 minutes')
  )
);

create table public.document_repair_exceptional_activations (
  id uuid primary key default gen_random_uuid(),
  recovery_id uuid not null references
    public.document_repair_exceptional_recoveries(id) on delete restrict,
  authorization_id uuid not null,
  ordinal smallint not null check (ordinal between 1 and 2),
  activation_id uuid not null,
  activated_by uuid not null,
  context_hash text not null check (context_hash ~ '^[0-9a-f]{64}$'),
  activated_at timestamptz not null,
  expires_at timestamptz not null,
  unique (recovery_id, ordinal),
  unique (recovery_id, activation_id),
  foreign key (recovery_id, authorization_id)
    references public.document_repair_exceptional_recoveries(id, authorization_id)
    on delete restrict,
  check (expires_at > activated_at and expires_at <= activated_at + interval '5 minutes')
);

create table public.document_repair_exceptional_events (
  id uuid primary key default gen_random_uuid(),
  recovery_id uuid not null references
    public.document_repair_exceptional_recoveries(id) on delete restrict,
  sequence_number bigint not null check (sequence_number > 0),
  event_type text not null check (event_type in (
    'requested','approved','rejected','activated','consumed'
  )),
  outcome text not null check (outcome in ('success','information')),
  actor_subject_id uuid not null,
  safe_code text check (safe_code is null or safe_code ~ '^[A-Z0-9_:-]{1,64}$'),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (recovery_id, sequence_number)
);

create index document_repair_exceptional_recoveries_state_idx
on public.document_repair_exceptional_recoveries(state, active_expires_at);

alter table public.document_repair_exceptional_recoveries enable row level security;
alter table public.document_repair_exceptional_activations enable row level security;
alter table public.document_repair_exceptional_events enable row level security;

revoke all on table public.document_repair_exceptional_recoveries,
  public.document_repair_exceptional_activations,
  public.document_repair_exceptional_events
from public, anon, authenticated, service_role;

create function public.protect_document_repair_exceptional_recovery()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  decision_changed boolean;
  activation_changed boolean;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501',
      message = 'Une récupération exceptionnelle est immuable.';
  end if;
  if (new.id, new.authorization_id, new.operation_id, new.original_attempt_id,
      new.requester_subject_id, new.request_id, new.reason,
      new.repair_plan_hash, new.requested_authorization_revision,
      new.request_context_hash, new.max_activations, new.requested_at)
     is distinct from
     (old.id, old.authorization_id, old.operation_id, old.original_attempt_id,
      old.requester_subject_id, old.request_id, old.reason,
      old.repair_plan_hash, old.requested_authorization_revision,
      old.request_context_hash, old.max_activations, old.requested_at) then
    raise exception using errcode = '42501',
      message = 'Le contexte de récupération exceptionnelle est immuable.';
  end if;

  decision_changed := (
    new.approver_subject_id, new.decision_id, new.decision_reason, new.decided_at
  ) is distinct from (
    old.approver_subject_id, old.decision_id, old.decision_reason, old.decided_at
  );
  activation_changed := (
    new.activation_count, new.last_activation_id,
    new.last_activated_at, new.active_expires_at
  ) is distinct from (
    old.activation_count, old.last_activation_id,
    old.last_activated_at, old.active_expires_at
  );

  if old.state = 'requested' and new.state in ('approved','rejected') then
    if not decision_changed or activation_changed
       or new.approver_subject_id is null
       or new.approver_subject_id = old.requester_subject_id
       or new.decision_id is null or new.decision_reason is null
       or new.decided_at < old.requested_at
       or new.row_revision <> old.row_revision + 1
       or new.consumed_at is not null then
      raise exception using errcode = '23514',
        message = 'Décision de récupération exceptionnelle invalide.';
    end if;
    return new;
  end if;

  if old.state = 'approved' and new.state = 'approved' and activation_changed then
    if decision_changed
       or new.activation_count <> old.activation_count + 1
       or new.activation_count > old.max_activations
       or new.last_activation_id is null
       or new.last_activation_id is not distinct from old.last_activation_id
       or new.last_activated_at < old.decided_at
       or new.active_expires_at <= new.last_activated_at
       or new.active_expires_at > new.last_activated_at + interval '5 minutes'
       or new.row_revision <> old.row_revision + 1
       or new.consumed_at is not null then
      raise exception using errcode = '23514',
        message = 'Activation de récupération exceptionnelle invalide.';
    end if;
    return new;
  end if;

  if old.state = 'approved' and new.state = 'consumed' then
    if decision_changed or activation_changed
       or old.activation_count = 0
       or new.consumed_at is null
       or new.consumed_at < old.last_activated_at
       or new.row_revision <> old.row_revision + 1 then
      raise exception using errcode = '23514',
        message = 'Consommation de récupération exceptionnelle invalide.';
    end if;
    return new;
  end if;

  if (new.state, new.approver_subject_id, new.decision_id,
      new.decision_reason, new.decided_at, new.activation_count,
      new.last_activation_id, new.last_activated_at, new.active_expires_at,
      new.consumed_at, new.row_revision)
     is distinct from
     (old.state, old.approver_subject_id, old.decision_id,
      old.decision_reason, old.decided_at, old.activation_count,
      old.last_activation_id, old.last_activated_at, old.active_expires_at,
      old.consumed_at, old.row_revision) then
    raise exception using errcode = '42501',
      message = 'Transition de récupération exceptionnelle interdite.';
  end if;
  return new;
end;
$$;

create trigger document_repair_exceptional_recoveries_protected
before update or delete on public.document_repair_exceptional_recoveries
for each row execute function public.protect_document_repair_exceptional_recovery();

create trigger document_repair_exceptional_activations_append_only
before update or delete on public.document_repair_exceptional_activations
for each row execute function public.protect_document_operation_audit_rows();

create trigger document_repair_exceptional_events_append_only
before update or delete on public.document_repair_exceptional_events
for each row execute function public.protect_document_operation_audit_rows();

create function public.append_document_repair_exceptional_event(
  p_recovery_id uuid,
  p_event_type text,
  p_actor_subject_id uuid,
  p_outcome text default 'success',
  p_safe_code text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_sequence bigint;
begin
  if p_actor_subject_id is null then
    raise exception using errcode = 'P4X02',
      message = 'Acteur de récupération exceptionnelle invalide.';
  end if;
  perform 1 from public.document_repair_exceptional_recoveries
  where id = p_recovery_id for update;
  if not found then
    raise exception using errcode = 'P4X02',
      message = 'Récupération exceptionnelle introuvable.';
  end if;
  select coalesce(max(event.sequence_number), 0) + 1 into next_sequence
  from public.document_repair_exceptional_events event
  where event.recovery_id = p_recovery_id;
  insert into public.document_repair_exceptional_events(
    recovery_id, sequence_number, event_type, outcome,
    actor_subject_id, safe_code
  ) values (
    p_recovery_id, next_sequence, p_event_type, p_outcome,
    p_actor_subject_id, p_safe_code
  );
  return next_sequence;
end;
$$;

create function public.document_repair_exceptional_context_fingerprint(
  p_authorization_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'authorizationId', repair_authorization.id,
    'operationId', repair_authorization.operation_id,
    'attemptId', repair_authorization.attempt_id,
    'authorizationRevision', repair_authorization.row_revision,
    'planHash', repair_authorization.repair_plan_hash,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'itemId', item.id,
        'itemRevision', item.row_revision,
        'progressState', item.progress_state,
        'executionId', item.execution_id,
        'targetId', item.target_id,
        'targetRevision', target.target_revision,
        'applicationState', target.application_state,
        'lockPresent', object_lock.target_id is not null,
        'observationCount', (
          select count(*) from public.document_repair_observations observation
          where observation.item_id = item.id
        )
      ) order by item.ordinal)
      from public.document_repair_items item
      join public.document_operation_targets target on target.id = item.target_id
      left join public.document_object_locks object_lock
        on object_lock.target_id = target.id
       and object_lock.operation_id = target.operation_id
       and object_lock.bucket_id = target.bucket_id
       and object_lock.object_path = target.object_path
      where item.authorization_id = repair_authorization.id
    ), '[]'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex')
  from public.document_repair_authorizations repair_authorization
  where repair_authorization.id = p_authorization_id;
$$;

create function public.assert_document_repair_exceptional_eligibility(
  p_authorization_id uuid
)
returns public.document_repair_authorizations
language plpgsql
security definer
set search_path = ''
as $$
declare
  authorization_row public.document_repair_authorizations%rowtype;
  operation_row public.document_operations%rowtype;
begin
  select * into authorization_row
  from public.document_repair_authorizations
  where id = p_authorization_id for update;
  if not found
     or authorization_row.state <> 'active'
     or authorization_row.renewal_count <> 6
     or coalesce(authorization_row.recovery_expires_at, authorization_row.expires_at)
        > clock_timestamp() then
    raise exception using errcode = 'P4X03',
      message = 'La réparation n’est pas éligible à une récupération exceptionnelle.';
  end if;
  if authorization_row.repair_plan_hash is distinct from
       public.document_repair_plan_hash(authorization_row.repair_plan) then
    raise exception using errcode = 'P4X04',
      message = 'Le plan de réparation a divergé.';
  end if;
  if not exists (
    select 1 from public.platform_administrators administrator
    where administrator.user_id = authorization_row.administrator_subject_id
  ) then
    raise exception using errcode = 'P4X01',
      message = 'L’administrateur initiateur n’est plus autorisé.';
  end if;
  if not exists (
    select 1 from public.document_repair_items item
    where item.authorization_id = authorization_row.id
      and item.progress_state <> 'authorized'
  ) then
    raise exception using errcode = 'P4X03',
      message = 'Une réparation non commencée ne peut pas être récupérée.';
  end if;
  if (select count(*) from public.document_repair_items item
      where item.authorization_id = authorization_row.id)
     <> authorization_row.target_count then
    raise exception using errcode = 'P4X04',
      message = 'La liste des cibles de réparation a divergé.';
  end if;
  select * into operation_row from public.document_operations
  where id = authorization_row.operation_id for update;
  if not found or operation_row.state <> 'attention_required'
     or operation_row.workflow in ('account_storage_neutralization','administrative_repair')
     or operation_row.row_revision
        is distinct from authorization_row.observed_operation_revision then
    raise exception using errcode = 'P4X04',
      message = 'L’opération documentaire a divergé.';
  end if;
  perform 1
  from public.document_repair_items item
  join public.document_operation_targets target
    on target.id = item.target_id and target.operation_id = item.operation_id
  where item.authorization_id = authorization_row.id
  order by target.id
  for update of target;
  perform 1
  from public.document_repair_items item
  join public.document_operation_targets target on target.id = item.target_id
  join public.document_object_locks object_lock
    on object_lock.target_id = target.id
   and object_lock.operation_id = target.operation_id
   and object_lock.bucket_id = target.bucket_id
   and object_lock.object_path = target.object_path
  where item.authorization_id = authorization_row.id
  order by object_lock.bucket_id, object_lock.object_path
  for update of object_lock;
  if exists (
    select 1
    from public.document_repair_items item
    left join public.document_operation_targets target
      on target.id = item.target_id and target.operation_id = item.operation_id
    left join public.document_object_locks object_lock
      on object_lock.target_id = target.id
     and object_lock.operation_id = target.operation_id
     and object_lock.bucket_id = target.bucket_id
     and object_lock.object_path = target.object_path
    where item.authorization_id = authorization_row.id
      and (target.id is null
        or target.target_revision is distinct from item.expected_target_revision
        or target.application_state is distinct from item.expected_application_state
        or object_lock.target_id is null)
  ) then
    raise exception using errcode = 'P4X06',
      message = 'Une cible ou son verrou a divergé.';
  end if;
  if exists (
    select 1
    from public.document_repair_items item
    join public.document_operation_targets target on target.id = item.target_id
    join public.document_operation_targets other_target
      on other_target.bucket_id = target.bucket_id
     and other_target.object_path = target.object_path
     and other_target.operation_id <> target.operation_id
    join public.account_storage_neutralizations neutralization
      on neutralization.target_id = other_target.id
    where item.authorization_id = authorization_row.id
      and neutralization.phase <> 'finalized'
  ) then
    raise exception using errcode = 'P4X06',
      message = 'Une neutralisation de compte est en conflit avec la récupération.';
  end if;
  return authorization_row;
end;
$$;

create function public.request_administrative_document_exceptional_recovery(
  p_authorization_id uuid,
  p_attempt_id uuid,
  p_expected_plan_hash text,
  p_request_id uuid,
  p_reason text,
  p_expected_authorization_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.document_repair_authorizations%rowtype;
  recovery_row public.document_repair_exceptional_recoveries%rowtype;
  context_hash_value text;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Demande de récupération exceptionnelle non autorisée.';
  end if;
  if p_request_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 1 and 2000 then
    raise exception using errcode = 'P4X02',
      message = 'Demande de récupération exceptionnelle invalide.';
  end if;
  select * into recovery_row
  from public.document_repair_exceptional_recoveries recovery
  where recovery.requester_subject_id = caller_id
    and recovery.request_id = p_request_id;
  if found then
    if recovery_row.authorization_id is distinct from p_authorization_id
       or recovery_row.original_attempt_id is distinct from p_attempt_id
       or recovery_row.repair_plan_hash is distinct from p_expected_plan_hash
       or recovery_row.requested_authorization_revision
          is distinct from p_expected_authorization_revision
       or recovery_row.reason is distinct from btrim(p_reason) then
      raise exception using errcode = 'P4X05',
        message = 'La clé de demande est déjà liée à une autre récupération.';
    end if;
    return jsonb_build_object(
      'recoveryId', recovery_row.id,
      'authorizationId', recovery_row.authorization_id,
      'operationId', recovery_row.operation_id,
      'state', recovery_row.state,
      'activationCount', recovery_row.activation_count,
      'maxActivations', recovery_row.max_activations,
      'revision', recovery_row.row_revision,
      'idempotent', true
    );
  end if;

  authorization_row := public.assert_document_repair_exceptional_eligibility(
    p_authorization_id
  );
  if authorization_row.administrator_subject_id is distinct from caller_id
     or authorization_row.attempt_id is distinct from p_attempt_id then
    raise exception using errcode = 'P4X01',
      message = 'Demande de récupération exceptionnelle non autorisée.';
  end if;
  if authorization_row.repair_plan_hash is distinct from p_expected_plan_hash
     or authorization_row.row_revision
        is distinct from p_expected_authorization_revision then
    raise exception using errcode = 'P4X04',
      message = 'Le contexte initial de réparation a divergé.';
  end if;
  context_hash_value := public.document_repair_exceptional_context_fingerprint(
    authorization_row.id
  );
  insert into public.document_repair_exceptional_recoveries(
    authorization_id, operation_id, original_attempt_id,
    requester_subject_id, request_id, reason, repair_plan_hash,
    requested_authorization_revision, request_context_hash
  ) values (
    authorization_row.id, authorization_row.operation_id,
    authorization_row.attempt_id, caller_id, p_request_id, btrim(p_reason),
    authorization_row.repair_plan_hash, authorization_row.row_revision,
    context_hash_value
  ) on conflict do nothing returning * into recovery_row;
  if recovery_row.id is null then
    select * into recovery_row
    from public.document_repair_exceptional_recoveries recovery
    where recovery.requester_subject_id = caller_id
      and recovery.request_id = p_request_id;
    if found
       and recovery_row.authorization_id is not distinct from p_authorization_id
       and recovery_row.original_attempt_id is not distinct from p_attempt_id
       and recovery_row.repair_plan_hash is not distinct from p_expected_plan_hash
       and recovery_row.requested_authorization_revision
          is not distinct from p_expected_authorization_revision
       and recovery_row.reason is not distinct from btrim(p_reason) then
      return jsonb_build_object(
        'recoveryId', recovery_row.id,
        'authorizationId', recovery_row.authorization_id,
        'operationId', recovery_row.operation_id,
        'state', recovery_row.state,
        'activationCount', recovery_row.activation_count,
        'maxActivations', recovery_row.max_activations,
        'revision', recovery_row.row_revision,
        'idempotent', true
      );
    end if;
    raise exception using errcode = 'P4X05',
      message = 'Une récupération exceptionnelle existe déjà pour cette réparation.';
  end if;
  perform public.append_document_repair_exceptional_event(
    recovery_row.id, 'requested', caller_id
  );
  return jsonb_build_object(
    'recoveryId', recovery_row.id,
    'authorizationId', recovery_row.authorization_id,
    'operationId', recovery_row.operation_id,
    'state', recovery_row.state,
    'activationCount', recovery_row.activation_count,
    'maxActivations', recovery_row.max_activations,
    'revision', recovery_row.row_revision,
    'idempotent', false
  );
end;
$$;

create function public.decide_administrative_document_exceptional_recovery(
  p_recovery_id uuid,
  p_decision_id uuid,
  p_approve boolean,
  p_reason text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  recovery_row public.document_repair_exceptional_recoveries%rowtype;
  authorization_row public.document_repair_authorizations%rowtype;
  context_hash_value text;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Décision de récupération exceptionnelle non autorisée.';
  end if;
  if p_decision_id is null or p_reason is null
     or char_length(btrim(p_reason)) not between 1 and 2000 then
    raise exception using errcode = 'P4X02',
      message = 'Décision de récupération exceptionnelle invalide.';
  end if;
  -- Read the immutable identifier first, then acquire the authorization lock
  -- before the recovery lock. The sealing RPC already locks in that order.
  -- Keeping the same order prevents an activation/decision from deadlocking
  -- with a concurrent seal that consumes the recovery in its AFTER trigger.
  select * into recovery_row
  from public.document_repair_exceptional_recoveries
  where id = p_recovery_id;
  if not found or recovery_row.requester_subject_id = caller_id then
    raise exception using errcode = 'P4X01',
      message = 'Une validation administrative indépendante est requise.';
  end if;
  if recovery_row.decision_id is not distinct from p_decision_id then
    if recovery_row.approver_subject_id is distinct from caller_id
       or recovery_row.decision_reason is distinct from btrim(p_reason)
       or recovery_row.state is distinct from
          (case when p_approve then 'approved' else 'rejected' end)
       or recovery_row.row_revision is distinct from p_expected_revision + 1 then
      raise exception using errcode = 'P4X05',
        message = 'La clé de décision est déjà liée à une autre décision.';
    end if;
    return jsonb_build_object(
      'recoveryId', recovery_row.id, 'state', recovery_row.state,
      'revision', recovery_row.row_revision, 'idempotent', true
    );
  end if;
  if p_approve then
    authorization_row := public.assert_document_repair_exceptional_eligibility(
      recovery_row.authorization_id
    );
  end if;
  select * into recovery_row
  from public.document_repair_exceptional_recoveries
  where id = p_recovery_id for update;
  if not found or recovery_row.requester_subject_id = caller_id then
    raise exception using errcode = 'P4X01',
      message = 'Une validation administrative indépendante est requise.';
  end if;
  if recovery_row.decision_id is not distinct from p_decision_id then
    if recovery_row.approver_subject_id is distinct from caller_id
       or recovery_row.decision_reason is distinct from btrim(p_reason)
       or recovery_row.state is distinct from
          (case when p_approve then 'approved' else 'rejected' end)
       or recovery_row.row_revision is distinct from p_expected_revision + 1 then
      raise exception using errcode = 'P4X05',
        message = 'La clé de décision est déjà liée à une autre décision.';
    end if;
    return jsonb_build_object(
      'recoveryId', recovery_row.id, 'state', recovery_row.state,
      'revision', recovery_row.row_revision, 'idempotent', true
    );
  end if;
  if recovery_row.state <> 'requested'
     or recovery_row.row_revision is distinct from p_expected_revision then
    raise exception using errcode = 'P4X05',
      message = 'La récupération a déjà reçu une décision ou a divergé.';
  end if;
  if p_approve then
    context_hash_value := public.document_repair_exceptional_context_fingerprint(
      authorization_row.id
    );
    if authorization_row.attempt_id is distinct from recovery_row.original_attempt_id
       or authorization_row.repair_plan_hash is distinct from recovery_row.repair_plan_hash
       or authorization_row.row_revision
          is distinct from recovery_row.requested_authorization_revision
       or context_hash_value is distinct from recovery_row.request_context_hash then
      raise exception using errcode = 'P4X04',
        message = 'Le contexte de récupération a divergé depuis la demande.';
    end if;
  end if;
  update public.document_repair_exceptional_recoveries
  set state = case when p_approve then 'approved' else 'rejected' end,
      approver_subject_id = caller_id,
      decision_id = p_decision_id,
      decision_reason = btrim(p_reason),
      decided_at = clock_timestamp(),
      row_revision = row_revision + 1
  where id = recovery_row.id returning * into recovery_row;
  perform public.append_document_repair_exceptional_event(
    recovery_row.id, case when p_approve then 'approved' else 'rejected' end,
    caller_id
  );
  return jsonb_build_object(
    'recoveryId', recovery_row.id, 'state', recovery_row.state,
    'revision', recovery_row.row_revision, 'idempotent', false
  );
end;
$$;

create function public.activate_administrative_document_exceptional_recovery(
  p_recovery_id uuid,
  p_activation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  activated_at_value timestamptz := clock_timestamp();
  recovery_row public.document_repair_exceptional_recoveries%rowtype;
  authorization_row public.document_repair_authorizations%rowtype;
  activation_row public.document_repair_exceptional_activations%rowtype;
  context_hash_value text;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4X01',
      message = 'Activation de récupération exceptionnelle non autorisée.';
  end if;
  if p_activation_id is null then
    raise exception using errcode = 'P4X02',
      message = 'Identité d’activation exceptionnelle invalide.';
  end if;
  -- The authorization is the first mutable aggregate locked by the historical
  -- progression and sealing RPCs. Read the recovery without a lock to discover
  -- it, lock the authorization context, then lock and re-read the recovery.
  select * into recovery_row
  from public.document_repair_exceptional_recoveries
  where id = p_recovery_id;
  if not found or recovery_row.requester_subject_id is distinct from caller_id then
    raise exception using errcode = 'P4X01',
      message = 'Activation de récupération exceptionnelle non autorisée.';
  end if;
  select * into activation_row
  from public.document_repair_exceptional_activations activation
  where activation.recovery_id = recovery_row.id
    and activation.activation_id = p_activation_id;
  if found then
    if p_expected_revision is distinct from activation_row.ordinal then
      raise exception using errcode = 'P4X05',
        message = 'La clé d’activation est déjà liée à une autre intention.';
    end if;
    return jsonb_build_object(
      'recoveryId', recovery_row.id,
      'state', case
        when recovery_row.state in ('rejected','consumed') then recovery_row.state
        when activation_row.expires_at > clock_timestamp() then 'active'
        else 'expired'
      end,
      'expiresAt', activation_row.expires_at,
      'activationCount', recovery_row.activation_count,
      'maxActivations', recovery_row.max_activations,
      'revision', recovery_row.row_revision, 'idempotent', true
    );
  end if;
  authorization_row := public.assert_document_repair_exceptional_eligibility(
    recovery_row.authorization_id
  );
  select * into recovery_row
  from public.document_repair_exceptional_recoveries
  where id = p_recovery_id for update;
  if not found or recovery_row.requester_subject_id is distinct from caller_id then
    raise exception using errcode = 'P4X01',
      message = 'Activation de récupération exceptionnelle non autorisée.';
  end if;
  select * into activation_row
  from public.document_repair_exceptional_activations activation
  where activation.recovery_id = recovery_row.id
    and activation.activation_id = p_activation_id;
  if found then
    if p_expected_revision is distinct from activation_row.ordinal then
      raise exception using errcode = 'P4X05',
        message = 'La clé d’activation est déjà liée à une autre intention.';
    end if;
    return jsonb_build_object(
      'recoveryId', recovery_row.id,
      'state', case
        when recovery_row.state in ('rejected','consumed') then recovery_row.state
        when activation_row.expires_at > clock_timestamp() then 'active'
        else 'expired'
      end,
      'expiresAt', activation_row.expires_at,
      'activationCount', recovery_row.activation_count,
      'maxActivations', recovery_row.max_activations,
      'revision', recovery_row.row_revision, 'idempotent', true
    );
  end if;
  if recovery_row.state <> 'approved'
     or recovery_row.row_revision is distinct from p_expected_revision then
    raise exception using errcode = 'P4X05',
      message = 'La récupération exceptionnelle n’est pas activable.';
  end if;
  if recovery_row.active_expires_at > activated_at_value then
    raise exception using errcode = 'P4X06',
      message = 'Une fenêtre exceptionnelle est déjà active.';
  end if;
  if recovery_row.activation_count >= recovery_row.max_activations then
    raise exception using errcode = 'P4X07',
      message = 'Le plafond des activations exceptionnelles est atteint.';
  end if;
  context_hash_value := public.document_repair_exceptional_context_fingerprint(
    authorization_row.id
  );
  if authorization_row.attempt_id is distinct from recovery_row.original_attempt_id
     or authorization_row.repair_plan_hash is distinct from recovery_row.repair_plan_hash
     or (recovery_row.activation_count = 0 and
       context_hash_value is distinct from recovery_row.request_context_hash) then
    raise exception using errcode = 'P4X04',
      message = 'Le contexte de récupération exceptionnelle a divergé.';
  end if;
  insert into public.document_repair_exceptional_activations(
    recovery_id, authorization_id, ordinal, activation_id, activated_by,
    context_hash, activated_at, expires_at
  ) values (
    recovery_row.id, recovery_row.authorization_id,
    recovery_row.activation_count + 1, p_activation_id, caller_id,
    context_hash_value, activated_at_value,
    activated_at_value + interval '5 minutes'
  ) returning * into activation_row;
  update public.document_repair_exceptional_recoveries
  set activation_count = activation_count + 1,
      last_activation_id = p_activation_id,
      last_activated_at = activated_at_value,
      active_expires_at = activation_row.expires_at,
      row_revision = row_revision + 1
  where id = recovery_row.id returning * into recovery_row;
  perform public.append_document_repair_exceptional_event(
    recovery_row.id, 'activated', caller_id, 'information',
    'EXCEPTIONAL_RECOVERY_WINDOW_ACTIVE'
  );
  return jsonb_build_object(
    'recoveryId', recovery_row.id, 'state', 'active',
    'expiresAt', activation_row.expires_at,
    'activationCount', recovery_row.activation_count,
    'maxActivations', recovery_row.max_activations,
    'revision', recovery_row.row_revision, 'idempotent', false
  );
end;
$$;

create or replace function public.document_repair_effective_expires_at(
  p_authorization public.document_repair_authorizations
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce(p_authorization.recovery_expires_at, p_authorization.expires_at),
    coalesce((
      select max(activation.expires_at)
      from public.document_repair_exceptional_recoveries recovery
      join public.document_repair_exceptional_activations activation
        on activation.recovery_id = recovery.id
       and activation.authorization_id = recovery.authorization_id
      where recovery.authorization_id = p_authorization.id
        and recovery.state = 'approved'
    ), '-infinity'::timestamptz)
  );
$$;

create function public.get_administrative_document_exceptional_recovery(
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
  from public.document_repair_exceptional_recoveries
  where id = p_recovery_id;
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
    'requestedAt', recovery_row.requested_at,
    'decidedAt', recovery_row.decided_at,
    'expiresAt', recovery_row.active_expires_at,
    'activationCount', recovery_row.activation_count,
    'maxActivations', recovery_row.max_activations,
    'revision', recovery_row.row_revision,
    'requesterIsCaller', recovery_row.requester_subject_id = caller_id,
    'approverIsCaller', recovery_row.approver_subject_id = caller_id,
    'canApprove', recovery_row.state = 'requested'
      and recovery_row.requester_subject_id <> caller_id
  );
end;
$$;

create function public.consume_document_repair_exceptional_recovery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recovery_row public.document_repair_exceptional_recoveries%rowtype;
  actor_id uuid := auth.uid();
  consumed_at_value timestamptz;
begin
  if old.state = 'active' and new.state = 'sealed' then
    select * into recovery_row
    from public.document_repair_exceptional_recoveries recovery
    where recovery.authorization_id = new.id
      and recovery.state = 'approved'
    for update;
    if found then
      consumed_at_value := clock_timestamp();
      if recovery_row.active_expires_at is null
         or recovery_row.active_expires_at <= consumed_at_value then
        raise exception using errcode = 'P4X03',
          message = 'La fenêtre exceptionnelle n’est plus active au scellement.';
      end if;
      update public.document_repair_exceptional_recoveries
      set state = 'consumed', consumed_at = consumed_at_value,
          row_revision = row_revision + 1
      where id = recovery_row.id returning * into recovery_row;
      perform public.append_document_repair_exceptional_event(
        recovery_row.id, 'consumed', actor_id, 'success',
        'EXCEPTIONAL_RECOVERY_CONSUMED'
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger document_repair_exceptional_recovery_consumed
after update of state on public.document_repair_authorizations
for each row execute function public.consume_document_repair_exceptional_recovery();

revoke all on function
  public.protect_document_repair_exceptional_recovery(),
  public.append_document_repair_exceptional_event(uuid,text,uuid,text,text),
  public.document_repair_exceptional_context_fingerprint(uuid),
  public.assert_document_repair_exceptional_eligibility(uuid),
  public.consume_document_repair_exceptional_recovery()
from public, anon, authenticated, service_role;

revoke all on function
  public.request_administrative_document_exceptional_recovery(uuid,uuid,text,uuid,text,bigint),
  public.decide_administrative_document_exceptional_recovery(uuid,uuid,boolean,text,bigint),
  public.activate_administrative_document_exceptional_recovery(uuid,uuid,bigint),
  public.get_administrative_document_exceptional_recovery(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.request_administrative_document_exceptional_recovery(uuid,uuid,text,uuid,text,bigint),
  public.decide_administrative_document_exceptional_recovery(uuid,uuid,boolean,text,bigint),
  public.activate_administrative_document_exceptional_recovery(uuid,uuid,bigint),
  public.get_administrative_document_exceptional_recovery(uuid)
to authenticated;

comment on table public.document_repair_exceptional_recoveries is
  'Double validation administrative exceptionnelle après six renouvellements ; le plan initial reste la seule autorité.';
comment on table public.document_repair_exceptional_activations is
  'Deux fenêtres append-only de cinq minutes maximum, sans remise à zéro du compteur de renouvellements.';
comment on function public.activate_administrative_document_exceptional_recovery(uuid,uuid,bigint) is
  'Active une fenêtre courte après double validation, sans mutation Storage ni création d’un second moteur.';
