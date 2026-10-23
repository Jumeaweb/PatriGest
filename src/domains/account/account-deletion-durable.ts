import { createHash } from "node:crypto";
import { z } from "zod";
import type { Json } from "@/types/database";

const BACKUP_BUCKET = "document-operation-backups";
const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const phase = z.enum([
  "reserved",
  "backup_verified",
  "original_deleted",
  "recreated",
  "verified",
  "backup_cleanup_authorized",
  "backup_cleaned",
  "finalized",
  "attention_required",
]);
const authorizationSchema = z.object({
  authorizationId: uuid,
  accountUserId: uuid,
  attemptId: uuid,
  expiresAt: z.string(),
  state: z.enum(["active", "sealed", "cancelled"]),
});
const operationSchema = z.object({
  operation_id: uuid,
  client_request_id: uuid,
  state: z.string(),
  phase,
  created_at: z.string(),
});
const progressSchema = z.object({
  operationId: uuid,
  state: z.string(),
  operationRevision: z.number().int().nonnegative(),
  targetId: uuid,
  bucketId: z.enum(["transaction-proofs", "bank-statements", "management-reports"]),
  objectPath: z.string().min(1),
  phase,
  resumePhase: phase.exclude(["attention_required", "finalized"]).nullable(),
  revision: z.number().int().nonnegative(),
  backupState: z.string().nullable(),
  objectPresent: z.boolean(),
  verifiedBackupPresent: z.boolean(),
  recoveryRequired: z.boolean(),
  uncertain: z.boolean(),
  expectedObjectId: uuid,
  expectedObjectVersion: z.string().min(1),
  recreatedObjectId: uuid.nullable(),
  recreatedObjectVersion: z.string().nullable(),
  expectedSha256: sha256,
  expectedByteSize: z.number().int().positive(),
});
const backupSchema = z.object({
  backupId: uuid,
  bucketId: z.literal(BACKUP_BUCKET),
  objectPath: z.string().min(1),
  state: z.string(),
  revision: z.number().int().nonnegative(),
  byteSize: z.number().int().positive().optional(),
  mimeType: z.string().min(1).optional(),
  sha256: sha256.optional(),
});
const recoverySchema = z.object({
  backupId: uuid,
  sourceBucketId: z.literal(BACKUP_BUCKET),
  sourceObjectPath: z.string().min(1),
  destinationBucketId: z.enum(["transaction-proofs", "bank-statements", "management-reports"]),
  destinationObjectPath: z.string().min(1),
  expectedSha256: sha256,
  expectedByteSize: z.number().int().positive(),
  mimeType: z.string().min(1),
  revision: z.number().int().nonnegative(),
});
const stepSchema = z.object({
  operationId: uuid,
  phase,
  revision: z.number().int().nonnegative(),
});

type RpcResult = { data: unknown; error: unknown | null };
type RpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<RpcResult>;
};
type StorageResult<T> = { data: T; error: unknown | null };
type StorageInfo = {
  id?: string;
  version?: string;
  contentType?: string;
  cacheControl?: string;
  metadata?: Record<string, unknown>;
  size?: number;
};
type StorageBucket = {
  download(path: string): PromiseLike<StorageResult<Blob | null>>;
  info(path: string): PromiseLike<StorageResult<StorageInfo | null>>;
  upload(
    path: string,
    body: Uint8Array,
    options: {
      contentType: string;
      cacheControl?: string;
      metadata?: Record<string, unknown>;
      upsert: boolean;
    },
  ): PromiseLike<StorageResult<unknown>>;
  remove(paths: string[]): PromiseLike<StorageResult<unknown>>;
  exists(path: string): PromiseLike<StorageResult<boolean>>;
};
export type AccountDeletionDurableUserClient = RpcClient;
export type AccountDeletionDurableAdminClient = RpcClient & {
  storage: { from(bucket: string): StorageBucket };
};
export type AccountDeletionOwnedObject = {
  bucket_id: string;
  name: string;
  metadata: Json;
  user_metadata: Json;
};

type StoredObject = {
  objectId: string;
  objectVersion: string;
  bytes: Uint8Array;
  byteSize: number;
  mimeType: string;
  sha256: string;
  cacheControl?: string;
  metadata: Record<string, unknown>;
};

class DurableRpcError extends Error {
  readonly code: string;

  constructor(code: string) {
    super("Opération documentaire refusée.");
    this.code = code;
  }
}

export class AccountDeletionDurableStorageError extends Error {}
export class AccountDeletionDurableAttentionError extends Error {}

function errorCode(error: unknown) {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
}

async function rpc(client: RpcClient, name: string, args: Record<string, unknown> = {}) {
  const result = await client.rpc(name, args);
  if (result.error) throw new DurableRpcError(errorCode(result.error));
  return result.data;
}

function checksum(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function metadataRecord(value: Json | Record<string, unknown> | undefined) {
  if (!value || Array.isArray(value) || typeof value !== "object") return {};
  return value as Record<string, unknown>;
}

function cacheControlSeconds(value: string | undefined) {
  return value?.replace(/^max-age=/, "");
}

function requestId(attemptId: string, bucketId: string, path: string) {
  const digest = createHash("sha256")
    .update("patrigest:account-storage-neutralization:v1\0")
    .update(attemptId)
    .update("\0")
    .update(bucketId)
    .update("\0")
    .update(path)
    .digest()
    .subarray(0, 16);
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = Buffer.from(digest).toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function reportsMissingObject(data: boolean, error: unknown) {
  if (data) return false;
  if (!error) return true;
  if (typeof error !== "object" || error === null) return false;
  const status = "statusCode" in error
    ? error.statusCode
    : "status" in error
      ? error.status
      : undefined;
  return String(status) === "400" || String(status) === "404";
}

async function objectExists(bucket: StorageBucket, path: string) {
  const result = await bucket.exists(path);
  if (reportsMissingObject(result.data, result.error)) return false;
  if (result.error) throw new AccountDeletionDurableStorageError("Vérification Storage impossible.");
  return result.data;
}

async function inspect(bucket: StorageBucket, path: string): Promise<StoredObject | null> {
  if (!(await objectExists(bucket, path))) return null;
  const [info, downloaded] = await Promise.all([bucket.info(path), bucket.download(path)]);
  if (
    info.error || !info.data?.id || !info.data.version
    || downloaded.error || !downloaded.data
  ) {
    throw new AccountDeletionDurableStorageError("Inspection Storage impossible.");
  }
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  return {
    objectId: info.data.id,
    objectVersion: info.data.version,
    bytes,
    byteSize: bytes.byteLength,
    mimeType: downloaded.data.type || info.data.contentType || "application/octet-stream",
    sha256: checksum(bytes),
    cacheControl: cacheControlSeconds(info.data.cacheControl),
    metadata: metadataRecord(info.data.metadata),
  };
}

function sameContent(actual: StoredObject, expected: {
  sha256: string;
  byteSize: number;
  mimeType?: string;
}) {
  return actual.sha256 === expected.sha256
    && actual.byteSize === expected.byteSize
    && (!expected.mimeType || actual.mimeType === expected.mimeType);
}

async function uploadFresh(
  bucket: StorageBucket,
  path: string,
  content: StoredObject,
) {
  const result = await bucket.upload(path, content.bytes, {
    contentType: content.mimeType,
    cacheControl: content.cacheControl,
    metadata: content.metadata,
    upsert: false,
  });
  if (result.error) {
    const existing = await inspect(bucket, path);
    if (!existing || !sameContent(existing, content)) {
      throw new AccountDeletionDurableStorageError("Création Storage impossible.");
    }
  }
}

async function removeAndConfirm(bucket: StorageBucket, path: string) {
  if (!(await objectExists(bucket, path))) return;
  const removed = await bucket.remove([path]);
  if (removed.error && await objectExists(bucket, path)) {
    throw new AccountDeletionDurableStorageError("Suppression Storage impossible.");
  }
  if (await objectExists(bucket, path)) {
    throw new AccountDeletionDurableStorageError("Suppression Storage non confirmée.");
  }
}

async function progress(admin: RpcClient, operationId: string) {
  return progressSchema.parse(await rpc(
    admin,
    "get_account_storage_neutralization_progress",
    { p_operation_id: operationId },
  ));
}

async function markAttention(
  admin: RpcClient,
  operationId: string,
  revision: number,
  safeCode: string,
) {
  try {
    await rpc(admin, "mark_account_storage_neutralization_attention_required", {
      p_operation_id: operationId,
      p_expected_revision: revision,
      p_safe_error_code: safeCode,
    });
  } catch {
    // L'erreur d'origine reste prioritaire ; un concurrent peut avoir déjà
    // avancé ou placé l'opération en attention.
  }
}

async function ensureBackup(
  admin: AccountDeletionDurableAdminClient,
  current: z.infer<typeof progressSchema>,
) {
  const originalBucket = admin.storage.from(current.bucketId);
  const original = await inspect(originalBucket, current.objectPath);
  if (
    !original
    || original.objectId !== current.expectedObjectId
    || original.objectVersion !== current.expectedObjectVersion
    || !sameContent(original, {
      sha256: current.expectedSha256,
      byteSize: current.expectedByteSize,
    })
  ) {
    throw new AccountDeletionDurableStorageError("L’objet original a divergé.");
  }
  const reserved = backupSchema.parse(await rpc(
    admin,
    "reserve_account_storage_neutralization_backup",
    { p_operation_id: current.operationId },
  ));
  const backupBucket = admin.storage.from(reserved.bucketId);
  const existing = await inspect(backupBucket, reserved.objectPath);
  if (existing) {
    if (!sameContent(existing, original)) {
      throw new AccountDeletionDurableStorageError("La sauvegarde durable a divergé.");
    }
  } else {
    await uploadFresh(backupBucket, reserved.objectPath, original);
  }
  const verified = await inspect(backupBucket, reserved.objectPath);
  if (!verified || !sameContent(verified, original)) {
    throw new AccountDeletionDurableStorageError("La sauvegarde durable n’est pas vérifiée.");
  }
  await rpc(admin, "confirm_account_storage_neutralization_backup", {
    p_operation_id: current.operationId,
    p_expected_neutralization_revision: current.revision,
    p_expected_backup_revision: reserved.revision,
    p_observed_sha256: verified.sha256,
    p_observed_byte_size: verified.byteSize,
  });
}

async function ensureOriginalDeleted(
  admin: AccountDeletionDurableAdminClient,
  current: z.infer<typeof progressSchema>,
) {
  const bucket = admin.storage.from(current.bucketId);
  const original = await inspect(bucket, current.objectPath);
  if (original && (
    original.objectId !== current.expectedObjectId
    || original.objectVersion !== current.expectedObjectVersion
    || !sameContent(original, {
      sha256: current.expectedSha256,
      byteSize: current.expectedByteSize,
    })
  )) {
    throw new AccountDeletionDurableStorageError("L’objet réservé a divergé.");
  }
  if (original) await removeAndConfirm(bucket, current.objectPath);
  await rpc(admin, "record_account_storage_neutralization_original_deleted", {
    p_operation_id: current.operationId,
    p_expected_revision: current.revision,
  });
}

async function recoverOriginal(
  admin: AccountDeletionDurableAdminClient,
  current: z.infer<typeof progressSchema>,
) {
  const recovery = recoverySchema.parse(await rpc(
    admin,
    "authorize_account_storage_neutralization_recovery",
    {
      p_operation_id: current.operationId,
      p_expected_revision: current.revision,
    },
  ));
  const sourceBucket = admin.storage.from(recovery.sourceBucketId);
  const destinationBucket = admin.storage.from(recovery.destinationBucketId);
  const backup = await inspect(sourceBucket, recovery.sourceObjectPath);
  if (!backup || !sameContent(backup, {
    sha256: recovery.expectedSha256,
    byteSize: recovery.expectedByteSize,
    mimeType: recovery.mimeType,
  })) {
    throw new AccountDeletionDurableStorageError("La sauvegarde de récupération a divergé.");
  }
  let recreated = await inspect(destinationBucket, recovery.destinationObjectPath);
  if (recreated && !sameContent(recreated, backup)) {
    await removeAndConfirm(destinationBucket, recovery.destinationObjectPath);
    recreated = null;
  }
  if (!recreated) {
    await uploadFresh(destinationBucket, recovery.destinationObjectPath, backup);
    recreated = await inspect(destinationBucket, recovery.destinationObjectPath);
  }
  if (!recreated || !sameContent(recreated, backup)) {
    throw new AccountDeletionDurableStorageError("La recréation Storage n’est pas vérifiée.");
  }
  await rpc(admin, "confirm_account_storage_neutralization_recovery", {
    p_operation_id: current.operationId,
    p_expected_revision: current.revision,
    p_observed_object_id: recreated.objectId,
    p_observed_object_version: recreated.objectVersion,
    p_observed_sha256: recreated.sha256,
    p_observed_byte_size: recreated.byteSize,
  });
}

async function verifyRecreated(
  admin: AccountDeletionDurableAdminClient,
  current: z.infer<typeof progressSchema>,
) {
  const recreated = await inspect(
    admin.storage.from(current.bucketId),
    current.objectPath,
  );
  if (!recreated || !sameContent(recreated, {
    sha256: current.expectedSha256,
    byteSize: current.expectedByteSize,
  })) {
    await recoverOriginal(admin, current);
    return;
  }
  await rpc(admin, "verify_account_storage_neutralization_content", {
    p_operation_id: current.operationId,
    p_expected_revision: current.revision,
    p_observed_sha256: recreated.sha256,
    p_observed_byte_size: recreated.byteSize,
  });
}

async function cleanupBackup(
  admin: AccountDeletionDurableAdminClient,
  current: z.infer<typeof progressSchema>,
) {
  const authorized = backupSchema.parse(await rpc(
    admin,
    "authorize_account_storage_neutralization_backup_cleanup",
    {
      p_operation_id: current.operationId,
      p_expected_revision: current.revision,
    },
  ));
  await removeAndConfirm(
    admin.storage.from(authorized.bucketId),
    authorized.objectPath,
  );
  await rpc(admin, "confirm_account_storage_neutralization_backup_cleanup", {
    p_operation_id: current.operationId,
    p_expected_neutralization_revision: current.phase === "verified"
      ? current.revision + 1
      : current.revision,
    p_expected_backup_revision: authorized.revision,
  });
}

export async function resumeAccountStorageNeutralization(
  admin: AccountDeletionDurableAdminClient,
  operationId: string,
) {
  for (let attempt = 0; attempt < 24; attempt += 1) {
    const current = await progress(admin, operationId);
    if (current.phase === "finalized") return current;
    if (current.phase === "attention_required") {
      throw new AccountDeletionDurableAttentionError(
        "La neutralisation documentaire requiert une intervention.",
      );
    }
    try {
      if (current.phase === "reserved") await ensureBackup(admin, current);
      else if (current.phase === "backup_verified") await ensureOriginalDeleted(admin, current);
      else if (current.phase === "original_deleted") await recoverOriginal(admin, current);
      else if (current.phase === "recreated") await verifyRecreated(admin, current);
      else if (current.phase === "verified") await cleanupBackup(admin, current);
      else if (current.phase === "backup_cleanup_authorized") {
        await cleanupBackup(admin, current);
      } else if (current.phase === "backup_cleaned") {
        stepSchema.parse(await rpc(admin, "finalize_account_storage_neutralization", {
          p_operation_id: current.operationId,
          p_expected_revision: current.revision,
        }));
      }
    } catch (error) {
      if (error instanceof DurableRpcError && error.code === "P4N04") continue;
      if (error instanceof AccountDeletionDurableStorageError) {
        await markAttention(admin, operationId, current.revision, "STORAGE_STATE_UNCERTAIN");
      }
      throw error;
    }
  }
  const current = await progress(admin, operationId);
  await markAttention(admin, operationId, current.revision, "PROGRESSION_RETRY_EXHAUSTED");
  throw new AccountDeletionDurableAttentionError(
    "La neutralisation documentaire n’a pas atteint un état terminal.",
  );
}

export async function issueAccountDeletionAuthorization(
  admin: AccountDeletionDurableAdminClient,
  accountUserId: string,
  attemptId: string,
) {
  return authorizationSchema.parse(await rpc(
    admin,
    "issue_account_deletion_document_authorization",
    { p_account_user_id: accountUserId, p_attempt_id: attemptId },
  ));
}

export async function cancelAccountDeletionAuthorization(
  admin: AccountDeletionDurableAdminClient,
  authorizationId: string,
) {
  await rpc(admin, "cancel_account_deletion_document_authorization", {
    p_authorization_id: authorizationId,
  });
}

export async function listAccountStorageNeutralizations(
  admin: AccountDeletionDurableAdminClient,
  accountUserId: string,
) {
  return z.array(operationSchema).parse(await rpc(
    admin,
    "list_account_storage_neutralization_operations",
    { p_account_user_id: accountUserId },
  ));
}

export async function beginAccountStorageNeutralization(
  user: AccountDeletionDurableUserClient,
  authorizationId: string,
  attemptId: string,
  object: AccountDeletionOwnedObject,
  observed: StoredObject,
) {
  const result = stepSchema.extend({ targetId: uuid }).parse(await rpc(
    user,
    "begin_account_storage_neutralization",
    {
      p_authorization_id: authorizationId,
      p_client_request_id: requestId(attemptId, object.bucket_id, object.name),
      p_bucket_id: object.bucket_id,
      p_object_path: object.name,
      p_expected_object_id: observed.objectId,
      p_expected_object_version: observed.objectVersion,
      p_expected_sha256: observed.sha256,
      p_expected_byte_size: observed.byteSize,
      p_mime_type: observed.mimeType,
    },
  ));
  return result.operationId;
}

export async function inspectAccountOwnedStorageObject(
  admin: AccountDeletionDurableAdminClient,
  object: AccountDeletionOwnedObject,
) {
  const observed = await inspect(admin.storage.from(object.bucket_id), object.name);
  if (!observed) {
    throw new AccountDeletionDurableStorageError("L’objet inventorié est introuvable.");
  }
  return observed;
}

export async function assertAccountDeletionDocumentBarrier(
  admin: AccountDeletionDurableAdminClient,
  authorizationId: string,
) {
  const result = z.object({ ready: z.literal(true) }).parse(await rpc(
    admin,
    "assert_account_deletion_document_barrier",
    { p_authorization_id: authorizationId },
  ));
  return result.ready;
}
