export const TRANSACTION_HISTORY_PAGE_SIZE = 500;
export const TRANSACTION_RELATION_BATCH_SIZE = 100;

type TransactionHistoryPage<T> = {
  data: T[] | null;
  error: unknown;
};

export async function loadCompleteTransactionHistory<T>(
  loadPage: (from: number, to: number) => PromiseLike<TransactionHistoryPage<T>>,
): Promise<T[]> {
  const rows: T[] = [];

  for (let from = 0; ; from += TRANSACTION_HISTORY_PAGE_SIZE) {
    const page = await loadPage(from, from + TRANSACTION_HISTORY_PAGE_SIZE - 1);
    if (page.error) throw page.error;
    const pageRows = page.data ?? [];
    rows.push(...pageRows);
    if (pageRows.length < TRANSACTION_HISTORY_PAGE_SIZE) return rows;
  }
}

export async function loadTransactionRelationsInBatches<T>(
  ids: readonly string[],
  loadBatch: (ids: readonly string[]) => PromiseLike<TransactionHistoryPage<T>>,
): Promise<T[]> {
  const rows: T[] = [];
  for (let index = 0; index < ids.length; index += TRANSACTION_RELATION_BATCH_SIZE) {
    const page = await loadBatch(ids.slice(index, index + TRANSACTION_RELATION_BATCH_SIZE));
    if (page.error) throw page.error;
    rows.push(...(page.data ?? []));
  }
  return rows;
}
