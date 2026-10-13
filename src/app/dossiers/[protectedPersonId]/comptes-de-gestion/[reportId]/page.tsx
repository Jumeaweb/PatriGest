import { notFound } from "next/navigation";
import Link from "next/link";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { ManagementReportDashboard } from "@/domains/management-reports/components";
import { ManagementReportPreviewView } from "@/domains/management-reports/preview";
import { ReportDocumentActions } from "@/domains/management-reports/report-document-actions";
import { ReportOutcome } from "@/domains/management-reports/report-outcome";
import { ReportTransmission } from "@/domains/management-reports/report-transmission";
import {
  getManagementReportDocument,
  getManagementReportPreviewState,
  getManagementReportOutcome,
  getManagementReportSnapshot,
  getManagementReportTransmission,
} from "@/domains/management-reports/services";
import { formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
export const dynamic = "force-dynamic";
export default async function Page({
  params,
}: {
  params: Promise<{ protectedPersonId: string; reportId: string }>;
}) {
  const { protectedPersonId, reportId } = await params;
  if (
    ![protectedPersonId, reportId].every((id) => z.uuid().safeParse(id).success)
  )
    notFound();
  const result = await getManagementReportPreviewState(
    protectedPersonId,
    reportId,
  );
  if (!result) notFound();
  const { person, report, state } = result;
  const preparationSnapshot = report.status === "draft"
    ? await getManagementReportSnapshot(protectedPersonId, reportId)
    : report.status === "ready"
      ? state.liveSnapshot
      : null;
  if (["draft", "ready"].includes(report.status) && !preparationSnapshot) notFound();
  const documentType = report.status === "generated"
    ? "management_report_draft" as const
    : ["finalized", "transmitted", "approved", "difficulty"].includes(report.status)
      ? "management_report" as const
      : null;
  const document = documentType
    ? await getManagementReportDocument(protectedPersonId, reportId, documentType)
    : null;
  const transmission = ["finalized", "transmitted", "approved", "difficulty"].includes(report.status)
    ? await getManagementReportTransmission(reportId)
    : null;
  const outcome = ["transmitted", "approved", "difficulty"].includes(report.status)
    ? await getManagementReportOutcome(reportId)
    : { approval: null, difficulty: null };
  const statusLabel = report.status === "approved"
    ? "Approuvé"
    : report.status === "difficulty"
      ? "Difficulté signalée"
      : report.status === "transmitted"
    ? "Transmis"
    : report.status === "finalized"
    ? "Finalisé"
    : report.status === "generated"
      ? "Projet généré"
    : report.status === "ready"
      ? "Prêt"
      : "En préparation";
  return (
    <PrivateShell
      current="dossiers"
      dossier={{
        id: protectedPersonId,
        name: `${person.first_name} ${person.last_name}`,
        current: "reports",
        accessRole: person.accessRole,
      }}
    >
      <AppBreadcrumb
        items={[
          { label: "Dossiers", href: "/dossiers" },
          {
            label: `${person.first_name} ${person.last_name}`,
            href: `/dossiers/${protectedPersonId}/comptes`,
          },
          {
            label: "Comptes de gestion",
            href: `/dossiers/${protectedPersonId}/comptes-de-gestion`,
          },
          { label: String(report.report_year) },
        ]}
      />
      <p className="text-xs font-bold uppercase tracking-wide text-blue-600">
        {person.first_name} {person.last_name}
      </p>
      <h1 className="mt-1 text-2xl font-bold">
        Compte de gestion {report.report_year}
      </h1>
      <p className="text-xs text-slate-500">
        {formatFinancialDate(report.period_start)} →{" "}
        {formatFinancialDate(report.period_end)} ·{" "}
        {statusLabel}
      </p>
      {["ready", "generated", "finalized", "transmitted", "approved", "difficulty"].includes(report.status) && (
        <Link
          className="button button-secondary mt-3"
          href={`/dossiers/${protectedPersonId}/comptes-de-gestion/${reportId}/apercu`}
        >
          Voir l’aperçu
        </Link>
      )}
      <DossierNavigation
        protectedPersonId={protectedPersonId}
        current="reports"
      />
      {preparationSnapshot ? (
        <ManagementReportDashboard
          snapshot={preparationSnapshot}
          canManage={person.accessRole !== "read_only"}
        />
      ) : state.availability === "available" ? (
        <ManagementReportPreviewView preview={state.preview} />
      ) : (
        <section className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4">
          <h2 className="font-bold text-amber-900">Données détaillées indisponibles</h2>
          <p className="mt-1 text-sm text-amber-800">
            {report.status === "generated"
              ? "Les données détaillées de ce projet sont figées dans le PDF projet."
              : "Les données détaillées de ce compte de gestion historique sont figées dans le document officiel PDF."}
          </p>
        </section>
      )}
      <ReportDocumentActions
        personId={protectedPersonId}
        reportId={reportId}
        status={report.status}
        canManage={person.accessRole !== "read_only"}
        hasDocument={Boolean(document)}
        refreshRequiredAt={report.refresh_required_at}
      />
      {["finalized", "transmitted", "approved", "difficulty"].includes(report.status) && (
        <ReportTransmission
          personId={protectedPersonId}
          reportId={reportId}
          status={report.status}
          finalizedAt={report.finalized_at}
          transmission={transmission}
          canManage={person.accessRole !== "read_only"}
        />
      )}
      {transmission && ["transmitted", "approved", "difficulty"].includes(report.status) && (
        <ReportOutcome
          personId={protectedPersonId}
          reportId={reportId}
          status={report.status}
          transmissionDate={transmission.transmission_date}
          approval={outcome.approval}
          difficulty={outcome.difficulty}
          canManage={person.accessRole !== "read_only"}
        />
      )}
    </PrivateShell>
  );
}
