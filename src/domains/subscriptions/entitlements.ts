import { z } from "zod";

export const DOSSIER_FEATURE_KEYS = [
  "core_management",
  "existing_accounting_documents",
  "data_export",
  "bank_operation_automation",
  "central_document_management",
] as const;

export const DOSSIER_FEATURE_ACCESS_MODES = ["read", "write"] as const;

export const DOSSIER_FEATURE_DENIAL_REASONS = [
  "feature_upcoming",
  "subscription_missing",
  "plan_unavailable",
  "not_in_plan",
  "role_forbidden",
  "operation_not_supported",
  "trial_export_unavailable",
] as const;

export type DossierFeatureKey = (typeof DOSSIER_FEATURE_KEYS)[number];
export type DossierFeatureAccessMode = (typeof DOSSIER_FEATURE_ACCESS_MODES)[number];
export type DossierFeatureDenialReason = (typeof DOSSIER_FEATURE_DENIAL_REASONS)[number];
export type DossierFeatureImplementationStatus = "available" | "upcoming";

export type DossierFeaturePermission = {
  allowed: boolean;
  denialReason: DossierFeatureDenialReason | null;
};

export type DossierFeatureCapability = {
  featureKey: DossierFeatureKey;
  implementationStatus: DossierFeatureImplementationStatus;
  read: DossierFeaturePermission;
  write: DossierFeaturePermission;
};

export type DossierFeatureAccessResult =
  | {
      allowed: true;
      featureKey: DossierFeatureKey;
      accessMode: DossierFeatureAccessMode;
    }
  | {
      allowed: false;
      featureKey: DossierFeatureKey;
      accessMode: DossierFeatureAccessMode;
      reason: DossierFeatureDenialReason;
    };

export type DossierFeatureServiceErrorCode =
  | "invalid_input"
  | "access_denied"
  | "invalid_response"
  | "technical";

export class DossierFeatureServiceError extends Error {
  readonly code: DossierFeatureServiceErrorCode;

  constructor(code: DossierFeatureServiceErrorCode, message: string) {
    super(message);
    this.name = "DossierFeatureServiceError";
    this.code = code;
  }
}

export type DossierFeatureRpcError = {
  code?: string | null;
  message?: string | null;
};

export type DossierFeatureRpcResult = {
  data: unknown;
  error: DossierFeatureRpcError | null;
};

export interface DossierFeatureRpcGateway {
  getCapabilities(protectedPersonId: string): Promise<DossierFeatureRpcResult>;
  checkAccess(input: {
    protectedPersonId: string;
    featureKey: DossierFeatureKey;
    accessMode: DossierFeatureAccessMode;
  }): Promise<DossierFeatureRpcResult>;
}

const featureKeySchema = z.enum(DOSSIER_FEATURE_KEYS);
const accessModeSchema = z.enum(DOSSIER_FEATURE_ACCESS_MODES);
const denialReasonSchema = z.enum(DOSSIER_FEATURE_DENIAL_REASONS);

const permissionConsistency = (
  allowed: boolean,
  denialReason: DossierFeatureDenialReason | null,
) => allowed ? denialReason === null : denialReason !== null;

const capabilityRowSchema = z.object({
  feature_key: featureKeySchema,
  implementation_status: z.enum(["available", "upcoming"]),
  can_read: z.boolean(),
  can_write: z.boolean(),
  read_denial_reason: denialReasonSchema.nullable(),
  write_denial_reason: denialReasonSchema.nullable(),
}).strict().superRefine((row, context) => {
  if (!permissionConsistency(row.can_read, row.read_denial_reason)) {
    context.addIssue({
      code: "custom",
      message: "Décision de lecture incohérente.",
    });
  }
  if (!permissionConsistency(row.can_write, row.write_denial_reason)) {
    context.addIssue({
      code: "custom",
      message: "Décision d’écriture incohérente.",
    });
  }
});

const capabilityRowsSchema = z.array(capabilityRowSchema).length(
  DOSSIER_FEATURE_KEYS.length,
).superRefine((rows, context) => {
  if (new Set(rows.map((row) => row.feature_key)).size !== DOSSIER_FEATURE_KEYS.length) {
    context.addIssue({
      code: "custom",
      message: "Liste de fonctionnalités incomplète.",
    });
  }
});

const accessRowSchema = z.object({
  allowed: z.boolean(),
  denial_reason: denialReasonSchema.nullable(),
}).strict().superRefine((row, context) => {
  if (!permissionConsistency(row.allowed, row.denial_reason)) {
    context.addIssue({
      code: "custom",
      message: "Décision d’accès incohérente.",
    });
  }
});

const accessRowsSchema = z.array(accessRowSchema).length(1);
const dossierIdSchema = z.uuid();
const accessInputSchema = z.object({
  protectedPersonId: dossierIdSchema,
  featureKey: featureKeySchema,
  accessMode: accessModeSchema,
}).strict();

const featureOrder = new Map<DossierFeatureKey, number>(
  DOSSIER_FEATURE_KEYS.map((featureKey, index) => [featureKey, index]),
);

export function parseDossierFeatureCapabilities(value: unknown): DossierFeatureCapability[] {
  const rows = capabilityRowsSchema.parse(value);
  return rows.map((row): DossierFeatureCapability => ({
    featureKey: row.feature_key,
    implementationStatus: row.implementation_status,
    read: {
      allowed: row.can_read,
      denialReason: row.read_denial_reason,
    },
    write: {
      allowed: row.can_write,
      denialReason: row.write_denial_reason,
    },
  })).sort((left, right) => (
    (featureOrder.get(left.featureKey) ?? 0) - (featureOrder.get(right.featureKey) ?? 0)
  ));
}

export function parseDossierFeatureAccessResult(
  value: unknown,
  featureKey: DossierFeatureKey,
  accessMode: DossierFeatureAccessMode,
): DossierFeatureAccessResult {
  const [row] = accessRowsSchema.parse(value);
  if (row.allowed) return { allowed: true, featureKey, accessMode };
  return {
    allowed: false,
    featureKey,
    accessMode,
    reason: row.denial_reason as DossierFeatureDenialReason,
  };
}

function invalidInput(): never {
  throw new DossierFeatureServiceError(
    "invalid_input",
    "Les paramètres de vérification des capacités sont invalides.",
  );
}

function classifyRpcError(error: DossierFeatureRpcError): never {
  if (error.code === "42501") {
    throw new DossierFeatureServiceError("access_denied", "Dossier introuvable.");
  }
  throw new DossierFeatureServiceError(
    "technical",
    "Impossible de vérifier les capacités du dossier.",
  );
}

async function callRpc(call: () => Promise<DossierFeatureRpcResult>) {
  let result: DossierFeatureRpcResult;
  try {
    result = await call();
  } catch {
    throw new DossierFeatureServiceError(
      "technical",
      "Impossible de vérifier les capacités du dossier.",
    );
  }
  if (result.error) classifyRpcError(result.error);
  return result.data;
}

function invalidResponse(): never {
  throw new DossierFeatureServiceError(
    "invalid_response",
    "La réponse du moteur de capacités est invalide.",
  );
}

export async function loadDossierFeatureCapabilities(
  gateway: DossierFeatureRpcGateway,
  protectedPersonId: string,
): Promise<DossierFeatureCapability[]> {
  const parsedId = dossierIdSchema.safeParse(protectedPersonId);
  if (!parsedId.success) invalidInput();

  const data = await callRpc(() => gateway.getCapabilities(parsedId.data));
  try {
    return parseDossierFeatureCapabilities(data);
  } catch {
    return invalidResponse();
  }
}

export async function verifyDossierFeatureAccess(
  gateway: DossierFeatureRpcGateway,
  input: {
    protectedPersonId: string;
    featureKey: DossierFeatureKey;
    accessMode: DossierFeatureAccessMode;
  },
): Promise<DossierFeatureAccessResult> {
  const parsedInput = accessInputSchema.safeParse(input);
  if (!parsedInput.success) invalidInput();

  const data = await callRpc(() => gateway.checkAccess(parsedInput.data));
  try {
    return parseDossierFeatureAccessResult(
      data,
      parsedInput.data.featureKey,
      parsedInput.data.accessMode,
    );
  } catch {
    return invalidResponse();
  }
}
