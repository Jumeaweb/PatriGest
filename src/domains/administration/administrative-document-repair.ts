import { createHash } from "node:crypto";
import { z } from "zod";

export const ADMIN_DOCUMENT_REPAIR_ENV = "PATRIGEST_ENABLE_ADMIN_DOCUMENT_REPAIR";

export function isAdminDocumentRepairEnabled() {
  return process.env[ADMIN_DOCUMENT_REPAIR_ENV] === "true";
}

export const repairActionSchema = z.enum([
  "resume_compensation",
  "restore_original",
  "complete_backup_cleanup",
  "confirm_already_conform",
  "accept_residual_state",
]);
export type AdministrativeDocumentRepairAction = z.infer<typeof repairActionSchema>;

export type AdministrativeRepairGuardTarget = {
  catalogObjectPresent: boolean;
  compensationAction: "insert" | "update" | "delete" | null;
};

export function getAdministrativeRepairGuardBlockReason(
  action: AdministrativeDocumentRepairAction,
  target: AdministrativeRepairGuardTarget,
  storageGuardEnabled: boolean,
) {
  if (storageGuardEnabled) return null;
  if (action === "complete_backup_cleanup") {
    return "Le nettoyage physique de la sauvegarde exige la future garde Storage.";
  }
  if (action === "resume_compensation" && target.compensationAction === "delete") {
    return "La suppression compensatoire exige la future garde Storage.";
  }
  if (["restore_original", "resume_compensation"].includes(action) && target.catalogObjectPresent) {
    return "La cible est actuellement présente : son éventuel écrasement exige la future garde Storage.";
  }
  return null;
}

const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const bucket = z.enum(["transaction-proofs", "bank-statements", "management-reports"]);
const backupState = z.enum(["upload_pending", "verified", "restored", "deleted", "attention_required"]);

const backupSchema = z.object({
  backupId: uuid,
  state: backupState,
  revision: z.number().int().nonnegative(),
  byteSize: z.number().int().nonnegative().nullable(),
  sha256: sha256.nullable(),
  recoveryObjectPath: z.string().min(1).nullable(),
  recoveryObjectId: uuid.nullable(),
  recoveryObjectVersion: z.string().min(1).nullable(),
});

export const repairProgressSchema = z.object({
  authorizationId: uuid,
  operationId: uuid,
  administratorSubjectId: uuid,
  attemptId: uuid,
  planHash: sha256,
  state: z.enum(["active", "cancelled", "sealed"]),
  revision: z.number().int().nonnegative(),
  expiresAt: z.string(),
  expired: z.boolean(),
  items: z.array(z.object({
    itemId: uuid,
    targetId: uuid,
    ordinal: z.number().int().positive(),
    action: repairActionSchema,
    progressState: z.enum(["authorized", "executing", "verification_required", "verified"]),
    revision: z.number().int().nonnegative(),
    executionId: uuid.nullable(),
    bucketId: bucket,
    objectPath: z.string().min(1),
    targetRevision: z.number().int().nonnegative(),
    applicationState: z.enum(["pending", "applied", "compensating", "compensated"]),
    observedObjectExists: z.boolean().nullable(),
    observedObjectId: uuid.nullable(),
    observedObjectVersion: z.string().nullable(),
    observedByteSize: z.number().int().nonnegative().nullable(),
    observedSha256: sha256.nullable(),
    backup: backupSchema.nullable(),
  })),
});
export type AdministrativeDocumentRepairProgress = z.infer<typeof repairProgressSchema>;
type RepairItem = AdministrativeDocumentRepairProgress["items"][number];

export type PhysicalDocumentObject = {
  bytes: Uint8Array;
  byteSize: number;
  mimeType: string;
  sha256: string;
  objectId: string;
  objectVersion: string;
};

export interface AdministrativeRepairStorageGateway {
  inspect(bucketId: string, objectPath: string): Promise<PhysicalDocumentObject | null>;
  upload(bucketId: string, objectPath: string, bytes: Uint8Array, mimeType: string, upsert: boolean): Promise<void>;
  remove(bucketId: string, objectPath: string): Promise<void>;
}

export interface AdministrativeRepairRpcGateway {
  progress(context: RepairContext): Promise<AdministrativeDocumentRepairProgress>;
  start(context: RepairContext, item: RepairItem, executionId: string, authorizationRevision: number): Promise<void>;
  observe(context: RepairContext, item: RepairItem, executionId: string, observation: RepairObservation): Promise<void>;
  verify(context: RepairContext, item: RepairItem, executionId: string, result: RepairResult): Promise<void>;
  markBackupRestored(context: RepairContext, item: RepairItem, executionId: string): Promise<void>;
  authorizeBackupCleanup(context: RepairContext, item: RepairItem, executionId: string): Promise<BackupCleanupDescriptor>;
  completeBackupCleanup(context: RepairContext, item: RepairItem, executionId: string, expectedBackupRevision: number): Promise<void>;
}

export type RepairContext = {
  authorizationId: string;
  administratorSubjectId: string;
  attemptId: string;
  planHash: string;
  compensationActions: ReadonlyMap<string, "insert" | "update" | "delete" | null>;
  expectedObjects: ReadonlyMap<string, { exists: boolean; objectId: string | null; objectVersion: string | null }>;
  storageGuardEnabled: boolean;
};

type RepairObservation = {
  kind: "physical_verified" | "catalog_absent" | "physical_read_impossible" | "content_divergent" | "backup_missing" | "original_missing" | "unqualifiable";
  object: PhysicalDocumentObject | null;
  physicalBytesVerified: boolean;
  backup: RepairItem["backup"];
  backupPresent: boolean;
};
type RepairResult = {
  resultKind: "compensation_completed" | "restoration_completed" | "backup_cleanup_completed" | "already_conform" | "residual_accepted";
  backupDisposition: "none" | "deleted" | "restored" | "retained_for_review";
};
type BackupCleanupDescriptor = {
  bucketId: "document-operation-backups";
  objectPath: string;
  objectId: string | null;
  objectVersion: string | null;
  byteSize: number | null;
  mimeType: string | null;
  sha256: string | null;
  state: z.infer<typeof backupState>;
  revision: number;
};

export class AdministrativeDocumentRepairError extends Error {
  readonly safeCode: string;

  constructor(
    message = "La réparation documentaire n’a pas pu être confirmée.",
    safeCode = "ADMIN_DOCUMENT_REPAIR_FAILED",
  ) {
    super(message);
    this.name = "AdministrativeDocumentRepairError";
    this.safeCode = safeCode;
  }
}

function digest(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertPhysicalObject(object: PhysicalDocumentObject) {
  if (
    object.byteSize !== object.bytes.byteLength
    || object.sha256 !== digest(object.bytes)
    || !/^[0-9a-f]{64}$/.test(object.sha256)
    || !object.objectId
    || !object.objectVersion
  ) {
    throw new AdministrativeDocumentRepairError(
      "L’intégrité physique du document ne peut pas être démontrée.",
      "PHYSICAL_INTEGRITY_FAILED",
    );
  }
}

function sameContent(left: PhysicalDocumentObject | null, right: PhysicalDocumentObject | null) {
  if (!left || !right) return left === right;
  return left.byteSize === right.byteSize
    && left.sha256 === right.sha256
    && left.mimeType === right.mimeType;
}

function executionId(attemptId: string, itemId: string) {
  const value = createHash("sha256")
    .update("patrigest:administrative-document-repair:v1\0")
    .update(attemptId).update("\0").update(itemId).digest().subarray(0, 16);
  value[6] = (value[6] & 0x0f) | 0x80;
  value[8] = (value[8] & 0x3f) | 0x80;
  const hex = value.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

async function restoreAndVerify(
  storage: AdministrativeRepairStorageGateway,
  item: RepairItem,
  backup: PhysicalDocumentObject,
  expected: { exists: boolean; objectId: string | null; objectVersion: string | null },
) {
  const before = await storage.inspect(item.bucketId, item.objectPath);
  if (before) assertPhysicalObject(before);
  if (!sameContent(before, backup) && (
    (before !== null) !== expected.exists
    || (before && (before.objectId !== expected.objectId || before.objectVersion !== expected.objectVersion))
  )) {
    throw new AdministrativeDocumentRepairError("La cible a changé avant restauration.", "TARGET_DIVERGED");
  }
  if (!sameContent(before, backup)) {
    if (before !== null) {
      throw new AdministrativeDocumentRepairError(
        "Le remplacement d’un original exige la garde Storage conditionnelle.",
        "STORAGE_GUARD_REQUIRED",
      );
    }
    try {
      await storage.upload(item.bucketId, item.objectPath, backup.bytes, backup.mimeType, before !== null);
    } catch {
      const afterUnknown = await storage.inspect(item.bucketId, item.objectPath);
      if (!sameContent(afterUnknown, backup)) {
        throw new AdministrativeDocumentRepairError(
          "Le résultat de la restauration Storage est incertain.",
          "AMBIGUOUS_STORAGE_MUTATION",
        );
      }
    }
  }
  const restored = await storage.inspect(item.bucketId, item.objectPath);
  if (!restored || !sameContent(restored, backup)) {
    throw new AdministrativeDocumentRepairError(
      "Les octets restaurés ne correspondent pas à la sauvegarde.",
      "RESTORE_VERIFICATION_FAILED",
    );
  }
  assertPhysicalObject(restored);
  return restored;
}

async function inspectBackup(
  storage: AdministrativeRepairStorageGateway,
  item: RepairItem,
) {
  const backup = item.backup;
  if (!backup) return null;
  if (!backup.recoveryObjectPath) {
    throw new AdministrativeDocumentRepairError("Le descripteur de sauvegarde est incomplet.", "BACKUP_DESCRIPTOR_INVALID");
  }
  const object = await storage.inspect("document-operation-backups", backup.recoveryObjectPath);
  if (!object) return null;
  assertPhysicalObject(object);
  if (
    backup.recoveryObjectId !== object.objectId
    || backup.recoveryObjectVersion !== object.objectVersion
    || backup.byteSize !== object.byteSize
    || backup.sha256 !== object.sha256
  ) {
    throw new AdministrativeDocumentRepairError("La sauvegarde physique a divergé.", "BACKUP_DIVERGED");
  }
  return object;
}

export class AdministrativeDocumentRepairEngine {
  private readonly rpc: AdministrativeRepairRpcGateway;
  private readonly storage: AdministrativeRepairStorageGateway;

  constructor(
    rpc: AdministrativeRepairRpcGateway,
    storage: AdministrativeRepairStorageGateway,
  ) {
    this.rpc = rpc;
    this.storage = storage;
  }

  async execute(context: RepairContext) {
    let progress = await this.rpc.progress(context);
    if (progress.administratorSubjectId !== context.administratorSubjectId
      || progress.attemptId !== context.attemptId
      || progress.planHash !== context.planHash) {
      throw new AdministrativeDocumentRepairError("Le contexte de réparation a divergé.", "CONTEXT_DIVERGED");
    }
    if (progress.state !== "active" || progress.expired) {
      throw new AdministrativeDocumentRepairError(
        "L’autorisation a expiré. Une prolongation administrative explicite est requise.",
        "AUTHORIZATION_EXPIRED",
      );
    }

    for (const initial of progress.items.toSorted((left, right) => left.ordinal - right.ordinal)) {
      progress = await this.rpc.progress(context);
      let item = progress.items.find(({ itemId }) => itemId === initial.itemId);
      if (!item) throw new AdministrativeDocumentRepairError("La cible autorisée est introuvable.", "TARGET_MISSING");
      const stableExecutionId = item.executionId ?? executionId(context.attemptId, item.itemId);
      if (item.progressState === "authorized") {
        const compensationAction = context.compensationActions.get(item.targetId) ?? null;
        const needsCatalogCheck = item.action === "restore_original" || item.action === "resume_compensation";
        const currentObject = needsCatalogCheck
          ? await this.storage.inspect(item.bucketId, item.objectPath)
          : null;
        const guardBlockReason = getAdministrativeRepairGuardBlockReason(item.action, {
          catalogObjectPresent: currentObject !== null,
          compensationAction,
        }, context.storageGuardEnabled);
        if (guardBlockReason) {
          throw new AdministrativeDocumentRepairError(guardBlockReason, "STORAGE_GUARD_REQUIRED");
        }
        await this.rpc.start(context, item, stableExecutionId, progress.revision);
        progress = await this.rpc.progress(context);
        item = progress.items.find(({ itemId }) => itemId === initial.itemId)!;
      }
      if (item.executionId !== stableExecutionId) {
        throw new AdministrativeDocumentRepairError("Une autre exécution a commencé cette cible.", "EXECUTION_DIVERGED");
      }
      if (item.progressState === "verified") continue;

      if (item.progressState === "executing") {
        let observation: RepairObservation;
        try {
          observation = await this.performAction(context, item, stableExecutionId);
        } catch (error) {
          await this.recordBlockingObservation(context, item, stableExecutionId, error);
          throw error;
        }
        try {
          await this.rpc.observe(context, item, stableExecutionId, observation);
        } catch {
          const replay = await this.rpc.progress(context);
          const replayItem = replay.items.find(({ itemId }) => itemId === item!.itemId);
          if (replayItem?.progressState !== "verification_required" && replayItem?.progressState !== "verified") throw new AdministrativeDocumentRepairError();
        }
        progress = await this.rpc.progress(context);
        item = progress.items.find(({ itemId }) => itemId === initial.itemId)!;
      }

      if (item.progressState === "verification_required") {
        const result = this.resultFor(item);
        try {
          await this.rpc.verify(context, item, stableExecutionId, result);
        } catch {
          const replay = await this.rpc.progress(context);
          if (replay.items.find(({ itemId }) => itemId === item!.itemId)?.progressState !== "verified") throw new AdministrativeDocumentRepairError();
        }
      }
    }
    return this.rpc.progress(context);
  }

  private async performAction(context: RepairContext, item: RepairItem, stableExecutionId: string): Promise<RepairObservation> {
    let original = await this.storage.inspect(item.bucketId, item.objectPath);
    if (original) assertPhysicalObject(original);
    const physicalBackup = await inspectBackup(this.storage, item);
    const expected = context.expectedObjects.get(item.targetId);
    if (!expected) throw new AdministrativeDocumentRepairError("Les préconditions de la cible sont absentes.", "TARGET_CONTEXT_MISSING");

    if (item.action === "restore_original") {
      if (!physicalBackup) throw new AdministrativeDocumentRepairError("La sauvegarde physique est absente.", "BACKUP_MISSING");
      original = await restoreAndVerify(this.storage, item, physicalBackup, expected);
      await this.rpc.markBackupRestored(context, item, stableExecutionId);
    } else if (item.action === "resume_compensation") {
      const compensation = context.compensationActions.get(item.targetId);
      if (compensation === "delete") {
        if (item.backup) {
          throw new AdministrativeDocumentRepairError(
            "Une compensation de suppression ne peut pas disposer implicitement d’une sauvegarde.",
            "INVALID_COMPENSATION",
          );
        }
        throw new AdministrativeDocumentRepairError(
          "La suppression compensatoire exige la garde Storage conditionnelle.",
          "STORAGE_GUARD_REQUIRED",
        );
      } else if (compensation === "insert" || compensation === "update") {
        if (!physicalBackup) throw new AdministrativeDocumentRepairError("La sauvegarde physique est absente.", "BACKUP_MISSING");
        original = await restoreAndVerify(this.storage, item, physicalBackup, expected);
        await this.rpc.markBackupRestored(context, item, stableExecutionId);
      } else {
        throw new AdministrativeDocumentRepairError("L’action de compensation est absente.", "INVALID_COMPENSATION");
      }
    } else if (item.action === "complete_backup_cleanup") {
      throw new AdministrativeDocumentRepairError(
        "Le nettoyage de sauvegarde exige la garde Storage conditionnelle.",
        "STORAGE_GUARD_REQUIRED",
      );
    }

    original = await this.storage.inspect(item.bucketId, item.objectPath);
    if (original) assertPhysicalObject(original);
    const refreshed = await this.rpc.progress(context);
    const refreshedItem = refreshed.items.find(({ itemId }) => item.itemId === itemId) ?? item;
    const finalBackup = await inspectBackup(this.storage, refreshedItem);
    return {
      kind: original ? "physical_verified" : "catalog_absent",
      object: original,
      physicalBytesVerified: original !== null,
      backup: refreshedItem.backup,
      backupPresent: finalBackup !== null,
    };
  }

  private async recordBlockingObservation(
    context: RepairContext,
    item: RepairItem,
    stableExecutionId: string,
    error: unknown,
  ) {
    try {
      const original = await this.storage.inspect(item.bucketId, item.objectPath);
      const backupObject = item.backup?.recoveryObjectPath
        ? await this.storage.inspect("document-operation-backups", item.backup.recoveryObjectPath)
        : null;
      const backupPresent = Boolean(
        backupObject
        && item.backup
        && backupObject.objectId === item.backup.recoveryObjectId
        && backupObject.objectVersion === item.backup.recoveryObjectVersion,
      );
      const safeCode = error instanceof AdministrativeDocumentRepairError ? error.safeCode : "";
      const contentDivergent = safeCode === "TARGET_DIVERGED" && original !== null;
      const kind: RepairObservation["kind"] = safeCode === "BACKUP_MISSING"
        ? "backup_missing"
        : safeCode === "LAST_RECOVERABLE_COPY" || (safeCode === "TARGET_DIVERGED" && !original)
          ? "original_missing"
          : contentDivergent
            ? "content_divergent"
            : "unqualifiable";
      await this.rpc.observe(context, item, stableExecutionId, {
        kind,
        object: original,
        physicalBytesVerified: contentDivergent,
        backup: item.backup,
        backupPresent,
      });
    } catch {
      // La preuve bloquante est best-effort : son propre échec ne doit jamais
      // masquer l'anomalie physique initiale ni déclencher une mutation.
    }
  }

  private resultFor(item: RepairItem): RepairResult {
    if (item.action === "resume_compensation") {
      return { resultKind: "compensation_completed", backupDisposition: item.backup ? "restored" : "none" };
    }
    if (item.action === "restore_original") return { resultKind: "restoration_completed", backupDisposition: "restored" };
    if (item.action === "complete_backup_cleanup") return { resultKind: "backup_cleanup_completed", backupDisposition: "deleted" };
    if (item.action === "accept_residual_state") {
      return { resultKind: "residual_accepted", backupDisposition: item.backup ? "retained_for_review" : "none" };
    }
    return { resultKind: "already_conform", backupDisposition: "none" };
  }
}

export const backupCleanupDescriptorSchema = z.object({
  bucketId: z.literal("document-operation-backups"),
  objectPath: z.string().min(1),
  objectId: uuid.nullable(),
  objectVersion: z.string().nullable(),
  byteSize: z.number().int().nonnegative().nullable(),
  mimeType: z.string().nullable(),
  sha256: sha256.nullable(),
  state: backupState,
  revision: z.number().int().nonnegative(),
});
