import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { getManagementReports } from "@/domains/management-reports/services";
import { buildPatrimonyAbsenceConfirmationState } from "@/domains/assets-liabilities/patrimony-absence";
import { getPatrimonySummary } from "../patrimony-summary";
import { getDashboardActions, getDashboardActionCounts } from "../action-engine";

export async function getDossierDashboardData(protectedPersonId: string) {
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) return null;

  const { supabase } = await getAuthenticatedUser();
  const [accounts, reports, recentTransactions, propertiesResult, debtsResult, confirmationsResult] =
    await Promise.all([
      getFinancialAccounts(protectedPersonId),
      getManagementReports(protectedPersonId),
      getTransactions(protectedPersonId, { limit: 5 }),
      supabase
        .from("real_estate_properties")
        .select("status,estimated_value,archived_at")
        .eq("protected_person_id", protectedPersonId)
        .is("archived_at", null),
      supabase
        .from("debts")
        .select("status,current_balance")
        .eq("protected_person_id", protectedPersonId),
      supabase
        .from("patrimony_absence_confirmations")
        .select("protected_person_id,category,confirmed_at,confirmed_by,confirmed_by_name")
        .eq("protected_person_id", protectedPersonId),
    ]);

  if (propertiesResult.error) throw new Error("Impossible de charger le patrimoine immobilier du dossier.");
  if (debtsResult.error) throw new Error("Impossible de charger les dettes du dossier.");
  if (confirmationsResult.error) throw new Error("Impossible de charger les confirmations patrimoniales du dossier.");

  const properties = propertiesResult.data;
  const debts = debtsResult.data;
  const confirmations = buildPatrimonyAbsenceConfirmationState(confirmationsResult.data);
  const patrimonySummary = getPatrimonySummary({ accounts, properties, debts, confirmations });

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
    patrimonySummary,
  };
}
