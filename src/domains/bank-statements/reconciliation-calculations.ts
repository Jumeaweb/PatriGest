import type { BankReconciliation, BankStatement, FinancialAccount } from "@/types/database";

export type ReconciliationUnavailableReason = "missing_statement_balance" | "before_minimum_date" | "after_closing_date";

type ReconciliationAttentionStatement = Pick<BankStatement, "id" | "statement_balance" | "statement_end_date">;
type ReconciliationAttentionState = Pick<BankReconciliation, "bank_statement_id" | "status">;

export type BankReconciliationAttentionSummary = {
  pendingCount: number;
  differenceByStatementId: Record<string, number | null>;
  singlePending: { statementEndDate: string; difference: number | null } | null;
};

export function toMoneyCents(value: number) {
  const cents = Math.round(value * 100);
  if (!Number.isFinite(value) || !Number.isSafeInteger(cents)) {
    throw new Error("Montant hors limites pour le contrôle bancaire.");
  }
  return cents;
}

export function getReconciliationUnavailableReason(
  statement: Pick<BankStatement, "statement_balance" | "statement_end_date">,
  account: Pick<FinancialAccount, "closing_date" | "initial_balance_date" | "opening_date">,
): ReconciliationUnavailableReason | null {
  if (statement.statement_balance === null) return "missing_statement_balance";
  const minimumDate = account.opening_date && account.opening_date > account.initial_balance_date
    ? account.opening_date
    : account.initial_balance_date;
  if (statement.statement_end_date < minimumDate) return "before_minimum_date";
  if (account.closing_date && statement.statement_end_date > account.closing_date) return "after_closing_date";
  return null;
}

export function calculateReconciliationDifference(statementBalance: number, calculatedBalanceInCents: number) {
  const statementBalanceInCents = toMoneyCents(statementBalance);
  const differenceInCents = statementBalanceInCents - calculatedBalanceInCents;
  if (!Number.isSafeInteger(differenceInCents)) {
    throw new Error("Écart hors limites pour le contrôle bancaire.");
  }
  return {
    statementBalance: statementBalanceInCents / 100,
    statementBalanceInCents,
    difference: differenceInCents / 100,
    differenceInCents,
  };
}

export function calculateDetailedReconciliation(
  statementBalance: number,
  calculatedBalanceInCents: number,
  outstandingDebitsInCents: number,
  outstandingCreditsInCents: number,
) {
  const statementBalanceInCents = toMoneyCents(statementBalance);
  const explainedBalanceInCents = calculatedBalanceInCents
    + outstandingDebitsInCents
    - outstandingCreditsInCents;
  const residualDifferenceInCents = statementBalanceInCents - explainedBalanceInCents;
  if (![calculatedBalanceInCents, outstandingDebitsInCents, outstandingCreditsInCents, explainedBalanceInCents, residualDifferenceInCents].every(Number.isSafeInteger)) {
    throw new Error("Montant hors limites pour le rapprochement détaillé.");
  }
  return {
    calculatedBalance: calculatedBalanceInCents / 100,
    outstandingDebits: outstandingDebitsInCents / 100,
    outstandingCredits: outstandingCreditsInCents / 100,
    explainedBankBalance: explainedBalanceInCents / 100,
    residualDifference: residualDifferenceInCents / 100,
  };
}

export function buildBankReconciliationAttentionSummary(
  statements: readonly ReconciliationAttentionStatement[],
  reconciliations: readonly ReconciliationAttentionState[],
  getPendingDifference: (statement: ReconciliationAttentionStatement) => number | null,
): BankReconciliationAttentionSummary {
  const reconciliationByStatement = new Map(
    reconciliations.map((reconciliation) => [reconciliation.bank_statement_id, reconciliation]),
  );
  const pendingStatements = statements.filter(
    (statement) => reconciliationByStatement.get(statement.id)?.status !== "validated",
  );
  const differenceByStatementId: Record<string, number | null> = {};

  for (const statement of pendingStatements) {
    differenceByStatementId[statement.id] = getPendingDifference(statement);
  }

  const singlePendingStatement = pendingStatements.length === 1 ? pendingStatements[0] : null;
  return {
    pendingCount: pendingStatements.length,
    differenceByStatementId,
    singlePending: singlePendingStatement
      ? {
          statementEndDate: singlePendingStatement.statement_end_date,
          difference: differenceByStatementId[singlePendingStatement.id] ?? null,
        }
      : null,
  };
}
