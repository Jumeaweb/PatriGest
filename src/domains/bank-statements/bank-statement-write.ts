import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { BankStatement, Database } from "@/types/database";
import { executeDurableBankStatementOperation } from "./bank-statement-durable";
import {
  isBankStatementDurableOperationsEnabled,
  runBankStatementDocumentWrite,
} from "./bank-statement-durable-availability";
import { createBankStatementRequestId } from "./bank-statement-durable-reservation";
import { bankStatementStoragePath } from "./helpers";
import type { BankStatementInput } from "./schemas";

type AuthenticatedClient = SupabaseClient<Database>;
type PreparedPdf = { file: File; bytes: Uint8Array };

export class BankStatementWriteError extends Error {
  constructor(message: string, public readonly status = 500) {
    super(message);
    this.name = "BankStatementWriteError";
  }
}

function documentMetadata(statement: BankStatement) {
  return statement.original_file_name !== null
    && statement.mime_type !== null
    && statement.file_size !== null;
}

function currentMetadata(statement: BankStatement): BankStatementInput {
  return {
    statementStartDate: statement.statement_start_date,
    statementEndDate: statement.statement_end_date,
    statementBalance: statement.statement_balance,
    note: statement.note,
  };
}

function duplicateOrGeneric(error: { code?: string } | null) {
  if (error?.code === "23505") {
    throw new BankStatementWriteError("Un relevé existe déjà à cette date.", 409);
  }
  throw new BankStatementWriteError("Impossible d’enregistrer le relevé.");
}

export async function createBankStatement(input: {
  personId: string;
  accountId: string;
  statementId: string;
  metadata: BankStatementInput;
  pdf: PreparedPdf | null;
}) {
  const { supabase, userId } = await getAuthenticatedUser();
  const storagePath = bankStatementStoragePath(
    input.personId,
    input.accountId,
    input.statementId,
  );

  if (!input.pdf) {
    const { error } = await supabase.from("bank_statements").insert({
      id: input.statementId,
      financial_account_id: input.accountId,
      statement_start_date: input.metadata.statementStartDate,
      statement_end_date: input.metadata.statementEndDate,
      statement_balance: input.metadata.statementBalance,
      storage_path: storagePath,
      original_file_name: null,
      mime_type: null,
      file_size: null,
      note: input.metadata.note,
      created_by: userId,
    });
    if (error) duplicateOrGeneric(error);
    return;
  }

  await runBankStatementDocumentWrite(
    isBankStatementDurableOperationsEnabled(),
    async () => createBankStatementHistorically({
      ...input,
      pdf: input.pdf!,
      supabase,
      userId,
      storagePath,
    }),
    async () => {
      try {
        await executeDurableBankStatementOperation({
          client: supabase as unknown as Parameters<typeof executeDurableBankStatementOperation>[0]["client"],
          personId: input.personId,
          accountId: input.accountId,
          statementId: input.statementId,
          intent: "create",
          metadata: input.metadata,
          bytes: input.pdf!.bytes,
          fileName: input.pdf!.file.name,
          fileSize: input.pdf!.file.size,
          clientRequestId: createBankStatementRequestId({
            personId: input.personId,
            accountId: input.accountId,
            statementId: input.statementId,
            intent: "create",
            existingUpdatedAt: null,
            metadata: input.metadata,
            bytes: input.pdf!.bytes,
          }),
        });
      } catch {
        throw new BankStatementWriteError(
          "Impossible d’enregistrer le relevé. Aucune reprise automatique par l’ancien parcours n’a été effectuée.",
        );
      }
    },
  );
}

async function createBankStatementHistorically(input: {
  personId: string;
  accountId: string;
  statementId: string;
  metadata: BankStatementInput;
  pdf: PreparedPdf;
  supabase: AuthenticatedClient;
  userId: string;
  storagePath: string;
}) {
  const { error } = await input.supabase.from("bank_statements").insert({
    id: input.statementId,
    financial_account_id: input.accountId,
    statement_start_date: input.metadata.statementStartDate,
    statement_end_date: input.metadata.statementEndDate,
    statement_balance: input.metadata.statementBalance,
    storage_path: input.storagePath,
    original_file_name: input.pdf.file.name,
    mime_type: "application/pdf",
    file_size: input.pdf.file.size,
    note: input.metadata.note,
    created_by: input.userId,
  });
  if (error) duplicateOrGeneric(error);

  const upload = await input.supabase.storage.from("bank-statements").upload(
    input.storagePath,
    input.pdf.bytes,
    { contentType: "application/pdf", upsert: false },
  );
  if (!upload.error) return;

  const cleanup = await input.supabase.from("bank_statements").delete().eq("id", input.statementId);
  throw new BankStatementWriteError(
    cleanup.error
      ? "Impossible d’envoyer le relevé et d’annuler sa création."
      : "Impossible d’envoyer le relevé.",
  );
}

export async function updateBankStatement(input: {
  personId: string;
  accountId: string;
  statement: BankStatement;
  metadata: BankStatementInput;
  pdf: PreparedPdf | null;
}) {
  const { supabase } = await getAuthenticatedUser();
  if (!input.pdf) {
    const { error } = await supabase.from("bank_statements").update({
      statement_start_date: input.metadata.statementStartDate,
      statement_end_date: input.metadata.statementEndDate,
      statement_balance: input.metadata.statementBalance,
      note: input.metadata.note,
    }).eq("id", input.statement.id).eq("financial_account_id", input.accountId);
    if (error) duplicateOrGeneric(error);
    return;
  }

  await runBankStatementDocumentWrite(
    isBankStatementDurableOperationsEnabled(),
    async () => updateBankStatementHistorically({ ...input, pdf: input.pdf!, supabase }),
    async () => {
      const intent = documentMetadata(input.statement) ? "replace" : "attach";
      try {
        await executeDurableBankStatementOperation({
          client: supabase as unknown as Parameters<typeof executeDurableBankStatementOperation>[0]["client"],
          personId: input.personId,
          accountId: input.accountId,
          statementId: input.statement.id,
          intent,
          metadata: input.metadata,
          bytes: input.pdf!.bytes,
          fileName: input.pdf!.file.name,
          fileSize: input.pdf!.file.size,
          clientRequestId: createBankStatementRequestId({
            personId: input.personId,
            accountId: input.accountId,
            statementId: input.statement.id,
            intent,
            existingUpdatedAt: input.statement.updated_at,
            metadata: input.metadata,
            bytes: input.pdf!.bytes,
          }),
        });
      } catch {
        throw new BankStatementWriteError(
          "Impossible d’enregistrer le PDF du relevé. Aucune reprise automatique par l’ancien parcours n’a été effectuée.",
        );
      }
    },
  );
}

async function updateBankStatementHistorically(input: {
  accountId: string;
  statement: BankStatement;
  metadata: BankStatementInput;
  pdf: PreparedPdf;
  supabase: AuthenticatedClient;
}) {
  let previous: Blob | null = null;
  if (documentMetadata(input.statement)) {
    const old = await input.supabase.storage.from("bank-statements").download(
      input.statement.storage_path,
    );
    if (old.error || !old.data) {
      throw new BankStatementWriteError("Impossible de préparer le remplacement du relevé.");
    }
    previous = old.data;
  }

  const upload = await input.supabase.storage.from("bank-statements").upload(
    input.statement.storage_path,
    input.pdf.bytes,
    { contentType: "application/pdf", upsert: previous !== null },
  );
  if (upload.error) throw new BankStatementWriteError("Impossible de remplacer le fichier.");

  const { error } = await input.supabase.from("bank_statements").update({
    statement_start_date: input.metadata.statementStartDate,
    statement_end_date: input.metadata.statementEndDate,
    statement_balance: input.metadata.statementBalance,
    note: input.metadata.note,
    original_file_name: input.pdf.file.name,
    mime_type: "application/pdf",
    file_size: input.pdf.file.size,
  }).eq("id", input.statement.id).eq("financial_account_id", input.accountId);
  if (!error) return;

  if (previous) {
    await input.supabase.storage.from("bank-statements").upload(
      input.statement.storage_path,
      previous,
      { contentType: input.statement.mime_type ?? "application/pdf", upsert: true },
    );
  } else {
    await input.supabase.storage.from("bank-statements").remove([input.statement.storage_path]);
  }
  duplicateOrGeneric(error);
}

export async function deleteBankStatementDocument(input: {
  personId: string;
  accountId: string;
  statement: BankStatement;
}) {
  if (!isBankStatementDurableOperationsEnabled()) {
    throw new BankStatementWriteError(
      "La suppression sécurisée du PDF du relevé n’est pas activée.",
      405,
    );
  }
  if (!documentMetadata(input.statement)) {
    throw new BankStatementWriteError("Aucun PDF n’est associé à ce relevé.", 404);
  }

  const { supabase } = await getAuthenticatedUser();
  const metadata = currentMetadata(input.statement);
  try {
    await executeDurableBankStatementOperation({
      client: supabase as unknown as Parameters<typeof executeDurableBankStatementOperation>[0]["client"],
      personId: input.personId,
      accountId: input.accountId,
      statementId: input.statement.id,
      intent: "delete",
      metadata,
      bytes: null,
      fileName: null,
      fileSize: null,
      clientRequestId: createBankStatementRequestId({
        personId: input.personId,
        accountId: input.accountId,
        statementId: input.statement.id,
        intent: "delete",
        existingUpdatedAt: input.statement.updated_at,
        metadata,
        bytes: null,
      }),
    });
  } catch {
    throw new BankStatementWriteError("Impossible de supprimer le PDF du relevé.");
  }
}

export async function deleteBankStatement(input: {
  accountId: string;
  statement: BankStatement;
}) {
  const durableEnabled = isBankStatementDurableOperationsEnabled();
  if (durableEnabled && documentMetadata(input.statement)) {
    throw new BankStatementWriteError(
      "Supprimez d’abord le PDF du relevé avant de supprimer le relevé bancaire.",
      409,
    );
  }

  const { supabase } = await getAuthenticatedUser();
  let backup: Blob | null = null;
  if (!durableEnabled && documentMetadata(input.statement)) {
    const downloaded = await supabase.storage.from("bank-statements").download(
      input.statement.storage_path,
    );
    if (downloaded.error || !downloaded.data) {
      throw new BankStatementWriteError("Impossible de préparer la suppression du relevé.");
    }
    backup = downloaded.data;
    const removed = await supabase.storage.from("bank-statements").remove([
      input.statement.storage_path,
    ]);
    if (removed.error) {
      throw new BankStatementWriteError("Impossible de supprimer le fichier du relevé.");
    }
  }

  const { error } = await supabase.from("bank_statements").delete()
    .eq("id", input.statement.id)
    .eq("financial_account_id", input.accountId);
  if (!error) return;

  if (backup) {
    await supabase.storage.from("bank-statements").upload(
      input.statement.storage_path,
      backup,
      { contentType: input.statement.mime_type ?? "application/pdf", upsert: true },
    );
  }
  throw new BankStatementWriteError("Impossible de supprimer le relevé.");
}
