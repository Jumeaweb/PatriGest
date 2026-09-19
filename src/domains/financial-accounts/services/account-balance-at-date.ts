import type { FinancialAccount, Transaction, TransactionType } from "@/types/database";

export type AccountBalanceAtDateResult = {
  balance: number;
  balanceInCents: number;
};

type BalanceTransaction = Pick<Transaction, "amount" | "transaction_date" | "transaction_type">;
type AccountBalanceContext = Pick<FinancialAccount, "closing_date" | "initial_balance_date" | "opening_date" | "protected_person_id">;
type AccountBalanceDates = Omit<AccountBalanceContext, "protected_person_id">;

const creditTransactionTypes = new Set<TransactionType>(["income", "transfer_in"]);

function toCents(value: number) {
  const cents = Math.round(value * 100);
  if (!Number.isFinite(value) || !Number.isSafeInteger(cents)) {
    throw new Error("Montant hors limites pour le calcul du solde.");
  }
  return cents;
}

function isValidIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export function getMinimumAccountBalanceDate(account: AccountBalanceDates) {
  return account.opening_date && account.opening_date > account.initial_balance_date
    ? account.opening_date
    : account.initial_balance_date;
}

export function validateAccountBalanceDate(account: AccountBalanceDates, date: string) {
  if (!isValidIsoDate(date)) throw new Error("Date de solde invalide.");
  if (date < getMinimumAccountBalanceDate(account)) {
    throw new Error("La date de solde est antérieure au début du compte.");
  }
  if (account.closing_date && date > account.closing_date) {
    throw new Error("La date de solde est postérieure à la clôture du compte.");
  }
}

export function validateAccountBalanceContext(account: AccountBalanceContext, protectedPersonId: string) {
  if (account.protected_person_id !== protectedPersonId) throw new Error("Compte introuvable.");
}

export function calculateAccountBalanceAtDate(
  initialBalance: number,
  transactions: readonly BalanceTransaction[],
  date: string,
): AccountBalanceAtDateResult {
  let balanceInCents = toCents(initialBalance);

  for (const transaction of transactions) {
    if (transaction.transaction_date > date) continue;
    const amountInCents = toCents(transaction.amount);
    const signedAmount = creditTransactionTypes.has(transaction.transaction_type)
      ? amountInCents
      : -amountInCents;
    const nextBalance = balanceInCents + signedAmount;
    if (!Number.isSafeInteger(nextBalance)) {
      throw new Error("Solde hors limites pour un calcul monétaire exact.");
    }
    balanceInCents = nextBalance;
  }

  return { balance: balanceInCents / 100, balanceInCents };
}
