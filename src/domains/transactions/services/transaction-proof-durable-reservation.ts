import { createHash } from "node:crypto";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

export type TransactionProofOperationIntent = "create" | "replace";

export type TransactionProofReservationClient = SupabaseClient<Database>;

const reservationSchema = z.object({
  operationId: z.uuid(),
  operationRevision: z.coerce.number().int().positive(),
  state: z.enum(["reserved", "completed", "attention_required", "cancelled"]),
  intent: z.enum(["create", "replace"]),
  documentId: z.uuid(),
  versionId: z.uuid(),
  versionNumber: z.coerce.number().int().positive(),
  storagePath: z.string().min(1),
  transactionRevision: z.coerce.number().int().positive(),
  proofReference: z.string().min(1),
  storageObjectId: z.uuid().nullable().optional(),
  idempotent: z.boolean(),
});

export type TransactionProofReservation = z.infer<typeof reservationSchema>;

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
    "reserve_transaction_proof_version",
    {
      p_protected_person_id: input.personId,
      p_transaction_id: input.transactionId,
      p_intent: input.intent,
      p_client_request_id: input.clientRequestId,
    },
  );
  if (error) throw new Error("La réservation du justificatif a échoué.");
  const reservation = reservationSchema.safeParse(data);
  if (!reservation.success) throw new Error("La réservation du justificatif est invalide.");
  return reservation.data;
}
