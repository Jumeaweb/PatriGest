export const INVITATION_HISTORY_PAGE_SIZE = 10;

export type AccessPageQuery = Record<string, string | string[] | undefined>;

export function parseInvitationHistoryPage(value: string | string[] | undefined) {
  const candidate = Array.isArray(value) ? value[0] : value;
  if (!candidate || !/^[1-9]\d*$/.test(candidate)) return 1;
  const page = Number(candidate);
  return Number.isSafeInteger(page) ? page : 1;
}

export function getInvitationHistoryPageMetadata(totalCount: number, requestedPage: number) {
  const totalPages = Math.ceil(totalCount / INVITATION_HISTORY_PAGE_SIZE);
  return {
    page: totalPages > 0 ? Math.min(requestedPage, totalPages) : 1,
    pageSize: INVITATION_HISTORY_PAGE_SIZE,
    totalCount,
    totalPages,
  };
}

export function getAccessPageHref(
  pathname: string,
  values: AccessPageQuery,
  changes: { view?: "invite" | "collaborators"; historyPage?: number },
) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (key === "vue" || key === "historiquePage" || value === undefined) continue;
    for (const item of Array.isArray(value) ? value : [value]) {
      if (item) params.append(key, item);
    }
  }
  if (changes.view === "collaborators") params.set("vue", "collaborateurs");
  if ((changes.historyPage ?? 1) > 1) params.set("historiquePage", String(changes.historyPage));
  const query = params.toString();
  return `${pathname}${query ? `?${query}` : ""}`;
}
