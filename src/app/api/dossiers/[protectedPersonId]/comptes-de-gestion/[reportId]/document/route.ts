import { NextResponse } from "next/server";
import { z } from "zod";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getManagementReportDocument, getManagementReportPreviewState, getManagementReportSnapshot } from "@/domains/management-reports/services";
import { buildManagementReportPreview } from "@/domains/management-reports/preview-model";
import { generateManagementReportPdf } from "@/domains/management-reports/pdf";
import { MANAGEMENT_REPORT_BUCKET, managementReportContentDisposition, managementReportDownloadName, managementReportStoragePath, type ManagementReportPdfMode } from "@/domains/management-reports/document-helpers";
import { finalizeManagementReportProjectSnapshot, MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION, parseManagementReportSnapshot, toJsonValue } from "@/domains/management-reports/snapshot";
import {
  isManagementReportDurableOperationsEnabled,
  runManagementReportDocumentWrite,
} from "@/domains/management-reports/management-report-durable-availability";
import { executeDurableManagementReportOperation } from "@/domains/management-reports/management-report-durable";
import { createManagementReportRequestId } from "@/domains/management-reports/management-report-durable-reservation";
import { cleanRetiredReportDocuments, inspectUnpublishedReportPdf, resolveUncertainReportFinalization, verifyUnpublishedReportPdf } from "@/domains/management-reports/report-document-retirement";
import { protectedStorageResponse } from "@/lib/supabase/protected-storage-response";

export const runtime = "nodejs";
type Params = { params: Promise<{ protectedPersonId: string; reportId: string }> };
type ReservationClient = Parameters<typeof executeDurableManagementReportOperation>[0]["client"];

async function identifiers(params: Params["params"]) { const value = await params; return [value.protectedPersonId, value.reportId].every((id) => z.uuid().safeParse(id).success) ? value : null; }
type PublishFinalRpc = {
  rpc(name: "publish_verified_management_report_final", args: {
    p_report_id: string; p_storage_object_id: string; p_file_name: string; p_file_size: number;
    p_preview_snapshot: ReturnType<typeof toJsonValue>; p_snapshot_schema_version: number;
  }): PromiseLike<{ error: unknown }>;
};
async function livePreview(personId: string, reportId: string, targetStatus: "generated" | "finalized") {
  const snapshot = await getManagementReportSnapshot(personId, reportId);
  if (!snapshot) return { success: false as const, reason: "context_unavailable" as const, issuePaths: [] };
  const preview = buildManagementReportPreview(snapshot);
  const parsed = parseManagementReportSnapshot(toJsonValue({ ...preview, report: { ...preview.report, status: targetStatus } }));
  if (!parsed.success) {
    return {
      success: false as const,
      reason: "invalid_snapshot" as const,
      issuePaths: [...new Set(parsed.error.issues.map((issue) => issue.path.join(".")).filter(Boolean))],
    };
  }
  return { success: true as const, preview: parsed.data, accessRole: snapshot.person.accessRole, currentStatus: snapshot.report.status, refreshRequiredAt: snapshot.report.refresh_required_at };
}

export async function POST(request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  try {
    const { supabase } = await getAuthenticatedUser();
    const { data: capabilities } = await supabase.rpc("get_management_report_commercial_capabilities", { p_protected_person_id: ids.protectedPersonId });
    if (!capabilities?.[0]?.can_generate) return NextResponse.json({ message: "La génération du PDF nécessite un abonnement. Votre préparation est conservée." }, { status: 403 });
    const generated = await livePreview(ids.protectedPersonId, ids.reportId, "generated");
    if (!generated.success) {
      console.error("MANAGEMENT_REPORT_PROJECT_CONTEXT_FAILURE", {
        reason: generated.reason,
        issuePaths: generated.issuePaths,
      });
      return NextResponse.json(
        {
          message: generated.reason === "invalid_snapshot"
            ? `L’instantané du compte de gestion est invalide (CRG-SNAPSHOT${generated.issuePaths.length ? ` : ${generated.issuePaths.join(", ")}` : ""}).`
            : "Le contexte du compte de gestion est indisponible (CRG-CTX-01).",
        },
        { status: 409 },
      );
    }
    const { preview, accessRole, currentStatus } = generated;
    if (accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas générer ce projet." }, { status: 403 });
    if (currentStatus !== "ready") return NextResponse.json({ message: "Le compte de gestion doit être prêt avant la génération du projet." }, { status: 409 });
    if (!preview.complete) return NextResponse.json({ message: "Le compte de gestion n’est plus complet. Vérifiez les informations à compléter." }, { status: 409 });
    if (!preview.checks.consistent) return NextResponse.json({ message: "Les contrôles de cohérence du compte de gestion ont échoué." }, { status: 409 });
    const durableEnabled = isManagementReportDurableOperationsEnabled();
    const previewSnapshot = toJsonValue(preview);
    const pdf = await generateManagementReportPdf(preview, {
      mode: "draft",
      deterministicCreationDate: preview.report.updated_at,
    });
    const storagePath = managementReportStoragePath(ids.protectedPersonId, ids.reportId, "draft");
    const fileName = managementReportDownloadName(preview.report.report_year, preview.person.first_name, preview.person.last_name, "draft");
    await cleanRetiredReportDocuments(ids.reportId);
    return runManagementReportDocumentWrite(
      durableEnabled,
      async () => {
        const bytes = new Uint8Array(pdf);
        let objectId: string | null = null;
        try {
          const upload = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).upload(storagePath, bytes, { contentType: "application/pdf", upsert: false });
          objectId = upload.data?.id ?? null;
        } catch {
          // The upload may have been committed before the response was lost.
        }
        objectId ??= (await inspectUnpublishedReportPdf(storagePath, bytes))?.id ?? null;
        if (!objectId) return NextResponse.json({ message: "Impossible de confirmer l’archivage du PDF projet." }, { status: 503 });
        let confirmed = false;
        try {
          const transition = await supabase.rpc("finalize_management_report_draft_generation", { p_report_id: ids.reportId, p_storage_path: storagePath, p_file_name: fileName, p_mime_type: "application/pdf", p_file_size: pdf.length, p_preview_snapshot: previewSnapshot, p_snapshot_schema_version: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION });
          confirmed = !transition.error;
        } catch {
          // PostgreSQL determines whether this exact object was published.
        }
        if (!confirmed && await resolveUncertainReportFinalization(ids.reportId, objectId, "project") !== "published") {
          return NextResponse.json({ message: "La génération du projet n’a pas pu être confirmée. Vérifiez son état avant de réessayer." }, { status: 409 });
        }
        return NextResponse.json({ message: "Le projet du compte de gestion a été généré." });
      },
      async () => {
        await executeDurableManagementReportOperation({
          client: supabase as unknown as ReservationClient,
          personId: ids.protectedPersonId,
          reportId: ids.reportId,
          intent: "generate",
          bytes: new Uint8Array(pdf),
          fileName,
          previewSnapshot,
          snapshotSchemaVersion: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
          clientRequestId: createManagementReportRequestId({
            personId: ids.protectedPersonId,
            reportId: ids.reportId,
            intent: "generate",
            clientRequestNonce: z.uuid().safeParse(request.headers.get("x-patrigest-request-id")).data ?? null,
            sourceDocumentRevision: null,
            previewSnapshot,
            snapshotSchemaVersion: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
            fileName,
            bytes: new Uint8Array(pdf),
          }),
        });
        return NextResponse.json({ message: "Le projet du compte de gestion a été généré." });
      },
    );
  } catch {
    return NextResponse.json({ message: "Impossible de générer le projet du compte de gestion." }, { status: 500 });
  }
}

export async function PATCH(request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  const { supabase } = await getAuthenticatedUser();
  const { data: capabilities } = await supabase.rpc("get_management_report_commercial_capabilities", { p_protected_person_id: ids.protectedPersonId });
  if (!capabilities?.[0]?.can_finalize) return NextResponse.json({ message: "La finalisation nécessite un abonnement. Votre projet est conservé." }, { status: 403 });
  const context = await getManagementReportPreviewState(ids.protectedPersonId, ids.reportId);
  if (!context) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas finaliser ce compte de gestion." }, { status: 403 });
  if (context.report.status !== "generated") return NextResponse.json({ message: "Un projet doit être généré avant la finalisation." }, { status: 409 });
  if (context.report.refresh_required_at) return NextResponse.json({ message: "Le compte de gestion doit être actualisé et son projet régénéré avant finalisation." }, { status: 409 });
  const draft = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, "management_report_draft");
  if (!draft) return NextResponse.json({ message: "Le PDF projet est introuvable." }, { status: 409 });
  const finalized = finalizeManagementReportProjectSnapshot(draft.preview_snapshot, draft.snapshot_schema_version);
  if (!finalized.success) return NextResponse.json({ message: "Le snapshot du projet est absent ou incompatible. Reprenez la préparation et générez un nouveau projet." }, { status: 409 });
  const { preview, snapshot } = finalized;
  if (!preview.complete || !preview.checks.consistent) return NextResponse.json({ message: "Les contrôles du projet ne permettent pas sa finalisation." }, { status: 409 });
  const durableEnabled = isManagementReportDurableOperationsEnabled();
  const finalPdf = await generateManagementReportPdf(preview, {
    mode: "final",
    deterministicCreationDate: preview.report.updated_at,
  });
  const finalPath = managementReportStoragePath(ids.protectedPersonId, ids.reportId, "final");
  const finalName = managementReportDownloadName(preview.report.report_year, preview.person.first_name, preview.person.last_name, "final");
  return runManagementReportDocumentWrite(
    durableEnabled,
    async () => {
      await cleanRetiredReportDocuments(ids.reportId);
      const bytes = new Uint8Array(finalPdf);
      try {
        await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).upload(finalPath, bytes, { contentType: "application/pdf", upsert: false });
      } catch {
        // Storage may have committed the upload before a connection failure.
      }
      let objectId: string | null;
      try {
        objectId = await verifyUnpublishedReportPdf(ids.reportId, finalPath, bytes);
      } catch {
        objectId = null;
      }
      if (!objectId) return NextResponse.json({ message: "Le PDF définitif n’a pas pu être vérifié. Le PDF projet a été conservé." }, { status: 503 });
      let confirmed = false;
      try {
        const transition = await (supabase as unknown as PublishFinalRpc).rpc("publish_verified_management_report_final", {
          p_report_id: ids.reportId, p_storage_object_id: objectId, p_file_name: finalName,
          p_file_size: bytes.length, p_preview_snapshot: snapshot, p_snapshot_schema_version: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
        });
        confirmed = !transition.error;
      } catch {
        // An uncertain result must be reconciled in PostgreSQL before removal.
      }
      if (!confirmed) {
        const outcome = await resolveUncertainReportFinalization(ids.reportId, objectId);
        if (outcome !== "published") {
          return NextResponse.json({ message: outcome === "retired"
            ? "La finalisation a été refusée. Le PDF projet a été conservé."
            : "La finalisation n’a pas pu être confirmée. Vérifiez l’état du compte de gestion avant de réessayer." }, { status: 409 });
        }
      } else await cleanRetiredReportDocuments(ids.reportId);
      return NextResponse.json({ message: "Le compte de gestion a été finalisé." });
    },
    async () => {
      try {
        const bytes = new Uint8Array(finalPdf);
        const sourceDocumentRevision = `${draft.id}:${draft.created_at}:${draft.storage_path}`;
        await executeDurableManagementReportOperation({
          client: supabase as unknown as ReservationClient,
          personId: ids.protectedPersonId,
          reportId: ids.reportId,
          intent: "finalize",
          bytes,
          fileName: finalName,
          previewSnapshot: snapshot,
          snapshotSchemaVersion: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
          clientRequestId: createManagementReportRequestId({
            personId: ids.protectedPersonId,
            reportId: ids.reportId,
            intent: "finalize",
            clientRequestNonce: z.uuid().safeParse(request.headers.get("x-patrigest-request-id")).data ?? null,
            sourceDocumentRevision,
            previewSnapshot: snapshot,
            snapshotSchemaVersion: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
            fileName: finalName,
            bytes,
          }),
        });
        return NextResponse.json({ message: "Le compte de gestion a été finalisé." });
      } catch {
        return NextResponse.json({ message: "La finalisation durable a échoué. Aucun repli vers l’ancien parcours n’a été effectué." }, { status: 500 });
      }
    },
  );
}

export async function DELETE(request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  const context = await getManagementReportPreviewState(ids.protectedPersonId, ids.reportId);
  if (!context) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas reprendre cette préparation." }, { status: 403 });
  if (context.report.status !== "generated") return NextResponse.json({ message: "Seul un projet généré peut être repris." }, { status: 409 });
  const draft = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, "management_report_draft");
  if (!draft) return NextResponse.json({ message: "Le PDF projet est introuvable." }, { status: 409 });
  const durableEnabled = isManagementReportDurableOperationsEnabled();
  const { supabase } = await getAuthenticatedUser();
  return runManagementReportDocumentWrite(
    durableEnabled,
    async () => {
      try {
        const transition = await supabase.rpc("resume_management_report_preparation", { p_report_id: ids.reportId });
        if (transition.error) throw transition.error;
      } catch {
        await cleanRetiredReportDocuments(ids.reportId);
        return NextResponse.json({ message: "La reprise n’a pas pu être confirmée. Vérifiez l’état du compte de gestion avant de réessayer." }, { status: 409 });
      }
      await cleanRetiredReportDocuments(ids.reportId);
      return NextResponse.json({ message: "Le compte de gestion est de nouveau en préparation." });
    },
    async () => {
      try {
        const sourceDocumentRevision = `${draft.id}:${draft.created_at}:${draft.storage_path}`;
        await executeDurableManagementReportOperation({
          client: supabase as unknown as ReservationClient,
          personId: ids.protectedPersonId,
          reportId: ids.reportId,
          intent: "resume",
          bytes: null,
          fileName: null,
          previewSnapshot: draft.preview_snapshot,
          snapshotSchemaVersion: draft.snapshot_schema_version,
          clientRequestId: createManagementReportRequestId({
            personId: ids.protectedPersonId,
            reportId: ids.reportId,
            intent: "resume",
            clientRequestNonce: z.uuid().safeParse(request.headers.get("x-patrigest-request-id")).data ?? null,
            sourceDocumentRevision,
            previewSnapshot: draft.preview_snapshot,
            snapshotSchemaVersion: draft.snapshot_schema_version,
            fileName: null,
            bytes: null,
          }),
        });
        return NextResponse.json({ message: "Le compte de gestion est de nouveau en préparation." });
      } catch {
        return NextResponse.json({ message: "La reprise durable a échoué. Aucun repli vers l’ancien parcours n’a été effectué." }, { status: 500 });
      }
    },
  );
}

export async function GET(request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const context = await getManagementReportPreviewState(ids.protectedPersonId, ids.reportId);
  if (!context || !["generated", "finalized", "transmitted", "approved", "difficulty"].includes(context.report.status)) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const mode: ManagementReportPdfMode = context.report.status === "generated" ? "draft" : "final";
  const document = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, mode === "draft" ? "management_report_draft" : "management_report");
  if (!document) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const download = new URL(request.url).searchParams.get("download") === "1";
  return protectedStorageResponse({ request, bucket: MANAGEMENT_REPORT_BUCKET, storagePath: document.storage_path,
    contentType: "application/pdf",
    contentDisposition: managementReportContentDisposition(document.file_name, download) });
}
