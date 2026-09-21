import Link from "next/link";
import { ClipboardList, LayoutDashboard, LayoutGrid, Users, WalletCards } from "lucide-react";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

export async function DossierNavigation({ protectedPersonId, current }: { protectedPersonId: string; current: "dashboard" | "overview" | "measure" | "accounts" | "operations" | "periods" | "properties" | "debts" | "reports" }) {
  const { supabase, userId } = await getAuthenticatedUser();
  const { data: person } = await supabase.from("protected_persons").select("owner_id").eq("id", protectedPersonId).maybeSingle();
  const { data: access } = person?.owner_id === userId
    ? { data: null }
    : await supabase.from("protected_person_access").select("role").eq("protected_person_id", protectedPersonId).eq("user_id", userId).maybeSingle();
  const accessRole = person?.owner_id === userId ? "owner" : access?.role;
  const items = [
    { key: "dashboard", label: "Tableau de bord", href: `/dossiers/${protectedPersonId}/tableau-de-bord`, icon: LayoutDashboard },
    { key: "accounts", label: "Gestion financière", href: `/dossiers/${protectedPersonId}/comptes`, icon: WalletCards },
    { key: "reports", label: "Comptes de gestion", href: `/dossiers/${protectedPersonId}/comptes-de-gestion`, icon: ClipboardList },
    { key: "overview", label: "Informations du dossier", href: `/dossiers/${protectedPersonId}`, icon: LayoutGrid },
    ...(accessRole === "owner" || accessRole === "manager" ? [{ key: "access", label: "Partage du dossier", href: `/dossiers/${protectedPersonId}/acces`, icon: Users }] : []),
  ] as const;
  return <nav className="mt-7 rounded-2xl border border-brand-accent/20 bg-brand-background/70 p-2 shadow-[0_6px_18px_rgba(15,23,42,0.04)] lg:hidden" aria-label="Navigation du dossier"><p className="px-2 pb-2 pt-1 text-xs font-bold uppercase tracking-[0.12em] text-brand-foreground/60">Dans ce dossier</p><div className="flex gap-2 overflow-x-auto pb-0.5">{items.map((item) => { const Icon = item.icon; const active = item.key === "accounts" ? current === "accounts" || current === "operations" : current === item.key; return <Link key={item.key} href={item.href} aria-current={active ? "page" : undefined} className={`focus-ring flex min-h-10 shrink-0 items-center gap-2 whitespace-nowrap rounded-xl px-3 py-2 text-sm font-semibold transition-colors ${active ? "bg-brand-navigation text-brand-foreground ring-1 ring-brand-accent/40" : "bg-transparent text-brand-foreground/75 hover:bg-brand-navigation/25 hover:text-brand-foreground"}`}><Icon aria-hidden="true" size={17} />{item.label}</Link>; })}</div></nav>;
}
