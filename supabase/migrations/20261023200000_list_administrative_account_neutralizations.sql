-- Permet à l'orchestrateur privilégié de retrouver les neutralisations d'une
-- tentative administrative après une interruption ou une réponse perdue.
create function public.get_administrative_account_deletion_attempt(
  p_target_user_id uuid,
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  authorization_row public.administrative_account_deletion_authorizations%rowtype;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4D01',
      message = 'Consultation administrative non autorisée.';
  end if;
  select * into authorization_row
  from public.administrative_account_deletion_authorizations authz
  where authz.administrator_subject_id = caller_id
    and authz.target_user_id = p_target_user_id
    and authz.attempt_id = p_attempt_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'authorizationId', authorization_row.id,
    'administratorUserId', authorization_row.administrator_subject_id,
    'targetUserId', authorization_row.target_user_id,
    'attemptId', authorization_row.attempt_id,
    'reason', authorization_row.reason,
    'planHash', authorization_row.document_plan_hash,
    'documentCount', authorization_row.document_count,
    'documentPlan', authorization_row.document_plan,
    'expiresAt', authorization_row.expires_at,
    'state', authorization_row.state,
    'revision', authorization_row.row_revision
  );
end;
$$;

create function public.list_administrative_account_storage_neutralization_operations(
  p_authorization_id uuid
)
returns table (
  operation_id uuid,
  client_request_id uuid,
  state text,
  phase text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.assert_account_storage_neutralization_service();
  if p_authorization_id is null then
    raise exception using errcode = 'P4D02',
      message = 'Autorisation administrative invalide.';
  end if;
  return query
  select operation.id, operation.client_request_id, operation.state,
         neutralization.phase, operation.created_at
  from public.account_storage_neutralizations neutralization
  join public.document_operations operation
    on operation.id = neutralization.operation_id
  where neutralization.administrative_authorization_id = p_authorization_id
    and operation.initiator_kind = 'platform_admin'
    and operation.workflow = 'account_storage_neutralization'
  order by operation.created_at, operation.id;
end;
$$;

revoke all on function
  public.get_administrative_account_deletion_attempt(uuid,uuid),
  public.list_administrative_account_storage_neutralization_operations(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_administrative_account_deletion_attempt(uuid,uuid)
to authenticated;

grant execute on function
  public.list_administrative_account_storage_neutralization_operations(uuid)
to service_role;

comment on function
  public.get_administrative_account_deletion_attempt(uuid,uuid)
is 'Restitue au seul administrateur initiateur le contexte immuable nécessaire à la reprise de sa tentative.';

comment on function
  public.list_administrative_account_storage_neutralization_operations(uuid)
is 'Inventaire privilégié et borné des neutralisations d une autorisation administrative, destiné exclusivement à leur reprise durable.';
