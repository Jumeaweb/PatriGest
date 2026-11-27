import "server-only";

import { createHash } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";
import { MANAGEMENT_REPORT_BUCKET } from "./document-helpers";

type RetirementRpc = {
  rpc(name: "record_management_report_final_verification", args: {
    p_report_id: string; p_object_id: string; p_object_version: string; p_size: number; p_sha256: string;
  }): PromiseLike<{ data: boolean | null; error: unknown }>;
  rpc(name: "list_management_report_retired_files", args: { p_report_id: string }): PromiseLike<{
    data: { storage_path: string }[] | null;
    error: unknown;
  }>;
  rpc(name: "retire_unpublished_management_report_final" | "retire_unpublished_management_report_project", args: { p_report_id: string; p_object_id: string }): PromiseLike<{
    data: "published" | "retired" | "unknown" | null;
    error: unknown;
  }>;
};

export async function cleanRetiredReportDocuments(reportId: string) {
  try {
    const admin = createAdminClient();
    const result = await (admin as unknown as RetirementRpc).rpc("list_management_report_retired_files", { p_report_id: reportId });
    if (result.error) throw new Error("list");
    for (const item of result.data ?? []) {
      const removed = await admin.storage.from(MANAGEMENT_REPORT_BUCKET).remove([item.storage_path]);
      if (removed.error) throw new Error("remove");
    }
  } catch {
    console.error("MANAGEMENT_REPORT_RETIREMENT_PENDING", { reportId });
  }
}

// The caller derives path from the authorized report and checks the exact
// bytes. The candidate remains invisible under the normal Storage RLS.
export async function inspectUnpublishedReportPdf(path: string, expected: Uint8Array, admin = createAdminClient()) {
  const storage = admin.storage.from(MANAGEMENT_REPORT_BUCKET);
  const before = await storage.info(path);
  if (before.error || !before.data?.id) return null;
  const downloaded = await storage.download(path);
  if (downloaded.error || !downloaded.data || downloaded.data.size !== expected.length) return null;
  const actualHash = createHash("sha256").update(Buffer.from(await downloaded.data.arrayBuffer())).digest("hex");
  if (actualHash !== createHash("sha256").update(expected).digest("hex")) return null;
  const after = await storage.info(path);
  if (after.error || after.data?.id !== before.data.id || !after.data.version || after.data.version !== before.data.version) return null;
  return { id: after.data.id, version: after.data.version, sha256: actualHash };
}

export async function verifyUnpublishedReportPdf(reportId: string, path: string, expected: Uint8Array) {
  const admin = createAdminClient();
  const object = await inspectUnpublishedReportPdf(path, expected, admin);
  if (!object) return null;
  const proof = await (admin as unknown as RetirementRpc).rpc("record_management_report_final_verification", {
    p_report_id: reportId, p_object_id: object.id, p_object_version: object.version,
    p_size: expected.length, p_sha256: object.sha256,
  });
  return !proof.error && proof.data === true ? object.id : null;
}

export async function resolveUncertainReportFinalization(reportId: string, storageObjectId: string, mode: "final" | "project" = "final") {
  try {
    const admin = createAdminClient() as unknown as RetirementRpc;
    const rpc = mode === "project" ? "retire_unpublished_management_report_project" : "retire_unpublished_management_report_final";
    const result = await admin.rpc(rpc, {
      p_report_id: reportId,
      p_object_id: storageObjectId,
    });
    if (result.error) return "unknown";
    if (result.data === "retired" || result.data === "published") await cleanRetiredReportDocuments(reportId);
    return result.data ?? "unknown";
  } catch {
    return "unknown";
  }
}
