-- PAT-STRIPE-02D: preserve the source PDF through the SQL transition.
-- Retirements are indexed by immutable Storage object identity, never by a
-- client-supplied path. The Storage API performs the physical removal.
create table public.management_report_file_retirements (
  storage_object_id uuid primary key,
  report_id uuid not null,
  storage_path text not null,
  reason text not null check (reason in ('retired_project', 'unpublished_final')),
  recorded_at timestamptz not null default clock_timestamp(),
  removed_at timestamptz
);
alter table public.management_report_file_retirements enable row level security;
revoke all on public.management_report_file_retirements from public, anon, authenticated, service_role;
create index management_report_file_retirements_by_report
  on public.management_report_file_retirements(report_id) where removed_at is null;
create index management_report_file_retirements_by_path
  on public.management_report_file_retirements(storage_path);

create table public.management_report_final_verifications (
  storage_object_id uuid primary key,
  report_id uuid not null,
  storage_version text not null,
  byte_count bigint not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  verified_at timestamptz not null default clock_timestamp()
);
alter table public.management_report_final_verifications enable row level security;
revoke all on public.management_report_final_verifications from public, anon, authenticated, service_role;

create function public.record_management_report_final_verification(
  p_report_id uuid, p_object_id uuid, p_object_version text, p_size bigint, p_sha256 text
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  insert into public.management_report_final_verifications(storage_object_id, report_id, storage_version, byte_count, sha256)
  select object.id, report.id, object.version, p_size, p_sha256
  from public.management_reports report join storage.objects object
    on object.name = 'protected-persons/' || report.protected_person_id || '/management-reports/' || report.id || '/management-report.pdf'
  where report.id = p_report_id and object.bucket_id = 'management-reports' and object.id = p_object_id
    and object.version = p_object_version and object.metadata ->> 'size' = p_size::text
    and object.metadata ->> 'mimetype' = 'application/pdf' and p_size between 1 and 20971520
  on conflict (storage_object_id) do nothing;
  return exists (select 1 from public.management_report_final_verifications proof
    where proof.storage_object_id = p_object_id and proof.report_id = p_report_id
      and proof.storage_version = p_object_version and proof.byte_count = p_size and proof.sha256 = p_sha256);
end;
$$;

revoke all on function public.record_management_report_final_verification(uuid, uuid, text, bigint, text)
from public, anon, authenticated, service_role;
grant execute on function public.record_management_report_final_verification(uuid, uuid, text, bigint, text) to service_role;

create function public.record_management_report_project_retirement()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.management_report_file_retirements(storage_object_id, report_id, storage_path, reason)
  select object.id, old.management_report_id, object.name, 'retired_project'
  from storage.objects object
  where object.bucket_id = 'management-reports' and object.name = old.storage_path
  on conflict (storage_object_id) do nothing;
  return old;
end;
$$;

create trigger management_report_project_retirement
after delete on public.management_report_documents
for each row when (old.document_type = 'management_report_draft')
execute function public.record_management_report_project_retirement();

create function public.is_management_report_file_referenced(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.management_report_documents document
    where document.storage_path = p_path);
$$;

-- The previously permissive policy is preserved for unpublished files only.
-- PostgreSQL decides whether the project reference has been retired.
create function public.can_discard_unpublished_report_project(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.management_reports report
    where p_path = 'protected-persons/' || report.protected_person_id || '/management-reports/' || report.id || '/management-report-draft.pdf'
      and report.status::text = 'ready' and public.can_manage_protected_person(report.protected_person_id)
      and not public.is_management_report_file_referenced(p_path)
  );
$$;

create policy management_reports_keep_referenced_objects
on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'management-reports' or public.can_discard_unpublished_report_project(name));

create function public.guard_management_report_retired_object()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- A late retry must not remove a new object that reused a canonical path.
  if exists (select 1 from public.management_report_file_retirements job
              where job.storage_path = old.name) then
    update public.management_report_file_retirements job
    set removed_at = clock_timestamp()
    where job.storage_object_id = old.id and job.storage_path = old.name
      and job.removed_at is null
      and not public.is_management_report_file_referenced(old.name);
    if not found then
      raise exception using errcode = '42501', message = 'Cette version du fichier ne peut pas être nettoyée.';
    end if;
  end if;
  return old;
end;
$$;

create trigger management_report_guard_retired_object
before delete on storage.objects for each row when (old.bucket_id = 'management-reports')
execute function public.guard_management_report_retired_object();

create function public.list_management_report_retired_files(p_report_id uuid)
returns table (storage_path text)
language sql stable security definer set search_path = '' as $$
  select job.storage_path
  from public.management_report_file_retirements job
  join storage.objects object on object.id = job.storage_object_id and object.name = job.storage_path
    and object.bucket_id = 'management-reports'
  where job.report_id = p_report_id and job.removed_at is null
    and not public.is_management_report_file_referenced(job.storage_path);
$$;

-- Used only after the server has staged and verified a particular object.
-- The report lock serializes this decision with a possibly committed RPC.
create function public.retire_unpublished_management_report_final(p_report_id uuid, p_object_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  report public.management_reports%rowtype;
  object_path text;
begin
  select * into report from public.management_reports where id = p_report_id for update;
  if not found then return 'unknown'; end if;
  object_path := 'protected-persons/' || report.protected_person_id || '/management-reports/' || report.id || '/management-report.pdf';
  if public.is_management_report_file_referenced(object_path) then
    if report.status::text = 'finalized' and exists (select 1 from storage.objects object
      where object.bucket_id = 'management-reports' and object.name = object_path and object.id = p_object_id) then
      return 'published';
    end if;
    return 'unknown';
  end if;
  if report.status::text <> 'generated' then return 'unknown'; end if;
  insert into public.management_report_file_retirements(storage_object_id, report_id, storage_path, reason)
  select object.id, report.id, object.name, 'unpublished_final'
  from storage.objects object where object.bucket_id = 'management-reports'
    and object.name = object_path and object.id = p_object_id
  on conflict (storage_object_id) do nothing;
  return case when exists (select 1 from public.management_report_file_retirements job
    where job.storage_object_id = p_object_id and job.report_id = p_report_id) then 'retired' else 'unknown' end;
end;
$$;

revoke all on function public.record_management_report_project_retirement(),
  public.guard_management_report_retired_object(), public.is_management_report_file_referenced(text),
  public.can_discard_unpublished_report_project(text),
  public.list_management_report_retired_files(uuid), public.retire_unpublished_management_report_final(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.can_discard_unpublished_report_project(text) to authenticated;
grant execute on function public.list_management_report_retired_files(uuid),
  public.retire_unpublished_management_report_final(uuid, uuid) to service_role;


create or replace function public.resume_management_report_preparation(p_report_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_report public.management_reports%rowtype;
  v_expected_path text;
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise.'; end if;
  select * into v_report from public.management_reports where id = p_report_id for update;
  if v_report.id is null or not public.can_manage_protected_person(v_report.protected_person_id) then
    raise exception 'Compte de gestion introuvable ou accès refusé.';
  end if;
  if v_report.status::text <> 'generated' then raise exception 'Seul un projet généré peut être repris.'; end if;
  v_expected_path := 'protected-persons/' || v_report.protected_person_id::text || '/management-reports/' || v_report.id::text || '/management-report-draft.pdf';
  delete from public.management_report_documents
  where management_report_id = v_report.id and document_type = 'management_report_draft' and storage_path = v_expected_path;
  if not found then raise exception 'Le document projet est introuvable.'; end if;
  update public.management_reports set status = 'draft', generated_at = null, finalized_at = null where id = v_report.id and status::text = 'generated';
  if not found then raise exception 'Le statut du compte de gestion a changé.'; end if;
end;
$$;

create or replace function public.finalize_management_report(
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
  v_storage_object_id uuid;
  v_draft_path text;
  v_expected_path text;
  v_row_count bigint;
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise.'; end if;
  select * into v_report from public.management_reports where id = p_report_id for update;
  if v_report.id is null or not public.can_manage_protected_person(v_report.protected_person_id) then
    raise exception 'Compte de gestion introuvable ou accès refusé.';
  end if;
  if v_report.status::text <> 'generated' then raise exception 'Un projet doit être généré avant la finalisation.'; end if;
  v_draft_path := 'protected-persons/' || v_report.protected_person_id::text || '/management-reports/' || v_report.id::text || '/management-report-draft.pdf';
  v_expected_path := 'protected-persons/' || v_report.protected_person_id::text || '/management-reports/' || v_report.id::text || '/management-report.pdf';
  if p_storage_path <> v_expected_path or p_mime_type <> 'application/pdf' or p_file_size <= 0 or p_file_size > 20971520 then
    raise exception 'Métadonnées du document final invalides.';
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
     or p_preview_snapshot #>> '{report,status}' is distinct from 'finalized' then
    raise exception 'Le snapshot ne correspond pas au compte de gestion.';
  end if;
  select object.id into v_storage_object_id from storage.objects object
  where object.bucket_id = 'management-reports' and object.name = p_storage_path
    and exists (select 1 from public.management_report_final_verifications proof
      where proof.storage_object_id = object.id and proof.storage_version = object.version
        and proof.report_id = p_report_id and proof.byte_count = p_file_size)
  for update;
  if v_storage_object_id is null or exists (
    select 1 from public.management_report_file_retirements job
    where job.storage_object_id = v_storage_object_id
  ) then
    raise exception 'Le PDF final est introuvable dans le stockage privé.';
  end if;
  insert into public.management_report_documents (
    management_report_id, document_type, storage_path, file_name, mime_type,
    file_size, preview_snapshot, snapshot_schema_version, generated_by
  ) values (
    v_report.id, 'management_report', p_storage_path, p_file_name, p_mime_type,
    p_file_size, p_preview_snapshot, p_snapshot_schema_version, (select auth.uid())
  ) returning id into v_document_id;
  delete from public.management_report_documents
  where management_report_id = v_report.id
    and document_type = 'management_report_draft'
    and storage_path = v_draft_path;
  if not found then raise exception 'Le document projet est introuvable.'; end if;
  execute 'update public.management_reports set status = ''finalized'', finalized_at = now() where id = $1 and status::text = ''generated''' using v_report.id;
  get diagnostics v_row_count = row_count;
  if v_row_count <> 1 then raise exception 'Le statut du compte de gestion a changé.'; end if;
  return v_document_id;
end;
$$;

create function public.publish_verified_management_report_final(
  p_report_id uuid, p_storage_object_id uuid, p_file_name text, p_file_size bigint,
  p_preview_snapshot jsonb, p_snapshot_schema_version integer
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  report public.management_reports%rowtype;
  object_path text;
begin
  select * into report from public.management_reports where id = p_report_id for update;
  if not found or not public.can_manage_protected_person(report.protected_person_id) then
    raise exception using errcode = '42501', message = 'Compte de gestion introuvable ou accès refusé.';
  end if;
  object_path := 'protected-persons/' || report.protected_person_id || '/management-reports/' || report.id || '/management-report.pdf';
  perform 1 from storage.objects object where object.id = p_storage_object_id
    and object.bucket_id = 'management-reports' and object.name = object_path for update;
  if not found then raise exception using errcode = '22023', message = 'Le PDF vérifié est absent.'; end if;
  return public.finalize_management_report(report.id, object_path, p_file_name, 'application/pdf',
    p_file_size, p_preview_snapshot, p_snapshot_schema_version);
end;
$$;

revoke all on function public.publish_verified_management_report_final(uuid, uuid, text, bigint, jsonb, integer)
from public, anon, authenticated, service_role;
grant execute on function public.publish_verified_management_report_final(uuid, uuid, text, bigint, jsonb, integer)
to authenticated;
