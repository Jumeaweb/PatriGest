import { createHash } from "node:crypto";
import { z } from "zod";
import type {
  DocumentBackupKey,
  DurableDocumentBackupStore,
  StoredDocumentObject,
} from "./contracts";

export const DOCUMENT_OPERATION_BACKUP_BUCKET = "document-operation-backups";

const uuid = z.uuid();
const sha256 = z.string().regex(/^[0-9a-f]{64}$/);
const backupState = z.enum([
  "upload_pending",
  "verified",
  "restored",
  "deleted",
  "attention_required",
]);
const publicBackupSchema = z.object({
  backupId: uuid,
  state: backupState,
  revision: z.number().int().nonnegative(),
  byteSize: z.number().int().positive().optional(),
  mimeType: z.string().min(1).optional(),
  sha256: sha256.optional(),
});
const descriptorSchema = publicBackupSchema.extend({
  operationId: uuid,
  targetId: uuid,
  bucketId: z.literal(DOCUMENT_OPERATION_BACKUP_BUCKET),
  objectPath: z.string().regex(
    /^operations\/[0-9a-f-]{36}\/targets\/[0-9a-f-]{36}\/backup$/,
  ),
  byteSize: z.number().int().positive(),
  mimeType: z.string().min(1),
  sha256,
});
const cleanupSchema = z.object({
  backupId: uuid,
  bucketId: z.literal(DOCUMENT_OPERATION_BACKUP_BUCKET),
  objectPath: z.string().regex(
    /^operations\/[0-9a-f-]{36}\/targets\/[0-9a-f-]{36}\/backup$/,
  ),
  state: backupState,
  revision: z.number().int().nonnegative(),
});

type RpcResult = { data: unknown; error: unknown | null };
type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
};
type StorageResult<T> = { data: T; error: unknown | null };
type StorageBucket = {
  exists(path: string): PromiseLike<StorageResult<boolean>>;
  download(path: string): PromiseLike<StorageResult<Blob | null>>;
  upload(
    path: string,
    body: Uint8Array,
    options: { contentType: string; upsert: boolean },
  ): PromiseLike<StorageResult<unknown>>;
  remove(paths: string[]): PromiseLike<StorageResult<unknown>>;
};
type PrivilegedClient = RpcClient & {
  storage: { from(bucket: string): StorageBucket };
};

function safeFailure(message: string): Error {
  return new Error(message);
}

async function rpc(
  client: RpcClient,
  name: string,
  args: Record<string, unknown>,
) {
  const result = await client.rpc(name, args);
  if (result.error) throw safeFailure("La sauvegarde documentaire n’a pas pu être confirmée.");
  return result.data;
}

function assertKey(key: DocumentBackupKey) {
  return z.object({ operationId: uuid, targetId: uuid }).parse(key);
}

function checksum(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertStoredObject(
  object: StoredDocumentObject,
  expected: { byteSize: number; mimeType: string; sha256: string },
) {
  if (
    object.byteSize !== expected.byteSize
    || object.mimeType !== expected.mimeType
    || object.sha256 !== expected.sha256
    || object.bytes.byteLength !== expected.byteSize
    || checksum(object.bytes) !== expected.sha256
  ) {
    throw safeFailure("L’intégrité de la sauvegarde documentaire n’est pas vérifiée.");
  }
}

async function downloadVerified(
  bucket: StorageBucket,
  path: string,
  expected: { byteSize: number; mimeType: string; sha256: string },
): Promise<StoredDocumentObject> {
  const downloaded = await bucket.download(path);
  if (downloaded.error || !downloaded.data) {
    throw safeFailure("La sauvegarde documentaire est introuvable.");
  }
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  const object = {
    bytes,
    byteSize: bytes.byteLength,
    mimeType: downloaded.data.type || "application/octet-stream",
    sha256: checksum(bytes),
  };
  assertStoredObject(object, expected);
  return object;
}

export function createDurableDocumentBackupStore(
  userClient: RpcClient,
  privilegedClient: PrivilegedClient,
): DurableDocumentBackupStore {
  const backupBucket = privilegedClient.storage.from(DOCUMENT_OPERATION_BACKUP_BUCKET);

  async function descriptor(backupId: string) {
    return descriptorSchema.parse(await rpc(
      privilegedClient,
      "get_document_operation_backup_storage_descriptor",
      { p_backup_id: backupId },
    ));
  }

  async function current(key: DocumentBackupKey) {
    const validated = assertKey(key);
    const data = await rpc(userClient, "get_document_operation_backup", {
      p_operation_id: validated.operationId,
      p_target_id: validated.targetId,
    });
    return data === null ? null : publicBackupSchema.parse(data);
  }

  return {
    available: true,

    async save(key, object) {
      const validated = assertKey(key);
      if (
        object.byteSize !== object.bytes.byteLength
        || object.sha256 !== checksum(object.bytes)
      ) {
        throw safeFailure("Les métadonnées de la sauvegarde documentaire sont invalides.");
      }
      const reserved = publicBackupSchema.parse(await rpc(
        userClient,
        "reserve_document_operation_backup",
        {
          p_operation_id: validated.operationId,
          p_target_id: validated.targetId,
          p_byte_size: object.byteSize,
          p_mime_type: object.mimeType,
          p_sha256: object.sha256,
        },
      ));
      if (reserved.state === "verified" || reserved.state === "restored") {
        assertStoredObject(await this.load(validated) as StoredDocumentObject, object);
        return;
      }
      if (reserved.state !== "upload_pending") {
        throw safeFailure("La sauvegarde documentaire n’est pas réutilisable.");
      }
      const storage = await descriptor(reserved.backupId);
      const exists = await backupBucket.exists(storage.objectPath);
      if (exists.error) throw safeFailure("Le stockage de récupération est indisponible.");
      if (!exists.data) {
        const uploaded = await backupBucket.upload(storage.objectPath, object.bytes, {
          contentType: object.mimeType,
          upsert: false,
        });
        if (uploaded.error) throw safeFailure("La sauvegarde documentaire n’a pas pu être créée.");
      }
      await downloadVerified(backupBucket, storage.objectPath, object);
      await rpc(userClient, "confirm_document_operation_backup", {
        p_operation_id: validated.operationId,
        p_target_id: validated.targetId,
        p_expected_revision: reserved.revision,
      });
    },

    async load(key) {
      const backup = await current(key);
      if (!backup || backup.state === "upload_pending" || backup.state === "deleted") return null;
      if (backup.state === "attention_required") {
        throw safeFailure("La sauvegarde documentaire requiert une intervention.");
      }
      if (backup.byteSize === undefined || !backup.mimeType || !backup.sha256) {
        throw safeFailure("Le registre de sauvegarde est incomplet.");
      }
      const storage = await descriptor(backup.backupId);
      return downloadVerified(backupBucket, storage.objectPath, {
        byteSize: backup.byteSize,
        mimeType: backup.mimeType,
        sha256: backup.sha256,
      });
    },

    async markRestored(key) {
      const validated = assertKey(key);
      const backup = await current(validated);
      if (!backup) throw safeFailure("La sauvegarde documentaire est introuvable.");
      if (backup.state === "restored") return;
      if (backup.state !== "verified") {
        throw safeFailure("La sauvegarde documentaire ne peut pas confirmer la restauration.");
      }
      await rpc(userClient, "mark_document_operation_backup_restored", {
        p_operation_id: validated.operationId,
        p_target_id: validated.targetId,
        p_expected_revision: backup.revision,
      });
    },

    async remove(key) {
      const backup = await current(key);
      if (!backup || backup.state === "deleted") return;
      const authorized = cleanupSchema.parse(await rpc(
        privilegedClient,
        "authorize_document_operation_backup_cleanup",
        { p_backup_id: backup.backupId, p_expected_revision: backup.revision },
      ));
      const exists = await backupBucket.exists(authorized.objectPath);
      if (exists.error) throw safeFailure("Le stockage de récupération est indisponible.");
      if (exists.data) {
        const removed = await backupBucket.remove([authorized.objectPath]);
        if (removed.error) throw safeFailure("La sauvegarde documentaire n’a pas pu être supprimée.");
      }
      const remaining = await backupBucket.exists(authorized.objectPath);
      if (remaining.error || remaining.data) {
        throw safeFailure("La suppression de la sauvegarde documentaire n’est pas vérifiée.");
      }
      await rpc(privilegedClient, "complete_document_operation_backup_cleanup", {
        p_backup_id: backup.backupId,
        p_expected_revision: backup.revision,
      });
    },
  };
}
