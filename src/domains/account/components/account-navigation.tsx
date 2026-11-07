import { CreditCard, Database, FileText, Mail, ShieldCheck, Trash2, UserRound, XCircle } from "lucide-react";
import Link from "next/link";
import { HorizontalNavigationScroll } from "@/components/ui/horizontal-navigation-scroll";
import {
  ACCOUNT_PROFILE_VIEW_ITEMS,
  ACCOUNT_VIEW_ITEMS,
  getAccountSection,
  getAccountViewHref,
  type AccountProfileView,
  type AccountSection,
  type AccountView,
} from "../account-navigation";

const ICONS = {
  profile: UserRound,
  subscription: CreditCard,
  invoices: FileText,
  cancellation: XCircle,
  data: Database,
} satisfies Record<AccountSection, typeof UserRound>;

const PROFILE_ICONS = {
  profile: UserRound,
  email: Mail,
  security: ShieldCheck,
  deletion: Trash2,
} satisfies Record<AccountProfileView, typeof UserRound>;

export function AccountNavigation({ current, subscriptionOnly = false }: { current: AccountView; subscriptionOnly?: boolean }) {
  const currentSection = getAccountSection(current);
  const items = subscriptionOnly
    ? ACCOUNT_VIEW_ITEMS.filter((item) => item.key === "subscription")
    : ACCOUNT_VIEW_ITEMS;
  return (
    <nav aria-label="Navigation de mon compte" className="mt-5 border-b border-[#E2E8F0]">
      <HorizontalNavigationScroll activeKey={currentSection}>
        <div className="flex min-w-max gap-1">
          {items.map((item) => <AccountNavigationLink key={item.key} item={item} active={currentSection === item.key} Icon={ICONS[item.key]} />)}
        </div>
      </HorizontalNavigationScroll>
    </nav>
  );
}

export function AccountProfileNavigation({ current }: { current: AccountProfileView }) {
  return <nav aria-label="Réglages du profil" className="mt-4 border-b border-[#E2E8F0]">
    <HorizontalNavigationScroll activeKey={current}>
      <div className="flex min-w-max gap-1">
        {ACCOUNT_PROFILE_VIEW_ITEMS.map((item) => <AccountNavigationLink key={item.key} item={item} active={current === item.key} Icon={PROFILE_ICONS[item.key]} compact />)}
      </div>
    </HorizontalNavigationScroll>
  </nav>;
}

function AccountNavigationLink({ item, active, Icon, compact = false }: {
  item: { key: AccountView; label: string };
  active: boolean;
  Icon: typeof UserRound;
  compact?: boolean;
}) {
  return <Link
    href={getAccountViewHref(item.key)}
    aria-current={active ? "page" : undefined}
    className={`focus-ring flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap rounded-t-lg border-b-2 px-3 py-2.5 font-semibold transition-colors ${compact ? "text-xs sm:text-sm" : "text-sm"} ${active ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
  >
    <Icon aria-hidden="true" size={compact ? 15 : 17} />
    {item.label}
  </Link>;
}
