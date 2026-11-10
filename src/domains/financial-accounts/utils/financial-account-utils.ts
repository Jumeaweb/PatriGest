import type { AccountValuation, FinancialAccount, FinancialAccountType, Transaction } from "@/types/database";
import { calculateClassicBalance } from "@/domains/transactions/utils/transaction-utils";
import { getCurrentValuationValue } from "./account-valuation-utils";
import { calculateValuationTransferAdjustment } from "./valuation-transfer-adjustment";

export const financialAccountLabels: Record<FinancialAccountType, string> = {
  checking: "Compte courant", livret_a: "Livret A", ldds: "LDDS", csl: "CSL", lep: "LEP",
  pel: "PEL", term_account: "Compte à terme", life_insurance: "Assurance-vie", other_investment: "Autre placement",
  securities_account: "Compte-titres",
};

export function isValuationAccount(type: FinancialAccountType) {
  return type === "life_insurance" || type === "other_investment" || type === "securities_account";
}

export function formatCurrency(value: number) {
  return new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);
}

export function formatFinancialDate(value: string) {
  return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

export function getCurrentAccountValue(account: FinancialAccount, valuations: AccountValuation[], transactions: Transaction[] = []) {
  const movements = (transactions.length ? transactions : (account as FinancialAccount & { transactions?: Transaction[] }).transactions ?? []).filter((transaction) => !transaction.cancelled_at);
  if (!isValuationAccount(account.account_type)) return { value: calculateClassicBalance(account.initial_balance, movements), valuation: null, transferAdjustment: 0 };
  const current = getCurrentValuationValue(account.initial_balance, valuations);
  const baselineDate = current.valuation?.valuation_date
    ?? (account.opening_date && account.opening_date > account.initial_balance_date ? account.opening_date : account.initial_balance_date);
  const transferAdjustment = calculateValuationTransferAdjustment(movements, baselineDate);
  return { ...current, value: current.value + transferAdjustment, transferAdjustment };
}

export function getCurrentPatrimonyValue(accounts: Array<FinancialAccount & { valuations: AccountValuation[]; transactions: Transaction[] }>) {
  return accounts
    .filter((account) => account.status === "active")
    .reduce((total, account) => total + getCurrentAccountValue(account, account.valuations, account.transactions).value, 0);
}
