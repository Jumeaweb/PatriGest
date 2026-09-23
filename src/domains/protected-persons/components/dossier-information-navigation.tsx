import Link from "next/link";

export type DossierInformationView = "person" | "assets" | "management" | "deletion";

export function DossierInformationNavigation({
  protectedPersonId,
  current,
  canDelete,
}: {
  protectedPersonId: string;
  current: DossierInformationView;
  canDelete: boolean;
}) {
  const baseHref = `/dossiers/${protectedPersonId}`;
  const items = [
    { key: "person", label: "Personne protégée", href: baseHref },
    { key: "assets", label: "Situation patrimoniale", href: `${baseHref}?vue=patrimoine` },
    { key: "management", label: "Gestion", href: `${baseHref}?vue=gestion` },
    ...(canDelete ? [{ key: "deletion", label: "Suppression du dossier", href: `${baseHref}?vue=suppression` }] : []),
  ] as const;

  return <nav aria-label="Informations du dossier" className="mt-5 overflow-x-auto border-b border-[#E2E8F0]">
    <div className="flex min-w-max gap-1">
      {items.map((item) => <Link
        key={item.key}
        href={item.href}
        aria-current={current === item.key ? "page" : undefined}
        className={`focus-ring rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${current === item.key ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
      >{item.label}</Link>)}
    </div>
  </nav>;
}
