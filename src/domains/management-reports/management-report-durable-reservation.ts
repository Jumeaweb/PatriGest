import { createHash } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/types/database";

export type ManagementReportOperationIntent = "generate" | "finalize" | "resume";

type RpcResult = { data: unknown; error: unknown | null };
type RpcInvoker = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<RpcResult>;

export type ManagementReportReservationClient = { rpc: RpcInvoker };

function canonicalJson(value: Json): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => (
    `${JSON.stringify(key)}:${canonicalJson(value[key] ?? null)}`
  )).join(",")}}`;
}

function digestPart(digest: ReturnType<typeof createHash>, value: string) {
  digest.update(String(Buffer.byteLength(value)));
  digest.update(":");
  digest.update(value);
  digest.update(";");
}

export function createManagementReportRequestId(input: {
  personId: string;
  reportId: string;
  intent: ManagementReportOperationIntent;
  clientRequestNonce: string | null;
  sourceDocumentRevision: string | null;
  previewSnapshot: Json | null;
  snapshotSchemaVersion: number | null;
  fileName: string | null;
  bytes: Uint8Array | null;
}) {
  const digest = createHash("sha256");
  for (const value of [
    "patrigest:management-report:v1",
    input.personId,
    input.reportId,
    input.intent,
    input.clientRequestNonce ?? "",
    input.sourceDocumentRevision ?? "",
    input.previewSnapshot === null ? "" : canonicalJson(input.previewSnapshot),
    input.snapshotSchemaVersion === null ? "" : String(input.snapshotSchemaVersion),
    input.fileName ?? "",
  ]) {
    digestPart(digest, value);
  }
  if (input.bytes) digest.update(input.bytes);
  const bytes = digest.digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export async function reserveManagementReportOperation(
  client: ManagementReportReservationClient,
  input: {
    personId: string;
    reportId: string;
    intent: ManagementReportOperationIntent;
    clientRequestId: string;
  },
) {
  const { data, error } = await client.rpc(
    "begin_management_report_document_operation",
    {
      p_protected_person_id: input.personId,
      p_report_id: input.reportId,
      p_intent: input.intent,
      p_client_request_id: input.clientRequestId,
    },
  );
  if (error) throw new Error("La réservation du document du compte de gestion a échoué.");
  const operationId = z.uuid().safeParse(data);
  if (!operationId.success) {
    throw new Error("La réservation du document du compte de gestion est invalide.");
  }
  return operationId.data;
}
