import {
  managementReportFinalizationOperation,
  managementReportGenerationOperation,
  managementReportResumeOperation,
} from "@/domains/document-operations/domain-adapters";
import { createServerDocumentOperationEngine } from "@/domains/document-operations/server";
import type { Json } from "@/types/database";
import {
  reserveManagementReportOperation,
  type ManagementReportOperationIntent,
  type ManagementReportReservationClient,
} from "./management-report-durable-reservation";

type DurableManagementReportInput = {
  client: ManagementReportReservationClient;
  personId: string;
  reportId: string;
  intent: ManagementReportOperationIntent;
  bytes: Uint8Array | null;
  fileName: string | null;
  previewSnapshot: Json | null;
  snapshotSchemaVersion: number | null;
  clientRequestId: string;
};

export function managementReportOperationForIntent(
  operationId: string,
  input: Omit<DurableManagementReportInput, "client" | "personId" | "reportId" | "clientRequestId">,
) {
  const finalization = {
    fileName: input.fileName,
    mimeType: input.bytes ? "application/pdf" : null,
    fileSize: input.bytes?.byteLength ?? null,
    previewSnapshot: input.previewSnapshot,
    snapshotSchemaVersion: input.snapshotSchemaVersion,
  };
  if (input.intent === "generate") {
    if (!input.bytes) throw new Error("Le PDF projet est absent.");
    return managementReportGenerationOperation(
      operationId,
      { bytes: input.bytes, mimeType: "application/pdf" },
      finalization,
    );
  }
  if (input.intent === "finalize") {
    if (!input.bytes) throw new Error("Le PDF définitif est absent.");
    return managementReportFinalizationOperation(
      operationId,
      { bytes: input.bytes, mimeType: "application/pdf" },
      finalization,
    );
  }
  return managementReportResumeOperation(operationId, finalization);
}

export async function executeDurableManagementReportOperation(
  input: DurableManagementReportInput,
) {
  const operationId = await reserveManagementReportOperation(input.client, input);
  const engine = await createServerDocumentOperationEngine();
  const progress = await engine.execute(managementReportOperationForIntent(operationId, input));
  if (progress.state !== "completed") {
    throw new Error("L’opération documentaire n’a pas été finalisée.");
  }
  return progress;
}
