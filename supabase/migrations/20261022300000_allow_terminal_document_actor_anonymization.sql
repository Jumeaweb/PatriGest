-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2B2
-- Autorise uniquement l'anonymisation référentielle des acteurs d'une opération
-- terminale lors de la suppression Auth. L'identité durable du sujet reste
-- conservée dans initiator_subject_id.

create or replace function public.validate_document_operation_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  actor_anonymization boolean;
begin
  if (new.id, new.protected_person_id, new.initiator_subject_id,
      new.initiator_kind, new.workflow, new.business_entity_type,
      new.business_entity_id, new.client_request_id, new.target_signature,
      new.created_at)
     is distinct from
     (old.id, old.protected_person_id, old.initiator_subject_id,
      old.initiator_kind, old.workflow, old.business_entity_type,
      old.business_entity_id, old.client_request_id, old.target_signature,
      old.created_at) then
    raise exception using errcode = '42501',
      message = 'L’identité de l’opération documentaire est immuable.';
  end if;

  if old.state in (
    'completed', 'compensated', 'cancelled', 'administratively_resolved'
  ) then
    actor_anonymization := (
      (
        new.initiated_by is not distinct from old.initiated_by
        or (old.initiated_by is not null and new.initiated_by is null)
      )
      and (
        new.resolution_by is not distinct from old.resolution_by
        or (old.resolution_by is not null and new.resolution_by is null)
      )
      and (
        new.initiated_by is distinct from old.initiated_by
        or new.resolution_by is distinct from old.resolution_by
      )
      and (new.state, new.started_at, new.last_activity_at, new.closed_at,
           new.safe_error_code, new.resolution_reason, new.resolution_at,
           new.row_revision)
          is not distinct from
          (old.state, old.started_at, old.last_activity_at, old.closed_at,
           old.safe_error_code, old.resolution_reason, old.resolution_at,
           old.row_revision)
    );
    if actor_anonymization then
      return new;
    end if;
    raise exception using errcode = '23514',
      message = 'Une opération documentaire terminale est immuable.';
  end if;

  if new.state <> old.state and not (
    (old.state = 'reserved'
      and new.state in ('executing','compensating','attention_required','cancelled'))
    or (old.state = 'executing'
      and new.state in ('completed','compensating','attention_required'))
    or (old.state = 'compensating'
      and new.state in ('compensated','attention_required'))
    or (old.state = 'attention_required'
      and new.state in ('compensating','administratively_resolved'))
  ) then
    raise exception using errcode = '23514',
      message = 'Transition documentaire invalide.';
  end if;

  if new.state = 'completed' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id and target.application_state <> 'applied'
  ) and not (
    new.workflow = 'account_storage_neutralization'
    and new.initiator_kind = 'account_deletion'
    and exists (
      select 1 from public.account_storage_neutralizations neutralization
      where neutralization.operation_id = new.id
        and neutralization.phase = 'finalized'
    )
  ) then
    raise exception using errcode = '23514',
      message = 'Toutes les cibles doivent être appliquées avant la finalisation.';
  end if;

  if new.state = 'compensated' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id
      and target.application_state not in ('pending','compensated')
  ) then
    raise exception using errcode = '23514',
      message = 'Toutes les cibles appliquées doivent être compensées.';
  end if;

  if new.state = 'cancelled' and exists (
    select 1 from public.document_operation_targets target
    where target.operation_id = new.id and target.application_state <> 'pending'
  ) then
    raise exception using errcode = '23514',
      message = 'Une opération déjà appliquée ne peut pas être annulée.';
  end if;

  return new;
end;
$$;

comment on function public.validate_document_operation_update() is
  'Protège les opérations documentaires ; une opération terminale autorise seulement la mise à NULL référentielle de initiated_by ou resolution_by lors de la suppression Auth.';

