import type { BankReconciliation, BankStatement, FinancialAccount } from "@/types/database";
import { getAccountBalanceAtDate } from "@/domains/financial-accounts/services/financial-account-service";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import {
  calculateReconciliationDifference,
  getReconciliationUnavailableReason,
  type ReconciliationUnavailableReason,
} from "./reconciliation-calculations";

const RECONCILIATION_QUERY_BATCH_SIZE = 100;

export type BankReconciliationListState = Pick<
  BankReconciliation,
  "id" | "bank_statement_id" | "status" | "calculated_balance" | "difference" | "validated_at"
>;

export type BankReconciliationControl = {
  reconciliationId: string | null;
  status: "none" | "draft" | "validated";
  unavailableReason: ReconciliationUnavailableReason | null;
  statementEndDate: string;
  statementBalance: number | null;
  calculatedBalance: number | null;
  calculatedBalanceInCents: number | null;
  difference: number | null;
  differenceInCents: number | null;
  validatedAt: string | null;
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
      .select("id, bank_statement_id, status, calculated_balance, difference, validated_at")
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
      unavailableReason: null,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: reconciliation.calculated_balance,
      calculatedBalanceInCents: reconciliation.calculated_balance === null ? null : Math.round(reconciliation.calculated_balance * 100),
      difference: reconciliation.difference,
      differenceInCents: reconciliation.difference === null ? null : Math.round(reconciliation.difference * 100),
      validatedAt: reconciliation.validated_at,
    };
  }

  const unavailableReason = getReconciliationUnavailableReason(statement, account);
  if (unavailableReason) {
    return {
      reconciliationId: reconciliation?.id ?? null,
      status: reconciliation?.status ?? "none",
      unavailableReason,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: null,
      calculatedBalanceInCents: null,
      difference: null,
      differenceInCents: null,
      validatedAt: null,
    };
  }

  if (!reconciliation) {
    return {
      reconciliationId: null,
      status: "none",
      unavailableReason: null,
      statementEndDate: statement.statement_end_date,
      statementBalance: statement.statement_balance,
      calculatedBalance: null,
      calculatedBalanceInCents: null,
      difference: null,
      differenceInCents: null,
      validatedAt: null,
    };
  }

  const calculated = await getAccountBalanceAtDate(protectedPersonId, account.id, statement.statement_end_date);
  const difference = calculateReconciliationDifference(statement.statement_balance!, calculated.balanceInCents);
  return {
    reconciliationId: reconciliation.id,
    status: "draft",
    unavailableReason: null,
    statementEndDate: statement.statement_end_date,
    statementBalance: difference.statementBalance,
    calculatedBalance: calculated.balance,
    calculatedBalanceInCents: calculated.balanceInCents,
    difference: difference.difference,
    differenceInCents: difference.differenceInCents,
    validatedAt: null,
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
