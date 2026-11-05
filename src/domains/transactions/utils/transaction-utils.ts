import type { ManagementPeriod, Transaction, TransactionType } from "@/types/database";
export const transactionTypeLabels: Record<TransactionType, string> = { income: "Recette", expense: "Dépense", transfer_in: "Virement entrant", transfer_out: "Virement sortant" };
export function calculateClassicBalance(initialBalance: number, transactions: Transaction[]) { return transactions.reduce((balance, item) => item.cancelled_at ? balance : balance + (item.transaction_type === "income" || item.transaction_type === "transfer_in" ? item.amount : -item.amount), initialBalance); }

export function calculateRunningBalances(initialBalance: number, transactions: Transaction[]) {
  const ordered = [...transactions].sort((left, right) =>
    left.transaction_date.localeCompare(right.transaction_date)
    || left.created_at.localeCompare(right.created_at)
    || left.id.localeCompare(right.id),
  );
  let balance = initialBalance;
  return new Map(ordered.map((transaction) => {
    if (!transaction.cancelled_at) balance += transaction.transaction_type === "income" || transaction.transaction_type === "transfer_in" ? transaction.amount : -transaction.amount;
    return [transaction.id, balance] as const;
  }));
}

export function isDateInClosedPeriod(date: string, periods: ManagementPeriod[]) {
  return periods.some((period) => period.status === "closed" && date >= period.start_date && date <= period.end_date);
}

export function isRangeInClosedPeriod(startDate: string | undefined, endDate: string | undefined, periods: ManagementPeriod[]) {
  if (!startDate || !endDate || endDate < startDate) return false;
  return periods.some((period) => period.status === "closed" && startDate >= period.start_date && endDate <= period.end_date);
}
