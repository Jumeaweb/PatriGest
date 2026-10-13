import { NextResponse } from "next/server";
import { z } from "zod";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getManagementReportDocument, getManagementReportPreviewState, getManagementReportSnapshot } from "@/domains/management-reports/services";
import { buildManagementReportPreview } from "@/domains/management-reports/preview-model";
import { generateManagementReportPdf } from "@/domains/management-reports/pdf";
import { MANAGEMENT_REPORT_BUCKET, managementReportContentDisposition, managementReportDownloadName, managementReportStoragePath, type ManagementReportPdfMode } from "@/domains/management-reports/document-helpers";
import { MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION, parseManagementReportSnapshot, toJsonValue } from "@/domains/management-reports/snapshot";

export const runtime = "nodejs";
type Params = { params: Promise<{ protectedPersonId: string; reportId: string }> };
type Supabase = Awaited<ReturnType<typeof getAuthenticatedUser>>["supabase"];

async function identifiers(params: Params["params"]) { const value = await params; return [value.protectedPersonId, value.reportId].every((id) => z.uuid().safeParse(id).success) ? value : null; }
async function restoreFile(supabase: Supabase, path: string, bytes: ArrayBuffer) { return supabase.storage.from(MANAGEMENT_REPORT_BUCKET).upload(path, new Uint8Array(bytes), { contentType: "application/pdf", upsert: false }); }
async function livePreview(personId: string, reportId: string, targetStatus: "generated" | "finalized") {
  const snapshot = await getManagementReportSnapshot(personId, reportId);
  if (!snapshot) return null;
  const parsed = parseManagementReportSnapshot(toJsonValue({ ...buildManagementReportPreview(snapshot), report: { ...snapshot.report, status: targetStatus } }));
  return parsed.success ? { preview: parsed.data, accessRole: snapshot.person.accessRole, currentStatus: snapshot.report.status, refreshRequiredAt: snapshot.report.refresh_required_at } : null;
}

export async function POST(_request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  try {
    const generated = await livePreview(ids.protectedPersonId, ids.reportId, "generated");
    if (!generated) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
    const { preview, accessRole, currentStatus } = generated;
    if (accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas générer ce projet." }, { status: 403 });
    if (currentStatus !== "ready") return NextResponse.json({ message: "Le compte de gestion doit être prêt avant la génération du projet." }, { status: 409 });
    if (!preview.complete) return NextResponse.json({ message: "Le compte de gestion n’est plus complet. Vérifiez les informations à compléter." }, { status: 409 });
    if (!preview.checks.consistent) return NextResponse.json({ message: "Les contrôles de cohérence du compte de gestion ont échoué." }, { status: 409 });
    const pdf = await generateManagementReportPdf(preview, { mode: "draft" });
    const storagePath = managementReportStoragePath(ids.protectedPersonId, ids.reportId, "draft");
    const fileName = managementReportDownloadName(preview.report.report_year, preview.person.first_name, preview.person.last_name, "draft");
    const { supabase } = await getAuthenticatedUser();
    const upload = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).upload(storagePath, new Uint8Array(pdf), { contentType: "application/pdf", upsert: false });
    if (upload.error) return NextResponse.json({ message: "Impossible d’archiver le PDF projet." }, { status: 500 });
    const transition = await supabase.rpc("finalize_management_report_draft_generation", { p_report_id: ids.reportId, p_storage_path: storagePath, p_file_name: fileName, p_mime_type: "application/pdf", p_file_size: pdf.length, p_preview_snapshot: toJsonValue(preview), p_snapshot_schema_version: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION });
    if (transition.error) {
      const compensation = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).remove([storagePath]);
      return NextResponse.json({ message: compensation.error ? "La génération a échoué et le fichier temporaire n’a pas pu être nettoyé. Contactez l’administrateur." : "La génération du projet n’a pas pu être finalisée. Aucun document n’a été conservé." }, { status: 500 });
    }
    return NextResponse.json({ message: "Le projet du compte de gestion a été généré." });
  } catch {
    return NextResponse.json({ message: "Impossible de générer le projet du compte de gestion." }, { status: 500 });
  }
}

export async function PATCH(_request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  const finalized = await livePreview(ids.protectedPersonId, ids.reportId, "finalized");
  if (!finalized) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  const { preview, accessRole, currentStatus, refreshRequiredAt } = finalized;
  if (accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas finaliser ce compte de gestion." }, { status: 403 });
  if (currentStatus !== "generated") return NextResponse.json({ message: "Un projet doit être généré avant la finalisation." }, { status: 409 });
  if (refreshRequiredAt) return NextResponse.json({ message: "Le compte de gestion doit être actualisé et son projet régénéré avant finalisation." }, { status: 409 });
  if (!preview.complete || !preview.checks.consistent) return NextResponse.json({ message: "Les contrôles du compte de gestion ne permettent plus sa finalisation." }, { status: 409 });
  const draft = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, "management_report_draft");
  if (!draft) return NextResponse.json({ message: "Le PDF projet est introuvable." }, { status: 409 });
  const { supabase } = await getAuthenticatedUser();
  const storedDraft = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).download(draft.storage_path);
  if (storedDraft.error || !storedDraft.data) return NextResponse.json({ message: "Impossible de sécuriser le PDF projet avant finalisation." }, { status: 500 });
  const draftBytes = await storedDraft.data.arrayBuffer();
  const finalPdf = await generateManagementReportPdf(preview, { mode: "final" });
  const finalPath = managementReportStoragePath(ids.protectedPersonId, ids.reportId, "final");
  const finalName = managementReportDownloadName(preview.report.report_year, preview.person.first_name, preview.person.last_name, "final");
  const finalUpload = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).upload(finalPath, new Uint8Array(finalPdf), { contentType: "application/pdf", upsert: false });
  if (finalUpload.error) return NextResponse.json({ message: "Impossible d’archiver le PDF final." }, { status: 500 });
  const draftRemoval = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).remove([draft.storage_path]);
  if (draftRemoval.error) {
    const finalCleanup = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).remove([finalPath]);
    return NextResponse.json({ message: finalCleanup.error ? "La finalisation a été annulée, mais le fichier final temporaire n’a pas pu être nettoyé. Contactez l’administrateur." : "Le PDF projet n’a pas pu être remplacé. La finalisation a été annulée." }, { status: 500 });
  }
  const transition = await supabase.rpc("finalize_management_report", { p_report_id: ids.reportId, p_storage_path: finalPath, p_file_name: finalName, p_mime_type: "application/pdf", p_file_size: finalPdf.length, p_preview_snapshot: toJsonValue(preview), p_snapshot_schema_version: MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION });
  if (transition.error) {
    const [finalCleanup, draftRestore] = await Promise.all([supabase.storage.from(MANAGEMENT_REPORT_BUCKET).remove([finalPath]), restoreFile(supabase, draft.storage_path, draftBytes)]);
    return NextResponse.json({ message: finalCleanup.error || draftRestore.error ? "La finalisation a échoué et la restauration des fichiers nécessite une intervention." : "La finalisation a échoué. Le PDF projet a été restauré." }, { status: 500 });
  }
  return NextResponse.json({ message: "Le compte de gestion a été finalisé." });
}

export async function DELETE(_request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  const context = await getManagementReportPreviewState(ids.protectedPersonId, ids.reportId);
  if (!context) return NextResponse.json({ message: "Compte de gestion introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") return NextResponse.json({ message: "Vous ne pouvez pas reprendre cette préparation." }, { status: 403 });
  if (context.report.status !== "generated") return NextResponse.json({ message: "Seul un projet généré peut être repris." }, { status: 409 });
  const draft = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, "management_report_draft");
  if (!draft) return NextResponse.json({ message: "Le PDF projet est introuvable." }, { status: 409 });
  const { supabase } = await getAuthenticatedUser();
  const stored = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).download(draft.storage_path);
  if (stored.error || !stored.data) return NextResponse.json({ message: "Impossible de sécuriser le PDF projet avant sa suppression." }, { status: 500 });
  const backup = await stored.data.arrayBuffer();
  const removal = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).remove([draft.storage_path]);
  if (removal.error) return NextResponse.json({ message: "Impossible de supprimer le PDF projet." }, { status: 500 });
  const transition = await supabase.rpc("resume_management_report_preparation", { p_report_id: ids.reportId });
  if (transition.error) { const restored = await restoreFile(supabase, draft.storage_path, backup); return NextResponse.json({ message: restored.error ? "La reprise a échoué et le PDF projet n’a pas pu être restauré." : "La reprise a échoué. Le PDF projet a été restauré." }, { status: 500 }); }
  return NextResponse.json({ message: "Le compte de gestion est de nouveau en préparation." });
}

export async function GET(request: Request, { params }: Params) {
  const ids = await identifiers(params);
  if (!ids) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const context = await getManagementReportPreviewState(ids.protectedPersonId, ids.reportId);
  if (!context || !["generated", "finalized", "transmitted", "approved", "difficulty"].includes(context.report.status)) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const mode: ManagementReportPdfMode = context.report.status === "generated" ? "draft" : "final";
  const document = await getManagementReportDocument(ids.protectedPersonId, ids.reportId, mode === "draft" ? "management_report_draft" : "management_report");
  if (!document) return NextResponse.json({ message: "Document introuvable." }, { status: 404 });
  const { supabase } = await getAuthenticatedUser();
  const stored = await supabase.storage.from(MANAGEMENT_REPORT_BUCKET).download(document.storage_path);
  if (stored.error || !stored.data) return NextResponse.json({ message: "Impossible de lire le document." }, { status: 500 });
  const download = new URL(request.url).searchParams.get("download") === "1";
  return new Response(await stored.data.arrayBuffer(), { headers: { "Content-Type": "application/pdf", "Content-Disposition": managementReportContentDisposition(document.file_name, download), "Content-Length": String(document.file_size), "Cache-Control": "private, no-store" } });
}
