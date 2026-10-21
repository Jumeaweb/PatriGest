import { bankStatementOperation } from "@/domains/document-operations/domain-adapters";
import { createServerDocumentOperationEngine } from "@/domains/document-operations/server";
import type { BankStatementInput } from "./schemas";
import {
  reserveBankStatementOperation,
  type BankStatementOperationIntent,
  type BankStatementReservationClient,
} from "./bank-statement-durable-reservation";

export async function executeDurableBankStatementOperation(input: {
  client: BankStatementReservationClient;
  personId: string;
  accountId: string;
  statementId: string;
  intent: BankStatementOperationIntent;
  metadata: BankStatementInput;
  bytes: Uint8Array | null;
  fileName: string | null;
  fileSize: number | null;
  clientRequestId: string;
}) {
  const operationId = await reserveBankStatementOperation(input.client, input);
  const engine = await createServerDocumentOperationEngine();
  return engine.execute(bankStatementOperation(
    operationId,
    input.bytes ? { bytes: input.bytes, mimeType: "application/pdf" } : null,
    {
      statementStartDate: input.metadata.statementStartDate,
      statementEndDate: input.metadata.statementEndDate,
      statementBalance: input.metadata.statementBalance,
      note: input.metadata.note,
      fileName: input.fileName,
      mimeType: input.bytes ? "application/pdf" : null,
      fileSize: input.fileSize,
    },
  ));
}
