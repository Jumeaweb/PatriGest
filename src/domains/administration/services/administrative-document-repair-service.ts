import "server-only";

import { createHash } from "node:crypto";
import { z } from "zod";
import { createAdminClient } from "@/lib/supabase/admin";
import { requirePlatformAdministrator } from "./administration-service";
import {
  AdministrativeDocumentRepairEngine,
  AdministrativeDocumentRepairError,
  backupCleanupDescriptorSchema,
  getAdministrativeRepairGuardBlockReason,
  isAdminDocumentRepairEnabled,
  repairProgressSchema,
  type AdministrativeDocumentRepairAction,
  type AdministrativeRepairRpcGateway,
  type AdministrativeRepairStorageGateway,
  type RepairContext,
} from "../administrative-document-repair";

const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const bucket = z.enum(["transaction-proofs", "bank-statements", "management-reports"]);
const targetSchema = z.object({
  targetId: uuid,
  ordinal: z.number().int().positive(),
  bucketId: bucket,
  objectPath: z.string().min(1),
  targetRole: z.enum(["primary", "source", "destination"]),
  forwardAction: z.enum(["insert", "update", "delete"]),
  compensationAction: z.enum(["insert", "update", "delete"]).nullable(),
  applicationState: z.enum(["pending", "applied", "compensating", "compensated"]),
  targetRevision: z.number().int().nonnegative(),
  catalogObservation: z.object({
    exists: z.boolean(), objectId: uuid.nullable(), objectVersion: z.string().nullable(),
  }),
  backup: z.object({
    backupId: uuid,
    state: z.enum(["upload_pending", "verified", "restored", "deleted", "attention_required"]),
    revision: z.number().int().nonnegative(),
  }).nullable(),
  lockPresent: z.boolean(),
});
const diagnosticSchema = z.object({
  operationId: uuid,
  workflow: z.string().min(1),
  businessEntityType: z.string().min(1),
  state: z.string(),
  revision: z.number().int().nonnegative(),
  safeErrorCode: z.string().nullable(),
  repairable: z.boolean(),
  targets: z.array(targetSchema),
  conflictingLocks: z.array(z.unknown()),
  conflictingNeutralizations: z.array(z.unknown()),
  activeAuthorization: z.object({
    ownedByCaller: z.boolean(),
    state: z.string(),
    expiresAt: z.string(),
    authorizationId: uuid.optional(),
    attemptId: uuid.optional(),
    revision: z.number().int().nonnegative().optional(),
  }).nullable(),
});
const authorizationSchema = z.object({
  authorizationId: uuid,
  operationId: uuid,
  attemptId: uuid,
  planHash: sha256,
  state: z.enum(["active", "cancelled", "sealed"]),
  expiresAt: z.string(),
  revision: z.number().int().nonnegative(),
});
const capabilitiesSchema = z.object({ storageGuardEnabled: z.boolean() });

type RpcClient = { rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown | null }> };
type UntypedTableClient = { from(table: string): {
  select(columns: string): { eq(column: string, value: unknown): { order(column: string, options: { ascending: boolean }): { limit(value: number): PromiseLike<{ data: unknown; error: unknown | null }> } } };
} };

function safeRpcError(error: unknown) {
  const code = typeof error === "object" && error && "code" in error ? String(error.code) : "";
  if (code === "P4R01") return "Cette réparation n’est pas autorisée.";
  if (code === "P4R04") return "L’état documentaire a changé. Actualisez le diagnostic.";
  if (code === "P4R05") return "La tentative ou le plan de réparation a expiré ou divergé.";
  if (code === "P4R06") return "Une autre opération documentaire est en conflit.";
  if (code === "P4R07") return "Les preuves documentaires sont insuffisantes ou divergentes.";
  if (code === "P4R08") return "Cette action exige la future garde Storage et ne peut pas encore être autorisée.";
  return "L’opération de réparation a été refusée.";
}

async function rpc(client: RpcClient, name: string, args: Record<string, unknown> = {}) {
  const result = await client.rpc(name, args);
  if (result.error) throw new AdministrativeDocumentRepairError(safeRpcError(result.error));
  return result.data;
}

function availableActions(target: z.infer<typeof targetSchema>): AdministrativeDocumentRepairAction[] {
  const actions: AdministrativeDocumentRepairAction[] = [];
  if (["applied", "compensating"].includes(target.applicationState) && target.compensationAction) {
    actions.push("resume_compensation");
  }
  if (target.backup && ["verified", "restored"].includes(target.backup.state)) actions.push("restore_original");
  if (target.backup && ["verified", "restored", "deleted"].includes(target.backup.state)) actions.push("complete_backup_cleanup");
  if (!target.backup) actions.push("confirm_already_conform");
  actions.push("accept_residual_state");
  return actions;
}

export type AdministrativeRepairTargetView = {
  targetId: string;
  ordinal: number;
  bucketLabel: string;
  applicationState: string;
  catalogObjectPresent: boolean;
  backupState: string | null;
  lockPresent: boolean;
  actions: AdministrativeDocumentRepairAction[];
  blockedActions: Array<{ action: AdministrativeDocumentRepairAction; reason: string }>;
};

async function getRepairCapabilities(client: RpcClient) {
  return capabilitiesSchema.parse(await rpc(client, "get_administrative_document_repair_capabilities"));
}

function actionCapabilities(
  target: z.infer<typeof targetSchema>,
  storageGuardEnabled: boolean,
) {
  const actions: AdministrativeDocumentRepairAction[] = [];
  const blockedActions: Array<{ action: AdministrativeDocumentRepairAction; reason: string }> = [];
  for (const action of availableActions(target)) {
    const reason = getAdministrativeRepairGuardBlockReason(action, {
      catalogObjectPresent: target.catalogObservation.exists,
      compensationAction: target.compensationAction,
    }, storageGuardEnabled);
    if (reason) blockedActions.push({ action, reason });
    else actions.push(action);
  }
  return { actions, blockedActions };
}

export async function getAdministrativeDocumentRepairPageData(operationId?: string) {
  const { supabase } = await requirePlatformAdministrator();
  if (!isAdminDocumentRepairEnabled()) {
    return { enabled: false as const, operations: [], diagnostic: null };
  }
  const admin = createAdminClient();
  const result = await (admin as unknown as UntypedTableClient)
    .from("document_operations")
    .select("id,workflow,business_entity_type,state,safe_error_code,created_at")
    .eq("state", "attention_required")
    .order("created_at", { ascending: false })
    .limit(50);
  if (result.error || !Array.isArray(result.data)) throw new Error("Impossible de charger les anomalies documentaires.");
  const operations = z.array(z.object({
    id: uuid, workflow: z.string(), business_entity_type: z.string(),
    state: z.string(), safe_error_code: z.string().nullable(), created_at: z.string(),
  })).parse(result.data);
  if (!operationId) return { enabled: true as const, operations, diagnostic: null };
  const diagnostic = diagnosticSchema.parse(await rpc(supabase as unknown as RpcClient, "get_administrative_document_repair_diagnostic", { p_operation_id: uuid.parse(operationId) }));
  const capabilities = await getRepairCapabilities(supabase as unknown as RpcClient);
  return {
    enabled: true as const,
    operations,
    diagnostic: {
      operationId: diagnostic.operationId,
      workflow: diagnostic.workflow,
      businessEntityType: diagnostic.businessEntityType,
      state: diagnostic.state,
      revision: diagnostic.revision,
      safeErrorCode: diagnostic.safeErrorCode,
      repairable: diagnostic.repairable,
      blocked: diagnostic.conflictingLocks.length > 0 || diagnostic.conflictingNeutralizations.length > 0,
      activeAttemptId: diagnostic.activeAuthorization?.ownedByCaller ? diagnostic.activeAuthorization.attemptId ?? null : null,
      ownedByAnotherAdministrator: diagnostic.activeAuthorization?.ownedByCaller === false,
      targets: diagnostic.targets.map((target): AdministrativeRepairTargetView => {
        const actionState = actionCapabilities(target, capabilities.storageGuardEnabled);
        return {
          targetId: target.targetId,
          ordinal: target.ordinal,
          bucketLabel: target.bucketId === "transaction-proofs" ? "Justificatif d’opération" : target.bucketId === "bank-statements" ? "Relevé bancaire" : "Compte de gestion",
          applicationState: target.applicationState,
          catalogObjectPresent: target.catalogObservation.exists,
          backupState: target.backup?.state ?? null,
          lockPresent: target.lockPresent,
          actions: actionState.actions,
          blockedActions: actionState.blockedActions,
        };
      }),
    },
  };
}

function checksum(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function createStorageGateway(admin: ReturnType<typeof createAdminClient>): AdministrativeRepairStorageGateway {
  return {
    async inspect(bucketId, objectPath) {
      const storage = admin.storage.from(bucketId);
      const exists = await storage.exists(objectPath);
      if (!exists.data && (!exists.error || String((exists.error as { statusCode?: string }).statusCode) === "400")) return null;
      if (exists.error || !exists.data) throw new AdministrativeDocumentRepairError("Le catalogue Storage est indisponible.");
      const [info, downloaded] = await Promise.all([storage.info(objectPath), storage.download(objectPath)]);
      if (info.error || !info.data?.id || !info.data.version || downloaded.error || !downloaded.data) {
        throw new AdministrativeDocumentRepairError("La lecture physique du document a échoué.");
      }
      const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
      return {
        bytes,
        byteSize: bytes.byteLength,
        mimeType: downloaded.data.type || "application/octet-stream",
        sha256: checksum(bytes),
        objectId: info.data.id,
        objectVersion: info.data.version,
      };
    },
    async upload(bucketId, objectPath, bytes, mimeType, upsert) {
      const result = await admin.storage.from(bucketId).upload(objectPath, bytes, { contentType: mimeType, upsert });
      if (result.error) throw result.error;
    },
    async remove(bucketId, objectPath) {
      const result = await admin.storage.from(bucketId).remove([objectPath]);
      if (result.error) throw result.error;
    },
  };
}

function createRpcGateway(admin: RpcClient): AdministrativeRepairRpcGateway {
  return {
    async progress(context) {
      return repairProgressSchema.parse(await rpc(admin, "get_administrative_document_repair_progress_for_service", {
        p_authorization_id: context.authorizationId,
        p_administrator_subject_id: context.administratorSubjectId,
        p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash,
      }));
    },
    async start(context, item, executionId, authorizationRevision) {
      await rpc(admin, "start_administrative_document_repair_item", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_expected_action: item.action,
        p_execution_id: executionId, p_expected_authorization_revision: authorizationRevision,
        p_expected_item_revision: item.revision,
      });
    },
    async observe(context, item, executionId, observation) {
      await rpc(admin, "record_administrative_document_repair_observation", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_expected_action: item.action,
        p_execution_id: executionId, p_expected_item_revision: item.revision,
        p_observation_kind: observation.kind, p_object_exists: observation.object !== null,
        p_object_id: observation.object?.objectId ?? null,
        p_object_version: observation.object?.objectVersion ?? null,
        p_byte_size: observation.physicalBytesVerified ? observation.object?.byteSize ?? null : null,
        p_sha256: observation.physicalBytesVerified ? observation.object?.sha256 ?? null : null,
        p_backup_present: observation.backupPresent,
        p_backup_id: observation.backup?.backupId ?? null,
        p_backup_revision: observation.backup?.revision ?? null,
        p_backup_state: observation.backup?.state ?? null,
      });
    },
    async verify(context, item, executionId, result) {
      await rpc(admin, "verify_administrative_document_repair_item", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_expected_action: item.action,
        p_execution_id: executionId, p_expected_item_revision: item.revision,
        p_result_kind: result.resultKind, p_backup_disposition: result.backupDisposition,
      });
    },
    async markBackupRestored(context, item, executionId) {
      await rpc(admin, "mark_administrative_document_repair_backup_restored", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_execution_id: executionId,
        p_expected_item_revision: item.revision, p_expected_backup_revision: item.backup?.revision,
      });
    },
    async authorizeBackupCleanup(context, item, executionId) {
      return backupCleanupDescriptorSchema.parse(await rpc(admin, "authorize_administrative_document_repair_backup_cleanup", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_execution_id: executionId,
        p_expected_item_revision: item.revision, p_expected_backup_revision: item.backup?.revision,
      }));
    },
    async completeBackupCleanup(context, item, executionId, expectedBackupRevision) {
      await rpc(admin, "complete_administrative_document_repair_backup_cleanup", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_execution_id: executionId,
        p_expected_item_revision: item.revision, p_expected_backup_revision: expectedBackupRevision,
      });
    },
  };
}

export async function authorizeAndExecuteAdministrativeDocumentRepair(input: {
  operationId: string;
  attemptId: string;
  reason: string;
  decisions: Array<{ targetId: string; action: AdministrativeDocumentRepairAction; residualReason?: string }>;
}) {
  if (!isAdminDocumentRepairEnabled()) throw new AdministrativeDocumentRepairError("La réparation documentaire administrative est désactivée.");
  const { supabase, userId } = await requirePlatformAdministrator();
  const operationId = uuid.parse(input.operationId);
  const attemptId = uuid.parse(input.attemptId);
  const reason = z.string().trim().min(1).max(2000).parse(input.reason);
  const diagnostic = diagnosticSchema.parse(await rpc(supabase as unknown as RpcClient, "get_administrative_document_repair_diagnostic", { p_operation_id: operationId }));
  const capabilities = await getRepairCapabilities(supabase as unknown as RpcClient);
  if (!diagnostic.repairable || diagnostic.conflictingLocks.length || diagnostic.conflictingNeutralizations.length) {
    throw new AdministrativeDocumentRepairError("Cette opération ne peut pas être réparée dans son état actuel.");
  }
  const byTarget = new Map(input.decisions.map((decision) => [uuid.parse(decision.targetId), decision]));
  if (byTarget.size !== diagnostic.targets.length) throw new AdministrativeDocumentRepairError("Une décision est requise pour chaque cible.");
  const plan = diagnostic.targets.map((target) => {
    const decision = byTarget.get(target.targetId);
    const actionState = actionCapabilities(target, capabilities.storageGuardEnabled);
    if (!decision || !actionState.actions.includes(decision.action)) {
      const blocked = decision && actionState.blockedActions.find(({ action }) => action === decision.action);
      throw new AdministrativeDocumentRepairError(blocked?.reason ?? "Une action de réparation est invalide.", blocked ? "STORAGE_GUARD_REQUIRED" : "INVALID_ACTION");
    }
    const residualReason = decision.action === "accept_residual_state"
      ? z.string().trim().min(1).max(2000).parse(decision.residualReason)
      : null;
    return {
      targetId: target.targetId,
      action: decision.action,
      expectedTargetRevision: target.targetRevision,
      expectedApplicationState: target.applicationState,
      expectedObjectExists: target.catalogObservation.exists,
      expectedObjectId: target.catalogObservation.objectId,
      expectedObjectVersion: target.catalogObservation.objectVersion,
      backupId: target.backup?.backupId ?? null,
      expectedBackupRevision: target.backup?.revision ?? null,
      expectedBackupState: target.backup?.state ?? null,
      residualReason,
    };
  });
  const authorization = authorizationSchema.parse(await rpc(supabase as unknown as RpcClient, "issue_administrative_document_repair_authorization", {
    p_operation_id: operationId,
    p_expected_operation_revision: diagnostic.revision,
    p_attempt_id: attemptId,
    p_reason: reason,
    p_repair_plan: plan,
  }));
  const admin = createAdminClient();
  const executionCapabilities = await getRepairCapabilities(supabase as unknown as RpcClient);
  const context: RepairContext = {
    authorizationId: authorization.authorizationId,
    administratorSubjectId: userId,
    attemptId,
    planHash: authorization.planHash,
    compensationActions: new Map(diagnostic.targets.map((target) => [target.targetId, target.compensationAction])),
    expectedObjects: new Map(diagnostic.targets.map((target) => [target.targetId, {
      exists: target.catalogObservation.exists,
      objectId: target.catalogObservation.objectId,
      objectVersion: target.catalogObservation.objectVersion,
    }])),
    storageGuardEnabled: executionCapabilities.storageGuardEnabled,
  };
  const engine = new AdministrativeDocumentRepairEngine(
    createRpcGateway(admin as unknown as RpcClient),
    createStorageGateway(admin),
  );
  const progress = await engine.execute(context);
  const sealed = authorizationSchema.pick({ authorizationId: true, operationId: true, state: true, revision: true }).parse(
    await rpc(supabase as unknown as RpcClient, "seal_administrative_document_repair", {
      p_authorization_id: authorization.authorizationId,
      p_expected_revision: progress.revision,
      p_expected_plan_hash: authorization.planHash,
    }),
  );
  return { operationId, state: sealed.state, residualAccepted: plan.some(({ action }) => action === "accept_residual_state") };
}

export async function renewAdministrativeDocumentRepair(input: {
  operationId: string; attemptId: string; renewalId: string;
}) {
  if (!isAdminDocumentRepairEnabled()) throw new AdministrativeDocumentRepairError("La réparation documentaire administrative est désactivée.");
  const { supabase } = await requirePlatformAdministrator();
  const authorizationData = await rpc(supabase as unknown as RpcClient, "get_administrative_document_repair_authorization", {
    p_operation_id: uuid.parse(input.operationId), p_attempt_id: uuid.parse(input.attemptId),
  });
  const authorization = z.object({
    authorizationId: uuid, attemptId: uuid, planHash: sha256,
    revision: z.number().int().nonnegative(), state: z.string(), renewalCount: z.number().int().min(0).max(6),
  }).parse(authorizationData);
  if (authorization.state !== "active" || authorization.renewalCount >= 6) throw new AdministrativeDocumentRepairError("Cette tentative ne peut plus être prolongée.");
  return rpc(supabase as unknown as RpcClient, "renew_administrative_document_repair_authorization", {
    p_authorization_id: authorization.authorizationId,
    p_attempt_id: authorization.attemptId,
    p_expected_plan_hash: authorization.planHash,
    p_renewal_id: uuid.parse(input.renewalId),
    p_expected_revision: authorization.revision,
  });
}
