import Link from "next/link";
import { getAccessPageHref, type AccessPageQuery } from "../access-pagination";

export function AccessTabs({
  pathname,
  values,
  current,
}: {
  pathname: string;
  values: AccessPageQuery;
  current: "invite" | "collaborators";
}) {
  const items = [
    { key: "invite" as const, label: "Inviter un collaborateur" },
    { key: "collaborators" as const, label: "Collaborateurs" },
  ];

  return (
    <nav aria-label="Navigation du partage" className="mt-4 overflow-x-auto border-b border-[#E2E8F0]">
      <div className="flex min-w-max gap-1">
        {items.map((item) => (
          <Link
            key={item.key}
            href={getAccessPageHref(pathname, values, { view: item.key })}
            aria-current={current === item.key ? "page" : undefined}
            className={`focus-ring rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${current === item.key ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
          >
            {item.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
