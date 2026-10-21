import { z } from "zod";
import type { Json } from "@/types/database";
import type { ManagementReportPreview } from "./preview-model";

export const MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION = 1;

const nullableString = z.string().nullable();
const nullableNumber = z.number().nullable();
const nullableBoolean = z.boolean().nullable();
const managementReportStatusSchema = z.enum(["draft", "ready", "generated", "finalized", "transmitted", "approved", "difficulty"]);
const measureTypeSchema = z.enum(["safeguard_of_justice", "safeguard_with_special_mandate", "simple_curatorship", "reinforced_curatorship", "guardianship", "future_protection_mandate", "family_authorization", "judicial_support_measure"]);
const datedValue = z.object({
  id: z.string(),
  institution: z.string(),
  name: z.string(),
  type: z.string(),
  startValue: nullableNumber,
  endValue: nullableNumber,
  startValueDate: nullableString,
  endValueDate: nullableString,
  reliable: z.boolean(),
});
const personSchema = z.object({
  id: z.string(), owner_id: z.string(), first_name: z.string(), last_name: z.string(),
  birth_name: nullableString, birth_date: nullableString, birth_place: nullableString,
  address_line1: nullableString, address_line2: nullableString, postal_code: nullableString,
  city: nullableString, country: z.string(), phone: nullableString, email: nullableString,
  residence_address_line1: nullableString, residence_address_line2: nullableString,
  residence_postal_code: nullableString, residence_city: nullableString, residence_country: nullableString,
  notes: nullableString, status: z.enum(["active", "archived"]), created_at: z.string(),
  updated_at: z.string(), archived_at: nullableString,
}).strict();
const measureSchema = z.object({
  id: z.string(), protected_person_id: z.string(), measure_type: measureTypeSchema,
  start_date: nullableString, end_date: nullableString, decision_date: nullableString,
  court_name: nullableString, court_city: nullableString, case_reference: nullableString,
  court_cabinet: nullableString, judge_name: nullableString, notary_name: nullableString,
  notes: nullableString, representative_first_name: nullableString,
  representative_last_name: nullableString, representative_appointment_date: nullableString,
  representative_address_line1: nullableString, representative_address_line2: nullableString,
  representative_postal_code: nullableString, representative_city: nullableString,
  representative_country: nullableString, representative_phone: nullableString,
  representative_email: nullableString, active: z.boolean(), created_at: z.string(), updated_at: z.string(),
}).strict().nullable();
const reportSchema = z.object({
  id: z.string(), protected_person_id: z.string(), management_period_id: nullableString,
  report_year: z.number(), period_start: z.string(), period_end: z.string(),
  status: managementReportStatusSchema, residence_changed: nullableBoolean,
  representative_address_changed: nullableBoolean, real_estate_confirmed: nullableBoolean,
  financial_investments_confirmed: nullableBoolean, observations: nullableString,
  signature_place: nullableString, generated_at: nullableString, finalized_at: nullableString,
  transmitted_at: nullableString, approved_at: nullableString, difficulty_reported_at: nullableString,
  created_by: z.string(), created_at: z.string(), updated_at: z.string(),
}).strict();
const officialSectionSchema = z.object({
  label: z.string(),
  lines: z.array(z.object({ code: z.string(), label: z.string(), amount: z.number(), amountCents: z.number() }).strict()),
  total: z.number(),
}).strict();

export const managementReportPreviewSchema = z.object({
  complete: z.boolean(),
  report: reportSchema,
  person: personSchema,
  measure: measureSchema,
  measureCorrespondence: z.union([
    z.object({ direct: z.literal(true), officialLabel: z.string() }).strict(),
    z.object({ direct: z.literal(false), officialLabel: z.null() }).strict(),
  ]).nullable(),
  resources: z.object({ sections: z.array(officialSectionSchema), total: z.number(), totalCents: z.number(), count: z.number() }).strict(),
  expenses: z.object({ sections: z.array(officialSectionSchema), total: z.number(), totalCents: z.number(), count: z.number() }).strict(),
  result: z.number(),
  balance: z.object({ start: nullableNumber, end: nullableNumber }).strict(),
  accounts: z.array(z.object({
    id: z.string(), institution: z.string(), name: z.string(), reference: nullableString,
    type: z.string(), startBalance: nullableNumber, income: z.number(), expense: z.number(),
    endBalance: nullableNumber, reliable: z.boolean(),
    presentAtPeriodStart: z.boolean().optional().default(true),
    presentAtPeriodEnd: z.boolean().optional().default(true),
    selectionSource: z.enum(["auto", "manual"]).optional().default("auto"),
    manualReason: nullableString.optional().default(null),
  }).strict()),
  placements: z.array(datedValue.strict()),
  statements: z.array(z.object({
    accountId: z.string(), accountName: z.string(), statementId: nullableString,
    startDate: nullableString, endDate: nullableString, hasDocument: z.boolean(),
  }).strict()),
  properties: z.array(z.object({
    id: z.string(), designation: z.string(), type: z.string(), status: z.string(),
    address: nullableString, estimatedValue: nullableNumber, valuationDate: nullableString,
    disposalDate: nullableString,
  }).strict()),
  propertyEvents: z.array(z.object({
    id: z.string(), property: z.string(), date: z.string(), type: z.string(),
    amount: nullableNumber, description: nullableString,
  }).strict()),
  debts: z.array(z.object({
    id: z.string(), creditor: z.string(), type: z.string(), designation: z.string(),
    startDate: nullableString, initialAmount: nullableNumber, initialDurationMonths: nullableNumber,
    monthlyPayment: nullableNumber, status: z.string(), balanceDate: nullableString,
    remainingBalance: nullableNumber, remainingDurationMonths: nullableNumber,
  }).strict()),
  confirmations: z.object({
    residenceChanged: nullableBoolean, representativeAddressChanged: nullableBoolean,
    realEstateConfirmed: nullableBoolean, financialInvestmentsConfirmed: nullableBoolean,
  }).strict(),
  observations: nullableString,
  signaturePlace: nullableString,
  checks: z.object({
    resources: z.boolean(), expenses: z.boolean(), result: z.boolean(), reference: z.boolean(),
    classified: z.boolean(), consistent: z.boolean(), unclassifiedOperations: z.number(),
    unexpectedCodes: z.array(z.string()),
  }).strict(),
}).strict();

export function parseManagementReportSnapshot(value: Json) {
  const parsed = managementReportPreviewSchema.safeParse(value);
  if (!parsed.success) return parsed;
  return { success: true as const, data: parsed.data as ManagementReportPreview };
}

export type FinalizedManagementReportSnapshotResult =
  | {
      success: true;
      preview: ManagementReportPreview;
      snapshot: Json;
    }
  | {
      success: false;
      reason: "missing" | "unsupported_version" | "invalid" | "invalid_status";
    };

export function finalizeManagementReportProjectSnapshot(
  value: Json | null,
  schemaVersion: number | null,
): FinalizedManagementReportSnapshotResult {
  if (value === null || schemaVersion === null) {
    return { success: false, reason: "missing" };
  }
  if (schemaVersion !== MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION) {
    return { success: false, reason: "unsupported_version" };
  }

  const project = parseManagementReportSnapshot(value);
  if (!project.success) return { success: false, reason: "invalid" };
  if (project.data.report.status !== "generated") {
    return { success: false, reason: "invalid_status" };
  }

  const raw = value as Record<string, Json>;
  const rawReport = raw.report as Record<string, Json>;
  const snapshot = {
    ...raw,
    report: { ...rawReport, status: "finalized" },
  } satisfies Json;
  const finalized = parseManagementReportSnapshot(snapshot);
  if (!finalized.success) return { success: false, reason: "invalid" };

  return { success: true, preview: finalized.data, snapshot };
}

export function toJsonValue(value: unknown): Json {
  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.map(toJsonValue);
  if (typeof value === "object") {
    const result: Record<string, Json> = {};
    for (const [key, item] of Object.entries(value)) {
      if (item !== undefined) result[key] = toJsonValue(item);
    }
    return result;
  }
  throw new Error("Le snapshot contient une valeur non sérialisable.");
}
