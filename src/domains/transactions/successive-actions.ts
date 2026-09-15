"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { transactionSchema } from "./schemas/transaction-schema";
import { createTransaction } from "./services/transaction-service";
import { ClassificationPrecisionRequiredError } from "./services/transaction-classification";
import { isClosedPeriodError } from "./errors";
import type { SuccessiveActionState } from "./successive-entry";
import { isSuccessiveAccountEligible } from "./successive-entry";

export async function createSuccessiveTransactionAction(personId: string, _state: SuccessiveActionState, formData: FormData): Promise<SuccessiveActionState> {
  if (!z.uuid().safeParse(personId).success) return { status: "error", message: "Dossier invalide." };
  try {
    const person = await getProtectedPerson(personId);
    if (!person || person.accessRole === "read_only") return { status: "error", message: "Impossible d’enregistrer cette opération." };
  } catch { return { status: "error", message: "Impossible d’enregistrer cette opération." }; }
  const parsed = transactionSchema.safeParse({
    financialAccountId: formData.get("financialAccountId"), transactionDate: formData.get("transactionDate"),
    transactionType: formData.get("transactionType"), label: formData.get("label"), amount: formData.get("amount"),
    categoryId: formData.get("categoryId"), classificationPrecision: formData.get("classificationPrecision"),
    proofReference: "", comment: "",
  });
  if (!parsed.success) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: parsed.error.flatten().fieldErrors };
  try {
    const { supabase } = await getAuthenticatedUser();
    const { data: account, error: accountError } = await supabase.from("financial_accounts").select("id,status,account_type,protected_person_id").eq("id", parsed.data.financialAccountId).maybeSingle();
    if (accountError || !account || account.protected_person_id !== personId || !isSuccessiveAccountEligible(account)) return { status: "error", message: "Choisissez un compte transactionnel actif de ce dossier.", fieldErrors: { financialAccountId: ["Ce compte ne permet pas cette saisie."] } };
    const transaction = await createTransaction(personId, parsed.data);
    revalidatePath(`/dossiers/${personId}/operations`);
    revalidatePath(`/dossiers/${personId}/comptes`);
    revalidatePath(`/dossiers/${personId}`);
    return { status: "success", message: "L’opération a été enregistrée.", created: {
      id: transaction.id, transaction_type: parsed.data.transactionType, transaction_date: parsed.data.transactionDate,
      label: parsed.data.label, amount: parsed.data.amount, financial_account_id: parsed.data.financialAccountId,
      proof_reference: transaction.proof_reference,
    } };
  } catch (error) {
    if (error instanceof ClassificationPrecisionRequiredError) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: { classificationPrecision: [error.message] } };
    return { status: "error", message: isClosedPeriodError(error) ? "Impossible d’ajouter une opération dans un exercice clôturé." : "Impossible d’enregistrer l’opération. Vérifiez le compte, la date et la classification." };
  }
}
