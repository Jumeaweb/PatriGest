import { createHash } from "node:crypto";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import type { PreparedProofFile } from "./transaction-proof-file";
import {
  reserveTransactionProofOperation,
  type TransactionProofOperationIntent,
} from "./transaction-proof-durable-reservation";

const finalizationSchema = z.object({
  operationId: z.uuid(),
  state: z.literal("completed"),
  revision: z.coerce.number().int().positive(),
  documentId: z.uuid(),
  versionId: z.uuid(),
  storageObjectId: z.uuid(),
  storageObjectVersion: z.string().min(1),
  idempotent: z.boolean(),
});

async function finalizeTransactionProof(
  client: SupabaseClient<Database>,
  input: {
    operationId: string;
    operationRevision: number;
    file: PreparedProofFile;
    fileName: string;
    sha256: string;
    storageObjectId: string;
  },
) {
  const args = {
    p_operation_id: input.operationId,
    p_expected_operation_revision: input.operationRevision,
    p_file_name: input.fileName,
    p_mime_type: input.file.mimeType,
    p_file_size: input.file.size,
    p_sha256: input.sha256,
    p_storage_object_id: input.storageObjectId,
  };
  let response = await client.rpc("finalize_transaction_proof_version", args);
  if (response.error) response = await client.rpc("finalize_transaction_proof_version", args);
  if (response.error) throw new Error("La finalisation du justificatif a échoué.");
  const parsed = finalizationSchema.safeParse(response.data);
  if (!parsed.success) throw new Error("La finalisation du justificatif est invalide.");
  return parsed.data;
}

export async function executeDurableTransactionProofOperation(input: {
  client: SupabaseClient<Database>;
  personId: string;
  transactionId: string;
  intent: TransactionProofOperationIntent;
  file: PreparedProofFile;
  fileName: string;
  clientRequestId: string;
}) {
  let reservation = await reserveTransactionProofOperation(input.client, input);
  const sha256 = createHash("sha256").update(input.file.bytes).digest("hex");
  const upload = await input.client.storage.from("transaction-proofs").upload(
    reservation.storagePath,
    input.file.bytes,
    { contentType: input.file.mimeType, metadata: { sha256 }, upsert: false },
  );
  let storageObjectId = upload.data?.id ?? null;
  if (upload.error || !storageObjectId) {
    reservation = await reserveTransactionProofOperation(input.client, input);
    storageObjectId = reservation.storageObjectId ?? null;
  }
  if (!storageObjectId) throw new Error("Le résultat du téléversement du justificatif est indéterminé.");
  return finalizeTransactionProof(input.client, {
    operationId: reservation.operationId,
    operationRevision: reservation.operationRevision,
    file: input.file,
    fileName: input.fileName,
    sha256,
    storageObjectId,
  });
}
