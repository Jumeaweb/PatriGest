import type { DossierAccessRole, ManagementReportStatus } from "@/types/database";

export type DashboardActionKind = "report_to_prepare" | "period_deadline" | "draft_to_resume";
export type DashboardAction = {
  id: string;
  kind: DashboardActionKind;
  protectedPersonId: string;
  periodId: string | null;
  reportId: string | null;
  label: string;
  startDate: string;
  dueDate: string;
  href: string;
  actionable: boolean;
};

type Period = { id: string; start_date: string; end_date: string; status: "open" | "closed" };
type Report = {
  id: string;
  management_period_id: string | null;
  period_start: string;
  period_end: string;
  report_year: number;
  status: ManagementReportStatus;
};

const priority: Record<DashboardActionKind, number> = {
  report_to_prepare: 0,
  period_deadline: 1,
  draft_to_resume: 2,
};

export function compareDashboardActions(first: DashboardAction, second: DashboardAction) {
  return priority[first.kind] - priority[second.kind] ||
    first.dueDate.localeCompare(second.dueDate) ||
    first.id.localeCompare(second.id);
}

export function getDashboardActions(
  protectedPersonId: string,
  accessRole: DossierAccessRole,
  periods: readonly Period[],
  reports: readonly Report[],
): DashboardAction[] {
  const actionable = accessRole !== "read_only";
  const actions: DashboardAction[] = [];

  for (const period of periods) {
    const covered = reports.some((report) =>
      report.management_period_id === period.id ||
      (report.management_period_id === null &&
        report.period_start === period.start_date &&
        report.period_end === period.end_date),
    );
    if (period.status === "closed" && !covered) {
      actions.push({
        id: `report-${protectedPersonId}-${period.id}`,
        kind: "report_to_prepare",
        protectedPersonId,
        periodId: period.id,
        reportId: null,
        label: actionable ? "Compte de gestion à préparer" : "Compte de gestion non préparé",
        startDate: period.start_date,
        dueDate: period.end_date,
        href: `/dossiers/${protectedPersonId}/comptes-de-gestion`,
        actionable,
      });
    } else if (period.status === "open") {
      actions.push({
        id: `period-${protectedPersonId}-${period.id}`,
        kind: "period_deadline",
        protectedPersonId,
        periodId: period.id,
        reportId: null,
        label: actionable ? "Échéance de l’exercice de gestion" : "Exercice de gestion en cours",
        startDate: period.start_date,
        dueDate: period.end_date,
        href: `/dossiers/${protectedPersonId}/exercices`,
        actionable,
      });
    }
  }

  for (const report of reports) {
    if (report.status !== "draft") continue;
    actions.push({
      id: `draft-${protectedPersonId}-${report.id}`,
      kind: "draft_to_resume",
      protectedPersonId,
      periodId: report.management_period_id,
      reportId: report.id,
      label: `Compte de gestion ${report.report_year} en préparation`,
      startDate: report.period_start,
      dueDate: report.period_end,
      href: `/dossiers/${protectedPersonId}/comptes-de-gestion/${report.id}`,
      actionable,
    });
  }

  return actions.sort(compareDashboardActions);
}

export function getDashboardActionCounts(actions: readonly DashboardAction[]) {
  const actionable = actions.filter((action) => action.actionable);
  return {
    actionCount: actionable.length,
    reportActionCount: actionable.filter((action) =>
      action.kind === "report_to_prepare" || action.kind === "draft_to_resume",
    ).length,
  };
}
