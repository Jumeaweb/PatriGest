import Link from "next/link";
import type { ReactNode } from "react";
import { getTransactionJournalPageHref, type TransactionJournalQuery } from "../transaction-pagination";

export function TransactionPagination({
  pathname,
  values,
  page,
  totalPages,
}: {
  pathname: string;
  values: TransactionJournalQuery;
  page: number;
  totalPages: number;
}) {
  if (totalPages <= 1) return null;

  return (
    <nav className="mt-3 flex items-center justify-center gap-1 text-sm" aria-label="Pagination des opérations">
      <PageControl label="Première page" href={page > 1 ? getTransactionJournalPageHref(pathname, values, 1) : undefined}>|&lt;</PageControl>
      <PageControl label="Page précédente" href={page > 1 ? getTransactionJournalPageHref(pathname, values, page - 1) : undefined}>Précédent</PageControl>
      <span className="px-1 text-center font-semibold text-[#475569]" aria-current="page">
        Page {page} sur {totalPages}
      </span>
      <PageControl label="Page suivante" href={page < totalPages ? getTransactionJournalPageHref(pathname, values, page + 1) : undefined}>Suivant</PageControl>
      <PageControl label="Dernière page" href={page < totalPages ? getTransactionJournalPageHref(pathname, values, totalPages) : undefined}>&gt;|</PageControl>
    </nav>
  );
}

function PageControl({ href, label, children }: { href?: string; label: string; children: ReactNode }) {
  const className = "button button-secondary min-h-9 px-2 text-xs";
  return href ? (
    <Link className={className} href={href} aria-label={label}>{children}</Link>
  ) : (
    <span className={`${className} cursor-not-allowed opacity-50`} aria-label={label} aria-disabled="true">{children}</span>
  );
}
