import { z } from "zod";

const FILTER_KEYS = new Set(["start", "end", "account", "category", "type", "q", "page", "reportId", "classificationIssue"]);

export function getSafeTransactionReturnTo(personId: string, value: string | undefined, fallbackAccountId?: string) {
  const globalPath = `/dossiers/${personId}/operations`;
  const fallback = fallbackAccountId && z.uuid().safeParse(fallbackAccountId).success
    ? `/dossiers/${personId}/comptes/${fallbackAccountId}/operations`
    : globalPath;
  if (!value || !value.startsWith("/") || value.startsWith("//")) return fallback;

  let url: URL;
  try { url = new URL(value, "https://patrigest.internal"); }
  catch { return fallback; }
  if (url.origin !== "https://patrigest.internal") return fallback;

  const accountMatch = url.pathname.match(new RegExp(`^/dossiers/${personId}/comptes/([0-9a-f-]{36})/operations$`, "i"));
  const validPath = url.pathname === globalPath || Boolean(accountMatch && z.uuid().safeParse(accountMatch[1]).success);
  if (!validPath) return fallback;
  if ([...url.searchParams.keys()].some((key) => !FILTER_KEYS.has(key))) return fallback;
  const pages = url.searchParams.getAll("page");
  if (pages.length > 1 || pages.length === 1 && (!/^[1-9]\d*$/.test(pages[0]) || !Number.isSafeInteger(Number(pages[0])))) return fallback;
  const reportIds = url.searchParams.getAll("reportId");
  const issues = url.searchParams.getAll("classificationIssue");
  if (reportIds.length || issues.length) {
    if (url.pathname !== globalPath || reportIds.length !== 1 || issues.length !== 1
      || !z.uuid().safeParse(reportIds[0]).success
      || (issues[0] !== "unclassified" && issues[0] !== "needs_precision")
      || [...url.searchParams.keys()].some((key) => key !== "reportId" && key !== "classificationIssue")) return fallback;
  }
  return `${url.pathname}${url.search}`;
}

export function withTransactionReturnTo(href: string, returnTo: string) {
  const separator = href.includes("?") ? "&" : "?";
  return `${href}${separator}returnTo=${encodeURIComponent(returnTo)}`;
}
