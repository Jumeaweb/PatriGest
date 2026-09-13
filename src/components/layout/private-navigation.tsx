"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { ArrowLeftRight, CalendarRange, ClipboardList, FolderCog, FolderOpen, History, LayoutDashboard, LayoutGrid, LogOut, Menu, Settings, ShieldCheck, UserRound, Users, WalletCards, X, type LucideIcon } from "lucide-react";
import { logoutAction } from "@/app/(auth)/actions";
import { APP_NAME, APP_VERSION } from "@/lib/app";

export type PrivateSection = "dashboard" | "dossiers" | "dossier-management" | "settings" | "account" | "administration" | "administration-requests" | "administration-users" | "history";
export type DossierSection = "dashboard" | "overview" | "accounts" | "operations" | "periods" | "access" | "properties" | "debts" | "reports";
export type PrivateDossierContext = { id: string; name: string; current: DossierSection; accessRole?: "owner" | "manager" | "read_only" };
type NavigationItem = { label: string; href: string; icon: LucideIcon; active: boolean };

export function PrivateNavigation({ current, dossier, isPlatformAdmin = false }: { current: PrivateSection; dossier?: PrivateDossierContext; isPlatformAdmin?: boolean }) {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const drawerRef = useRef<HTMLElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const principal: NavigationItem[] = isPlatformAdmin ? [
    { label: "Tableau de bord", href: "/tableau-de-bord", icon: LayoutDashboard, active: current === "dashboard" || current === "administration" },
    { label: "Inscriptions à valider", href: "/administration/demandes", icon: ShieldCheck, active: current === "administration-requests" },
    { label: "Comptes utilisateurs", href: "/administration/utilisateurs", icon: Users, active: current === "administration-users" },
  ] : [
    { label: "Tableau de bord", href: "/tableau-de-bord", icon: LayoutDashboard, active: current === "dashboard" },
    { label: "Dossiers", href: "/dossiers", icon: FolderOpen, active: current === "dossiers" && !dossier },
    { label: "Gérer les dossiers", href: "/dossiers/gestion", icon: FolderCog, active: current === "dossier-management" },
  ];
  const dossierItems: NavigationItem[] = dossier ? [
    { label: "Tableau de bord", href: `/dossiers/${dossier.id}/tableau-de-bord`, icon: LayoutDashboard, active: dossier.current === "dashboard" },
    { label: "Comptes et patrimoine", href: `/dossiers/${dossier.id}/comptes`, icon: WalletCards, active: dossier.current === "accounts" },
    { label: "Opérations", href: `/dossiers/${dossier.id}/operations`, icon: ArrowLeftRight, active: dossier.current === "operations" },
    { label: "Exercices de gestion", href: `/dossiers/${dossier.id}/exercices`, icon: CalendarRange, active: dossier.current === "periods" },
    { label: "Comptes de gestion", href: `/dossiers/${dossier.id}/comptes-de-gestion`, icon: ClipboardList, active: dossier.current === "reports" },
    { label: "Informations du dossier", href: `/dossiers/${dossier.id}`, icon: LayoutGrid, active: dossier.current === "overview" },
    ...(dossier.accessRole === "owner" || dossier.accessRole === "manager" ? [{ label: "Accès au dossier", href: `/dossiers/${dossier.id}/acces`, icon: Users, active: dossier.current === "access" }] : []),
  ] : [];
  const settings: NavigationItem[] = isPlatformAdmin ? [] : [{ label: "Catégories", href: "/parametres/categories", icon: Settings, active: current === "settings" }];

  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") { setOpen(false); triggerRef.current?.focus(); return; }
      if (event.key !== "Tab") return;
      const focusable = drawerRef.current?.querySelectorAll<HTMLElement>('a[href], button:not([disabled])');
      if (!focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => { document.body.style.overflow = previousOverflow; document.removeEventListener("keydown", handleKeyDown); };
  }, [open]);

  const navigation = <NavigationContent current={current} principal={principal} principalLabel={isPlatformAdmin ? "Administration" : "Principal"} dossier={isPlatformAdmin ? undefined : dossier} dossierItems={isPlatformAdmin ? [] : dossierItems} settings={settings} onNavigate={() => setOpen(false)} />;
  return <>
    <aside className="sticky top-0 hidden h-screen w-[248px] shrink-0 flex-col overflow-y-auto border-r border-[#E2E8F0] bg-white lg:flex" aria-label="Navigation privée">{navigation}</aside>
    <header className="sticky top-0 z-30 flex h-16 items-center justify-between border-b border-[#E2E8F0] bg-white px-5 lg:hidden">
      <button ref={triggerRef} type="button" className="focus-ring -ml-2 flex size-10 items-center justify-center rounded-xl text-[#334155] hover:bg-slate-100" aria-label="Ouvrir le menu" aria-expanded={open} aria-controls="mobile-private-navigation" onClick={() => setOpen(true)}><Menu aria-hidden="true" size={22} /></button>
      <Link href="/tableau-de-bord" className="focus-ring flex items-center gap-2 rounded-lg font-bold"><ShieldCheck aria-hidden="true" className="text-[#2563EB]" size={21} />{APP_NAME}</Link>
      <span className="size-10" aria-hidden="true" />
    </header>
    {open && <div className="fixed inset-0 z-50 lg:hidden">
      <button type="button" className="absolute inset-0 bg-slate-950/40" aria-label="Fermer le menu" onClick={() => setOpen(false)} />
      <aside ref={drawerRef} id="mobile-private-navigation" role="dialog" aria-modal="true" aria-label="Menu de navigation" className="relative flex h-full w-[min(86vw,320px)] flex-col overflow-y-auto bg-white shadow-2xl">
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-[#E2E8F0] px-5"><span className="flex items-center gap-2 font-bold"><ShieldCheck aria-hidden="true" className="text-[#2563EB]" size={21} />{APP_NAME}</span><button ref={closeRef} type="button" className="focus-ring flex size-10 items-center justify-center rounded-xl text-[#64748B] hover:bg-slate-100" aria-label="Fermer le menu" onClick={() => setOpen(false)}><X aria-hidden="true" size={21} /></button></div>
        {navigation}
      </aside>
    </div>}
  </>;
}

function NavigationContent({ current, principal, principalLabel, dossier, dossierItems, settings, onNavigate }: { current: PrivateSection; principal: NavigationItem[]; principalLabel: string; dossier?: PrivateDossierContext; dossierItems: NavigationItem[]; settings: NavigationItem[]; onNavigate: () => void }) {
  return <div className="flex min-h-full flex-1 flex-col px-4 py-5">
    <Link href="/tableau-de-bord" onClick={onNavigate} className="focus-ring mb-7 flex items-center gap-3 rounded-xl px-2"><span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-[#2563EB] text-white"><ShieldCheck aria-hidden="true" size={20} /></span><span className="min-w-0"><span className="block font-bold leading-tight">{APP_NAME}</span><span className="block text-xs text-[#94A3B8]">v{APP_VERSION}</span></span></Link>
    <NavigationGroup label={principalLabel} items={principal} onNavigate={onNavigate} />
    {dossier && <div className="mt-7 min-w-0"><p className="px-3 text-xs font-bold uppercase tracking-[0.12em] text-[#94A3B8]">Dossier en cours</p><p className="mt-2 truncate px-3 text-sm font-bold text-[#334155]" title={dossier.name}>{dossier.name}</p><div className="mt-2 space-y-1"><NavigationLinks items={dossierItems} onNavigate={onNavigate} /></div></div>}
    {settings.length > 0 && <div className="mt-7"><NavigationGroup label="Paramètres" items={settings} onNavigate={onNavigate} /></div>}
    <div className="mt-auto space-y-1 border-t border-[#E2E8F0] pt-4"><NavigationLinks items={[{ label: "Mon compte", href: "/parametres/compte", icon: UserRound, active: current === "account" }, { label: "Historique des versions", href: "/historique-versions", icon: History, active: current === "history" }]} onNavigate={onNavigate} /><form action={logoutAction}><button type="submit" className="focus-ring flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm font-semibold text-[#64748B] transition-colors hover:bg-slate-50 hover:text-[#0F172A]"><LogOut aria-hidden="true" size={18} />Déconnexion</button></form><Link href="/historique-versions" onClick={onNavigate} className="focus-ring ml-3 inline-block rounded text-xs text-[#94A3B8] hover:text-[#64748B]">{APP_NAME} v{APP_VERSION}</Link></div>
  </div>;
}

function NavigationGroup({ label, items, onNavigate }: { label: string; items: NavigationItem[]; onNavigate: () => void }) { return <div><p className="px-3 text-xs font-bold uppercase tracking-[0.12em] text-[#94A3B8]">{label}</p><div className="mt-2 space-y-1"><NavigationLinks items={items} onNavigate={onNavigate} /></div></div>; }
function NavigationLinks({ items, onNavigate }: { items: NavigationItem[]; onNavigate: () => void }) { return items.map((item) => { const Icon = item.icon; return <Link key={item.href} href={item.href} onClick={onNavigate} aria-current={item.active ? "page" : undefined} className={`focus-ring flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-colors ${item.active ? "bg-blue-50 text-[#2563EB]" : "text-[#64748B] hover:bg-slate-50 hover:text-[#0F172A]"}`}><Icon aria-hidden="true" size={18} />{item.label}</Link>; }); }
