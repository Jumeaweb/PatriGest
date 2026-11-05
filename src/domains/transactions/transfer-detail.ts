import type { TransactionJournalItem } from "./services/transaction-service";

export type UnifiedTransferDetail = {
  selectedMovement: TransactionJournalItem;
  sourceMovement: TransactionJournalItem;
  destinationMovement: TransactionJournalItem;
  transfer: NonNullable<TransactionJournalItem["transfer"]>;
};

export function resolveUnifiedTransferDetail(
  items: TransactionJournalItem[],
  transactionId: string,
): UnifiedTransferDetail | null {
  const selectedMovement = items.find((item) => item.id === transactionId);
  if (!selectedMovement?.transfer_id || !selectedMovement.transfer) return null;

  const { transfer } = selectedMovement;
  const sourceMovement = items.find((item) =>
    item.transfer_id === transfer.id
    && item.transaction_type === "transfer_out"
    && item.financial_account_id === transfer.source_account_id,
  );
  const destinationMovement = items.find((item) =>
    item.transfer_id === transfer.id
    && item.transaction_type === "transfer_in"
    && item.financial_account_id === transfer.destination_account_id,
  );
  if (!sourceMovement || !destinationMovement) return null;

  return { selectedMovement, sourceMovement, destinationMovement, transfer };
}
