export const TRANSACTION_DOCUMENT_BATCH_SIZE = 100;

export async function loadTransactionDocumentsInBatches<T>(
  transactionIds: readonly string[],
  loadBatch: (transactionIds: readonly string[]) => Promise<T[]>,
): Promise<T[]> {
  const documents: T[] = [];

  for (let index = 0; index < transactionIds.length; index += TRANSACTION_DOCUMENT_BATCH_SIZE) {
    const batch = transactionIds.slice(index, index + TRANSACTION_DOCUMENT_BATCH_SIZE);
    documents.push(...await loadBatch(batch));
  }

  return documents;
}
