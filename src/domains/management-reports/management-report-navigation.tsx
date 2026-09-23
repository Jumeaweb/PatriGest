import Link from "next/link";

type ManagementReportNavigationCurrent = "reports" | "periods";

export function ManagementReportNavigation({
  protectedPersonId,
  current,
}: {
  protectedPersonId: string;
  current: ManagementReportNavigationCurrent;
}) {
  const items = [
    {
      key: "reports",
      label: "Comptes de gestion",
      href: `/dossiers/${protectedPersonId}/comptes-de-gestion`,
    },
    {
      key: "periods",
      label: "Exercices de gestion",
      href: `/dossiers/${protectedPersonId}/exercices`,
    },
  ] as const;

  return (
    <nav
      aria-label="Navigation des comptes et exercices de gestion"
      className="mt-4 overflow-x-auto border-b border-[#E2E8F0]"
    >
      <div className="flex min-w-max gap-1">
        {items.map((item) => {
          const active = item.key === current;
          return (
            <Link
              key={item.key}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={`focus-ring rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${active ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
            >
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
