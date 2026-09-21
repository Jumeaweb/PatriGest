import Link from "next/link";
import {
  getFinancialNavigationItems,
  type FinancialNavigationCurrent,
} from "../financial-navigation-links";

export function FinancialNavigation({
  protectedPersonId,
  current,
  accountId,
}: {
  protectedPersonId: string;
  current: FinancialNavigationCurrent;
  accountId?: string;
}) {
  const items = getFinancialNavigationItems(protectedPersonId, current, accountId);
  return (
    <nav aria-label={accountId ? "Navigation du compte" : "Navigation financière"} className="mt-4 overflow-x-auto border-b border-[#E2E8F0]">
      <div className="flex min-w-max gap-1">
        {items.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            aria-current={item.active ? "page" : undefined}
            className={`focus-ring rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${item.active ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
          >
            {item.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
