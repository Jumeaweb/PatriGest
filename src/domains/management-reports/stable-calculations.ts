import type {
  Category,
  FinancialAccount,
  Transaction,
} from "@/types/database";

export type StableReportLine = {
  officialCode: string;
  label: string;
  amount: number;
  order: number;
};

export type StableReportAggregation = {
  resources: StableReportLine[];
  expenses: StableReportLine[];
  unclassified: number;
  needsPrecision: number;
};

const placementAccountTypes: readonly FinancialAccount["account_type"][] = [
  "life_insurance",
  "other_investment",
  "securities_account",
];

function transferOfficialCode(
  transaction: Transaction,
  account: FinancialAccount | undefined,
): "DEP-8-01" | null {
  return transaction.transaction_type === "transfer_in"
    && account
    && placementAccountTypes.includes(account.account_type)
    ? "DEP-8-01"
    : null;
}

function addLine(
  lines: Map<string, StableReportLine>,
  category: Category,
  amount: number,
) {
  const code = category.official_code!;
  const current = lines.get(code);
  lines.set(code, {
    officialCode: code,
    label: category.name,
    amount: (current?.amount ?? 0) + amount,
    order: category.official_order ?? 9999,
  });
}

function ordered(lines: Map<string, StableReportLine>) {
  return [...lines.values()].sort(
    (a, b) => a.order - b.order || a.officialCode.localeCompare(b.officialCode),
  );
}

export function aggregateStableReportOperations(
  transactions: Transaction[],
  categories: Category[],
  accounts: FinancialAccount[],
): StableReportAggregation {
  const officialCategories = categories.filter(
    (category) =>
      category.is_system
      && category.owner_id === null
      && category.official_code !== null
      && category.official_category_id === null,
  );
  const officialById = new Map(
    officialCategories.map((category) => [category.id, category]),
  );
  const officialByCode = new Map(
    officialCategories.map((category) => [category.official_code!, category]),
  );
  const accountById = new Map(accounts.map((account) => [account.id, account]));
  const lines = new Map<string, StableReportLine>();
  let unclassified = 0;
  let needsPrecision = 0;

  for (const transaction of transactions) {
    if (
      transaction.transaction_type === "transfer_in"
      || transaction.transaction_type === "transfer_out"
    ) {
      const code = transferOfficialCode(
        transaction,
        accountById.get(transaction.financial_account_id),
      );
      const category = code ? officialByCode.get(code) : undefined;
      if (category) addLine(lines, category, transaction.amount);
      continue;
    }

    if (transaction.accounting_nature === "capital_movement") continue;

    if (
      transaction.accounting_nature !== "ordinary"
      || !transaction.official_category_id
    ) {
      unclassified += 1;
      continue;
    }

    const category = officialById.get(transaction.official_category_id);
    if (!category || category.usage !== transaction.transaction_type) {
      unclassified += 1;
      continue;
    }

    addLine(lines, category, transaction.amount);
    if (
      category.requires_precision
      && !transaction.classification_precision?.trim()
    ) {
      needsPrecision += 1;
    }
  }

  const reportLines = ordered(lines);
  return {
    resources: reportLines.filter((line) => line.officialCode.startsWith("RES-")),
    expenses: reportLines.filter((line) => line.officialCode.startsWith("DEP-")),
    unclassified,
    needsPrecision,
  };
}
