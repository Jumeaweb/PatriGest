-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3G-2A
-- Le document définitif doit reprendre exactement le snapshot réglementaire
-- du projet relu. Seul le statut documentaire passe de generated à finalized.

create function public.final_management_report_snapshot_from_project(
  p_project_snapshot jsonb
)
returns jsonb
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_project_snapshot) = 'object'
      and jsonb_typeof(p_project_snapshot -> 'report') = 'object'
      and p_project_snapshot #>> '{report,status}' = 'generated'
    then jsonb_set(
      p_project_snapshot,
      '{report,status}',
      to_jsonb('finalized'::text),
      false
    )
    else null
  end;
$$;

create function public.validate_final_management_report_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  report_status text;
  project_snapshot jsonb;
  project_schema_version integer;
  expected_final_snapshot jsonb;
begin
  if new.document_type <> 'management_report' then
    return new;
  end if;

  select report.status::text
  into report_status
  from public.management_reports report
  where report.id = new.management_report_id;

  -- Les lignes historiques ne sont pas réécrites par cette migration. Les
  -- deux RPC de finalisation sont les seuls parcours qui créent un document
  -- définitif et elles le font pendant le statut generated. Les restaurations
  -- documentaires existantes restaurent uniquement l'objet Storage associé.
  if report_status is distinct from 'generated' then
    raise exception using
      errcode = '23514',
      message = 'Un document définitif ne peut être créé que depuis un projet généré.';
  end if;

  select document.preview_snapshot, document.snapshot_schema_version
  into project_snapshot, project_schema_version
  from public.management_report_documents document
  where document.management_report_id = new.management_report_id
    and document.document_type = 'management_report_draft'
  for update;

  if not found or project_snapshot is null or project_schema_version is null then
    raise exception using
      errcode = '23514',
      message = 'Le snapshot du projet est absent.';
  end if;

  if project_schema_version <> 1
     or new.snapshot_schema_version is distinct from project_schema_version then
    raise exception using
      errcode = '23514',
      message = 'La version du snapshot du projet est incompatible.';
  end if;

  expected_final_snapshot := public.final_management_report_snapshot_from_project(
    project_snapshot
  );
  if expected_final_snapshot is null
     or new.preview_snapshot is distinct from expected_final_snapshot then
    raise exception using
      errcode = '23514',
      message = 'Le snapshot définitif diffère du projet généré.';
  end if;

  return new;
end;
$$;

create trigger management_report_documents_10_validate_final_snapshot
before insert on public.management_report_documents
for each row execute function public.validate_final_management_report_snapshot();

revoke all on function public.final_management_report_snapshot_from_project(jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.validate_final_management_report_snapshot()
from public, anon, authenticated, service_role;

comment on function public.final_management_report_snapshot_from_project(jsonb) is
  'Normalise exclusivement le statut generated en finalized sans recalculer les données métier.';
comment on function public.validate_final_management_report_snapshot() is
  'Protège les RPC historique et durable contre un document final différent du projet relu.';
