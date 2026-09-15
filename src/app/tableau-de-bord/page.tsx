import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, CalendarDays, ClipboardList, FolderOpen, ListTodo, UserRound } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AdministrationDashboard } from "@/domains/administration/components/administration-dashboard";
import { getPrivateAccessContext } from "@/domains/administration/services/private-access-context";
import { getDashboardData, type DashboardDossier, type DashboardReportSummary, type DashboardTask } from "@/domains/dashboard/services/dashboard-service";
import { formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";

export const metadata: Metadata = { title: "Tableau de bord" };
export const dynamic = "force-dynamic";

const roleLabels = { owner: "Propriétaire", manager: "Gestionnaire", read_only: "Lecture seule" } as const;
const reportStatusLabels = { draft: "En préparation", ready: "Prêt", generated: "Projet généré", finalized: "Finalisé", transmitted: "Transmis", approved: "Approuvé", difficulty: "Difficulté signalée" } as const;

export default async function DashboardPage() {
  const { isPlatformAdmin } = await getPrivateAccessContext();
  if (isPlatformAdmin) return <PrivateShell current="dashboard"><AdministrationDashboard /></PrivateShell>;
  const data = await getDashboardData();
  return <PrivateShell current="dashboard">
    <header><p className="text-sm font-semibold text-[#64748B]">{data.firstName ? `Bonjour, ${data.firstName}` : "Bonjour"}</p><h1 className="mt-1 text-2xl font-bold tracking-tight sm:text-3xl">Tableau de bord</h1><p className="mt-1 text-sm text-[#64748B]">Suivez vos dossiers et les prochaines actions à traiter.</p></header>
    <section className="mt-5 grid gap-3 sm:grid-cols-3" aria-label="Indicateurs principaux">
      <StatCard href="/dossiers" title="Dossiers actifs" value={data.activeDossierCount} icon={FolderOpen} color="blue" />
      <StatCard title="Comptes de gestion à préparer" value={data.reportToPrepareCount} icon={ClipboardList} color="amber" />
      <StatCard title="Actions à traiter" value={data.actionCount} icon={ListTodo} color="violet" />
    </section>
    <div className="mt-4 grid items-start gap-4 xl:grid-cols-[minmax(0,1.55fr)_minmax(19rem,0.85fr)]">
      <DossiersSection dossiers={data.dossiers} canCreate={!isPlatformAdmin} />
      <TasksSection tasks={data.tasks} />
    </div>
  </PrivateShell>;
}

const colors = { blue: "bg-blue-50 text-[#2563EB]", amber: "bg-amber-50 text-[#EA580C]", violet: "bg-violet-50 text-[#7C3AED]" } as const;
function StatCard({ href, title, value, icon: Icon, color }: { href?: string; title: string; value: number; icon: typeof FolderOpen; color: keyof typeof colors }) { const content = <div className="flex items-center gap-3"><span className={`flex size-9 shrink-0 items-center justify-center rounded-lg ${colors[color]}`}><Icon aria-hidden="true" size={18} /></span><div className="min-w-0"><p className="text-xs font-semibold text-[#64748B]">{title}</p><p className="text-2xl font-bold tracking-tight">{value}</p></div></div>; const className = "focus-ring rounded-xl border border-[#E2E8F0] bg-white p-3.5 shadow-[0_6px_18px_rgba(15,23,42,0.035)]"; return href ? <Link className={`${className} transition hover:border-blue-200`} href={href}>{content}</Link> : <article className={className}>{content}</article>; }

function DossiersSection({ dossiers, canCreate }: { dossiers: DashboardDossier[]; canCreate: boolean }) { return <section className="rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-[0_8px_24px_rgba(15,23,42,0.04)] sm:p-5"><div className="flex items-center justify-between gap-3"><div><h2 className="text-lg font-bold">Dossiers suivis</h2><p className="text-xs text-[#64748B]">Personnes protégées dont vous pouvez consulter le dossier.</p></div><Link className="auth-link shrink-0 text-xs" href="/dossiers">Voir tous les dossiers</Link></div>{dossiers.length ? <div className="mt-3 grid items-start gap-3 md:grid-cols-2">{dossiers.map((dossier) => <DossierCard key={dossier.id} dossier={dossier} />)}</div> : <div className="mt-4 rounded-xl border border-dashed border-[#CBD5E1] p-5 text-center"><p className="text-sm font-semibold">Aucun dossier accessible actuellement.</p><p className="mt-1 text-xs text-[#64748B]">{canCreate ? "Vous pouvez créer votre premier dossier ou consulter la liste des dossiers." : "Consultez la liste des dossiers ou attendez qu’un accès vous soit accordé."}</p><div className="mt-3 flex flex-wrap justify-center gap-2">{canCreate && <Link className="button button-primary" href="/dossiers/nouveau">Créer mon premier dossier</Link>}<Link className="button button-secondary" href="/dossiers">Voir tous les dossiers</Link></div></div>}</section>; }

function DossierCard({ dossier }: { dossier: DashboardDossier }) { return <article className="rounded-xl border border-[#E2E8F0] p-3.5"><div className="flex items-start gap-3"><span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><UserRound aria-hidden="true" size={16} /></span><div className="min-w-0 flex-1"><h3 className="truncate text-sm font-bold">{dossier.firstName} {dossier.lastName}</h3><p className="text-[11px] font-semibold text-[#64748B]">{roleLabels[dossier.accessRole]} · {dossier.activeAccountCount} {dossier.activeAccountCount > 1 ? "comptes actifs" : "compte actif"}</p></div></div><div className="mt-3 border-t border-[#E2E8F0] pt-2.5"><ReportSummary report={dossier.latestReport} />{dossier.nextAction && <p className="mt-1.5 line-clamp-2 text-[11px] text-[#64748B]"><span className="font-semibold text-[#334155]">Prochaine action :</span> {dossier.nextAction.label}</p>}</div><Link className="focus-ring mt-3 inline-flex items-center gap-1 rounded text-xs font-bold text-[#2563EB] hover:text-blue-700" href={`/dossiers/${dossier.id}/tableau-de-bord`}>Ouvrir le dossier <ArrowRight aria-hidden="true" size={14} /></Link></article>; }

function ReportSummary({ report }: { report: DashboardReportSummary | null }) { return report ? <p className="text-xs text-[#64748B]">Compte de gestion {report.reportYear} : <span className="font-semibold text-[#334155]">{reportStatusLabels[report.status]}</span></p> : <p className="text-xs text-[#94A3B8]">Aucun compte de gestion</p>; }

function TasksSection({ tasks }: { tasks: DashboardTask[] }) { return <section className="rounded-2xl border border-amber-100 bg-amber-50/60 p-4 shadow-[0_8px_24px_rgba(15,23,42,0.03)] sm:p-5"><div className="flex items-center gap-3"><span className="flex size-9 items-center justify-center rounded-lg bg-amber-100 text-[#EA580C]"><CalendarDays aria-hidden="true" size={18} /></span><div><h2 className="text-lg font-bold">À faire prochainement</h2><p className="text-xs text-[#64748B]">Actions classées par priorité et échéance.</p></div></div>{tasks.length ? <div className="mt-3 divide-y divide-amber-100">{tasks.map((task) => <Link key={task.id} href={task.href} className="focus-ring -mx-2 block rounded-lg px-2 py-3 transition hover:bg-white/70"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="truncate text-xs font-bold text-[#334155]">{task.personName}</p><p className="mt-0.5 text-sm font-semibold">{task.label}</p><p className="mt-0.5 text-[11px] text-[#64748B]">Du {formatFinancialDate(task.startDate)} au {formatFinancialDate(task.dueDate)}</p></div><ArrowRight aria-hidden="true" className="mt-1 shrink-0 text-[#EA580C]" size={15} /></div><p className="mt-1 text-[11px] font-semibold text-[#9A3412]">Échéance : {formatFinancialDate(task.dueDate)}</p></Link>)}</div> : <p className="mt-4 text-sm font-semibold text-[#64748B]">Aucune action à traiter actuellement.</p>}</section>; }
