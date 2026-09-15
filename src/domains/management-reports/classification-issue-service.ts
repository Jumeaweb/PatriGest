import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { getIncludedReportAccountIds } from "./account-selection";
import { filterReportClassificationIssues, type StableClassificationIssue } from "./stable-calculations";

export async function getReportClassificationIssueJournal(
  personId: string,
  reportId: string,
  issue: StableClassificationIssue,
) {
  const { supabase } = await getAuthenticatedUser();
  const { data: report, error } = await supabase.from("management_reports")
    .select("id,protected_person_id,period_start,period_end,report_year,status")
    .eq("id", reportId).eq("protected_person_id", personId).maybeSingle();
  if (error || !report || report.status !== "draft") return null;

  const [accounts, selectionResult, categoryResult] = await Promise.all([
    getFinancialAccounts(personId),
    supabase.from("management_report_account_selections").select("*").eq("management_report_id", report.id),
    supabase.from("categories").select("*"),
  ]);
  if (selectionResult.error || categoryResult.error) throw new Error("Impossible de charger les opérations à corriger.");
  const includedAccountIds = getIncludedReportAccountIds(accounts, selectionResult.data, report.period_start, report.period_end);
  const transactions = includedAccountIds.length
    ? await getTransactions(personId, { startDate: report.period_start, endDate: report.period_end, reportAccountIds: includedAccountIds })
    : [];
  return {
    report,
    items: filterReportClassificationIssues(transactions, categoryResult.data, includedAccountIds, report.period_start, report.period_end, issue),
  };
}
