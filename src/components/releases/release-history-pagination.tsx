import { ChevronsLeft, ChevronsRight } from "lucide-react";
import Link from "next/link";
import { getReleaseHistoryPaginationTargets } from "./release-history-page";

export function ReleaseHistoryPagination({ page, totalPages }: { page: number; totalPages: number }) {
  if (totalPages <= 1) return null;
  const targets = getReleaseHistoryPaginationTargets(page, totalPages);

  return (
    <nav aria-label="Pagination de l’historique des versions" className="mt-4 flex flex-wrap items-center justify-center gap-2 text-sm">
      <PageControl href={targets.first} label="Première page">
        <ChevronsLeft aria-hidden="true" size={17} />
      </PageControl>
      <PageControl href={targets.previous} label="Page précédente">
        Précédent
      </PageControl>
      <span className="px-1 text-center font-semibold text-[#475569]" aria-current="page">Page {page} sur {totalPages}</span>
      <PageControl href={targets.next} label="Page suivante">
        Suivant
      </PageControl>
      <PageControl href={targets.last} label="Dernière page">
        <ChevronsRight aria-hidden="true" size={17} />
      </PageControl>
    </nav>
  );
}

function PageControl({ href, label, children }: { href?: string; label: string; children: React.ReactNode }) {
  const classes = "focus-ring inline-flex min-h-9 items-center justify-center rounded-lg border border-[#CBD5E1] bg-white px-3 font-semibold text-[#475569]";
  return href
    ? <Link className={`${classes} hover:border-brand-accent hover:text-brand-foreground`} href={href} aria-label={label}>{children}</Link>
    : <span className={`${classes} cursor-not-allowed opacity-45`} aria-label={label} aria-disabled="true">{children}</span>;
}
