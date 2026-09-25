import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Check, History } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { PublicFooter } from "@/components/marketing/public-footer";
import { PublicHeader } from "@/components/marketing/public-header";
import { getReleaseHistoryPage, parseReleaseHistoryPage } from "@/components/releases/release-history-page";
import { ReleaseHistoryPagination } from "@/components/releases/release-history-pagination";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { APP_NAME, APP_VERSION } from "@/lib/app";
import { APP_RELEASES, type AppRelease } from "@/lib/releases";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Historique des versions" };
export const dynamic = "force-dynamic";

const dateFormatter = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" });

export default async function ReleaseHistoryPage({ searchParams }: { searchParams: Promise<{ page?: string | string[] }> }) {
  const query = await searchParams;
  const releasePage = getReleaseHistoryPage(APP_RELEASES, parseReleaseHistoryPage(query.page));
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();
  const authenticated = !error && Boolean(data?.claims?.sub);

  if (authenticated) {
    return <PrivateShell current="history"><div className="mx-auto max-w-4xl"><AppBreadcrumb items={[{ label: "Tableau de bord", href: "/tableau-de-bord" }, { label: "Historique des versions" }]} /><ReleaseHistoryContent returnHref="/tableau-de-bord" returnLabel="Retour au tableau de bord" releases={releasePage.items} page={releasePage.page} totalPages={releasePage.totalPages} /></div></PrivateShell>;
  }

  return <div className="min-h-screen bg-brand-background text-brand-foreground"><PublicHeader /><main className="mx-auto max-w-4xl px-5 py-8 sm:px-8 sm:py-10"><ReleaseHistoryContent returnHref="/" returnLabel="Retour à l’accueil" releases={releasePage.items} page={releasePage.page} totalPages={releasePage.totalPages} /></main><PublicFooter /></div>;
}

function ReleaseHistoryContent({ returnHref, returnLabel, releases, page, totalPages }: { returnHref: string; returnLabel: string; releases: readonly AppRelease[]; page: number; totalPages: number }) {
  return <><Link href={returnHref} className="focus-ring inline-flex items-center gap-1.5 rounded-lg text-xs font-semibold text-[#64748B] hover:text-[#2563EB]"><ArrowLeft aria-hidden="true" size={15} />{returnLabel}</Link><div className="mt-5"><div className="flex size-9 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><History aria-hidden="true" size={18} /></div><h1 className="mt-3 text-[22px] leading-7 font-bold tracking-tight sm:text-2xl sm:leading-[30px]">Historique des versions</h1><p className="mt-1 text-sm text-[#64748B]">Découvrez les nouveautés et évolutions de {APP_NAME}.</p></div><ReleaseHistoryPagination page={page} totalPages={totalPages} /><div className="mt-6 space-y-4">{releases.map((release) => <article key={release.version} className="rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_6px_18px_rgba(15,23,42,0.035)] sm:p-5"><div className="flex flex-wrap items-center gap-2"><span className="text-xs font-bold text-[#2563EB]">v{release.version}</span>{release.version === APP_VERSION && <span className="rounded-full bg-green-50 px-2 py-0.5 text-[10px] font-bold text-[#15803D]">Version actuelle</span>}<time dateTime={release.date} className="text-[11px] text-[#94A3B8]">{dateFormatter.format(new Date(`${release.date}T00:00:00Z`))}</time></div><h2 className="mt-2 text-lg font-bold">{release.title}</h2><p className="mt-1.5 text-sm leading-6 text-[#64748B]">{release.summary}</p><ul className="mt-3 grid gap-x-4 gap-y-1.5 sm:grid-cols-2">{release.changes.map((change) => <li key={change} className="flex gap-1.5 text-xs leading-5 text-[#475569]"><Check aria-hidden="true" className="mt-0.5 shrink-0 text-[#16A34A]" size={14} /><span>{change}</span></li>)}</ul></article>)}</div><ReleaseHistoryPagination page={page} totalPages={totalPages} /></>;
}
