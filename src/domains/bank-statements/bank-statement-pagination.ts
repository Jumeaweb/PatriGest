export const BANK_STATEMENT_PAGE_SIZE = 25;

export function parseBankStatementPage(value: string | string[] | undefined) {
  const candidate = Array.isArray(value) ? value[0] : value;
  if (!candidate || !/^[1-9]\d*$/.test(candidate)) return 1;
  const page = Number(candidate);
  return Number.isSafeInteger(page) ? page : 1;
}

export function getBankStatementPageMetadata(totalCount: number, requestedPage: number) {
  const totalPages = Math.ceil(totalCount / BANK_STATEMENT_PAGE_SIZE);
  return {
    page: totalPages > 0 ? Math.min(requestedPage, totalPages) : 1,
    pageSize: BANK_STATEMENT_PAGE_SIZE,
    totalCount,
    totalPages,
  };
}

export type BankStatementQuery = Record<string, string | string[] | undefined>;

export function getBankStatementPageHref(
  pathname: string,
  values: BankStatementQuery,
  page: number,
) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (key === "page" || value === undefined) continue;
    for (const item of Array.isArray(value) ? value : [value]) {
      if (item) params.append(key, item);
    }
  }
  if (page > 1) params.set("page", String(page));
  const query = params.toString();
  return `${pathname}${query ? `?${query}` : ""}`;
}
