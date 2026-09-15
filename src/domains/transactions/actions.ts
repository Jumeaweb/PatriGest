"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { transferSchema } from "@/domains/transfers/schemas/transfer-schema";
import { createTransfer, deleteTransfer } from "@/domains/transfers/services/transfer-service";
import { isClosedPeriodError } from "./errors";
import { transactionSchema } from "./schemas/transaction-schema";
import { createTransaction, deleteTransaction, updateTransaction } from "./services/transaction-service";
import { ClassificationPrecisionRequiredError } from "./services/transaction-classification";
import type { TransactionActionState } from "./state";
import { getSafeTransactionReturnTo } from "./return-to";

const idsValid = (...ids: string[]) => ids.every((id) => z.uuid().safeParse(id).success);
const txValues = (formData: FormData) => ({ financialAccountId: formData.get("financialAccountId"), transactionDate: formData.get("transactionDate"), transactionType: formData.get("transactionType"), label: formData.get("label"), amount: formData.get("amount"), categoryId: formData.get("categoryId"), classificationPrecision: formData.get("classificationPrecision"), proofReference: formData.get("proofReference"), comment: formData.get("comment") });
const transferValues = (formData: FormData) => ({ sourceAccountId: formData.get("sourceAccountId"), destinationAccountId: formData.get("destinationAccountId"), transferDate: formData.get("transferDate"), amount: formData.get("amount"), label: formData.get("label"), comment: formData.get("comment") });
function refresh(personId: string) { revalidatePath(`/dossiers/${personId}`); revalidatePath(`/dossiers/${personId}/operations`); revalidatePath(`/dossiers/${personId}/comptes`); }

export async function createTransactionAction(personId: string, _state: TransactionActionState, formData: FormData): Promise<TransactionActionState> {
  if (!idsValid(personId)) return { status: "error", message: "Dossier invalide." };
  const parsed = transactionSchema.safeParse(txValues(formData));
  if (!parsed.success) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: parsed.error.flatten().fieldErrors };
  try { await createTransaction(personId, parsed.data); }
  catch (error) { if (error instanceof ClassificationPrecisionRequiredError) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: { classificationPrecision: [error.message] } }; return { status: "error", message: isClosedPeriodError(error) ? "Impossible d’ajouter une opération dans un exercice clôturé." : error instanceof Error ? error.message : "Impossible d’enregistrer l’opération." }; }
  refresh(personId);
  return { status: "success", message: "L’opération a été créée." };
}

export async function updateTransactionAction(personId: string, transactionId: string, returnTo: string, _state: TransactionActionState, formData: FormData): Promise<TransactionActionState> {
  if (!idsValid(personId, transactionId)) return { status: "error", message: "Opération invalide." };
  const parsed = transactionSchema.safeParse(txValues(formData));
  if (!parsed.success) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: parsed.error.flatten().fieldErrors };
  try { await updateTransaction(transactionId, personId, parsed.data); }
  catch (error) { if (error instanceof ClassificationPrecisionRequiredError) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: { classificationPrecision: [error.message] } }; return { status: "error", message: isClosedPeriodError(error) ? "Cette opération appartient à un exercice clôturé et ne peut plus être modifiée." : error instanceof Error ? error.message : "Impossible de modifier l’opération." }; }
  refresh(personId);
  redirect(getSafeTransactionReturnTo(personId, returnTo));
}

export async function createTransferAction(personId: string, returnHref: string, _state: TransactionActionState, formData: FormData): Promise<TransactionActionState> {
  if (!idsValid(personId)) return { status: "error", message: "Dossier invalide." };
  const parsed = transferSchema.safeParse(transferValues(formData));
  if (!parsed.success) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: parsed.error.flatten().fieldErrors };
  try { await createTransfer(personId, parsed.data); }
  catch (error) { return { status: "error", message: isClosedPeriodError(error) ? "Impossible d’ajouter un virement dans un exercice clôturé." : "Impossible de créer le virement. Vérifiez les comptes et la date." }; }
  refresh(personId);
  redirect(getSafeTransactionReturnTo(personId, returnHref));
}

export async function deleteTransactionAction(personId: string, id: string, returnHref: string, _state: TransactionActionState, _formData: FormData): Promise<TransactionActionState> {
  void _state;
  void _formData;
  if (!idsValid(personId, id)) return { status: "error", message: "Opération invalide." };
  try { await deleteTransaction(id, personId); }
  catch (error) { return { status: "error", message: isClosedPeriodError(error) ? "Cette opération appartient à un exercice clôturé et ne peut plus être supprimée." : "Impossible de supprimer l’opération." }; }
  refresh(personId);
  redirect(getSafeTransactionReturnTo(personId, returnHref));
}

export async function deleteTransferAction(personId: string, id: string, returnHref: string, _state: TransactionActionState, _formData: FormData): Promise<TransactionActionState> {
  void _state;
  void _formData;
  if (!idsValid(personId, id)) return { status: "error", message: "Virement invalide." };
  try { await deleteTransfer(id); }
  catch (error) { return { status: "error", message: isClosedPeriodError(error) ? "Ce virement appartient à un exercice clôturé et ne peut plus être supprimé." : "Impossible de supprimer le virement." }; }
  refresh(personId);
  redirect(getSafeTransactionReturnTo(personId, returnHref));
}
