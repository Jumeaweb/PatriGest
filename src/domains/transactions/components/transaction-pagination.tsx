import Link from "next/link";
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
    <nav className="mt-4 flex items-center justify-center gap-3 text-sm" aria-label="Pagination des opérations">
      {page > 1 ? (
        <Link className="button button-secondary min-h-9 px-3 text-xs" href={getTransactionJournalPageHref(pathname, values, page - 1)}>
          Précédent
        </Link>
      ) : (
        <span className="button button-secondary min-h-9 cursor-not-allowed px-3 text-xs opacity-50" aria-disabled="true">
          Précédent
        </span>
      )}
      <span className="font-semibold text-[#475569]" aria-current="page">
        Page {page} sur {totalPages}
      </span>
      {page < totalPages ? (
        <Link className="button button-secondary min-h-9 px-3 text-xs" href={getTransactionJournalPageHref(pathname, values, page + 1)}>
          Suivant
        </Link>
      ) : (
        <span className="button button-secondary min-h-9 cursor-not-allowed px-3 text-xs opacity-50" aria-disabled="true">
          Suivant
        </span>
      )}
    </nav>
  );
}
