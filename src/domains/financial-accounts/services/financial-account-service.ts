import type { AccountValuation, FinancialAccount, Transaction } from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { FinancialAccountInput } from "../schemas/financial-account-schema";
import type { AccountValuationInput } from "../schemas/account-valuation-schema";
import { isValuationAccount } from "../utils/financial-account-utils";
import { deleteAccountValuationRow } from "./account-valuation-delete";
import { loadCompleteTransactionHistory } from "@/domains/transactions/services/transaction-history";

export type FinancialAccountWithValuations = FinancialAccount & { valuations: AccountValuation[]; transactions: Transaction[] };

async function requireOwnedPerson(protectedPersonId: string) {
  const auth = await getAuthenticatedUser();
  const { data, error } = await auth.supabase.from("protected_persons").select("id").eq("id", protectedPersonId).maybeSingle();
  if (error || !data) throw new Error("Dossier introuvable.");
  return auth;
}

async function requireManagedPerson(protectedPersonId: string) {
  const auth = await requireOwnedPerson(protectedPersonId);
  const { data: canManage, error } = await auth.supabase.rpc("can_manage_protected_person", { person_id: protectedPersonId });
  if (error || !canManage) throw new Error("Création du compte non autorisée.");
  return auth;
}

async function requireOwnedAccount(accountId: string) {
  const auth = await getAuthenticatedUser();
  const { data: account, error } = await auth.supabase.from("financial_accounts").select("*").eq("id", accountId).maybeSingle();
  if (error || !account) throw new Error("Compte introuvable.");
  const { data: person } = await auth.supabase.from("protected_persons").select("id").eq("id", account.protected_person_id).maybeSingle();
  if (!person) throw new Error("Compte introuvable.");
  return { ...auth, account };
}

async function requireManagedAccount(accountId: string) {
  const result = await requireOwnedAccount(accountId);
  const { data: canManage, error } = await result.supabase.rpc("can_manage_protected_person", { person_id: result.account.protected_person_id });
  if (error || !canManage) throw new Error("Modification du compte non autorisée.");
  return result;
}

export async function getFinancialAccounts(protectedPersonId: string): Promise<FinancialAccountWithValuations[]> {
  const { supabase } = await requireOwnedPerson(protectedPersonId);
  const { data: accounts, error } = await supabase.from("financial_accounts").select("*").eq("protected_person_id", protectedPersonId).order("created_at", { ascending: false });
  if (error) throw new Error("Impossible de charger les comptes.");
  if (accounts.length === 0) return [];
  const accountIds = accounts.map((account) => account.id);
  const [{ data: valuations, error: valuationsError }, transactionsResult] = await Promise.all([
    supabase.from("account_valuations").select("*").in("financial_account_id", accountIds).order("valuation_date", { ascending: false }),
    loadCompleteTransactionHistory((from, to) => supabase.from("transactions").select("*")
      .in("financial_account_id", accountIds)
      .order("transaction_date", { ascending: false })
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(from, to)).catch(() => { throw new Error("Impossible de charger les opérations."); }),
  ]);
  if (valuationsError) throw new Error("Impossible de charger les valorisations.");
  return accounts.map((account) => ({ ...account, valuations: valuations.filter((valuation) => valuation.financial_account_id === account.id), transactions: transactionsResult.filter((transaction) => transaction.financial_account_id === account.id) }));
}

export async function getFinancialAccount(accountId: string): Promise<FinancialAccountWithValuations | null> {
  try {
    const { supabase, account } = await requireOwnedAccount(accountId);
    const [{ data: valuations, error }, transactions] = await Promise.all([
      supabase.from("account_valuations").select("*").eq("financial_account_id", accountId).order("valuation_date", { ascending: false }),
      loadCompleteTransactionHistory((from, to) => supabase.from("transactions").select("*")
        .eq("financial_account_id", accountId)
        .order("transaction_date", { ascending: false })
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(from, to)).catch(() => { throw new Error("Impossible de charger les données du compte."); }),
    ]);
    if (error) throw new Error("Impossible de charger les données du compte.");
    return { ...account, valuations, transactions };
  } catch (error) {
    if (error instanceof Error && error.message === "Compte introuvable.") return null;
    throw error;
  }
}

export async function createFinancialAccount(protectedPersonId: string, input: FinancialAccountInput) {
  const { supabase } = await requireManagedPerson(protectedPersonId);
  const { data, error } = await supabase.from("financial_accounts").insert({ protected_person_id: protectedPersonId, account_type: input.accountType, account_name: input.accountName, institution_name: input.institutionName, account_reference: input.accountReference, initial_balance: input.initialBalance, initial_balance_date: input.initialBalanceDate, opening_date: input.openingDate, notes: input.notes }).select("*").single();
  if (error) throw new Error("Impossible de créer le compte.");
  return data;
}

export async function updateFinancialAccount(accountId: string, input: FinancialAccountInput) {
  const { supabase } = await requireOwnedAccount(accountId);
  const { data, error } = await supabase.from("financial_accounts").update({ account_type: input.accountType, account_name: input.accountName, institution_name: input.institutionName, account_reference: input.accountReference, initial_balance: input.initialBalance, initial_balance_date: input.initialBalanceDate, opening_date: input.openingDate, notes: input.notes }).eq("id", accountId).select("*").single();
  if (error) throw new Error("Impossible de modifier le compte.");
  return data;
}

export async function closeFinancialAccount(accountId: string, closingDate: string) {
  const { supabase, account } = await requireManagedAccount(accountId);
  if (closingDate < account.initial_balance_date || (account.opening_date && closingDate < account.opening_date)) throw new Error("La date de clôture est antérieure aux dates du compte.");
  const { error } = await supabase.from("financial_accounts").update({ status: "closed", closing_date: closingDate }).eq("id", accountId);
  if (error) throw new Error("Impossible de clôturer le compte.");
}

export async function reopenFinancialAccount(accountId: string) {
  const { supabase } = await requireManagedAccount(accountId);
  const { error } = await supabase.from("financial_accounts").update({ status: "active", closing_date: null }).eq("id", accountId);
  if (error) throw new Error("Impossible de rouvrir le compte.");
}

export async function deleteFinancialAccount(accountId: string, protectedPersonId: string) {
  const { supabase, account } = await requireOwnedAccount(accountId);
  if (account.protected_person_id !== protectedPersonId) throw new Error("Compte introuvable.");
  const { error } = await supabase.rpc("delete_empty_financial_account", { p_account_id: accountId });
  if (error) {
    if (error.message.includes("contient des opérations")) throw new Error("Ce compte ne peut pas être supprimé tant qu’il contient des opérations, virements, valorisations, justificatifs ou relevés bancaires.");
    throw new Error("Impossible de supprimer ce compte.");
  }
}

export async function getAccountValuations(accountId: string) {
  const { supabase } = await requireOwnedAccount(accountId);
  const { data, error } = await supabase.from("account_valuations").select("*").eq("financial_account_id", accountId).order("valuation_date", { ascending: false });
  if (error) throw new Error("Impossible de charger les valorisations.");
  return data;
}

export async function createAccountValuation(accountId: string, input: AccountValuationInput) {
  const { supabase, account } = await requireOwnedAccount(accountId);
  if (!isValuationAccount(account.account_type)) throw new Error("Ce compte n’accepte pas de valorisations.");
  const { data, error } = await supabase.from("account_valuations").insert({ financial_account_id: accountId, valuation_date: input.valuationDate, value: input.value, comment: input.comment }).select("*").single();
  if (error) throw new Error("Impossible d’ajouter la valorisation.");
  return data;
}

export async function updateAccountValuation(accountId: string, valuationId: string, input: AccountValuationInput) {
  const { supabase, account } = await requireOwnedAccount(accountId);
  if (!isValuationAccount(account.account_type)) throw new Error("Ce compte n’accepte pas de valorisations.");

  const { data: valuation, error: lookupError } = await supabase
    .from("account_valuations")
    .select("id, financial_account_id")
    .eq("id", valuationId)
    .eq("financial_account_id", accountId)
    .maybeSingle();

  if (lookupError || !valuation) throw new Error("Valorisation introuvable.");

  const { data, error } = await supabase
    .from("account_valuations")
    .update({ valuation_date: input.valuationDate, value: input.value, comment: input.comment })
    .eq("id", valuationId)
    .eq("financial_account_id", accountId)
    .select("*")
    .single();

  if (error?.code === "23505") throw new Error("Une valorisation existe déjà à cette date.");
  if (error) throw new Error("Impossible de modifier la valorisation.");
  return data;
}

export async function deleteAccountValuation(
  accountId: string,
  valuationId: string,
) {
  const { supabase, account } = await requireManagedAccount(accountId);
  if (!isValuationAccount(account.account_type)) {
    throw new Error("Ce compte n’accepte pas de valorisations.");
  }

  await deleteAccountValuationRow(supabase, accountId, valuationId);
}
