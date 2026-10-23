-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2B
-- Gèle les nouvelles écritures documentaires de l'utilisateur pendant une
-- tentative de suppression de compte. Aucun trigger Storage n'est installé.

create function public.is_current_account_deletion_document_write_frozen()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.account_deletion_document_authorizations authz
    where authz.account_user_id = auth.uid()
      and (
        authz.state = 'sealed'
        or (
          authz.state = 'active'
          and authz.expires_at > statement_timestamp()
        )
        or exists (
          select 1
          from public.account_storage_neutralizations neutralization
          where neutralization.authorization_id = authz.id
            and neutralization.phase <> 'finalized'
        )
      )
  );
$$;

create function public.assert_account_deletion_document_writes_allowed()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_current_account_deletion_document_write_frozen() then
    raise exception using errcode = 'P4N06',
      message = 'Les écritures documentaires sont suspendues pendant la suppression du compte.';
  end if;
end;
$$;

-- Ce point central est appelé par les trois RPC d'ouverture de workflow.
-- Les lectures et les reprises d'opérations existantes restent possibles.
create or replace function public.assert_document_operation_opening_access(
  p_protected_person_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  dossier_status text;
begin
  if caller_id is null or not public.is_application_user_active()
     or public.is_platform_admin() then
    raise exception using errcode = 'P4O01',
      message = 'Accès à la réservation documentaire refusé.';
  end if;
  perform public.assert_account_deletion_document_writes_allowed();
  select status into dossier_status
  from public.protected_persons
  where id = p_protected_person_id
  for key share;
  if not found or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = 'P4O01',
      message = 'Accès à la réservation documentaire refusé.';
  end if;
  if dossier_status <> 'active' then
    raise exception using errcode = 'P4O03',
      message = 'Le dossier doit être actif.';
  end if;
end;
$$;

-- Les politiques existantes restent permissives pour les comptes ordinaires.
-- Ces politiques restrictives ajoutent uniquement le gel de la suppression.
create policy account_deletion_freeze_storage_insert
on storage.objects as restrictive
for insert to authenticated
with check (not public.is_current_account_deletion_document_write_frozen());

create policy account_deletion_freeze_storage_update
on storage.objects as restrictive
for update to authenticated
using (not public.is_current_account_deletion_document_write_frozen())
with check (not public.is_current_account_deletion_document_write_frozen());

create policy account_deletion_freeze_storage_delete
on storage.objects as restrictive
for delete to authenticated
using (not public.is_current_account_deletion_document_write_frozen());

create function public.list_account_storage_neutralization_operations(
  p_account_user_id uuid
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
  if p_account_user_id is null then
    raise exception using errcode = 'P4N02',
      message = 'Compte de neutralisation invalide.';
  end if;
  return query
  select operation.id, operation.client_request_id, operation.state,
         neutralization.phase, operation.created_at
  from public.document_operations operation
  join public.account_storage_neutralizations neutralization
    on neutralization.operation_id = operation.id
  where neutralization.account_user_id = p_account_user_id
    and operation.initiator_kind = 'account_deletion'
    and operation.workflow = 'account_storage_neutralization'
  order by operation.created_at, operation.id;
end;
$$;

revoke all on function
  public.is_current_account_deletion_document_write_frozen(),
  public.assert_account_deletion_document_writes_allowed(),
  public.list_account_storage_neutralization_operations(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.is_current_account_deletion_document_write_frozen()
to authenticated;

grant execute on function
  public.list_account_storage_neutralization_operations(uuid)
to service_role;

comment on function public.is_current_account_deletion_document_write_frozen() is
  'Indique uniquement pour auth.uid() si une tentative active, une récupération non finalisée ou une autorisation scellée suspend les mutations documentaires.';
comment on function public.list_account_storage_neutralization_operations(uuid) is
  'Inventaire privilégié des neutralisations existantes à reprendre avant tout nouvel inventaire Storage.';
