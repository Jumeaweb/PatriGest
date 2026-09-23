import Link from "next/link";
import type { ReactNode } from "react";
import {
  getBankStatementPageHref,
  type BankStatementQuery,
} from "../bank-statement-pagination";

export function BankStatementPagination({
  pathname,
  values,
  page,
  totalPages,
}: {
  pathname: string;
  values: BankStatementQuery;
  page: number;
  totalPages: number;
}) {
  if (totalPages === 0) return null;

  return (
    <nav
      className="mt-3 flex flex-wrap items-center justify-center gap-1 text-sm"
      aria-label="Pagination des relevés bancaires"
    >
      <PageControl
        label="Première page"
        href={page > 1 ? getBankStatementPageHref(pathname, values, 1) : undefined}
      >
        |&lt;
      </PageControl>
      <PageControl
        label="Page précédente"
        href={page > 1 ? getBankStatementPageHref(pathname, values, page - 1) : undefined}
      >
        Précédent
      </PageControl>
      <span className="px-1 text-center font-semibold text-[#475569]" aria-current="page">
        Page {page} sur {totalPages}
      </span>
      <PageControl
        label="Page suivante"
        href={page < totalPages ? getBankStatementPageHref(pathname, values, page + 1) : undefined}
      >
        Suivant
      </PageControl>
      <PageControl
        label="Dernière page"
        href={page < totalPages ? getBankStatementPageHref(pathname, values, totalPages) : undefined}
      >
        &gt;|
      </PageControl>
    </nav>
  );
}

function PageControl({
  href,
  label,
  children,
}: {
  href?: string;
  label: string;
  children: ReactNode;
}) {
  const className = "button button-secondary min-h-9 px-2 text-xs";
  return href ? (
    <Link className={className} href={href} aria-label={label}>
      {children}
    </Link>
  ) : (
    <span
      className={`${className} cursor-not-allowed opacity-50`}
      aria-label={label}
      aria-disabled="true"
    >
      {children}
    </span>
  );
}
