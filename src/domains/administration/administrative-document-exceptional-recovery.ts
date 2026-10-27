import { z } from "zod";

const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const timestamp = z.iso.datetime({ offset: true });

export const exceptionalRecoveryStateSchema = z.enum([
  "requested",
  "approved",
  "active",
  "expired",
  "rejected",
  "consumed",
]);

export const exceptionalRecoveryActivationSchema = z.object({
  ordinal: z.number().int().min(1).max(2),
  activatedAt: timestamp,
  expiresAt: timestamp,
  activatedByCaller: z.boolean(),
});

export const exceptionalRecoveryEventSchema = z.object({
  sequenceNumber: z.number().int().positive(),
  eventType: z.enum(["requested", "approved", "rejected", "activated", "consumed"]),
  outcome: z.enum(["success", "information"]),
  safeCode: z.string().nullable(),
  occurredAt: timestamp,
  actorIsCaller: z.boolean(),
});

export const exceptionalRecoverySummarySchema = z.object({
  recoveryId: uuid,
  authorizationId: uuid,
  operationId: uuid,
  state: z.literal("requested"),
  reason: z.string().min(1).max(2000),
  requestedAt: timestamp,
  revision: z.number().int().nonnegative(),
  requesterIsCaller: z.boolean(),
  canApprove: z.boolean(),
});

export const exceptionalRecoverySchema = z.object({
  recoveryId: uuid,
  authorizationId: uuid,
  operationId: uuid,
  state: exceptionalRecoveryStateSchema,
  reason: z.string().min(1).max(2000),
  decisionReason: z.string().min(1).max(2000).nullable(),
  requestedAt: timestamp,
  decidedAt: timestamp.nullable(),
  expiresAt: timestamp.nullable(),
  activationCount: z.number().int().min(0).max(2),
  maxActivations: z.literal(2),
  revision: z.number().int().nonnegative(),
  requesterIsCaller: z.boolean(),
  approverIsCaller: z.boolean(),
  canApprove: z.boolean(),
  activations: z.array(exceptionalRecoveryActivationSchema).max(2),
  history: z.array(exceptionalRecoveryEventSchema),
});

export const exceptionalRecoveryListSchema = z.object({
  items: z.array(exceptionalRecoverySummarySchema).max(50),
  hasMore: z.boolean(),
  limit: z.number().int().min(1).max(50),
  nextRequestedAt: timestamp.nullable(),
  nextId: uuid.nullable(),
}).superRefine((value, context) => {
  if (value.hasMore !== Boolean(value.nextRequestedAt && value.nextId)) {
    context.addIssue({ code: "custom", message: "Curseur de récupération incohérent." });
  }
});

export const exceptionalRepairAuthorizationSchema = z.object({
  authorizationId: uuid,
  operationId: uuid,
  administratorSubjectId: uuid,
  attemptId: uuid,
  reason: z.string().min(1),
  repairPlan: z.array(z.object({
    targetId: uuid,
    action: z.enum([
      "resume_compensation",
      "restore_original",
      "complete_backup_cleanup",
      "confirm_already_conform",
      "accept_residual_state",
    ]),
    expectedTargetRevision: z.number().int().nonnegative(),
    expectedApplicationState: z.enum(["pending", "applied", "compensating", "compensated"]),
    expectedObjectExists: z.boolean(),
    expectedObjectId: uuid.nullable(),
    expectedObjectVersion: z.string().nullable(),
    backupId: uuid.nullable(),
    expectedBackupRevision: z.number().int().nonnegative().nullable(),
    expectedBackupState: z.string().nullable(),
    residualReason: z.string().nullable(),
  })).min(1),
  planHash: sha256,
  state: z.enum(["active", "cancelled", "sealed"]),
  revision: z.number().int().nonnegative(),
  expiresAt: timestamp,
  renewalCount: z.number().int().min(0).max(6),
});

export const exceptionalRecoveryRequestSchema = z.object({
  operationId: uuid,
  authorizationId: uuid,
  attemptId: uuid,
  expectedPlanHash: sha256,
  requestId: uuid,
  reason: z.string().trim().min(1).max(2000),
  expectedAuthorizationRevision: z.coerce.number().int().nonnegative(),
  confirmation: z.literal("on"),
});

export const exceptionalRecoveryDecisionSchema = z.object({
  operationId: uuid,
  recoveryId: uuid,
  decisionId: uuid,
  decision: z.enum(["approve", "reject"]),
  reason: z.string().trim().min(1).max(2000),
  expectedRevision: z.coerce.number().int().nonnegative(),
  confirmation: z.literal("on"),
});

export const exceptionalRecoveryActivationRequestSchema = z.object({
  operationId: uuid,
  recoveryId: uuid,
  activationId: uuid,
  expectedRevision: z.coerce.number().int().nonnegative(),
  confirmation: z.literal("on"),
});

export const exceptionalRecoveryResumeSchema = z.object({
  operationId: uuid,
  attemptId: uuid,
  confirmation: z.literal("on"),
});

export type AdministrativeDocumentExceptionalRecovery = z.infer<typeof exceptionalRecoverySchema>;
export type AdministrativeDocumentExceptionalRecoverySummary = z.infer<typeof exceptionalRecoverySummarySchema>;
export type AdministrativeDocumentExceptionalRecoveryList = z.infer<typeof exceptionalRecoveryListSchema>;
export type AdministrativeExceptionalRepairAuthorization = z.infer<typeof exceptionalRepairAuthorizationSchema>;

export function isExceptionalRecoveryRequestEligible(
  authorization: AdministrativeExceptionalRepairAuthorization | null,
  now = Date.now(),
) {
  return Boolean(
    authorization
    && authorization.state === "active"
    && authorization.renewalCount === 6
    && Date.parse(authorization.expiresAt) <= now,
  );
}

export function getExceptionalRecoveryErrorMessage(error: unknown) {
  const code = typeof error === "object" && error && "code" in error ? String(error.code) : "";
  if (code === "P4X01") return "Cette récupération exceptionnelle n’est pas autorisée.";
  if (code === "P4X02") return "La demande de récupération exceptionnelle est invalide.";
  if (code === "P4X03") return "La réparation n’est pas éligible ou la fenêtre a expiré.";
  if (code === "P4X04") return "Le plan, les cibles ou les révisions ont changé. Actualisez la page.";
  if (code === "P4X05") return "Une décision concurrente ou une clé déjà utilisée a été détectée.";
  if (code === "P4X06") return "Une opération concurrente empêche cette récupération.";
  if (code === "P4X07") return "Les deux activations exceptionnelles ont été consommées.";
  return "L’opération de récupération exceptionnelle a été refusée.";
}

export const exceptionalRecoveryStateLabels: Record<z.infer<typeof exceptionalRecoveryStateSchema>, string> = {
  requested: "En attente d’une validation indépendante",
  approved: "Approuvée, activation disponible",
  active: "Fenêtre active",
  expired: "Fenêtre expirée",
  rejected: "Refusée",
  consumed: "Consommée par le scellement",
};
