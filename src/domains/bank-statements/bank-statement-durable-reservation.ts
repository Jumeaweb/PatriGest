import { createHash } from "node:crypto";
import { z } from "zod";
import type { BankStatementInput } from "./schemas";

export type BankStatementOperationIntent = "create" | "attach" | "replace" | "delete";

type RpcResult = { data: unknown; error: unknown | null };
type RpcInvoker = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<RpcResult>;

export type BankStatementReservationClient = { rpc: RpcInvoker };

export function createBankStatementRequestId(input: {
  personId: string;
  accountId: string;
  statementId: string;
  intent: BankStatementOperationIntent;
  existingUpdatedAt: string | null;
  metadata: BankStatementInput;
  bytes: Uint8Array | null;
}) {
  const digest = createHash("sha256");
  for (const value of [
    "patrigest:bank-statement:v1",
    input.personId,
    input.accountId,
    input.statementId,
    input.intent,
    input.existingUpdatedAt ?? "",
    input.metadata.statementStartDate ?? "",
    input.metadata.statementEndDate,
    input.metadata.statementBalance === null ? "" : String(input.metadata.statementBalance),
    input.metadata.note ?? "",
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

export async function reserveBankStatementOperation(
  client: BankStatementReservationClient,
  input: {
    personId: string;
    accountId: string;
    statementId: string;
    intent: BankStatementOperationIntent;
    clientRequestId: string;
  },
) {
  const { data, error } = await client.rpc(
    "begin_bank_statement_document_operation",
    {
      p_protected_person_id: input.personId,
      p_financial_account_id: input.accountId,
      p_statement_id: input.statementId,
      p_intent: input.intent,
      p_client_request_id: input.clientRequestId,
    },
  );
  if (error) throw new Error("La réservation du relevé bancaire a échoué.");
  const operationId = z.uuid().safeParse(data);
  if (!operationId.success) throw new Error("La réservation du relevé bancaire est invalide.");
  return operationId.data;
}
