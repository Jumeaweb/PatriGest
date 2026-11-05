import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { Category, FinancialAccount, Transaction, TransactionDocument, Transfer } from "@/types/database";
import { isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { TransactionFilters, TransactionInput } from "../schemas/transaction-schema";
import { resolveTransactionClassification, resolveTransactionClassificationForUpdate } from "./transaction-classification";
import { loadTransactionDocumentsInBatches } from "./transaction-document-batches";
import { getTransactionPageMetadata, TRANSACTION_JOURNAL_PAGE_SIZE } from "../transaction-pagination";
import { loadCompleteTransactionHistory, loadTransactionRelationsInBatches } from "./transaction-history";

import { resolveEffectiveTransactionClassification, type EffectiveTransactionClassification } from "./transaction-classification-read";

export type TransactionJournalItem = Transaction & { account: FinancialAccount; category: Category | null; classification: EffectiveTransactionClassification; transfer: Transfer | null; counterpartAccount: FinancialAccount | null; attachmentCount: number };
export type TransactionJournalPage = ReturnType<typeof getTransactionPageMetadata> & { items: TransactionJournalItem[] };
async function ownedPerson(id: string) { const auth = await getAuthenticatedUser(); const { data } = await auth.supabase.from("protected_persons").select("id").eq("id", id).maybeSingle(); if (!data) throw new Error("Dossier introuvable."); return auth; }
async function ownedAccount(id: string, personId?: string) { const auth = await getAuthenticatedUser(); const { data: account } = await auth.supabase.from("financial_accounts").select("*").eq("id", id).maybeSingle(); if (!account || (personId && account.protected_person_id !== personId)) throw new Error("Compte introuvable."); const { data: person } = await auth.supabase.from("protected_persons").select("id").eq("id", account.protected_person_id).maybeSingle(); if (!person) throw new Error("Compte introuvable."); return { ...auth, account }; }
function validDate(account: FinancialAccount, date: string) { return date >= account.initial_balance_date && (!account.opening_date || date >= account.opening_date) && (!account.closing_date || date <= account.closing_date); }

const mutationResultSchema = z.object({ id: z.uuid(), revision: z.coerce.number().int().positive(), replayed: z.boolean() });
const mutationReasonSchema = z.string().trim().min(3).max(1000);
export type FinancialTransactionMutationResult = z.infer<typeof mutationResultSchema>;
export type FinancialTransactionMutationOptions = { requestId?: string };
export type FinancialTransactionCorrectionOptions = FinancialTransactionMutationOptions & { expectedRevision: number; reason: string };

function transactionMutationError(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return new Error(fallback);
  if (error.code === "40001") return new Error("L’opération a été modifiée. Rechargez la page.");
  if (error.code === "22007") return new Error("La date d’une opération réelle ne peut pas être future.");
  if (error.code === "42501") return new Error("Dossier introuvable ou accès refusé.");
  if (error.code === "P0002") return new Error("Opération introuvable.");
  if (error.code === "23503") return new Error("Compte introuvable dans ce dossier.");
  if (error.code === "23505") return new Error("Cette demande a déjà été utilisée pour une autre opération.");
  if (error.code === "55000" && error.message) return new Error(error.message);
  if (error.message?.toLocaleLowerCase("fr-FR").includes("exercice clôturé")) return new Error("Cette opération appartient à un exercice clôturé.");
  return new Error(fallback);
}

async function enrichTransactions(
  supabase: Awaited<ReturnType<typeof getAuthenticatedUser>>["supabase"],
  accounts: FinancialAccount[],
  data: Transaction[],
): Promise<TransactionJournalItem[]> {
  const categoryIds = [...new Set(data.map((transaction) => transaction.category_id).filter((id): id is string => Boolean(id)))];
  const stableOfficialCategoryIds = data.map((transaction) => transaction.official_category_id).filter((id): id is string => Boolean(id));
  const initialCategoryIds = [...new Set([...categoryIds, ...stableOfficialCategoryIds])];
  const transferIds = [...new Set(data.map((transaction) => transaction.transfer_id).filter((id): id is string => Boolean(id)))];
  const transactionIds = data.map((transaction) => transaction.id);
  const [initialCategories, transfers, documents] = await Promise.all([
    initialCategoryIds.length ? supabase.from("categories").select("*").in("id", initialCategoryIds).then(({ data: rows }) => rows ?? []) : [],
    transferIds.length ? loadTransactionRelationsInBatches(transferIds, async (ids) => {
      const { data: rows } = await supabase.from("transfers").select("*").in("id", [...ids]);
      return { data: rows ?? [], error: null };
    }) : [],
    transactionIds.length ? loadTransactionDocumentsInBatches(transactionIds, async (batchTransactionIds) => {
      const { data: rows, error: documentError } = await supabase
        .from("transaction_documents")
        .select("transaction_id")
        .in("transaction_id", batchTransactionIds);
      if (documentError) throw new Error("Impossible de charger les justificatifs.");
      return rows ?? [];
    }) : [],
  ]);
  const categoryById = new Map(initialCategories.map((category) => [category.id, category]));
  const missingPresetTargetIds = [...new Set(categoryIds.flatMap((categoryId) => {
    const category = categoryById.get(categoryId);
    return category && !category.is_system && category.official_category_id && !categoryById.has(category.official_category_id)
      ? [category.official_category_id]
      : [];
  }))];
  if (missingPresetTargetIds.length) {
    const { data: presetTargets } = await supabase.from("categories").select("*").in("id", missingPresetTargetIds);
    for (const category of presetTargets ?? []) categoryById.set(category.id, category);
  }

  const attachmentCounts = new Map<string, number>();
  for (const document of documents) attachmentCounts.set(document.transaction_id, (attachmentCounts.get(document.transaction_id) ?? 0) + 1);
  return data.map((transaction) => {
    const category = transaction.category_id ? categoryById.get(transaction.category_id) ?? null : null;
    const stableOfficialCategory = transaction.official_category_id ? categoryById.get(transaction.official_category_id) ?? null : null;
    const legacyOfficialCategory = category?.official_category_id ? categoryById.get(category.official_category_id) ?? null : null;
    const transfer = transaction.transfer_id ? transfers.find((entry) => entry.id === transaction.transfer_id) ?? null : null;
    const counterpartId = transfer ? transaction.financial_account_id === transfer.source_account_id ? transfer.destination_account_id : transfer.source_account_id : null;
    return {
      ...transaction,
      account: accounts.find((account) => account.id === transaction.financial_account_id)!,
      category,
      classification: resolveEffectiveTransactionClassification({ transaction, stableOfficialCategory, legacyCategory: category, legacyOfficialCategory }),
      transfer,
      counterpartAccount: counterpartId ? accounts.find((account) => account.id === counterpartId) ?? null : null,
      attachmentCount: attachmentCounts.get(transaction.id) ?? 0,
    };
  });
}

export async function getTransactions(personId: string, filters: TransactionFilters = {}): Promise<TransactionJournalItem[]> {
  const { supabase } = await ownedPerson(personId);
  const { data: accounts, error: ae } = await supabase.from("financial_accounts").select("*").eq("protected_person_id", personId);
  if (ae) throw new Error("Impossible de charger les comptes.");
  if (!accounts.length) return [];
  const accessibleAccountIds = accounts.map((a) => a.id);
  const accountIds = filters.reportAccountIds ? accessibleAccountIds.filter((id) => filters.reportAccountIds!.includes(id)) : accessibleAccountIds;
  if (!accountIds.length) return [];
  const buildQuery = () => {
    let query = supabase.from("transactions").select("*").in("financial_account_id", accountIds)
      .order("transaction_date", { ascending: false })
      .order("created_at", { ascending: false })
      .order("id", { ascending: false });
    if (filters.includeCancelled === false) query = query.is("cancelled_at", null);
    if (filters.startDate) query = query.gte("transaction_date", filters.startDate);
    if (filters.endDate) query = query.lte("transaction_date", filters.endDate);
    if (filters.accountId) query = query.eq("financial_account_id", filters.accountId);
    if (filters.type) query = filters.type === "transfer" ? query.in("transaction_type", ["transfer_in", "transfer_out"]) : query.eq("transaction_type", filters.type);
    if (filters.categoryId) query = query.eq("category_id", filters.categoryId);
    if (filters.query) query = query.ilike("label", `%${filters.query.replace(/[%_]/g, "")}%`);
    return query;
  };
  let data: Transaction[];
  try {
    if (filters.limit && filters.limit > 0) {
      const result = await buildQuery().limit(filters.limit);
      if (result.error) throw result.error;
      data = result.data ?? [];
    } else {
      data = await loadCompleteTransactionHistory((from, to) => buildQuery().range(from, to));
    }
  } catch {
    throw new Error("Impossible de charger les opérations.");
  }
  return enrichTransactions(supabase, accounts, data);
}

export async function getTransactionJournalPage(
  personId: string,
  filters: TransactionFilters,
  requestedPage: number,
): Promise<TransactionJournalPage> {
  const { supabase } = await ownedPerson(personId);
  const { data: accounts, error: accountError } = await supabase.from("financial_accounts").select("*").eq("protected_person_id", personId);
  if (accountError) throw new Error("Impossible de charger les comptes.");
  if (!accounts.length) return { items: [], ...getTransactionPageMetadata(0, requestedPage) };
  const accessibleAccountIds = accounts.map((account) => account.id);

  const loadPage = async (page: number) => {
    const offset = (page - 1) * TRANSACTION_JOURNAL_PAGE_SIZE;
    let query = supabase.from("transactions").select("*", { count: "exact" }).in("financial_account_id", accessibleAccountIds)
      .order("transaction_date", { ascending: false })
      .order("created_at", { ascending: false })
      .order("id", { ascending: false });
    if (filters.includeCancelled === false) query = query.is("cancelled_at", null);
    if (filters.startDate) query = query.gte("transaction_date", filters.startDate);
    if (filters.endDate) query = query.lte("transaction_date", filters.endDate);
    if (filters.accountId) query = query.eq("financial_account_id", filters.accountId);
    if (filters.type) query = filters.type === "transfer" ? query.in("transaction_type", ["transfer_in", "transfer_out"]) : query.eq("transaction_type", filters.type);
    if (filters.categoryId) query = query.eq("category_id", filters.categoryId);
    if (filters.query) query = query.ilike("label", `%${filters.query.replace(/[%_]/g, "")}%`);
    return query.range(offset, offset + TRANSACTION_JOURNAL_PAGE_SIZE - 1);
  };

  const initialResult = await loadPage(requestedPage);
  if (initialResult.error) throw new Error("Impossible de charger les opérations.");
  let data = initialResult.data;
  let count = initialResult.count;
  let metadata = getTransactionPageMetadata(count ?? 0, requestedPage);
  if (metadata.page !== requestedPage) {
    const normalizedResult = await loadPage(metadata.page);
    if (normalizedResult.error) throw new Error("Impossible de charger les opérations.");
    data = normalizedResult.data;
    count = normalizedResult.count;
    metadata = getTransactionPageMetadata(count ?? 0, metadata.page);
  }

  return { items: await enrichTransactions(supabase, accounts, data ?? []), ...metadata };
}

export async function getTransaction(id: string) { const auth = await getAuthenticatedUser(); const { data } = await auth.supabase.from("transactions").select("*").eq("id", id).maybeSingle(); if (!data) return null; try { const { account } = await ownedAccount(data.financial_account_id); return { ...data, account }; } catch { return null; } }
export async function createTransaction(
  personId: string,
  input: TransactionInput,
  options: FinancialTransactionMutationOptions = {},
) {
  const { supabase, userId, account } = await ownedAccount(input.financialAccountId, personId);
  if (isValuationAccount(account.account_type)) throw new Error("Les recettes et dépenses nécessitent un compte transactionnel.");
  if (!validDate(account, input.transactionDate)) throw new Error("Date incompatible avec le compte.");
  const classification = await resolveTransactionClassification({ supabase, userId, transactionType: input.transactionType, categoryId: input.categoryId, classificationPrecision: input.classificationPrecision, requirePrecision: true });
  const requestId = z.uuid().parse(options.requestId ?? randomUUID());
  const { data, error } = await supabase.rpc("create_financial_transaction", {
    p_protected_person_id: personId,
    p_financial_account_id: input.financialAccountId,
    p_transaction_date: input.transactionDate,
    p_transaction_type: input.transactionType,
    p_label: input.label,
    p_amount: input.amount,
    p_category_id: classification.categoryId,
    p_official_category_id: classification.officialCategoryId,
    p_classification_precision: classification.classificationPrecision,
    p_comment: input.comment,
    p_request_id: requestId,
  });
  if (error) throw transactionMutationError(error, "Impossible de créer l’opération.");
  const result = mutationResultSchema.safeParse(data);
  if (!result.success) throw new Error("Impossible de confirmer la création de l’opération.");
  const created = await supabase.from("transactions").select("id,proof_reference,revision").eq("id", result.data.id).single();
  if (created.error || !created.data) throw new Error("Impossible de confirmer la création de l’opération.");
  return { ...created.data, replayed: result.data.replayed };
}

export async function updateTransaction(
  id: string,
  personId: string,
  input: TransactionInput,
  options: FinancialTransactionCorrectionOptions,
): Promise<FinancialTransactionMutationResult> {
  const existing = await getTransaction(id);
  if (!existing || existing.transfer_id || existing.account.protected_person_id !== personId) throw new Error("Opération introuvable.");
  const { supabase, userId, account } = await ownedAccount(input.financialAccountId, personId);
  if (isValuationAccount(account.account_type)) throw new Error("Les recettes et dépenses nécessitent un compte transactionnel.");
  if (!validDate(account, input.transactionDate)) throw new Error("Date incompatible avec le compte.");
  const classification = await resolveTransactionClassificationForUpdate({ supabase, userId, transactionType: input.transactionType, existing, categoryId: input.categoryId, classificationPrecision: input.classificationPrecision, requirePrecision: true });
  const reason = mutationReasonSchema.parse(options.reason);
  const { data, error } = await supabase.rpc("correct_financial_transaction", {
    p_protected_person_id: personId,
    p_transaction_id: id,
    p_expected_revision: options.expectedRevision,
    p_financial_account_id: input.financialAccountId,
    p_transaction_date: input.transactionDate,
    p_transaction_type: input.transactionType,
    p_label: input.label,
    p_amount: input.amount,
    p_category_id: classification.categoryId,
    p_official_category_id: classification.officialCategoryId,
    p_classification_precision: classification.classificationPrecision,
    p_comment: input.comment,
    p_reason: reason,
    p_request_id: z.uuid().parse(options.requestId ?? randomUUID()),
  });
  if (error) throw transactionMutationError(error, "Impossible de modifier l’opération.");
  return mutationResultSchema.parse(data);
}

export async function getTransactionDocument(transactionId: string): Promise<TransactionDocument | null> { const { supabase } = await getAuthenticatedUser(); const { data, error } = await supabase.from("transaction_documents").select("*").eq("transaction_id", transactionId).maybeSingle(); if (error) throw new Error("Impossible de charger le justificatif."); return data; }
export async function deleteTransaction(
  id: string,
  personId: string,
  options: FinancialTransactionCorrectionOptions,
): Promise<FinancialTransactionMutationResult> {
  const existing = await getTransaction(id);
  if (!existing || existing.transfer_id || existing.account.protected_person_id !== personId) throw new Error("Opération introuvable.");
  const { supabase } = await ownedPerson(personId);
  const { data, error } = await supabase.rpc("cancel_financial_transaction", {
    p_protected_person_id: personId,
    p_transaction_id: id,
    p_expected_revision: options.expectedRevision,
    p_reason: mutationReasonSchema.parse(options.reason),
    p_request_id: z.uuid().parse(options.requestId ?? randomUUID()),
  });
  if (error) throw transactionMutationError(error, "Impossible d’annuler l’opération.");
  return mutationResultSchema.parse(data);
}
