import type { getManagementReportSnapshot } from "./services";
import { financialAccountLabels } from "@/domains/financial-accounts/utils/financial-account-utils";
import {
  propertyEventTypeLabels,
  propertyTypeLabels,
  safePropertyText,
} from "@/domains/assets-liabilities/property-format";

type Snapshot = NonNullable<
  Awaited<ReturnType<typeof getManagementReportSnapshot>>
>;

const debtTypeLabels = {
  bank_loan: "Prêt bancaire",
  tax_debt: "Dette fiscale",
  institution_debt: "Dette envers un établissement",
  personal_debt: "Dette personnelle",
  other: "Autre",
} as const;

const toCents = (value: number) => Math.round(value * 100);
const fromCents = (value: number) => value / 100;

function address(parts: Array<string | null | undefined>) {
  return parts.filter(Boolean).join(", ") || null;
}

function maskReference(reference: string | null) {
  if (!reference) return null;
  const compact = reference.replace(/\s/g, "");
  return `•••• ${compact.slice(-4)}`;
}

function latestValuation(
  valuations: Snapshot["placementAccounts"][number]["valuations"],
  date: string,
) {
  return valuations
    .filter((valuation) => valuation.valuation_date <= date)
    .sort((a, b) => b.valuation_date.localeCompare(a.valuation_date))[0] ?? null;
}

function buildOfficialSections(
  snapshot: Snapshot,
  prefix: "RES-" | "DEP-",
) {
  const amounts = new Map(
    (prefix === "RES-"
      ? snapshot.aggregation.resources
      : snapshot.aggregation.expenses
    ).map((line) => [line.officialCode, toCents(line.amount)]),
  );
  const categories = snapshot.officialCategories
    .filter((category) => category.official_code?.startsWith(prefix))
    .sort(
      (a, b) =>
        (a.official_order ?? 9999) - (b.official_order ?? 9999) ||
        (a.official_code ?? "").localeCompare(b.official_code ?? ""),
    );
  const groups = new Map<
    string,
    Array<{ code: string; label: string; amount: number; amountCents: number }>
  >();
  for (const category of categories) {
    const code = category.official_code!;
    const amountCents = amounts.get(code) ?? 0;
    const group = category.official_group ?? "Autres";
    groups.set(group, [
      ...(groups.get(group) ?? []),
      { code, label: category.name, amount: fromCents(amountCents), amountCents },
    ]);
  }
  const sections = [...groups.entries()].map(([label, lines]) => ({
    label,
    lines,
    total: fromCents(lines.reduce((sum, line) => sum + line.amountCents, 0)),
  }));
  const totalCents = sections.reduce(
    (total, section) =>
      total + section.lines.reduce((sum, line) => sum + line.amountCents, 0),
    0,
  );
  return { sections, total: fromCents(totalCents), totalCents, count: categories.length };
}

export function buildManagementReportPreview(snapshot: Snapshot) {
  const { accessRole: _accessRole, protectionMeasures: _protectionMeasures, managementPeriods: _managementPeriods, ...person } = snapshot.person;
  const { refresh_required_at: _refreshRequiredAt, ...report } = snapshot.report;
  void _accessRole;
  void _protectionMeasures;
  void _managementPeriods;
  void _refreshRequiredAt;
  const resources = buildOfficialSections(snapshot, "RES-");
  const expenses = buildOfficialSections(snapshot, "DEP-");
  const resultCents = resources.totalCents - expenses.totalCents;
  const knownCodes = new Set(
    snapshot.officialCategories.flatMap((category) =>
      category.official_code ? [category.official_code] : [],
    ),
  );
  const unexpectedCodes = [
    ...snapshot.aggregation.resources,
    ...snapshot.aggregation.expenses,
  ]
    .map((line) => line.officialCode)
    .filter((code) => !knownCodes.has(code));
  const accounts = snapshot.situations.map((situation) => ({
    id: situation.account.id,
    institution: situation.account.institution_name,
    name: situation.account.account_name,
    reference: maskReference(situation.account.account_reference),
    type: financialAccountLabels[situation.account.account_type],
    startBalance: situation.startBalance,
    income: situation.income,
    expense: situation.expense,
    endBalance: situation.endBalance,
    reliable: situation.startReliable && situation.endReliable,
    presentAtPeriodStart: situation.selection.presentAtPeriodStart,
    presentAtPeriodEnd: situation.selection.presentAtPeriodEnd,
    selectionSource: situation.selection.selectionSource,
    manualReason: situation.selection.manualReason,
  }));
  const placements = snapshot.placementAccounts.map((account) => {
    const situation = snapshot.situations.find(
      (item) => item.account.id === account.id,
    );
    const startValuation = latestValuation(account.valuations, snapshot.report.period_start);
    const endValuation = latestValuation(account.valuations, snapshot.report.period_end);
    return {
      id: account.id,
      institution: account.institution_name,
      name: account.account_name,
      type: financialAccountLabels[account.account_type],
      startValue: situation?.startBalance ?? null,
      endValue: situation?.endBalance ?? null,
      startValueDate: startValuation?.valuation_date ??
        (account.initial_balance_date <= snapshot.report.period_start
          ? account.initial_balance_date
          : null),
      endValueDate: endValuation?.valuation_date ??
        (account.initial_balance_date <= snapshot.report.period_end
          ? account.initial_balance_date
          : null),
      reliable: situation ? situation.startReliable && situation.endReliable : false,
    };
  });
  const properties = snapshot.properties
    .filter(
      (property) =>
        (!property.entry_date || property.entry_date <= snapshot.report.period_end) &&
        (!property.disposal_date || property.disposal_date >= snapshot.report.period_start),
    )
    .map((property) => ({
      id: property.id,
      designation: property.designation,
      type: propertyTypeLabels[property.property_type],
      status: property.status === "active" ? "Actif" : "Cédé",
      address: address([
        safePropertyText(property.address_line1),
        safePropertyText(property.address_line2),
        safePropertyText(property.postal_code),
        safePropertyText(property.city),
        safePropertyText(property.country),
      ]),
      estimatedValue: property.estimated_value,
      valuationDate: property.valuation_date,
      disposalDate: property.disposal_date,
    }));
  const propertyEvents = snapshot.propertyEvents.map(({ property, event }) => ({
    id: event.id,
    property: property.designation,
    date: event.event_date,
    type: propertyEventTypeLabels[event.event_type],
    amount: event.amount,
    description: safePropertyText(event.description),
  }));
  const debts = snapshot.relevantDebts.map(({ debt, balance }) => ({
    id: debt.id,
    creditor: debt.creditor,
    type: debtTypeLabels[debt.debt_type],
    designation: debt.designation,
    startDate: debt.start_date,
    initialAmount: debt.initial_amount,
    initialDurationMonths: debt.initial_duration_months,
    monthlyPayment: debt.monthly_payment,
    status: debt.status === "active" ? "Active" : "Soldée",
    balanceDate: balance?.balance_date ?? null,
    remainingBalance: balance?.remaining_balance ?? null,
    remainingDurationMonths: balance?.remaining_duration_months ?? null,
  }));
  const statements = snapshot.latestStatements.map(({ account, statement }) => ({
    accountId: account.id,
    accountName: account.account_name,
    statementId: statement?.id ?? null,
    startDate: statement?.statement_start_date ?? null,
    endDate: statement?.statement_end_date ?? null,
    hasDocument: Boolean(statement?.storage_path),
  }));
  const resourceLinesCents = resources.sections.reduce(
    (total, section) =>
      total + section.lines.reduce((sum, line) => sum + line.amountCents, 0),
    0,
  );
  const expenseLinesCents = expenses.sections.reduce(
    (total, section) =>
      total + section.lines.reduce((sum, line) => sum + line.amountCents, 0),
    0,
  );
  const checks = {
    resources: resourceLinesCents === resources.totalCents,
    expenses: expenseLinesCents === expenses.totalCents,
    result: resultCents === resources.totalCents - expenses.totalCents,
    reference: resources.count === 18 && expenses.count === 38,
    classified: snapshot.aggregation.unclassified === 0 && unexpectedCodes.length === 0,
  };
  const startAccounts = accounts.filter((account) => account.presentAtPeriodStart);
  const startBalanceCents = startAccounts.every((account) => account.startBalance !== null)
    ? startAccounts.reduce((total, account) => total + toCents(account.startBalance ?? 0), 0)
    : null;
  return {
    complete: snapshot.completeness.complete,
    report,
    person,
    measure: snapshot.activeMeasure,
    measureCorrespondence: snapshot.measureCorrespondence,
    resources,
    expenses,
    result: fromCents(resultCents),
    balance: {
      start: startBalanceCents === null ? null : fromCents(startBalanceCents),
      end:
        startBalanceCents === null
          ? null
          : fromCents(startBalanceCents + resultCents),
    },
    accounts,
    placements,
    statements,
    properties,
    propertyEvents,
    debts,
    confirmations: {
      residenceChanged: snapshot.report.residence_changed,
      representativeAddressChanged: snapshot.report.representative_address_changed,
      realEstateConfirmed: snapshot.report.real_estate_confirmed,
      financialInvestmentsConfirmed: snapshot.report.financial_investments_confirmed,
    },
    observations: snapshot.report.observations,
    signaturePlace: snapshot.report.signature_place,
    checks: {
      ...checks,
      consistent: Object.values(checks).every(Boolean),
      unclassifiedOperations: snapshot.aggregation.unclassified,
      unexpectedCodes,
    },
  };
}

export type ManagementReportPreview = ReturnType<
  typeof buildManagementReportPreview
>;
