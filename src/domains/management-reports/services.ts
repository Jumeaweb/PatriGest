import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import {
  getProtectedPersonRegulatoryCompleteness,
  getProtectionMeasureRegulatoryCompleteness,
  getOfficialMeasureCorrespondence,
} from "@/domains/protected-persons/regulatory-helpers";
import { getProperties, getDebts } from "@/domains/assets-liabilities/services";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { getLatestBankStatementAtOrBefore } from "@/domains/bank-statements/services";
import {
  calculateAccountSituations,
} from "./calculations";
import { aggregateStableReportOperations } from "./stable-calculations";
import {
  getManagementReportCompleteness,
  type ReportSectionCompleteness,
} from "./completeness";
import type { Database } from "@/types/database";
import type { ManagementReportDocumentType } from "@/types/database";
import { buildManagementReportPreview } from "./preview-model";
import { MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION, parseManagementReportSnapshot } from "./snapshot";
import { getManagementReportAccountSelection } from "./account-selection";
export async function getManagementReports(personId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("management_reports")
    .select("*")
    .eq("protected_person_id", personId)
    .order("period_end", { ascending: false });
  if (error) throw new Error("Impossible de charger les comptes de gestion.");
  return data;
}
export async function getManagementReportDocument(
  personId: string,
  reportId: string,
  documentType: ManagementReportDocumentType,
) {
  const { supabase } = await getAuthenticatedUser();
  const report = await supabase
    .from("management_reports")
    .select("id")
    .eq("id", reportId)
    .eq("protected_person_id", personId)
    .maybeSingle();
  if (report.error) throw new Error("Impossible de vérifier le compte de gestion.");
  if (!report.data) return null;
  const { data, error } = await supabase
    .from("management_report_documents")
    .select("*")
    .eq("management_report_id", reportId)
    .eq("document_type", documentType)
    .maybeSingle();
  if (error) throw new Error("Impossible de charger le document du compte de gestion.");
  return data;
}
export async function createManagementReport(
  personId: string,
  input: {
    managementPeriodId: string | null;
    reportYear: number;
    periodStart: string;
    periodEnd: string;
  },
) {
  const { supabase, userId } = await getAuthenticatedUser();

  if (input.managementPeriodId) {
    const { data: period, error: periodError } = await supabase
      .from("management_periods")
      .select("start_date,end_date")
      .eq("id", input.managementPeriodId)
      .eq("protected_person_id", personId)
      .maybeSingle();
    if (periodError || !period)
      throw new Error("L’exercice de gestion sélectionné est introuvable.");
    if (period.start_date !== input.periodStart || period.end_date !== input.periodEnd)
      throw new Error("Les dates doivent correspondre exactement à l’exercice de gestion sélectionné.");
  }

  const { data: overlappingReports, error: overlapError } = await supabase
    .from("management_reports")
    .select("id")
    .eq("protected_person_id", personId)
    .lte("period_start", input.periodEnd)
    .gte("period_end", input.periodStart)
    .limit(1);
  if (overlapError) throw new Error("Impossible de vérifier la période du compte de gestion.");
  if (overlappingReports.length)
    throw new Error("Un compte de gestion existe déjà sur tout ou partie de cette période.");

  const { data, error } = await supabase
    .from("management_reports")
    .insert({
      protected_person_id: personId,
      management_period_id: input.managementPeriodId,
      report_year: input.reportYear,
      period_start: input.periodStart,
      period_end: input.periodEnd,
      created_by: userId,
    })
    .select("id")
    .single();
  if (error)
    throw new Error(
      error.code === "23505" || error.code === "23P01"
        ? "Un compte de gestion existe déjà sur tout ou partie de cette période."
        : "Impossible de préparer le compte de gestion.",
    );
  return data;
}
export async function updateManagementReport(
  personId: string,
  reportId: string,
  input: Database["public"]["Tables"]["management_reports"]["Update"],
) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("management_reports")
    .update(input)
    .eq("id", reportId)
    .eq("protected_person_id", personId)
    .select("id")
    .maybeSingle();
  if (error || !data)
    throw new Error("Impossible de modifier le compte de gestion.");
}
export async function updateManagementReportStatus(
  personId: string,
  reportId: string,
  currentStatus: "draft" | "ready",
  nextStatus: "draft" | "ready",
) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("management_reports")
    .update({ status: nextStatus })
    .eq("id", reportId)
    .eq("protected_person_id", personId)
    .eq("status", currentStatus)
    .select("id")
    .maybeSingle();
  if (error) throw new Error("Impossible de modifier le statut du compte de gestion.");
  return Boolean(data);
}
export async function setManagementReportAccountSelection(
  personId: string,
  reportId: string,
  accountId: string,
  selectionMode: "auto" | "included_manual" | "excluded_manual",
  reason: string,
) {
  const { supabase, userId } = await getAuthenticatedUser();
  const [{ data: report }, { data: account }, { data: canManage, error: permissionError }] = await Promise.all([
    supabase.from("management_reports").select("id,status").eq("id", reportId).eq("protected_person_id", personId).maybeSingle(),
    supabase.from("financial_accounts").select("id").eq("id", accountId).eq("protected_person_id", personId).maybeSingle(),
    supabase.rpc("can_manage_protected_person", { person_id: personId }),
  ]);
  if (!report || !account) throw new Error("Compte ou compte de gestion introuvable.");
  if (permissionError || !canManage) throw new Error("Modification du périmètre non autorisée.");
  if (report.status !== "draft") throw new Error("Le périmètre est verrouillé hors préparation.");

  const existing = await supabase
    .from("management_report_account_selections")
    .select("id")
    .eq("management_report_id", reportId)
    .eq("financial_account_id", accountId)
    .maybeSingle();
  if (existing.error) throw new Error("Impossible de vérifier la sélection du compte.");

  if (selectionMode === "auto") {
    if (!existing.data) return;
    const { error } = await supabase
      .from("management_report_account_selections")
      .delete()
      .eq("id", existing.data.id);
    if (error) throw new Error("Impossible de rétablir la règle automatique.");
    return;
  }

  if (existing.data) {
    const { error } = await supabase
      .from("management_report_account_selections")
      .update({ selection_mode: selectionMode, reason })
      .eq("id", existing.data.id);
    if (error) throw new Error("Impossible de modifier l’exception de sélection.");
    return;
  }
  const { error } = await supabase.from("management_report_account_selections").insert({
    management_report_id: reportId,
    financial_account_id: accountId,
    selection_mode: selectionMode,
    reason,
    created_by: userId,
  });
  if (error) throw new Error("Impossible d’enregistrer l’exception de sélection.");
}
export async function getManagementReportTransmission(reportId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("management_report_transmissions")
    .select("*")
    .eq("management_report_id", reportId)
    .maybeSingle();
  if (error)
    throw new Error("Impossible de charger la transmission du compte de gestion.");
  return data;
}
export async function getManagementReportOutcome(reportId: string) {
  const { supabase } = await getAuthenticatedUser();
  const [approvalResult, difficultyResult] = await Promise.all([
    supabase.from("management_report_approvals").select("*").eq("management_report_id", reportId).maybeSingle(),
    supabase.from("management_report_difficulties").select("*").eq("management_report_id", reportId).maybeSingle(),
  ]);
  if (approvalResult.error || difficultyResult.error)
    throw new Error("Impossible de charger le retour du contrôleur.");
  return { approval: approvalResult.data, difficulty: difficultyResult.data };
}
export async function getManagementReportSnapshot(
  personId: string,
  reportId: string,
) {
  const { supabase } = await getAuthenticatedUser();
  const [result, person, accounts, properties, debts] = await Promise.all([
    supabase
      .from("management_reports")
      .select("*")
      .eq("id", reportId)
      .eq("protected_person_id", personId)
      .maybeSingle(),
    getProtectedPerson(personId),
    getFinancialAccounts(personId),
    getProperties(personId),
    getDebts(personId),
  ]);
  if (result.error || !result.data || !person) return null;
  const report = result.data;
  const [reportTransmission, selectionResult] = await Promise.all([
    getManagementReportTransmission(report.id),
    supabase
      .from("management_report_account_selections")
      .select("*")
      .eq("management_report_id", report.id),
  ]);
  if (selectionResult.error)
    throw new Error("Impossible de charger le périmètre des comptes.");
  const accountSelections = getManagementReportAccountSelection(
    accounts,
    selectionResult.data,
    report.period_start,
    report.period_end,
  );
  const includedAccounts = accountSelections
    .filter((selection) => selection.included)
    .map((selection) => selection.account);
  const accountIds = includedAccounts.map((account) => account.id);
  const empty = { data: [], error: null };
  const [categoryResult, transactionResult, latestStatements] =
    await Promise.all([
      supabase.from("categories").select("*"),
      accountIds.length
        ? supabase
            .from("transactions")
            .select("*")
            .in("financial_account_id", accountIds)
            .gte("transaction_date", report.period_start)
            .lte("transaction_date", report.period_end)
        : Promise.resolve(empty),
      Promise.all(includedAccounts.map(async (account) => ({
        account,
        statement: await getLatestBankStatementAtOrBefore(account.id, report.period_end),
      }))),
    ]);
  if (categoryResult.error || transactionResult.error)
    throw new Error("Impossible de calculer le compte de gestion.");
  const stableAggregation = aggregateStableReportOperations(
    transactionResult.data,
    categoryResult.data,
    includedAccounts,
  );
  const { needsPrecision, ...aggregation } = stableAggregation;
  const situations = calculateAccountSituations(
    accountSelections,
    includedAccounts.flatMap((account) => account.transactions),
    includedAccounts.flatMap((account) => account.valuations),
    report.period_start,
    report.period_end,
  );
  const activeMeasure =
    person.protectionMeasures.find((measure) => measure.active) ?? null;
  const personCheck = getProtectedPersonRegulatoryCompleteness(person);
  const measureCheck =
    getProtectionMeasureRegulatoryCompleteness(activeMeasure);
  const measureCorrespondence = activeMeasure
    ? getOfficialMeasureCorrespondence(activeMeasure.measure_type)
    : null;
  const propertyEvents = properties.flatMap((property) =>
    property.events
      .filter(
        (event) =>
          event.event_date >= report.period_start &&
          event.event_date <= report.period_end,
      )
      .map((event) => ({ property, event })),
  );
  const placementAccounts = includedAccounts.filter(
    (account) =>
      account.account_type === "life_insurance" ||
      account.account_type === "other_investment" ||
      account.account_type === "securities_account",
  );
  const relevantDebts = debts
    .filter(
      (debt) =>
        (!debt.start_date || debt.start_date <= report.period_end) &&
        (!debt.settled_at || debt.settled_at >= report.period_start),
    )
    .map((debt) => ({
      debt,
      balance:
        debt.balances.find(
          (balance) => balance.balance_date <= report.period_end,
        ) ?? null,
    }));
  const sections: ReportSectionCompleteness[] = [
    {
      key: "person",
      label: "Personne protégée",
      complete: personCheck.complete && report.residence_changed !== null,
      missing: [
        ...personCheck.missingFields.map((item) => item.label),
        ...(report.residence_changed === null
          ? ["Changement de résidence"]
          : []),
      ],
    },
    {
      key: "measure",
      label: "Mesure de protection",
      complete:
        measureCheck.complete &&
        report.representative_address_changed !== null &&
        Boolean(measureCorrespondence?.direct),
      missing: [
        ...measureCheck.missingFields.map((item) => item.label),
        ...(report.representative_address_changed === null
          ? ["Changement d’adresse du représentant"]
          : []),
        ...(!measureCorrespondence?.direct
          ? ["Correspondance réglementaire du type de mesure"]
          : []),
      ],
    },
    {
      key: "acts",
      label: "Actes de gestion",
      complete:
        report.real_estate_confirmed !== null &&
        report.financial_investments_confirmed !== null,
      missing: [
        ...(report.real_estate_confirmed === null
          ? ["Confirmation du patrimoine immobilier"]
          : []),
        ...(report.financial_investments_confirmed === null
          ? ["Confirmation des placements"]
          : []),
      ],
    },
    {
      key: "operations",
      label: "Ressources et dépenses",
      complete:
        aggregation.unclassified === 0 && needsPrecision === 0,
      missing: [
        ...(aggregation.unclassified
          ? [`${aggregation.unclassified} opération(s) sans classement officiel`]
          : []),
        ...(needsPrecision
          ? [`${needsPrecision} opération(s) nécessitant une précision`]
          : []),
      ],
    },
    {
      key: "accounts",
      label: "Comptes et placements",
      complete: situations.every((item) => item.startReliable && item.endReliable),
      missing: situations.flatMap((item) => [
        ...(!item.startReliable
          ? [`Solde de départ indisponible — ${item.account.account_name}`]
          : []),
        ...(!item.endReliable
          ? [`Situation de fin indisponible — ${item.account.account_name}`]
          : []),
      ]),
    },
    {
      key: "statements",
      label: "Relevés / pièces",
      complete: latestStatements.every((item) => Boolean(item.statement)),
      missing: latestStatements
        .filter((item) => !item.statement)
        .map((item) => `Relevé manquant — ${item.account.account_name}`),
    },
    {
      key: "debts",
      label: "Dettes",
      complete: relevantDebts.every((item) => Boolean(item.balance)),
      missing: relevantDebts
        .filter((item) => !item.balance)
        .map((item) => `Situation manquante — ${item.debt.creditor}`),
    },
    { key: "observations", label: "Observations", complete: true, missing: [] },
  ];
  return {
    report,
    reportTransmission,
    person,
    properties,
    propertyEvents,
    placementAccounts,
    relevantDebts,
    aggregation,
    classificationIssueCounts: { unclassified: aggregation.unclassified, needsPrecision },
    officialCategories: categoryResult.data.filter(
      (category) => category.is_system && Boolean(category.official_code),
    ),
    situations,
    accountSelections,
    latestStatements,
    activeMeasure,
    measureCorrespondence,
    completeness: getManagementReportCompleteness(sections),
  };
}

export async function getLiveManagementReportPreview(
  personId: string,
  reportId: string,
) {
  const snapshot = await getManagementReportSnapshot(personId, reportId);
  return snapshot ? buildManagementReportPreview(snapshot) : null;
}

export type ManagementReportPreviewState =
  | {
      availability: "available";
      preview: NonNullable<Awaited<ReturnType<typeof getLiveManagementReportPreview>>>;
      liveSnapshot: NonNullable<Awaited<ReturnType<typeof getManagementReportSnapshot>>> | null;
    }
  | {
      availability: "draft" | "missing_snapshot" | "unsupported_version" | "invalid_snapshot";
      preview: null;
      liveSnapshot: null;
    };

export async function getManagementReportPreviewState(personId: string, reportId: string) {
  const { supabase } = await getAuthenticatedUser();
  const [reportResult, person] = await Promise.all([
    supabase.from("management_reports").select("*").eq("id", reportId).eq("protected_person_id", personId).maybeSingle(),
    getProtectedPerson(personId),
  ]);
  if (reportResult.error || !reportResult.data || !person) return null;
  const report = reportResult.data;

  if (report.status === "draft") {
    return { report, person, state: { availability: "draft", preview: null, liveSnapshot: null } satisfies ManagementReportPreviewState };
  }
  if (report.status === "ready") {
    const liveSnapshot = await getManagementReportSnapshot(personId, reportId);
    return liveSnapshot
      ? {
          report,
          person,
          state: {
            availability: "available",
            preview: buildManagementReportPreview(liveSnapshot),
            liveSnapshot,
          } satisfies ManagementReportPreviewState,
        }
      : null;
  }

  const documentType = report.status === "generated" ? "management_report_draft" : "management_report";
  const document = await getManagementReportDocument(personId, reportId, documentType);
  if (!document?.preview_snapshot || document.snapshot_schema_version === null) {
    return { report, person, state: { availability: "missing_snapshot", preview: null, liveSnapshot: null } satisfies ManagementReportPreviewState };
  }
  if (document.snapshot_schema_version !== MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION) {
    return { report, person, state: { availability: "unsupported_version", preview: null, liveSnapshot: null } satisfies ManagementReportPreviewState };
  }
  const parsed = parseManagementReportSnapshot(document.preview_snapshot);
  if (!parsed.success) {
    return { report, person, state: { availability: "invalid_snapshot", preview: null, liveSnapshot: null } satisfies ManagementReportPreviewState };
  }
  return { report, person, state: { availability: "available", preview: parsed.data, liveSnapshot: null } satisfies ManagementReportPreviewState };
}
