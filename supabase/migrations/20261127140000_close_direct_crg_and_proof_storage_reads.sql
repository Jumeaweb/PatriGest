-- PAT-STRIPE-02D. Install the server-compatible operations before the
-- application cutover. The restrictive policies are installed separately.
-- The published legacy paths remain readable through the app. New writes
-- publish a reserved version instead of overwriting the previous object.
create function public.reserve_transaction_proof_for_storage(
  p_protected_person_id uuid, p_transaction_id uuid, p_intent text, p_client_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare previous_intent text;
begin
  select reservation.intent into previous_intent
  from public.document_operations operation
  join public.transaction_proof_version_reservations reservation on reservation.operation_id = operation.id
  where operation.initiator_kind = 'user' and operation.initiator_subject_id = auth.uid()
    and operation.client_request_id = p_client_request_id
    and reservation.protected_person_id = p_protected_person_id and reservation.transaction_id = p_transaction_id;
  return public.reserve_transaction_proof_version(p_protected_person_id, p_transaction_id,
    coalesce(previous_intent, p_intent), p_client_request_id);
end;
$$;
revoke all on function public.reserve_transaction_proof_for_storage(uuid, uuid, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.reserve_transaction_proof_for_storage(uuid, uuid, text, uuid) to authenticated;

alter table public.management_report_file_retirements
  drop constraint management_report_file_retirements_reason_check,
  add constraint management_report_file_retirements_reason_check
    check (reason in ('retired_project', 'unpublished_final', 'unpublished_project'));

create function public.retire_unpublished_management_report_project(p_report_id uuid, p_object_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  report public.management_reports%rowtype;
  object_path text;
begin
  select * into report from public.management_reports where id = p_report_id for update;
  if not found then return 'unknown'; end if;
  object_path := 'protected-persons/' || report.protected_person_id || '/management-reports/' || report.id || '/management-report-draft.pdf';
  if public.is_management_report_file_referenced(object_path) then
    if report.status::text = 'generated' and exists (select 1 from storage.objects object
      where object.bucket_id = 'management-reports' and object.name = object_path and object.id = p_object_id) then
      return 'published';
    end if;
    return 'unknown';
  end if;
  if report.status::text <> 'ready' then return 'unknown'; end if;
  insert into public.management_report_file_retirements(storage_object_id, report_id, storage_path, reason)
  select object.id, report.id, object.name, 'unpublished_project'
  from storage.objects object where object.bucket_id = 'management-reports'
    and object.name = object_path and object.id = p_object_id
  on conflict (storage_object_id) do nothing;
  return case when exists (select 1 from public.management_report_file_retirements job
    where job.storage_object_id = p_object_id and job.report_id = p_report_id) then 'retired' else 'unknown' end;
end;
$$;
revoke all on function public.retire_unpublished_management_report_project(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.retire_unpublished_management_report_project(uuid, uuid) to service_role;


create or replace function public.finalize_management_report_draft_generation(
  p_report_id uuid,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint,
  p_preview_snapshot jsonb,
  p_snapshot_schema_version integer
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_report public.management_reports%rowtype;
  v_document_id uuid;
  v_expected_path text;
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise.'; end if;
  select * into v_report from public.management_reports where id = p_report_id for update;
  if v_report.id is null or not public.can_manage_protected_person(v_report.protected_person_id) then
    raise exception 'Compte de gestion introuvable ou accès refusé.';
  end if;
  if v_report.status::text <> 'ready' then raise exception 'Le compte de gestion doit être prêt.'; end if;
  v_expected_path := 'protected-persons/' || v_report.protected_person_id::text || '/management-reports/' || v_report.id::text || '/management-report-draft.pdf';
  if p_storage_path <> v_expected_path or p_mime_type <> 'application/pdf' or p_file_size <= 0 or p_file_size > 20971520 then
    raise exception 'Métadonnées du document invalides.';
  end if;
  if p_preview_snapshot is null or jsonb_typeof(p_preview_snapshot) <> 'object'
     or p_snapshot_schema_version is null or p_snapshot_schema_version <= 0 then
    raise exception 'Snapshot réglementaire invalide.';
  end if;
  if p_preview_snapshot #>> '{report,id}' is distinct from v_report.id::text
     or p_preview_snapshot #>> '{report,protected_person_id}' is distinct from v_report.protected_person_id::text
     or p_preview_snapshot #>> '{person,id}' is distinct from v_report.protected_person_id::text
     or p_preview_snapshot #>> '{report,report_year}' is distinct from v_report.report_year::text
     or p_preview_snapshot #>> '{report,period_start}' is distinct from v_report.period_start::text
     or p_preview_snapshot #>> '{report,period_end}' is distinct from v_report.period_end::text
     or p_preview_snapshot #>> '{report,status}' is distinct from 'generated' then
    raise exception 'Le snapshot ne correspond pas au compte de gestion.';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'management-reports' and object.name = p_storage_path
      and not exists (select 1 from public.management_report_file_retirements job where job.storage_object_id = object.id)
    for update
  ) then
    raise exception 'Le PDF projet est introuvable dans le stockage privé.';
  end if;
  insert into public.management_report_documents (
    management_report_id, document_type, storage_path, file_name, mime_type,
    file_size, preview_snapshot, snapshot_schema_version, generated_by
  ) values (
    v_report.id, 'management_report_draft', p_storage_path, p_file_name, p_mime_type,
    p_file_size, p_preview_snapshot, p_snapshot_schema_version, (select auth.uid())
  ) returning id into v_document_id;
  update public.management_reports
  set status = 'generated', generated_at = now(), finalized_at = null
  where id = v_report.id and status::text = 'ready';
  if not found then raise exception 'Le statut du compte de gestion a changé.'; end if;
  return v_document_id;
end;
$$;
