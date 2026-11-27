import "server-only";

import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { BankStatement } from "@/types/database";
import { isBankStatementDurableOperationsEnabled } from "./bank-statement-durable-availability";
import { createBankStatementRequestId, type BankStatementReservationClient } from "./bank-statement-durable-reservation";
import { cleanRetiredBankStatementFiles, publishBankStatementFile } from "./bank-statement-file-transition";
import { bankStatementStoragePath } from "./helpers";
import type { BankStatementInput } from "./schemas";

type PreparedPdf = { file: File; bytes: Uint8Array };
type StatementContext = { personId: string; accountId: string; statementId: string };

export class BankStatementWriteError extends Error {
  constructor(message: string, public readonly status = 500) {
    super(message);
    this.name = "BankStatementWriteError";
  }
}

function rejectWrite(error: unknown) {
  const code = error && typeof error === "object" && "code" in error ? error.code : null;
  if (code === "23505") throw new BankStatementWriteError("Un relevé existe déjà à cette date.", 409);
  if (code === "42501") throw new BankStatementWriteError("Relevé introuvable ou accès refusé.", 403);
  if (code === "40001") throw new BankStatementWriteError("Le relevé a changé. Rechargez la page et réessayez.", 409);
  if (code === "55000") throw new BankStatementWriteError("Le document du relevé est figé ou son fichier n’a pas pu être vérifié.", 409);
  throw new BankStatementWriteError("Impossible d’enregistrer le relevé.");
}

function statementMetadata(metadata: BankStatementInput) {
  return {
    statement_start_date: metadata.statementStartDate,
    statement_end_date: metadata.statementEndDate,
    statement_balance: metadata.statementBalance,
    note: metadata.note,
  };
}

async function savePdf(input: StatementContext & { metadata: BankStatementInput; pdf: PreparedPdf; statement?: BankStatement }) {
  const { supabase } = await getAuthenticatedUser();
  const intent = !input.statement ? "create" : input.statement.original_file_name ? "replace" : "attach";
  const existingUpdatedAt = input.statement?.updated_at ?? null;
  try {
    await publishBankStatementFile({
      client: supabase,
      ...input,
      expectedUpdatedAt: existingUpdatedAt,
      requestId: createBankStatementRequestId({ ...input, intent, existingUpdatedAt, bytes: input.pdf.bytes }),
      bytes: input.pdf.bytes,
      fileName: input.pdf.file.name,
      metadata: {
        startDate: input.metadata.statementStartDate,
        endDate: input.metadata.statementEndDate,
        balance: input.metadata.statementBalance,
        note: input.metadata.note,
      },
    });
  } catch (error) {
    rejectWrite(error);
  }
}

export async function createBankStatement(input: StatementContext & { metadata: BankStatementInput; pdf: PreparedPdf | null }) {
  if (input.pdf) return savePdf({ ...input, pdf: input.pdf });
  const { supabase, userId } = await getAuthenticatedUser();
  const { error } = await supabase.from("bank_statements").insert({
    id: input.statementId,
    financial_account_id: input.accountId,
    ...statementMetadata(input.metadata),
    storage_path: bankStatementStoragePath(input.personId, input.accountId, input.statementId),
    original_file_name: null,
    mime_type: null,
    file_size: null,
    created_by: userId,
  });
  if (error) rejectWrite(error);
}

export async function updateBankStatement(input: Omit<StatementContext, "statementId"> & {
  statement: BankStatement; metadata: BankStatementInput; pdf: PreparedPdf | null;
}) {
  if (input.pdf) return savePdf({ ...input, statementId: input.statement.id, pdf: input.pdf });
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.from("bank_statements").update(statementMetadata(input.metadata))
    .eq("id", input.statement.id).eq("financial_account_id", input.accountId).select("id").maybeSingle();
  if (error) rejectWrite(error);
  if (!data) throw new BankStatementWriteError("Relevé introuvable ou accès refusé.", 403);
}

async function removeBankStatement(input: Omit<StatementContext, "statementId"> & { statement: BankStatement }, documentOnly: boolean) {
  const { supabase } = await getAuthenticatedUser();
  const client = supabase as unknown as BankStatementReservationClient;
  const rpc = documentOnly ? "detach_unreconciled_bank_statement_file" : "delete_unreconciled_bank_statement";
  const args = { p_person: input.personId, p_account: input.accountId, p_statement: input.statement.id };
  let result = await client.rpc(rpc, args).then(undefined, () => null);
  if (!result || result.error) result = await client.rpc(rpc, args);
  if (result.error) rejectWrite(result.error);
  await cleanRetiredBankStatementFiles(input.statement.id);
}

export async function deleteBankStatementDocument(input: Omit<StatementContext, "statementId"> & { statement: BankStatement }) {
  if (!isBankStatementDurableOperationsEnabled()) {
    throw new BankStatementWriteError("La suppression sécurisée du PDF du relevé n’est pas activée.", 405);
  }
  if (!input.statement.original_file_name) throw new BankStatementWriteError("Aucun PDF n’est associé à ce relevé.", 404);
  return removeBankStatement(input, true);
}

export async function deleteBankStatement(input: Omit<StatementContext, "statementId"> & { statement: BankStatement }) {
  if (isBankStatementDurableOperationsEnabled() && input.statement.original_file_name) {
    throw new BankStatementWriteError("Supprimez d’abord le PDF du relevé avant de supprimer le relevé bancaire.", 409);
  }
  return removeBankStatement(input, false);
}
