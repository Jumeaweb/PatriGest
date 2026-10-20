import { transactionProofOperation } from "@/domains/document-operations/domain-adapters";
import { createServerDocumentOperationEngine } from "@/domains/document-operations/server";
import type { PreparedProofFile } from "./transaction-proof-file";
import {
  reserveTransactionProofOperation,
  type TransactionProofOperationIntent,
  type TransactionProofReservationClient,
} from "./transaction-proof-durable-reservation";

export async function executeDurableTransactionProofOperation(input: {
  client: TransactionProofReservationClient;
  personId: string;
  transactionId: string;
  intent: TransactionProofOperationIntent;
  file: PreparedProofFile | null;
  fileName: string | null;
  clientRequestId: string;
}) {
  const operationId = await reserveTransactionProofOperation(input.client, input);
  const engine = await createServerDocumentOperationEngine();
  return engine.execute(transactionProofOperation(
    operationId,
    input.file ? { bytes: input.file.bytes, mimeType: input.file.mimeType } : null,
    {
      fileName: input.fileName,
      mimeType: input.file?.mimeType ?? null,
      fileSize: input.file?.size ?? null,
    },
  ));
}
