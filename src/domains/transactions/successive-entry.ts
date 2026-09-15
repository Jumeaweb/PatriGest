import type { FinancialAccount, Transaction } from "@/types/database";
import { isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
export { nextSuccessiveDraft } from "./successive-draft";
export type { SuccessiveDraft } from "./successive-draft";

export type CreatedSuccessiveTransaction = Pick<Transaction, "id" | "transaction_type" | "transaction_date" | "label" | "amount" | "financial_account_id" | "proof_reference">;
export type SuccessiveActionState = { status: "idle" | "error" | "success"; message: string; fieldErrors?: Record<string, string[]>; created?: CreatedSuccessiveTransaction };
export const initialSuccessiveActionState: SuccessiveActionState = { status: "idle", message: "" };

export function isSuccessiveAccountEligible(account: Pick<FinancialAccount, "status" | "account_type">) {
  return account.status === "active" && !isValuationAccount(account.account_type);
}
