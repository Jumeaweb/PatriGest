import type { FinancialAccount, ManagementReportAccountSelection } from "@/types/database";

export type ManagementReportAccountDecision<TAccount extends FinancialAccount = FinancialAccount> = {
  account: TAccount;
  relevantForPeriod: boolean;
  presentAtPeriodStart: boolean;
  presentAtPeriodEnd: boolean;
  included: boolean;
  selectionSource: "auto" | "manual";
  automaticReason: "active_during_period" | "opened_after_period" | "closed_before_period";
  manualMode: ManagementReportAccountSelection["selection_mode"] | null;
  manualReason: string | null;
};

export function getManagementReportAccountSelection<TAccount extends FinancialAccount>(
  accounts: TAccount[],
  selections: ManagementReportAccountSelection[],
  periodStart: string,
  periodEnd: string,
): ManagementReportAccountDecision<TAccount>[] {
  const selectionByAccount = new Map(
    selections.map((selection) => [selection.financial_account_id, selection]),
  );

  return accounts.map((account) => {
    const openedByPeriodEnd = !account.opening_date || account.opening_date <= periodEnd;
    const notClosedBeforePeriod = !account.closing_date || account.closing_date >= periodStart;
    const relevantForPeriod = openedByPeriodEnd && notClosedBeforePeriod;
    const presentAtPeriodStart =
      (!account.opening_date || account.opening_date <= periodStart) &&
      (!account.closing_date || account.closing_date >= periodStart);
    const presentAtPeriodEnd =
      (!account.opening_date || account.opening_date <= periodEnd) &&
      (!account.closing_date || account.closing_date >= periodEnd);
    const manual = selectionByAccount.get(account.id) ?? null;

    return {
      account,
      relevantForPeriod,
      presentAtPeriodStart,
      presentAtPeriodEnd,
      included: manual ? manual.selection_mode === "included_manual" : relevantForPeriod,
      selectionSource: manual ? "manual" : "auto",
      automaticReason: !openedByPeriodEnd
        ? "opened_after_period"
        : !notClosedBeforePeriod
          ? "closed_before_period"
          : "active_during_period",
      manualMode: manual?.selection_mode ?? null,
      manualReason: manual?.reason ?? null,
    };
  });
}

export function getIncludedReportAccountIds(
  accounts: FinancialAccount[],
  selections: ManagementReportAccountSelection[],
  periodStart: string,
  periodEnd: string,
) {
  return getManagementReportAccountSelection(accounts, selections, periodStart, periodEnd)
    .filter((selection) => selection.included)
    .map((selection) => selection.account.id);
}
