import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getManagementReports } from "@/domains/management-reports/services";
import { ManagementReportCreateForm } from "@/domains/management-reports/management-report-create-form";
import { ManagementReportNavigation } from "@/domains/management-reports/management-report-navigation";
import { getManagementReportStatusPresentation } from "@/domains/management-reports/management-report-status";
import { getReportPreparationGuidance } from "@/domains/management-reports/report-preparation-guidance";
import { formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
export const dynamic = "force-dynamic";
export default async function Page({
  params,
}: {
  params: Promise<{ protectedPersonId: string }>;
}) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const [person, reports] = await Promise.all([
    getProtectedPerson(protectedPersonId),
    getManagementReports(protectedPersonId),
  ]);
  if (!person) notFound();
  const canManage = person.accessRole !== "read_only";
  const { suggested, state: preparationState } = getReportPreparationGuidance(
    person.managementPeriods,
    reports,
  );
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
          { label: "Comptes de gestion" },
        ]}
      />
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-wide text-blue-600">
            {person.first_name} {person.last_name}
          </p>
          <h1 className="mt-1 text-2xl font-bold">Comptes de gestion</h1>
        </div>
        <a
          className="text-xs font-semibold text-blue-600"
          href="https://www.legifrance.gouv.fr/search/all?tab_selection=all&searchField=ALL&query=arr%C3%AAt%C3%A9+4+juillet+2024+compte+gestion"
          target="_blank"
          rel="noreferrer"
        >
          Consulter le modèle officiel sur Légifrance
        </a>
      </div>
      <DossierNavigation
        protectedPersonId={protectedPersonId}
        current="reports"
      />
      <ManagementReportNavigation
        protectedPersonId={protectedPersonId}
        current="reports"
      />
      <div className="mt-4 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <div className="text-sm text-[#475569]">
          {preparationState === "no_period" ? (
            <>
              <p className="font-semibold">Aucun exercice de gestion n&apos;est actuellement disponible.</p>
              <p className="mt-1">
                {canManage
                  ? "Vous pouvez utiliser l’onglet Exercices de gestion pour définir une période, ou continuer en renseignant les dates manuellement ci-dessous."
                  : "Les comptes de gestion déjà préparés restent consultables ci-dessous."}
              </p>
            </>
          ) : preparationState === "manual" ? (
            <>
              <p className="font-semibold">Aucun exercice ne peut préremplir la période d&apos;un nouveau compte de gestion.</p>
              <p className="mt-1">
                {canManage
                  ? "Vous pouvez consulter l’onglet Exercices de gestion ou renseigner les dates manuellement ci-dessous."
                  : "Les comptes de gestion déjà préparés restent consultables ci-dessous."}
              </p>
            </>
          ) : (
            <p>
              {canManage
                ? "Les dates du formulaire reprennent un exercice de gestion. Vérifiez-les avant de préparer le compte de gestion."
                : "Un exercice de gestion est disponible. Les comptes de gestion préparés restent consultables ci-dessous."}
            </p>
          )}
        </div>
      </div>
      {canManage && (
        <ManagementReportCreateForm
          personId={protectedPersonId}
          suggested={suggested ?? null}
        />
      )}
      <div className="mt-4 space-y-2">
        {reports.map((report) => {
          const status = getManagementReportStatusPresentation(report.status);
          return (
            <Link
              key={report.id}
              href={`/dossiers/${protectedPersonId}/comptes-de-gestion/${report.id}`}
              className="focus-ring flex items-center justify-between gap-3 rounded-xl border bg-white p-4"
            >
              <span>
                <strong>{report.report_year}</strong>
                <span className="ml-3 text-xs text-slate-500">
                  {formatFinancialDate(report.period_start)} →{" "}
                  {formatFinancialDate(report.period_end)}
                </span>
              </span>
              <span
                className={`shrink-0 rounded-full border px-2.5 py-1 text-xs font-semibold ${status.className}`}
              >
                {status.label}
              </span>
            </Link>
          );
        })}
        {!reports.length && (
          <p className="rounded-xl border border-dashed bg-white p-6 text-center text-sm text-slate-500">
            Aucun compte de gestion préparé.
          </p>
        )}
      </div>
    </PrivateShell>
  );
}
