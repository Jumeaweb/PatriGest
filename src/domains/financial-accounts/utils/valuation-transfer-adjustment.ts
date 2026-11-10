import type { Transaction } from "@/types/database";

type TransferMovement = Pick<
  Transaction,
  "amount" | "cancelled_at" | "transaction_date" | "transaction_type" | "transfer_id"
>;

export function calculateValuationTransferAdjustment(
  transactions: TransferMovement[],
  baselineDate: string,
) {
  return transactions.reduce((total, transaction) => {
    if (transaction.cancelled_at || !transaction.transfer_id || transaction.transaction_date <= baselineDate) return total;
    if (transaction.transaction_type === "transfer_in") return total + transaction.amount;
    if (transaction.transaction_type === "transfer_out") return total - transaction.amount;
    return total;
  }, 0);
}
