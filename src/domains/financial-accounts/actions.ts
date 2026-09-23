"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { accountValuationSchema } from "./schemas/account-valuation-schema";
import { closeFinancialAccountSchema, financialAccountSchema } from "./schemas/financial-account-schema";
import { closeFinancialAccount, createAccountValuation, createFinancialAccount, deleteAccountValuation, deleteFinancialAccount, getFinancialAccount, reopenFinancialAccount, updateAccountValuation, updateFinancialAccount } from "./services/financial-account-service";
import type { FinancialAccountActionState } from "./state";
import { getFinancialAccountEntryHref } from "./financial-account-entry";
import { isValuationAccount } from "./utils/financial-account-utils";

function invalid(error: z.ZodError): FinancialAccountActionState { return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: error.flatten().fieldErrors }; }
function accountValues(formData: FormData) { return { accountType: formData.get("accountType"), accountName: formData.get("accountName"), institutionName: formData.get("institutionName"), accountReference: formData.get("accountReference"), initialBalance: formData.get("initialBalance"), initialBalanceDate: formData.get("initialBalanceDate"), openingDate: formData.get("openingDate"), notes: formData.get("notes") }; }
function validIds(...ids: string[]) { return ids.every((id) => z.uuid().safeParse(id).success); }

export async function createFinancialAccountAction(protectedPersonId: string, _state: FinancialAccountActionState, formData: FormData): Promise<FinancialAccountActionState> {
  if (!validIds(protectedPersonId)) return { status: "error", message: "Dossier invalide." };
  const parsed = financialAccountSchema.safeParse(accountValues(formData));
  if (!parsed.success) return invalid(parsed.error);
  let account;
  try { account = await createFinancialAccount(protectedPersonId, parsed.data); } catch { return { status: "error", message: "Impossible de créer le compte. Veuillez réessayer." }; }
  revalidatePath(`/dossiers/${protectedPersonId}`);
  redirect(getFinancialAccountEntryHref(protectedPersonId, account.id, isValuationAccount(account.account_type)));
}

export async function updateFinancialAccountAction(protectedPersonId: string, accountId: string, _state: FinancialAccountActionState, formData: FormData): Promise<FinancialAccountActionState> {
  if (!validIds(protectedPersonId, accountId)) return { status: "error", message: "Compte invalide." };
  const parsed = financialAccountSchema.safeParse(accountValues(formData));
  if (!parsed.success) return invalid(parsed.error);
  const account = await getFinancialAccount(accountId);
  if (!account || account.protected_person_id !== protectedPersonId) return { status: "error", message: "Compte introuvable." };
  try { await updateFinancialAccount(accountId, parsed.data); } catch { return { status: "error", message: "Impossible de modifier le compte. Veuillez réessayer." }; }
  revalidatePath(`/dossiers/${protectedPersonId}/comptes`);
  revalidatePath(`/dossiers/${protectedPersonId}`);
  redirect(`/dossiers/${protectedPersonId}/comptes/${accountId}`);
}

export async function closeFinancialAccountAction(protectedPersonId: string, accountId: string, _state: FinancialAccountActionState, formData: FormData): Promise<FinancialAccountActionState> {
  if (!validIds(protectedPersonId, accountId)) return { status: "error", message: "Compte invalide." };
  const parsed = closeFinancialAccountSchema.safeParse({ closingDate: formData.get("closingDate") });
  if (!parsed.success) return invalid(parsed.error);
  const account = await getFinancialAccount(accountId);
  if (!account || account.protected_person_id !== protectedPersonId) return { status: "error", message: "Compte introuvable." };
  try { await closeFinancialAccount(accountId, parsed.data.closingDate); revalidatePath(`/dossiers/${protectedPersonId}/comptes`); revalidatePath(`/dossiers/${protectedPersonId}/comptes/${accountId}`); revalidatePath(`/dossiers/${protectedPersonId}`); return { status: "success", message: "Le compte a été clôturé." }; } catch { return { status: "error", message: "Impossible de clôturer le compte. Vérifiez la date saisie." }; }
}

export async function reopenFinancialAccountAction(protectedPersonId: string, accountId: string) {
  if (!validIds(protectedPersonId, accountId)) return;
  const account = await getFinancialAccount(accountId);
  if (!account || account.protected_person_id !== protectedPersonId) return;
  await reopenFinancialAccount(accountId);
  revalidatePath(`/dossiers/${protectedPersonId}/comptes`);
  revalidatePath(`/dossiers/${protectedPersonId}/comptes/${accountId}`);
  revalidatePath(`/dossiers/${protectedPersonId}`);
}

export async function deleteFinancialAccountAction(protectedPersonId: string, accountId: string, _state: FinancialAccountActionState, _formData: FormData): Promise<FinancialAccountActionState> {
  void _state;
  void _formData;
  if (!validIds(protectedPersonId, accountId)) return { status: "error", message: "Compte invalide." };
  try { await deleteFinancialAccount(accountId, protectedPersonId); }
  catch (error) { return { status: "error", message: error instanceof Error ? error.message : "Impossible de supprimer ce compte." }; }
  revalidatePath(`/dossiers/${protectedPersonId}`);
  revalidatePath(`/dossiers/${protectedPersonId}/comptes`);
  redirect(`/dossiers/${protectedPersonId}/comptes`);
}

export async function createAccountValuationAction(protectedPersonId: string, accountId: string, _state: FinancialAccountActionState, formData: FormData): Promise<FinancialAccountActionState> {
  if (!validIds(protectedPersonId, accountId)) return { status: "error", message: "Compte invalide." };
  const parsed = accountValuationSchema.safeParse({ valuationDate: formData.get("valuationDate"), value: formData.get("value"), comment: formData.get("comment") });
  if (!parsed.success) return invalid(parsed.error);
  const account = await getFinancialAccount(accountId);
  if (!account || account.protected_person_id !== protectedPersonId) return { status: "error", message: "Compte introuvable." };
  try { await createAccountValuation(accountId, parsed.data); revalidatePath(`/dossiers/${protectedPersonId}/comptes`); revalidatePath(`/dossiers/${protectedPersonId}/comptes/${accountId}`); revalidatePath(`/dossiers/${protectedPersonId}`); return { status: "success", message: "La valorisation a été ajoutée." }; } catch { return { status: "error", message: "Impossible d’ajouter la valorisation. Vérifiez qu’aucune valeur n’existe déjà à cette date." }; }
}

export async function updateAccountValuationAction(protectedPersonId: string, accountId: string, valuationId: string, _state: FinancialAccountActionState, formData: FormData): Promise<FinancialAccountActionState> {
  if (!validIds(protectedPersonId, accountId, valuationId)) return { status: "error", message: "Valorisation invalide." };
  const parsed = accountValuationSchema.safeParse({ valuationDate: formData.get("valuationDate"), value: formData.get("value"), comment: formData.get("comment") });
  if (!parsed.success) return invalid(parsed.error);
  const account = await getFinancialAccount(accountId);
  if (!account || account.protected_person_id !== protectedPersonId) return { status: "error", message: "Compte introuvable." };
  try {
    await updateAccountValuation(accountId, valuationId, parsed.data);
    revalidatePath(`/dossiers/${protectedPersonId}/comptes`);
    revalidatePath(`/dossiers/${protectedPersonId}/comptes/${accountId}`);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    return { status: "success", message: "La valorisation a été modifiée." };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "Impossible de modifier la valorisation." };
  }
}

export async function deleteAccountValuationAction(
  protectedPersonId: string,
  accountId: string,
  valuationId: string,
  _state: FinancialAccountActionState,
  _formData: FormData,
): Promise<FinancialAccountActionState> {
  void _state;
  void _formData;
  if (!validIds(protectedPersonId, accountId, valuationId)) {
    return { status: "error", message: "Valorisation invalide." };
  }

  try {
    await deleteAccountValuation(accountId, valuationId);
  } catch {
    return {
      status: "error",
      message: "Impossible de supprimer la valorisation. Veuillez réessayer.",
    };
  }

  revalidatePath(`/dossiers/${protectedPersonId}`);
  revalidatePath(`/dossiers/${protectedPersonId}/comptes`);
  revalidatePath(`/dossiers/${protectedPersonId}/comptes/${accountId}`);
  return { status: "success", message: "La valorisation a été supprimée." };
}
