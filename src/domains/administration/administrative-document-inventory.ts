import { z } from "zod";

export const documentInventoryCategorySchema = z.enum([
  "transaction_proof", "bank_statement", "management_report", "backup",
  "document_operation", "account_neutralization", "repair",
]);

export const documentInventoryAnomalySchema = z.enum([
  "business_reference_without_catalog_object",
  "catalog_object_without_business_reference",
  "unresolved_catalog_path",
  "historical_noncanonical_path",
  "business_attachment_mismatch",
  "storage_identity_incomplete",
  "storage_owner_unrecorded",
  "no_durable_operation_history",
  "backup_catalog_object_missing",
  "backup_physical_verification_required",
  "terminal_operation_residual",
  "non_terminal_operation",
  "attention_required_operation",
  "incomplete_account_neutralization",
  "expired_repair_authorization",
  "repair_renewals_exhausted",
]);

export const documentInventoryFindingSchema = z.object({
  inventoryKey: z.string().min(1).max(200),
  documentCategory: documentInventoryCategorySchema,
  anomalyType: documentInventoryAnomalySchema,
  findingStatus: z.enum(["sql_fact", "possible_anomaly", "historical_legitimate"]),
  protectedPersonId: z.uuid().nullable(),
  businessEntityType: z.string().nullable(),
  businessEntityId: z.uuid().nullable(),
  operationId: z.uuid().nullable(),
  catalogObjectPresent: z.boolean().nullable(),
  physicalVerification: z.literal("not_performed"),
  physicalVerificationRequired: z.boolean(),
  actionBlocked: z.boolean(),
  storageGuardRequired: z.boolean(),
  detailCode: z.string().regex(/^[A-Z0-9_:-]+$/),
  sourceCreatedAt: z.string(),
});

export const documentInventoryResponseSchema = z.object({
  items: z.array(documentInventoryFindingSchema),
  nextCursor: z.string().min(1).max(200).nullable(),
  hasMore: z.boolean(),
  limit: z.number().int().min(1).max(100),
  physicalInspectionPerformed: z.literal(false),
  consistency: z.literal("keyset_without_snapshot"),
});

export type DocumentInventoryCategory = z.infer<typeof documentInventoryCategorySchema>;
export type DocumentInventoryAnomaly = z.infer<typeof documentInventoryAnomalySchema>;
export type DocumentInventoryFinding = z.infer<typeof documentInventoryFindingSchema>;

const cursorSchema = z.string().min(1).max(200).regex(/^[a-z0-9_:-]+$/);
const pageSizeSchema = z.coerce.number().int().min(1).max(100).default(25);

export type AdministrativeDocumentInventoryQuery = {
  cursor: string | null;
  category: DocumentInventoryCategory | null;
  anomaly: DocumentInventoryAnomaly | null;
  limit: number;
  finding: string | null;
};

function optionalValue(value: string | string[] | undefined) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function parseAdministrativeDocumentInventoryQuery(searchParams: {
  cursor?: string | string[];
  category?: string | string[];
  anomaly?: string | string[];
  limit?: string | string[];
  finding?: string | string[];
}): AdministrativeDocumentInventoryQuery {
  const cursor = optionalValue(searchParams.cursor);
  const category = optionalValue(searchParams.category);
  const anomaly = optionalValue(searchParams.anomaly);
  const limit = optionalValue(searchParams.limit);
  const finding = optionalValue(searchParams.finding);
  return {
    cursor: cursor ? cursorSchema.parse(cursor) : null,
    category: category ? documentInventoryCategorySchema.parse(category) : null,
    anomaly: anomaly ? documentInventoryAnomalySchema.parse(anomaly) : null,
    limit: pageSizeSchema.parse(limit ?? 25),
    finding: finding ? cursorSchema.parse(finding) : null,
  };
}

export function getAdministrativeDocumentInventoryHref(
  query: AdministrativeDocumentInventoryQuery,
  cursor: string | null = query.cursor,
) {
  const params = new URLSearchParams();
  if (query.category) params.set("category", query.category);
  if (query.anomaly) params.set("anomaly", query.anomaly);
  if (query.limit !== 25) params.set("limit", String(query.limit));
  if (cursor) params.set("cursor", cursor);
  if (query.finding) params.set("finding", query.finding);
  const suffix = params.toString();
  return `/administration/inventaire-documentaire${suffix ? `?${suffix}` : ""}`;
}

export const documentInventoryCategoryLabels: Record<DocumentInventoryCategory, string> = {
  transaction_proof: "Justificatifs d’opérations",
  bank_statement: "Relevés bancaires",
  management_report: "Comptes de gestion",
  backup: "Sauvegardes durables",
  document_operation: "Opérations documentaires",
  account_neutralization: "Neutralisations de compte",
  repair: "Réparations administratives",
};

export const documentInventoryAnomalyLabels: Record<DocumentInventoryAnomaly, string> = {
  business_reference_without_catalog_object: "Référence métier sans objet catalogué",
  catalog_object_without_business_reference: "Objet catalogué sans référence métier directe",
  unresolved_catalog_path: "Objet catalogué sans rattachement canonique déterminable",
  historical_noncanonical_path: "Chemin historique à examiner",
  business_attachment_mismatch: "Rattachement canonique incohérent",
  storage_identity_incomplete: "Identité ou métadonnées Storage incomplètes",
  storage_owner_unrecorded: "Propriétaire Storage non enregistré",
  no_durable_operation_history: "Document antérieur au suivi durable",
  backup_catalog_object_missing: "Objet de sauvegarde absent du catalogue",
  backup_physical_verification_required: "Sauvegarde à vérifier physiquement",
  terminal_operation_residual: "Résidu après opération terminale",
  non_terminal_operation: "Opération documentaire non terminale",
  attention_required_operation: "Opération nécessitant une intervention",
  incomplete_account_neutralization: "Neutralisation de compte inachevée",
  expired_repair_authorization: "Autorisation de réparation expirée",
  repair_renewals_exhausted: "Renouvellements de réparation épuisés",
};
