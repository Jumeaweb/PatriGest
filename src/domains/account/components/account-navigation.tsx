import { Mail, ShieldCheck, Trash2, UserRound } from "lucide-react";
import Link from "next/link";
import { ACCOUNT_VIEW_ITEMS, getAccountViewHref, type AccountView } from "../account-navigation";

const ICONS = {
  profile: UserRound,
  email: Mail,
  security: ShieldCheck,
  deletion: Trash2,
} satisfies Record<AccountView, typeof UserRound>;

export function AccountNavigation({ current }: { current: AccountView }) {
  return (
    <nav aria-label="Navigation de mon compte" className="mt-5 overflow-x-auto border-b border-[#E2E8F0]">
      <div className="flex min-w-max gap-1">
        {ACCOUNT_VIEW_ITEMS.map((item) => {
          const Icon = ICONS[item.key];
          const active = current === item.key;
          return (
            <Link
              key={item.key}
              href={getAccountViewHref(item.key)}
              aria-current={active ? "page" : undefined}
              className={`focus-ring flex items-center gap-2 rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold transition-colors ${active ? "border-brand-accent bg-brand-navigation text-brand-foreground" : "border-transparent bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}
            >
              <Icon aria-hidden="true" size={17} />
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
