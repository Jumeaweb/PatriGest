import type {
  AccountValuation,
  Category,
  FinancialAccount,
  Transaction,
} from "@/types/database";
import { isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
import {
  resolveCategoryReference,
  resolveTransferOfficialCodeForFutureReport,
} from "@/domains/categories/category-reference";
import type { ManagementReportAccountDecision } from "./account-selection";
export type ReportLine = {
  officialCode: string;
  label: string;
  amount: number;
  order: number;
};
export type ReportAccountSituation = {
  account: FinancialAccount;
  selection: ManagementReportAccountDecision;
  startBalance: number | null;
  income: number;
  expense: number;
  endBalance: number | null;
  startReliable: boolean;
  endReliable: boolean;
};
const sum = (items: Transaction[], credit: boolean) =>
  items
    .filter((item) => !item.cancelled_at)
    .filter((item) =>
      credit
        ? ["income", "transfer_in"].includes(item.transaction_type)
        : ["expense", "transfer_out"].includes(item.transaction_type),
    )
    .reduce((total, item) => total + item.amount, 0);
export function aggregateReportOperations(
  transactions: Transaction[],
  categories: Category[],
  accounts: FinancialAccount[],
) {
  const official = categories.filter(
    (category) => category.is_system && category.official_code,
  );
  const categoryById = new Map(
    categories.map((category) => [category.id, category]),
  );
  const accountById = new Map(accounts.map((account) => [account.id, account]));
  const lines = new Map<string, ReportLine>();
  let unclassified = 0;
  for (const item of transactions) {
    let category: Category | undefined;
    let code: string | null = null;
    if (
      item.transaction_type === "income" ||
      item.transaction_type === "expense"
    ) {
      category = item.category_id
        ? categoryById.get(item.category_id)
        : undefined;
      if (category)
        code =
          resolveCategoryReference(category, official)?.officialCode ?? null;
    } else {
      const account = accountById.get(item.financial_account_id);
      if (account)
        code = resolveTransferOfficialCodeForFutureReport({
          transactionType: item.transaction_type,
          accountType: account.account_type,
        });
    }
    if (!code) {
      if (item.transaction_type === "income" || item.transaction_type === "expense") unclassified += 1;
      continue;
    }
    const officialCategory = official.find(
      (entry) => entry.official_code === code,
    );
    const current = lines.get(code);
    lines.set(code, {
      officialCode: code,
      label: officialCategory?.name ?? "Versement sur placement",
      amount: (current?.amount ?? 0) + item.amount,
      order: officialCategory?.official_order ?? 9999,
    });
  }
  const ordered = [...lines.values()].sort(
    (a, b) => a.order - b.order || a.officialCode.localeCompare(b.officialCode),
  );
  return {
    resources: ordered.filter((line) => line.officialCode.startsWith("RES-")),
    expenses: ordered.filter((line) => line.officialCode.startsWith("DEP-")),
    unclassified,
  };
}
export function calculateAccountSituations(
  selections: ManagementReportAccountDecision[],
  transactions: Transaction[],
  valuations: AccountValuation[],
  start: string,
  end: string,
): ReportAccountSituation[] {
  return selections
    .filter((selection) => selection.included)
    .map((selection) => {
      const { account } = selection;
      const movements = transactions.filter(
        (item) => item.financial_account_id === account.id && !item.cancelled_at,
      );
      if (isValuationAccount(account.account_type)) {
        const before = (date: string) =>
          valuations
            .filter(
              (value) =>
                value.financial_account_id === account.id &&
                value.valuation_date <= date,
            )
            .sort((a, b) => b.valuation_date.localeCompare(a.valuation_date))[0]
            ?.value ??
          (account.initial_balance_date <= date
            ? account.initial_balance
            : null);
        const startBalance = selection.presentAtPeriodStart ? before(start) : null;
        const endDate = selection.presentAtPeriodEnd ? end : account.closing_date ?? end;
        const endBalance = before(endDate);
        return {
          account,
          selection,
          startBalance,
          income: 0,
          expense: 0,
          endBalance,
          startReliable: !selection.presentAtPeriodStart || startBalance !== null,
          endReliable: !selection.presentAtPeriodEnd || endBalance !== null,
        };
      }
      const beforeStart = movements.filter(
        (item) => item.transaction_date < start,
      );
      const inPeriod = movements.filter(
        (item) =>
          item.transaction_date >= start && item.transaction_date <= end,
      );
      const startBalance = selection.presentAtPeriodStart && account.initial_balance_date <= start
        ? account.initial_balance + sum(beforeStart, true) - sum(beforeStart, false)
        : null;
      const endDate = selection.presentAtPeriodEnd ? end : account.closing_date ?? end;
      const throughEnd = movements.filter((item) => item.transaction_date <= endDate);
      const endBalance = account.initial_balance_date <= endDate
        ? account.initial_balance + sum(throughEnd, true) - sum(throughEnd, false)
        : null;
      return {
        account,
        selection,
        startBalance,
        income: sum(inPeriod, true),
        expense: sum(inPeriod, false),
        endBalance,
        startReliable: !selection.presentAtPeriodStart || startBalance !== null,
        endReliable: !selection.presentAtPeriodEnd || endBalance !== null,
      };
    });
}
