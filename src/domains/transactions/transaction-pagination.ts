export const TRANSACTION_JOURNAL_PAGE_SIZE = 50;

export function parseTransactionPage(value: string | undefined) {
  if (!value || !/^[1-9]\d*$/.test(value)) return 1;
  const page = Number(value);
  return Number.isSafeInteger(page) ? page : 1;
}

export function getTransactionPageMetadata(totalCount: number, requestedPage: number) {
  const totalPages = Math.ceil(totalCount / TRANSACTION_JOURNAL_PAGE_SIZE);
  return {
    page: totalPages > 0 ? Math.min(requestedPage, totalPages) : 1,
    pageSize: TRANSACTION_JOURNAL_PAGE_SIZE,
    totalCount,
    totalPages,
  };
}

export type TransactionJournalQuery = Record<string, string | undefined>;

export function getTransactionJournalPageHref(
  pathname: string,
  values: TransactionJournalQuery,
  page: number,
) {
  const params = new URLSearchParams(
    Object.entries(values).filter((entry): entry is [string, string] => Boolean(entry[1])),
  );
  if (page > 1) params.set("page", String(page));
  else params.delete("page");
  const query = params.toString();
  return `${pathname}${query ? `?${query}` : ""}`;
}
