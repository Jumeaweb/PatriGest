import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { ManagementPeriodManager } from "@/domains/protected-persons/components/management-period-manager";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { ManagementReportNavigation } from "@/domains/management-reports/management-report-navigation";

export const metadata: Metadata = { title: "Exercices de gestion" };
export const dynamic = "force-dynamic";

export default async function ManagementPeriodsPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "periods", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Exercices de gestion" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Exercices de gestion</h1>
    <p className="mt-1 text-sm text-[#64748B]">Les exercices regroupent les opérations saisies sur une période. Leur création ne déplace ni ne duplique aucune opération.</p>
    <DossierNavigation protectedPersonId={protectedPersonId} current="periods" />
    <ManagementReportNavigation protectedPersonId={protectedPersonId} current="periods" />
    {person.accessRole === "read_only" ? <div className="mt-5 space-y-2">{person.managementPeriods.length ? person.managementPeriods.map((period) => { const open = period.status === "open"; return <article key={period.id} className="rounded-xl border border-[#E2E8F0] bg-white p-4"><p className="text-sm font-bold">Du {period.start_date} au {period.end_date}</p><span className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-[10px] font-bold ${open ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-slate-200 bg-slate-100 text-slate-700"}`}>{open ? "Ouvert · exercice courant" : "Clôturé"} · Lecture seule</span></article>; }) : <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun exercice de gestion.</p>}</div> : <ManagementPeriodManager protectedPersonId={protectedPersonId} periods={person.managementPeriods} />}
  </PrivateShell>;
}
