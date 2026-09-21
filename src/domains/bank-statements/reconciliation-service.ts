import type { BankReconciliation, BankStatement, FinancialAccount } from "@/types/database";
import { getAccountBalanceAtDate } from "@/domains/financial-accounts/services/financial-account-service";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import {
  calculateReconciliationDifference,
  getReconciliationUnavailableReason,
  type ReconciliationUnavailableReason,
} from "./reconciliation-calculations";

const RECONCILIATION_QUERY_BATCH_SIZE = 100;
export const OUTSTANDING_TRANSACTION_PAGE_SIZE = 50;

export type BankReconciliationListState = Pick<
  BankReconciliation,
  "id" | "bank_statement_id" | "status" | "reconciliation_mode" | "calculated_balance" | "difference" |
  "outstanding_debits" | "outstanding_credits" | "explained_bank_balance" | "residual_difference" | "validated_at"
>;

export type BankReconciliationControl = {
  reconciliationId: string | null;
  status: "none" | "draft" | "validated";
  reconciliationMode: "simple" | "complete";
  unavailableReason: ReconciliationUnavailableReason | null;
  statementEndDate: string;
  statementBalance: number | null;
  calculatedBalance: number | null;
  calculatedBalanceInCents: number | null;
  difference: number | null;
  differenceInCents: number | null;
  validatedAt: string | null;
  outstandingDebits: number | null;
  outstandingCredits: number | null;
  explainedBankBalance: number | null;
  residualDifference: number | null;
  outstandingCount: number | null;
};

export type OutstandingTransactionCandidate = {
  transactionId: string;
  transactionDate: string;
  transactionCreatedAt: string;
  transactionType: "income" | "expense" | "transfer_in" | "transfer_out";
  label: string;
  amount: number;
  isOutstanding: boolean;
  carriedFromPrevious: boolean;
};

export type OutstandingTransactionPage = {
  items: OutstandingTransactionCandidate[];
  nextCursor: string | null;
  summary: Pick<BankReconciliationControl, "calculatedBalance" | "outstandingDebits" | "outstandingCredits" | "explainedBankBalance" | "residualDifference" | "outstandingCount">;
};

export class BankReconciliationServiceError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

export async function getBankReconciliationListStates(statementIds: string[]) {
  if (statementIds.length === 0) return [];
  const { supabase } = await getAuthenticatedUser();
  const states: BankReconciliationListState[] = [];
  for (let index = 0; index < statementIds.length; index += RECONCILIATION_QUERY_BATCH_SIZE) {
    const batch = statementIds.slice(index, index + RECONCILIATION_QUERY_BATCH_SIZE);
    const { data, error } = await supabase
      .from("bank_reconciliations")
      .select("id, bank_statement_id, status, reconciliation_mode, calculated_balance, difference, outstanding_debits, outstanding_credits, explained_bank_balance, residual_difference, validated_at")
      .in("bank_statement_id", batch);
    if (error) throw new Error("Impossible de charger les contrôles bancaires.");
    states.push(...data);
  }
  return states;
}

export async function getBankReconciliation(statementId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("bank_reconciliations")
    .select("*")
    .eq("bank_statement_id", statementId)
    .maybeSingle();
  if (error) throw new BankReconciliationServiceError("Impossible de charger le contrôle bancaire.", 500);
  return data;
}

export async function buildBankReconciliationControl(
  protectedPersonId: string,
  account: FinancialAccount,
  statement: BankStatement,
  reconciliation: BankReconciliation | null,
): Promise<BankReconciliationControl> {
  if (reconciliation?.status === "validated") {
    return {
      reconciliationId: reconciliation.id,
      status: "validated",
      reconciliationMode: reconciliation.reconciliation_mode,
      unavailableReason: null,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: reconciliation.calculated_balance,
      calculatedBalanceInCents: reconciliation.calculated_balance === null ? null : Math.round(reconciliation.calculated_balance * 100),
      difference: reconciliation.difference,
      differenceInCents: reconciliation.difference === null ? null : Math.round(reconciliation.difference * 100),
      validatedAt: reconciliation.validated_at,
      outstandingDebits: reconciliation.outstanding_debits,
      outstandingCredits: reconciliation.outstanding_credits,
      explainedBankBalance: reconciliation.explained_bank_balance,
      residualDifference: reconciliation.residual_difference,
      outstandingCount: null,
    };
  }

  const unavailableReason = getReconciliationUnavailableReason(statement, account);
  if (unavailableReason) {
    return {
      reconciliationId: reconciliation?.id ?? null,
      status: reconciliation?.status ?? "none",
      reconciliationMode: reconciliation?.reconciliation_mode ?? "simple",
      unavailableReason,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: null,
      calculatedBalanceInCents: null,
      difference: null,
      differenceInCents: null,
      validatedAt: null,
      outstandingDebits: null,
      outstandingCredits: null,
      explainedBankBalance: null,
      residualDifference: null,
      outstandingCount: null,
    };
  }

  if (!reconciliation) {
    return {
      reconciliationId: null,
      status: "none",
      reconciliationMode: "simple",
      unavailableReason: null,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: null,
      calculatedBalanceInCents: null,
      difference: null,
      differenceInCents: null,
      validatedAt: null,
      outstandingDebits: null,
      outstandingCredits: null,
      explainedBankBalance: null,
      residualDifference: null,
      outstandingCount: null,
    };
  }

  if (reconciliation.reconciliation_mode === "complete") {
    const summary = await getDetailedSummary(reconciliation.id);
    const simpleDifference = calculateReconciliationDifference(statement.statement_balance!, Math.round(summary.calculated_balance * 100));
    return {
      reconciliationId: reconciliation.id,
      status: "draft",
      reconciliationMode: "complete",
      unavailableReason: null,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: summary.calculated_balance,
      calculatedBalanceInCents: Math.round(summary.calculated_balance * 100),
      difference: simpleDifference.difference,
      differenceInCents: simpleDifference.differenceInCents,
      validatedAt: null,
      outstandingDebits: summary.outstanding_debits,
      outstandingCredits: summary.outstanding_credits,
      explainedBankBalance: summary.explained_bank_balance,
      residualDifference: summary.residual_difference,
      outstandingCount: summary.outstanding_count,
    };
  }

  const calculated = await getAccountBalanceAtDate(protectedPersonId, account.id, statement.statement_end_date);
  const difference = calculateReconciliationDifference(statement.statement_balance!, calculated.balanceInCents);
  return {
    reconciliationId: reconciliation.id,
    status: "draft",
    reconciliationMode: "simple",
    unavailableReason: null,
    statementEndDate: statement.statement_end_date,
    statementBalance: difference.statementBalance,
    calculatedBalance: calculated.balance,
    calculatedBalanceInCents: calculated.balanceInCents,
    difference: difference.difference,
    differenceInCents: difference.differenceInCents,
    validatedAt: null,
    outstandingDebits: null,
    outstandingCredits: null,
    explainedBankBalance: null,
    residualDifference: null,
    outstandingCount: null,
  };
}

export async function createBankReconciliationDraft(statement: BankStatement, account: FinancialAccount) {
  const unavailableReason = getReconciliationUnavailableReason(statement, account);
  if (unavailableReason) throw new BankReconciliationServiceError("Ce relevé ne peut pas être contrôlé.", 409);

  const existing = await getBankReconciliation(statement.id);
  if (existing) return existing;

  const { supabase, userId } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("bank_reconciliations")
    .insert({ bank_statement_id: statement.id, created_by: userId })
    .select("*")
    .single();
  if (!error) return data;
  if (error.code === "23505") {
    const concurrent = await getBankReconciliation(statement.id);
    if (concurrent) return concurrent;
  }
  throw new BankReconciliationServiceError("Impossible de créer le contrôle bancaire.", 500);
}

export async function validateBankReconciliation(reconciliationId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.rpc("validate_bank_reconciliation", {
    p_reconciliation_id: reconciliationId,
  });
  if (error || !data) throw new BankReconciliationServiceError("Impossible de valider le contrôle bancaire.", 409);
  return data;
}

async function getDetailedSummary(reconciliationId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.rpc("get_bank_reconciliation_detailed_summary", {
    p_reconciliation_id: reconciliationId,
  }).single();
  if (error || !data) throw new BankReconciliationServiceError("Impossible de calculer le rapprochement détaillé.", 500);
  return data;
}

export async function activateCompleteBankReconciliation(reconciliationId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.rpc("activate_complete_bank_reconciliation", {
    p_reconciliation_id: reconciliationId,
  });
  if (error || !data) throw new BankReconciliationServiceError("Impossible d’activer le rapprochement détaillé.", 409);
  return data;
}

export async function setOutstandingTransaction(reconciliationId: string, transactionId: string, outstanding: boolean) {
  const { supabase } = await getAuthenticatedUser();
  const result = outstanding
    ? await supabase.rpc("add_bank_reconciliation_outstanding_transaction", {
        p_reconciliation_id: reconciliationId,
        p_transaction_id: transactionId,
      })
    : await supabase.rpc("remove_bank_reconciliation_outstanding_transaction", {
        p_reconciliation_id: reconciliationId,
        p_transaction_id: transactionId,
      });
  if (result.error) throw new BankReconciliationServiceError("Impossible de modifier l’opération en circulation.", 409);
}

type CursorValue = { date: string; createdAt: string; id: string };

function decodeCursor(cursor: string | null): CursorValue | null {
  if (!cursor) return null;
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as Partial<CursorValue>;
    if (typeof parsed.date !== "string" || typeof parsed.createdAt !== "string" || typeof parsed.id !== "string") return null;
    return { date: parsed.date, createdAt: parsed.createdAt, id: parsed.id };
  } catch {
    return null;
  }
}

function encodeCursor(item: OutstandingTransactionCandidate) {
  return Buffer.from(JSON.stringify({ date: item.transactionDate, createdAt: item.transactionCreatedAt, id: item.transactionId })).toString("base64url");
}

export async function getOutstandingTransactionPage(reconciliationId: string, cursor: string | null): Promise<OutstandingTransactionPage> {
  const { supabase } = await getAuthenticatedUser();
  const after = decodeCursor(cursor);
  if (cursor && !after) throw new BankReconciliationServiceError("Curseur de pagination invalide.", 400);
  const [candidatesResult, summaryResult] = await Promise.all([
    supabase.rpc("list_bank_reconciliation_candidate_transactions", {
      p_reconciliation_id: reconciliationId,
      p_after_date: after?.date ?? null,
      p_after_created_at: after?.createdAt ?? null,
      p_after_id: after?.id ?? null,
      p_limit: OUTSTANDING_TRANSACTION_PAGE_SIZE + 1,
    }),
    supabase.rpc("get_bank_reconciliation_detailed_summary", { p_reconciliation_id: reconciliationId }).single(),
  ]);
  if (candidatesResult.error || summaryResult.error || !summaryResult.data) {
    throw new BankReconciliationServiceError("Impossible de charger les opérations en circulation.", 500);
  }
  const candidates = (candidatesResult.data ?? []).map((item) => ({
    transactionId: item.transaction_id,
    transactionDate: item.transaction_date,
    transactionCreatedAt: item.transaction_created_at,
    transactionType: item.transaction_type,
    label: item.label,
    amount: item.amount,
    isOutstanding: item.is_outstanding,
    carriedFromPrevious: item.carried_from_previous,
  }));
  const hasMore = candidates.length > OUTSTANDING_TRANSACTION_PAGE_SIZE;
  const items = candidates.slice(0, OUTSTANDING_TRANSACTION_PAGE_SIZE);
  return {
    items,
    nextCursor: hasMore && items.length ? encodeCursor(items.at(-1)!) : null,
    summary: {
      calculatedBalance: summaryResult.data.calculated_balance,
      outstandingDebits: summaryResult.data.outstanding_debits,
      outstandingCredits: summaryResult.data.outstanding_credits,
      explainedBankBalance: summaryResult.data.explained_bank_balance,
      residualDifference: summaryResult.data.residual_difference,
      outstandingCount: summaryResult.data.outstanding_count,
    },
  };
}
