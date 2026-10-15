import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { ArrowDownLeft, ArrowLeftRight, ArrowRight, ArrowUpRight, Building2, ClipboardList, Landmark, Scale, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getDossierDashboardData } from "@/domains/dashboard/services/dossier-dashboard-service";
import type { PatrimonyIncompleteReason, PatrimonySummaryComponent } from "@/domains/dashboard/patrimony-summary";
import { formatCurrency, formatFinancialDate, isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
import { transactionTypeLabels } from "@/domains/transactions/utils/transaction-utils";
import type { ManagementReportStatus } from "@/types/database";

export const metadata: Metadata = { title: "Tableau de bord du dossier" };
export const dynamic = "force-dynamic";
const roleLabels = { owner: "Propriétaire", manager: "Gestionnaire", read_only: "Lecture seule" } as const;
const reportStatusLabels: Record<ManagementReportStatus, string> = { draft: "En préparation", ready: "Prêt", generated: "Projet généré", finalized: "Finalisé", transmitted: "Transmis", approved: "Approuvé", difficulty: "Difficulté signalée" };
type DashboardData = NonNullable<Awaited<ReturnType<typeof getDossierDashboardData>>>;

export default async function DossierDashboardPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const data = await getDossierDashboardData(protectedPersonId);
  if (!data) notFound();
  const { person, accounts, relevantReport } = data;
  const activeAccounts = accounts.filter((account) => account.status === "active");
  const placementCount = activeAccounts.filter((account) => isValuationAccount(account.account_type)).length;
  const classicAccountCount = activeAccounts.length - placementCount;
  const personName = `${person.first_name} ${person.last_name}`;
  const canManage = person.accessRole !== "read_only";
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: personName, current: "dashboard", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: personName, href: `/dossiers/${protectedPersonId}/tableau-de-bord` }, { label: "Tableau de bord" }]} />
    <header><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">Tableau de bord du dossier</p><h1 className="mt-1 text-2xl font-bold tracking-tight sm:text-[28px]">{personName}</h1><p className="mt-1 text-xs text-[#64748B]">Dossier {person.status === "active" ? "actif" : "archivé"} · {roleLabels[person.accessRole]}</p></header>
    <DossierNavigation protectedPersonId={protectedPersonId} current="dashboard" />
    <section className="mt-5 grid items-start gap-3 sm:grid-cols-2" aria-label="Suivi du dossier">
      <SummaryCard icon={Landmark} title="Comptes actifs" href={`/dossiers/${protectedPersonId}/comptes`} linkLabel="Voir les comptes"><p className="text-xl font-bold">{activeAccounts.length}</p><p className="text-[11px] text-[#64748B]">{classicAccountCount} compte{classicAccountCount > 1 ? "s" : ""} courant{classicAccountCount > 1 ? "s" : ""} / livret{classicAccountCount > 1 ? "s" : ""} · {placementCount} placement{placementCount > 1 ? "s" : ""}</p></SummaryCard>
      <SummaryCard icon={ClipboardList} title="Compte de gestion" href={relevantReport ? `/dossiers/${protectedPersonId}/comptes-de-gestion/${relevantReport.id}` : `/dossiers/${protectedPersonId}/comptes-de-gestion`} linkLabel={relevantReport ? relevantReport.status === "draft" && canManage ? "Continuer" : "Voir" : canManage ? "Préparer" : "Voir"}>{relevantReport ? <><p className="text-sm font-bold">Compte de gestion {relevantReport.report_year}</p><p className="mt-0.5 text-xs text-[#64748B]">{reportStatusLabels[relevantReport.status]}</p></> : <p className="text-sm text-[#64748B]">Aucun compte de gestion</p>}</SummaryCard>
    </section>
    <PatrimonySummarySection personId={protectedPersonId} summary={data.patrimonySummary} />
    <div className="mt-4 grid items-start gap-4 xl:grid-cols-[minmax(0,1.5fr)_minmax(18rem,0.8fr)]"><RecentTransactions personId={protectedPersonId} items={data.recentTransactions} /><Tasks personId={protectedPersonId} tasks={data.tasks} actionCount={data.actionCounts.actionCount} /></div>
  </PrivateShell>;
}

function PatrimonySummarySection({ personId, summary }: { personId: string; summary: DashboardData["patrimonySummary"] }) {
  const complete = summary.netEstimatedValue !== null;
  return <section className="mt-4" aria-labelledby="patrimony-summary-title">
    <div><h2 id="patrimony-summary-title" className="text-lg font-bold">Synthèse patrimoniale</h2><p className="mt-0.5 text-xs text-[#64748B]">Estimation actuelle calculée à partir des informations connues du dossier.</p></div>
    <div className="mt-3 grid grid-cols-1 items-start gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <PatrimonyIndicator icon={WalletCards} title="Avoirs bancaires" component={summary.banking} href={`/dossiers/${personId}/comptes`} linkLabel="Voir les comptes" />
      <PatrimonyIndicator icon={Building2} title="Patrimoine immobilier" component={summary.realEstate} href={`/dossiers/${personId}/patrimoine-immobilier`} linkLabel="Voir les biens" />
      <PatrimonyIndicator icon={Landmark} title="Dettes" component={summary.activeDebts} href={`/dossiers/${personId}/dettes`} linkLabel="Voir les dettes" />
      <SummaryCard icon={Scale} title="Patrimoine net estimé" href={complete ? undefined : "#patrimony-missing-data"} linkLabel={complete ? undefined : "Voir les informations à compléter"}>
        {complete
          ? <p className="text-xl font-bold">{formatCurrency(summary.netEstimatedValue!)}</p>
          : <p className="text-sm font-bold text-amber-700">Données incomplètes</p>}
        <p className="mt-1 text-[11px] text-[#64748B]">Avoirs bancaires + immobilier actuel − dettes actives</p>
      </SummaryCard>
    </div>
    {summary.incompleteReasons.length > 0 && <div id="patrimony-missing-data" className="mt-3 scroll-mt-24 rounded-xl border border-amber-200 bg-amber-50/60 p-3.5">
      <h3 className="text-sm font-bold text-amber-900">Informations nécessaires au calcul</h3>
      <ul className="mt-2 space-y-2">
        {summary.incompleteReasons.map((reason) => <li key={reason.code} className="flex flex-col gap-1 text-xs text-[#475569] sm:flex-row sm:items-center sm:justify-between">
          <span>{reason.message}</span>
          <Link className="auth-link shrink-0" href={patrimonyReasonHref(personId, reason)}>{patrimonyReasonLinkLabel(reason)}<span className="sr-only"> : {reason.message}</span></Link>
        </li>)}
      </ul>
    </div>}
  </section>;
}

function PatrimonyIndicator({ icon, title, component, href, linkLabel }: { icon: typeof WalletCards; title: string; component: PatrimonySummaryComponent; href: string; linkLabel: string }) {
  const complete = component.state === "complete" || component.state === "confirmed_absent";
  return <SummaryCard icon={icon} title={title} href={href} linkLabel={linkLabel}>
    {complete && component.amount !== null
      ? <p className="text-xl font-bold">{formatCurrency(component.amount)}</p>
      : <p className="text-sm font-bold text-amber-700">Données incomplètes</p>}
    <p className="mt-1 text-[11px] text-[#64748B]">{component.state === "confirmed_absent" ? "Absence explicitement confirmée" : complete ? "Données actuelles disponibles" : component.incompleteReasons[0]?.message}</p>
  </SummaryCard>;
}

function patrimonyReasonHref(personId: string, reason: PatrimonyIncompleteReason) {
  if (reason.code === "no_financial_accounts") return `/dossiers/${personId}/comptes`;
  if (reason.code === "unconfirmed_real_estate_absence" || reason.code === "missing_real_estate_estimates") return `/dossiers/${personId}/patrimoine-immobilier`;
  return `/dossiers/${personId}/dettes`;
}

function patrimonyReasonLinkLabel(reason: PatrimonyIncompleteReason) {
  if (reason.code === "no_financial_accounts") return "Renseigner les comptes";
  if (reason.code === "unconfirmed_real_estate_absence" || reason.code === "missing_real_estate_estimates") return "Compléter l’immobilier";
  return "Compléter les dettes";
}

function SummaryCard({ icon: Icon, title, children, href, linkLabel }: { icon: typeof WalletCards; title: string; children: React.ReactNode; href?: string; linkLabel?: string }) { return <article className="self-start rounded-xl border border-[#E2E8F0] bg-white p-3.5 shadow-[0_6px_18px_rgba(15,23,42,0.035)]"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon aria-hidden="true" size={15} /></span><h2 className="text-sm font-bold">{title}</h2></div><div className="mt-2.5">{children}</div>{href && linkLabel && <Link className="auth-link mt-2 inline-flex items-center gap-1 text-xs" href={href}>{linkLabel}<ArrowRight aria-hidden="true" size={13} /></Link>}</article>; }
function RecentTransactions({ personId, items }: { personId: string; items: DashboardData["recentTransactions"] }) { return <section className="rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-[0_8px_24px_rgba(15,23,42,0.04)] sm:p-5"><div className="flex items-center justify-between gap-3"><h2 className="text-lg font-bold">Dernières opérations</h2><Link className="auth-link text-xs" href={`/dossiers/${personId}/operations`}>Voir le journal</Link></div>{items.length ? <div className="mt-2 divide-y divide-[#E2E8F0]">{items.map((item) => { const income = item.transaction_type === "income" || item.transaction_type === "transfer_in"; const expense = item.transaction_type === "expense" || item.transaction_type === "transfer_out"; const Icon = income ? ArrowDownLeft : expense ? ArrowUpRight : ArrowLeftRight; return <Link key={item.id} href={`/dossiers/${personId}/operations/${item.id}`} className="focus-ring -mx-2 grid grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-2 rounded-lg px-2 py-2.5 transition hover:bg-slate-50"><span className={`flex size-8 items-center justify-center rounded-lg ${income ? "bg-emerald-50 text-emerald-700" : expense ? "bg-red-50 text-red-700" : "bg-blue-50 text-blue-700"}`}><Icon aria-hidden="true" size={15} /></span><div className="min-w-0"><p className="truncate text-xs font-bold">{item.label}</p><p className="truncate text-[11px] text-[#64748B]">{formatFinancialDate(item.transaction_date)} · {item.account.account_name} · {dashboardClassificationLabel(item)}</p></div><p className={`text-xs font-bold ${income ? "text-emerald-700" : "text-red-700"}`}>{income ? "+" : "−"} {formatCurrency(item.amount)}</p></Link>; })}</div> : <p className="mt-4 text-sm text-[#64748B]">Aucune opération enregistrée.</p>}</section>; }
function dashboardClassificationLabel(item: DashboardData["recentTransactions"][number]) {
  switch (item.classification.state) {
    case "transfer": return transactionTypeLabels[item.transaction_type];
    case "capital_movement": return "Mouvement de capital";
    case "unclassified": return "À classer";
    case "needs_precision": return `${item.classification.officialCategory.name} · À préciser`;
    case "classified": return item.classification.precision
      ? `${item.classification.officialCategory.name} · ${item.classification.precision}`
      : item.classification.officialCategory.name;
  }
}
function Tasks({ personId, tasks, actionCount }: { personId: string; tasks: DashboardData["tasks"]; actionCount: number }) {
  const actionable = tasks.filter((task) => task.actionable);
  const information = tasks.filter((task) => !task.actionable);
  return <section className="rounded-2xl border border-amber-100 bg-amber-50/60 p-4 shadow-[0_8px_24px_rgba(15,23,42,0.03)] sm:p-5"><h2 className="text-lg font-bold">À faire ({actionCount})</h2>{actionable.length ? <div className="mt-2 divide-y divide-amber-100">{actionable.map((task) => <Link key={task.id} href={task.href} className="focus-ring -mx-2 flex items-start justify-between gap-3 rounded-lg px-2 py-2.5 transition hover:bg-white/70"><div><p className="text-sm font-semibold">{task.label}</p><p className="mt-0.5 text-[11px] text-[#64748B]">Échéance : {formatFinancialDate(task.dueDate)}</p></div><ArrowRight aria-hidden="true" className="mt-1 shrink-0 text-[#EA580C]" size={14} /></Link>)}</div> : <p className="mt-3 text-sm text-[#64748B]">Aucune action à traiter pour ce dossier.</p>}{information.length > 0 && <div className="mt-3 border-t border-amber-100 pt-3"><h3 className="text-sm font-semibold text-[#64748B]">Pour information</h3>{information.map((task) => <article key={task.id} className="mt-2 text-sm"><p className="font-semibold">{task.label}</p><p className="text-[11px] text-[#64748B]">Fin de période : {formatFinancialDate(task.dueDate)}</p></article>)}</div>}<Link className="auth-link mt-3 inline-block text-xs" href={`/dossiers/${personId}/exercices`}>Voir les exercices</Link></section>;
}
