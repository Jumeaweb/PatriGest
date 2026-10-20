import { createHash } from "node:crypto";
import { z } from "zod";

export type TransactionProofOperationIntent = "create" | "replace" | "delete";

type RpcResult = { data: unknown; error: unknown | null };
type RpcInvoker = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<RpcResult>;

export type TransactionProofReservationClient = { rpc: RpcInvoker };

export function createTransactionProofRequestId(input: {
  personId: string;
  transactionId: string;
  intent: TransactionProofOperationIntent;
  existingDocumentId: string | null;
  existingUpdatedAt: string | null;
  bytes: Uint8Array | null;
}) {
  const digest = createHash("sha256");
  for (const value of [
    "patrigest:transaction-proof:v1",
    input.personId,
    input.transactionId,
    input.intent,
    input.existingDocumentId ?? "",
    input.existingUpdatedAt ?? "",
  ]) {
    digest.update(String(Buffer.byteLength(value)));
    digest.update(":");
    digest.update(value);
    digest.update(";");
  }
  if (input.bytes) digest.update(input.bytes);
  const bytes = digest.digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export async function reserveTransactionProofOperation(
  client: TransactionProofReservationClient,
  input: {
    personId: string;
    transactionId: string;
    intent: TransactionProofOperationIntent;
    clientRequestId: string;
  },
) {
  const { data, error } = await client.rpc(
    "begin_transaction_proof_document_operation",
    {
      p_protected_person_id: input.personId,
      p_transaction_id: input.transactionId,
      p_intent: input.intent,
      p_client_request_id: input.clientRequestId,
    },
  );
  if (error) throw new Error("La réservation du justificatif a échoué.");
  const operationId = z.uuid().safeParse(data);
  if (!operationId.success) throw new Error("La réservation du justificatif est invalide.");
  return operationId.data;
}
