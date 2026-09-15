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

export type StableClassificationIssue = "unclassified" | "needs_precision";

export function getStableOfficialCategoriesById(categories: Category[]) {
  return new Map(categories.filter((category) =>
    category.is_system
    && category.owner_id === null
    && category.official_code !== null
    && category.official_category_id === null,
  ).map((category) => [category.id, category]));
}

export function getStableClassificationIssue(
  transaction: Transaction,
  officialById: ReadonlyMap<string, Category>,
): StableClassificationIssue | null {
  if (transaction.transaction_type === "transfer_in" || transaction.transaction_type === "transfer_out") return null;
  if (transaction.accounting_nature === "capital_movement") return null;
  if (transaction.accounting_nature !== "ordinary" || !transaction.official_category_id) return "unclassified";
  const category = officialById.get(transaction.official_category_id);
  if (!category || category.usage !== transaction.transaction_type) return "unclassified";
  return category.requires_precision && !transaction.classification_precision?.trim() ? "needs_precision" : null;
}

export function filterReportClassificationIssues<T extends Transaction>(
  transactions: T[],
  categories: Category[],
  includedAccountIds: readonly string[],
  periodStart: string,
  periodEnd: string,
  issue: StableClassificationIssue,
): T[] {
  const included = new Set(includedAccountIds);
  const officialById = getStableOfficialCategoriesById(categories);
  return transactions.filter((transaction) =>
    included.has(transaction.financial_account_id)
    && transaction.transaction_date >= periodStart
    && transaction.transaction_date <= periodEnd
    && getStableClassificationIssue(transaction, officialById) === issue,
  );
}

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
  const officialById = getStableOfficialCategoriesById(categories);
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

    const issue = getStableClassificationIssue(transaction, officialById);
    if (transaction.accounting_nature === "capital_movement") continue;
    if (issue === "unclassified") {
      unclassified += 1;
      continue;
    }
    const category = officialById.get(transaction.official_category_id!);
    if (!category) continue;
    addLine(lines, category, transaction.amount);
    if (issue === "needs_precision") needsPrecision += 1;
  }

  const reportLines = ordered(lines);
  return {
    resources: reportLines.filter((line) => line.officialCode.startsWith("RES-")),
    expenses: reportLines.filter((line) => line.officialCode.startsWith("DEP-")),
    unclassified,
    needsPrecision,
  };
}
