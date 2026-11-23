import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { ManagementReportPreviewView } from "@/domains/management-reports/preview";
import { PrintPreviewButton } from "@/domains/management-reports/print-preview-button";
import { getManagementReportPreviewState } from "@/domains/management-reports/services";

export const dynamic = "force-dynamic";

export default async function Page({
  params,
}: {
  params: Promise<{ protectedPersonId: string; reportId: string }>;
}) {
  const { protectedPersonId, reportId } = await params;
  if (![protectedPersonId, reportId].every((id) => z.uuid().safeParse(id).success)) notFound();
  const result = await getManagementReportPreviewState(protectedPersonId, reportId);
  if (!result) notFound();
  const { person, report, state } = result;
  const personName = `${person.first_name} ${person.last_name}`;
  const reportHref = `/dossiers/${protectedPersonId}/comptes-de-gestion/${reportId}`;
  const documentEndpoint = `/api/dossiers/${protectedPersonId}/comptes-de-gestion/${reportId}/document`;
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: personName, current: "reports", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: personName, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Comptes de gestion", href: `/dossiers/${protectedPersonId}/comptes-de-gestion` }, { label: String(report.report_year), href: reportHref }, { label: "Aperçu" }]} />
    <div className="flex flex-wrap items-start justify-between gap-3 print:hidden">
      <div><p className="text-xs font-bold uppercase tracking-wide text-blue-600">{personName}</p><h1 className="mt-1 text-2xl font-bold">Aperçu réglementaire</h1><p className="mt-1 text-xs text-slate-500">{report.status === "draft" ? "Aperçu provisoire · données recalculées depuis la préparation." : report.status === "ready" ? "Lecture seule · données recalculées avant génération." : report.status === "generated" ? "Photographie figée du PDF projet." : ["finalized", "transmitted", "approved", "difficulty"].includes(report.status) ? "Photographie figée du document officiel." : "Lecture seule."}</p></div>
      <div className="flex flex-wrap gap-2"><PrintPreviewButton /><Link className="button button-secondary" href={reportHref}>Retour au compte de gestion</Link></div>
    </div>
    <div className="print:hidden"><DossierNavigation protectedPersonId={protectedPersonId} current="reports" /></div>
    {state.availability === "available" ? <ManagementReportPreviewView preview={state.preview} /> : <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4"><h2 className="font-bold text-amber-900">Aperçu indisponible</h2><p className="mt-1 text-sm text-amber-800">{state.availability === "unsupported_version" ? "Cet aperçu historique utilise une version de données non prise en charge. Le document officiel reste disponible au format PDF." : state.availability === "invalid_snapshot" ? "L’aperçu historique ne peut pas être lu de manière fiable. Le document PDF reste disponible." : report.status === "generated" ? "Le snapshot du projet n’est pas disponible. Seul le PDF projet peut être consulté." : "Le document officiel finalisé est disponible au format PDF."}</p><div className="mt-3 flex flex-wrap gap-2"><a className="button button-secondary" href={documentEndpoint} target="_blank" rel="noreferrer">Voir le PDF</a><a className="button button-secondary" href={`${documentEndpoint}?download=1`}>Télécharger le PDF</a><Link className="button button-secondary" href={reportHref}>Revenir au compte de gestion</Link></div></div>}
  </PrivateShell>;
}
