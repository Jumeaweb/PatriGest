import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { getManagementReports } from "@/domains/management-reports/services";
import { getDashboardActions, getDashboardActionCounts } from "../action-engine";

export async function getDossierDashboardData(protectedPersonId: string) {
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) return null;

  const { supabase } = await getAuthenticatedUser();
  const [accounts, reports, recentTransactions, activePropertiesResult, disposedPropertiesResult, debtsResult] =
    await Promise.all([
      getFinancialAccounts(protectedPersonId),
      getManagementReports(protectedPersonId),
      getTransactions(protectedPersonId, { limit: 5 }),
      supabase
        .from("real_estate_properties")
        .select("id", { count: "exact", head: true })
        .eq("protected_person_id", protectedPersonId)
        .is("archived_at", null)
        .eq("status", "active"),
      supabase
        .from("real_estate_properties")
        .select("id", { count: "exact", head: true })
        .eq("protected_person_id", protectedPersonId)
        .is("archived_at", null)
        .eq("status", "disposed"),
      supabase
        .from("debts")
        .select("id", { count: "exact", head: true })
        .eq("protected_person_id", protectedPersonId)
        .eq("status", "active"),
    ]);

  if (activePropertiesResult.error || disposedPropertiesResult.error || debtsResult.error)
    throw new Error("Impossible de charger la synthèse du dossier.");

  const activeReport = reports.find((report) =>
    ["draft", "ready", "generated"].includes(report.status),
  );
  const relevantReport = activeReport ?? reports[0] ?? null;
  const tasks = getDashboardActions(
    protectedPersonId,
    person.accessRole,
    person.managementPeriods,
    reports,
  );

  return {
    person,
    accounts,
    relevantReport,
    recentTransactions,
    tasks,
    actionCounts: getDashboardActionCounts(tasks),
    activePropertyCount: activePropertiesResult.count ?? 0,
    disposedPropertyCount: disposedPropertiesResult.count ?? 0,
    activeDebtCount: debtsResult.count ?? 0,
  };
}
