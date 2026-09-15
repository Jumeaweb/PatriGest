import type { AccountValuation, FinancialAccount, FinancialAccountType, Transaction } from "@/types/database";
import { calculateClassicBalance } from "@/domains/transactions/utils/transaction-utils";
import { getCurrentValuationValue } from "./account-valuation-utils";

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
  const movements = transactions.length ? transactions : (account as FinancialAccount & { transactions?: Transaction[] }).transactions ?? [];
  if (!isValuationAccount(account.account_type)) return { value: calculateClassicBalance(account.initial_balance, movements), valuation: null };
  return getCurrentValuationValue(account.initial_balance, valuations);
}

export function getCurrentPatrimonyValue(accounts: Array<FinancialAccount & { valuations: AccountValuation[]; transactions: Transaction[] }>) {
  const activeAccounts = accounts.filter((account) => account.status === "active");
  const displayedValue = activeAccounts.reduce((total, account) => total + getCurrentAccountValue(account, account.valuations, account.transactions).value, 0);
  const accountById = new Map(activeAccounts.map((account) => [account.id, account]));
  const transferLegs = new Map<string, Transaction[]>();
  for (const account of activeAccounts) for (const transaction of account.transactions) if (transaction.transfer_id) transferLegs.set(transaction.transfer_id, [...(transferLegs.get(transaction.transfer_id) ?? []), transaction]);
  let placementTransferAdjustment = 0;
  for (const legs of transferLegs.values()) {
    if (legs.length !== 2) continue;
    const placementLeg = legs.find((leg) => isValuationAccount(accountById.get(leg.financial_account_id)?.account_type ?? "checking"));
    const classicLeg = legs.find((leg) => !isValuationAccount(accountById.get(leg.financial_account_id)?.account_type ?? "checking"));
    if (!placementLeg || !classicLeg) continue;
    const placement = accountById.get(placementLeg.financial_account_id)!;
    const latestValuationDate = placement.valuations.reduce<string | null>((latest, valuation) => !latest || valuation.valuation_date > latest ? valuation.valuation_date : latest, null);
    const baselineDate = latestValuationDate ?? placement.initial_balance_date;
    if (placementLeg.transaction_date <= baselineDate) continue;
    placementTransferAdjustment += placementLeg.transaction_type === "transfer_in" ? placementLeg.amount : -placementLeg.amount;
  }
  return displayedValue + placementTransferAdjustment;
}
