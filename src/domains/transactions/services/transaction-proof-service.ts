import { z } from "zod";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { isDateInClosedPeriod } from "../utils/transaction-utils";
import { getTransaction, getTransactionDocument } from "./transaction-service";
import { getProofWriteDenial } from "./transaction-proof-access";
import { buildProofFileName, type PreparedProofFile } from "./transaction-proof-file";
import { executeDurableTransactionProofOperation } from "./transaction-proof-durable";
import { createTransactionProofRequestId } from "./transaction-proof-durable-reservation";

export class ProofServiceError extends Error {
  constructor(message: string, public readonly status: number = 500) { super(message); }
}

export async function getExpenseProofContext(personId: string, transactionId: string) {
  if (!z.uuid().safeParse(personId).success || !z.uuid().safeParse(transactionId).success) return null;
  const [person, transaction] = await Promise.all([getProtectedPerson(personId), getTransaction(transactionId)]);
  if (!person || !transaction || transaction.transaction_type !== "expense" || transaction.transfer_id || transaction.account.protected_person_id !== personId || !transaction.proof_reference) return null;
  return { person, transaction };
}

export async function saveTransactionProof(personId: string, transactionId: string, file: PreparedProofFile, requestedClientRequestId?: string) {
  const context = await getExpenseProofContext(personId, transactionId);
  if (!context) throw new ProofServiceError("Dépense introuvable.", 404);
  const denial = getProofWriteDenial({ personId, transactionPersonId: context.transaction.account.protected_person_id, transactionType: context.transaction.transaction_type, transferId: context.transaction.transfer_id, proofReference: context.transaction.proof_reference, role: context.person.accessRole, closed: isDateInClosedPeriod(context.transaction.transaction_date, context.person.managementPeriods) });
  if (denial === "read_only") throw new ProofServiceError("Vous ne pouvez pas ajouter ce justificatif.", 403);
  if (denial === "closed") throw new ProofServiceError("Cette dépense appartient à un exercice clôturé.", 403);
  if (denial) throw new ProofServiceError("Dépense introuvable.", 404);
  const { supabase } = await getAuthenticatedUser();
  const existing = await getTransactionDocument(transactionId);
  const fileName = buildProofFileName(context.transaction.proof_reference!, context.transaction.label, file.extension);

  const intent = existing ? "replace" : "create";
  try {
    await executeDurableTransactionProofOperation({
      client: supabase,
      personId,
      transactionId,
      intent,
      file,
      fileName,
      clientRequestId: z.uuid().parse(requestedClientRequestId ?? createTransactionProofRequestId({
        personId,
        transactionId,
        intent,
        existingDocumentId: existing?.id ?? null,
        existingUpdatedAt: existing?.updated_at ?? null,
        bytes: file.bytes,
      })),
    });
  } catch {
    throw new ProofServiceError("Impossible d’enregistrer le justificatif. La dépense reste disponible.");
  }
}

export async function deleteTransactionProof(personId: string, transactionId: string) {
  void personId;
  void transactionId;
  throw new ProofServiceError("Le retrait sécurisé des anciennes versions n’est pas encore disponible.", 405);
}
