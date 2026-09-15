import type {
  DossierAccessRole,
  ManagementReportStatus,
} from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { compareDashboardActions, getDashboardActions, getDashboardActionCounts, type DashboardAction } from "../action-engine";

export type DashboardReportSummary = {
  id: string;
  reportYear: number;
  status: ManagementReportStatus;
};

export type DashboardTask = DashboardAction & { personName: string };

export type DashboardDossier = {
  id: string;
  firstName: string;
  lastName: string;
  accessRole: DossierAccessRole;
  activeAccountCount: number;
  latestReport: DashboardReportSummary | null;
  nextAction: DashboardTask | null;
};

export async function getDashboardData() {
  const { supabase, userId } = await getAuthenticatedUser();
  const [profileResult, personsResult, accessResult] = await Promise.all([
    supabase.from("profiles").select("first_name").eq("id", userId).maybeSingle(),
    supabase
      .from("protected_persons")
      .select("id,owner_id,first_name,last_name,status,updated_at")
      .eq("status", "active")
      .order("updated_at", { ascending: false }),
    supabase
      .from("protected_person_access")
      .select("protected_person_id,role")
      .eq("user_id", userId),
  ]);
  if (profileResult.error || personsResult.error || accessResult.error)
    throw new Error("Impossible de charger le tableau de bord.");

  const persons = personsResult.data;
  const personIds = persons.map((person) => person.id);
  if (!personIds.length)
    return {
      firstName: profileResult.data?.first_name ?? null,
      dossiers: [] as DashboardDossier[],
      tasks: [] as DashboardTask[],
      activeDossierCount: 0,
      reportActionCount: 0,
      actionCount: 0,
    };

  const [accountsResult, periodsResult, reportsResult] = await Promise.all([
    supabase
      .from("financial_accounts")
      .select("id,protected_person_id,status")
      .in("protected_person_id", personIds),
    supabase
      .from("management_periods")
      .select("id,protected_person_id,start_date,end_date,status")
      .in("protected_person_id", personIds)
      .in("status", ["open", "closed"])
      .order("end_date", { ascending: true }),
    supabase
      .from("management_reports")
      .select("id,protected_person_id,management_period_id,report_year,period_start,period_end,status,created_at")
      .in("protected_person_id", personIds)
      .order("period_end", { ascending: false })
      .order("created_at", { ascending: false }),
  ]);
  if (accountsResult.error || periodsResult.error || reportsResult.error)
    throw new Error("Impossible de charger le tableau de bord.");

  const accessRoleByPersonId = new Map(
    accessResult.data.map((access) => [access.protected_person_id, access.role]),
  );
  const activeAccountCountByPersonId = new Map<string, number>();
  for (const account of accountsResult.data) {
    if (account.status !== "active") continue;
    activeAccountCountByPersonId.set(
      account.protected_person_id,
      (activeAccountCountByPersonId.get(account.protected_person_id) ?? 0) + 1,
    );
  }

  const latestReportByPersonId = new Map<string, DashboardReportSummary>();
  for (const report of reportsResult.data) {
    if (!latestReportByPersonId.has(report.protected_person_id)) {
      latestReportByPersonId.set(report.protected_person_id, {
        id: report.id,
        reportYear: report.report_year,
        status: report.status,
      });
    }
  }

  const tasks: DashboardTask[] = [];
  for (const person of persons) {
    const accessRole = person.owner_id === userId
      ? "owner"
      : accessRoleByPersonId.get(person.id) ?? "read_only";
    const personName = `${person.first_name} ${person.last_name}`;
    tasks.push(...getDashboardActions(
      person.id,
      accessRole,
      periodsResult.data.filter((period) => period.protected_person_id === person.id),
      reportsResult.data.filter((report) => report.protected_person_id === person.id),
    ).map((action) => ({ ...action, personName })));
  }
  tasks.sort(compareDashboardActions);

  const nextActionByPersonId = new Map<string, DashboardTask>();
  for (const task of tasks) {
    if (task.actionable && !nextActionByPersonId.has(task.protectedPersonId))
      nextActionByPersonId.set(task.protectedPersonId, task);
  }

  const dossiers: DashboardDossier[] = persons.map((person) => ({
    id: person.id,
    firstName: person.first_name,
    lastName: person.last_name,
    accessRole:
      person.owner_id === userId
        ? "owner"
        : accessRoleByPersonId.get(person.id) ?? "read_only",
    activeAccountCount: activeAccountCountByPersonId.get(person.id) ?? 0,
    latestReport: latestReportByPersonId.get(person.id) ?? null,
    nextAction: nextActionByPersonId.get(person.id) ?? null,
  }));

  return {
    firstName: profileResult.data?.first_name ?? null,
    dossiers,
    tasks,
    activeDossierCount: dossiers.length,
    ...getDashboardActionCounts(tasks),
  };
}
