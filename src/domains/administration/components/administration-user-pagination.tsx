import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight } from "lucide-react";
import Link from "next/link";
import { getAdministrationUsersPageHref } from "../administration-user-pagination";

export function AdministrationUserPagination({ page, totalPages }: { page: number; totalPages: number }) {
  const first = page <= 1;
  const last = page >= totalPages;
  return (
    <nav aria-label="Pagination des comptes utilisateurs" className="mt-4 flex flex-wrap items-center justify-center gap-2 text-sm">
      <PaginationLink href={getAdministrationUsersPageHref(1)} disabled={first} label="Première page"><ChevronsLeft aria-hidden="true" size={17} /></PaginationLink>
      <PaginationLink href={getAdministrationUsersPageHref(Math.max(1, page - 1))} disabled={first} label="Page précédente"><ChevronLeft aria-hidden="true" size={17} /><span>Précédent</span></PaginationLink>
      <span className="px-1 text-center font-semibold text-[#475569]" aria-current="page">Page {page} sur {totalPages}</span>
      <PaginationLink href={getAdministrationUsersPageHref(Math.min(totalPages, page + 1))} disabled={last} label="Page suivante"><span>Suivant</span><ChevronRight aria-hidden="true" size={17} /></PaginationLink>
      <PaginationLink href={getAdministrationUsersPageHref(totalPages)} disabled={last} label="Dernière page"><ChevronsRight aria-hidden="true" size={17} /></PaginationLink>
    </nav>
  );
}

function PaginationLink({ href, disabled, label, children }: { href: string; disabled: boolean; label: string; children: React.ReactNode }) {
  const classes = "focus-ring inline-flex min-h-9 items-center justify-center gap-1 rounded-lg border border-[#CBD5E1] bg-white px-2.5 font-semibold text-[#475569]";
  return disabled
    ? <span className={`${classes} cursor-not-allowed opacity-45`} aria-disabled="true" aria-label={label}>{children}</span>
    : <Link className={`${classes} hover:border-brand-accent hover:text-brand-foreground`} href={href} aria-label={label}>{children}</Link>;
}
