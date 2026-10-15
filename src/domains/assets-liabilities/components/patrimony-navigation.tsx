import Link from "next/link";
import { HorizontalNavigationScroll } from "@/components/ui/horizontal-navigation-scroll";
import {
  getPatrimonyNavigationItems,
  type PatrimonyNavigationCurrent,
} from "../patrimony-navigation-links";

export function PatrimonyNavigation({
  protectedPersonId,
  current,
}: {
  protectedPersonId: string;
  current: PatrimonyNavigationCurrent;
}) {
  const items = getPatrimonyNavigationItems(protectedPersonId, current);

  return <nav aria-label="Navigation patrimoniale" className="mt-4 sm:border-b sm:border-[#E2E8F0]">
    <HorizontalNavigationScroll activeKey={current}>
      <div className="flex min-w-max gap-1">
        {items.map((item) => <Link
          key={item.href}
          href={item.href}
          aria-current={item.active ? "page" : undefined}
          className={`focus-ring flex min-h-11 shrink-0 items-center whitespace-nowrap rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${item.active ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
        >{item.label}</Link>)}
      </div>
    </HorizontalNavigationScroll>
  </nav>;
}
