import { createHash } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/types/database";
import {
  AccountDeletionDurableAttentionError,
  inspectAccountOwnedStorageObject,
  resumeAccountStorageNeutralization,
  type AccountDeletionDurableAdminClient,
  type AccountDeletionDurableUserClient,
  type AccountDeletionOwnedObject,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "../account/account-deletion-durable.ts";

const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const storageObjectSchema = z.object({
  bucketId: z.enum(["transaction-proofs", "bank-statements", "management-reports"]),
  objectPath: z.string().min(1),
  objectId: uuid,
  objectVersion: z.string().min(1),
  catalogByteSize: z.number().int().positive().nullable(),
  catalogMimeType: z.string().nullable(),
  canonical: z.literal(true),
  protectedPersonId: uuid,
  businessEntityType: z.string().min(1),
  businessEntityId: uuid,
});
const diagnosticSchema = z.object({
  targetUserId: uuid,
  eligible: z.boolean(),
  businessBlockers: z.array(z.string()),
  blockingAnomalies: z.array(z.string()),
  storageObjects: z.array(storageObjectSchema),
  nonTerminalOperationCount: z.number().int().nonnegative(),
  unfinishedNeutralizationCount: z.number().int().nonnegative(),
  unclearedBackupCount: z.number().int().nonnegative(),
});
const authorizationSchema = z.object({
  authorizationId: uuid,
  administratorUserId: uuid,
  targetUserId: uuid,
  attemptId: uuid,
  planHash: sha256,
  documentCount: z.number().int().nonnegative(),
  expiresAt: z.string(),
  state: z.enum(["active", "sealed", "cancelled"]),
  revision: z.number().int().nonnegative(),
});
const planItemSchema = z.object({
  ordinal: z.number().int().positive(),
  bucketId: z.enum(["transaction-proofs", "bank-statements", "management-reports"]),
  objectPath: z.string().min(1),
  objectId: uuid,
  objectVersion: z.string().min(1),
  sha256,
  byteSize: z.number().int().positive(),
  mimeType: z.string().min(1),
  protectedPersonId: uuid,
  businessEntityType: z.string().min(1),
  businessEntityId: uuid,
});
const existingAuthorizationSchema = authorizationSchema.extend({
  reason: z.string().min(1),
  documentPlan: z.array(planItemSchema),
});
const operationSchema = z.object({
  operation_id: uuid,
  client_request_id: uuid,
  state: z.string(),
  phase: z.string(),
  created_at: z.string(),
});
const beginSchema = z.object({ operationId: uuid });
const barrierSchema = z.object({
  ready: z.literal(true),
  targetAuthExists: z.boolean().optional(),
});

type RpcResult = { data: unknown; error: unknown | null };
type RpcClient = { rpc(name: string, args?: Record<string, unknown>): PromiseLike<RpcResult> };
type AdminAuthClient = AccountDeletionDurableAdminClient & {
  auth: { admin: {
    deleteUser(userId: string): PromiseLike<{ data: { user: { id: string } | null }; error: unknown | null }>;
    getUserById(userId: string): PromiseLike<{ data: { user: { id: string } | null }; error: unknown | null }>;
  } };
};

type PlanItem = z.infer<typeof planItemSchema>;

export class AdministrativeAccountDeletionError extends Error {
  readonly safeCode: string;

  constructor(message = "La suppression administrative durable a été refusée.", safeCode = "") {
    super(message);
    this.safeCode = safeCode;
  }
}
export class AdministrativeAccountDeletionAuthOutcomeUnknownError extends Error {}

function code(error: unknown) {
  return typeof error === "object" && error !== null && "code" in error ? String(error.code) : "";
}

async function rpc(client: RpcClient, name: string, args: Record<string, unknown> = {}) {
  const result = await client.rpc(name, args);
  if (result.error) throw new AdministrativeAccountDeletionError(undefined, code(result.error));
  return result.data;
}

function requestId(attemptId: string, bucketId: string, path: string) {
  const digest = createHash("sha256")
    .update("patrigest:administrative-account-storage-neutralization:v1\0")
    .update(attemptId).update("\0").update(bucketId).update("\0").update(path)
    .digest().subarray(0, 16);
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = Buffer.from(digest).toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function asOwnedObject(item: z.infer<typeof storageObjectSchema>): AccountDeletionOwnedObject {
  return { bucket_id: item.bucketId, name: item.objectPath, metadata: {} as Json, user_metadata: {} as Json };
}

export async function prepareAdministrativeAccountDeletionPlan(
  session: AccountDeletionDurableUserClient,
  admin: AccountDeletionDurableAdminClient,
  targetUserId: string,
) {
  const diagnostic = diagnosticSchema.parse(await rpc(
    session,
    "get_administrative_account_deletion_diagnostic",
    { p_target_user_id: targetUserId },
  ));
  if (!diagnostic.eligible || diagnostic.businessBlockers.length) {
    throw new AdministrativeAccountDeletionError("Le compte ne satisfait pas les conditions de suppression.");
  }
  if (diagnostic.blockingAnomalies.length) {
    throw new AdministrativeAccountDeletionError("L’état documentaire doit être vérifié avant la suppression.");
  }
  const plan: PlanItem[] = [];
  for (const [index, item] of diagnostic.storageObjects.entries()) {
    const observed = await inspectAccountOwnedStorageObject(admin, asOwnedObject(item));
    if (observed.objectId !== item.objectId || observed.objectVersion !== item.objectVersion) {
      throw new AdministrativeAccountDeletionError("L’inventaire documentaire a changé.");
    }
    if (item.catalogByteSize !== null && item.catalogByteSize !== observed.byteSize) {
      throw new AdministrativeAccountDeletionError("La taille d’un document a divergé.");
    }
    if (item.catalogMimeType !== null && item.catalogMimeType !== observed.mimeType) {
      throw new AdministrativeAccountDeletionError("Le type d’un document a divergé.");
    }
    plan.push({
      ordinal: index + 1,
      bucketId: item.bucketId,
      objectPath: item.objectPath,
      objectId: observed.objectId,
      objectVersion: observed.objectVersion,
      sha256: observed.sha256,
      byteSize: observed.byteSize,
      mimeType: observed.mimeType,
      protectedPersonId: item.protectedPersonId,
      businessEntityType: item.businessEntityType,
      businessEntityId: item.businessEntityId,
    });
  }
  return { diagnostic, plan };
}

async function beginAdministrativeNeutralization(
  session: AccountDeletionDurableUserClient,
  authorizationId: string,
  attemptId: string,
  item: PlanItem,
) {
  const result = beginSchema.parse(await rpc(session, "begin_administrative_account_storage_neutralization", {
    p_authorization_id: authorizationId,
    p_client_request_id: requestId(attemptId, item.bucketId, item.objectPath),
    p_bucket_id: item.bucketId,
    p_object_path: item.objectPath,
    p_expected_object_id: item.objectId,
    p_expected_object_version: item.objectVersion,
    p_expected_sha256: item.sha256,
    p_expected_byte_size: item.byteSize,
    p_mime_type: item.mimeType,
  }));
  return result.operationId;
}

async function deleteAuthUserWithVerification(admin: AdminAuthClient, targetUserId: string) {
  let confirmed = false;
  try {
    const deleted = await admin.auth.admin.deleteUser(targetUserId);
    confirmed = !deleted.error && deleted.data.user?.id === targetUserId;
  } catch {
    // Une réponse perdue est qualifiée par une lecture Auth autoritaire.
  }
  if (!confirmed) {
    let verification;
    try {
      verification = await admin.auth.admin.getUserById(targetUserId);
    } catch {
      throw new AdministrativeAccountDeletionAuthOutcomeUnknownError(
        "Le résultat de la suppression Auth ne peut pas être confirmé.",
      );
    }
    if (verification.data.user?.id === targetUserId) {
      throw new AdministrativeAccountDeletionError("La suppression Auth a été refusée.");
    }
    const errorCode = code(verification.error);
    const status = typeof verification.error === "object" && verification.error !== null && "status" in verification.error
      ? String(verification.error.status)
      : "";
    if ((!verification.error && !verification.data.user) || errorCode === "user_not_found" || status === "404") {
      confirmed = true;
    } else {
      throw new AdministrativeAccountDeletionAuthOutcomeUnknownError(
        "Le résultat de la suppression Auth ne peut pas être confirmé.",
      );
    }
  }
  return { accountDeleted: confirmed as true };
}

export async function deletePlatformUserWithDurableNeutralization(
  session: AccountDeletionDurableUserClient,
  admin: AdminAuthClient,
  input: { administratorUserId: string; targetUserId: string; attemptId: string; reason: string },
) {
  if (input.administratorUserId === input.targetUserId) {
    throw new AdministrativeAccountDeletionError("Vous ne pouvez pas supprimer votre propre compte administrateur.");
  }
  const priorData = await rpc(session, "get_administrative_account_deletion_attempt", {
    p_target_user_id: input.targetUserId,
    p_attempt_id: input.attemptId,
  });
  let plan: PlanItem[];
  let authorization: z.infer<typeof authorizationSchema>;
  if (priorData === null) {
    ({ plan } = await prepareAdministrativeAccountDeletionPlan(session, admin, input.targetUserId));
    authorization = authorizationSchema.parse(await rpc(
      session,
      "issue_administrative_account_deletion_authorization",
      {
        p_target_user_id: input.targetUserId,
        p_attempt_id: input.attemptId,
        p_reason: input.reason,
        p_document_plan: plan,
      },
    ));
  } else {
    const prior = existingAuthorizationSchema.parse(priorData);
    if (prior.reason !== input.reason.trim()) {
      throw new AdministrativeAccountDeletionError("La tentative est déjà liée à un autre motif.");
    }
    plan = prior.documentPlan;
    authorization = prior;
  }
  if (authorization.administratorUserId !== input.administratorUserId || authorization.targetUserId !== input.targetUserId) {
    throw new AdministrativeAccountDeletionError("L’autorisation administrative ne correspond pas à la demande.");
  }
  const existing = operationSchema.array().parse(await rpc(
    admin,
    "list_administrative_account_storage_neutralization_operations",
    { p_authorization_id: authorization.authorizationId },
  ));
  for (const operation of existing) {
    if (operation.phase !== "finalized") {
      await resumeAccountStorageNeutralization(admin, operation.operation_id);
    }
  }
  if (existing.some((operation) => operation.phase === "attention_required")) {
    throw new AccountDeletionDurableAttentionError("Une neutralisation documentaire requiert une intervention.");
  }
  if (authorization.state === "cancelled") {
    throw new AdministrativeAccountDeletionError("Cette tentative de suppression a été annulée.");
  }

  if (authorization.state === "active") {
    for (const item of plan) {
      const itemRequestId = requestId(input.attemptId, item.bucketId, item.objectPath);
      if (existing.some((operation) => operation.client_request_id === itemRequestId)) continue;
      const operationId = await beginAdministrativeNeutralization(
        session, authorization.authorizationId, input.attemptId, item,
      );
      await resumeAccountStorageNeutralization(admin, operationId);
    }
  }

  const barrier = barrierSchema.parse(await rpc(
    session,
    "assert_administrative_account_deletion_barrier",
    {
      p_authorization_id: authorization.authorizationId,
      p_expected_revision: authorization.revision,
      p_expected_plan_hash: authorization.planHash,
    },
  ));
  if (!barrier.ready) throw new AdministrativeAccountDeletionError();
  if (barrier.targetAuthExists === false) return { accountDeleted: true as const, alreadyAbsent: true as const };
  return { ...(await deleteAuthUserWithVerification(admin, input.targetUserId)), alreadyAbsent: false as const };
}
