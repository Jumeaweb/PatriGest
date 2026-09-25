export const RELEASE_HISTORY_PAGE_SIZE = 10;

export function parseReleaseHistoryPage(value: string | string[] | undefined): number {
  const candidate = Array.isArray(value) ? value[0] : value;
  if (!candidate || !/^[1-9]\d*$/.test(candidate)) return 1;
  const page = Number(candidate);
  return Number.isSafeInteger(page) ? page : 1;
}

export function getReleaseHistoryPage<T>(items: readonly T[], requestedPage: number) {
  const totalCount = items.length;
  const totalPages = Math.ceil(totalCount / RELEASE_HISTORY_PAGE_SIZE);
  const page = totalPages > 0 ? Math.min(Math.max(1, requestedPage), totalPages) : 1;
  const start = (page - 1) * RELEASE_HISTORY_PAGE_SIZE;

  return {
    items: items.slice(start, start + RELEASE_HISTORY_PAGE_SIZE),
    page,
    pageSize: RELEASE_HISTORY_PAGE_SIZE,
    totalCount,
    totalPages,
  };
}

export function getReleaseHistoryPageHref(page: number): string {
  return `/historique-versions?page=${Math.max(1, page)}`;
}

export function getReleaseHistoryPaginationTargets(page: number, totalPages: number) {
  return {
    first: page > 1 ? getReleaseHistoryPageHref(1) : undefined,
    previous: page > 1 ? getReleaseHistoryPageHref(page - 1) : undefined,
    next: page < totalPages ? getReleaseHistoryPageHref(page + 1) : undefined,
    last: page < totalPages ? getReleaseHistoryPageHref(totalPages) : undefined,
  };
}
