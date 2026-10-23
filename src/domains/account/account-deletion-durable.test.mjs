import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { afterEach, test } from "node:test";

import { isAccountDeletionDurableNeutralizationEnabled } from "./account-deletion-durable-availability.ts";
import {
  AccountDeletionDurableStorageError,
  beginAccountStorageNeutralization,
  resumeAccountStorageNeutralization,
} from "./account-deletion-durable.ts";

const flag = "PATRIGEST_ENABLE_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION";
const operationId = "99500000-0000-4000-8000-000000000001";
const targetId = "99500000-0000-4000-8000-000000000002";
const originalId = "99500000-0000-4000-8000-000000000003";
const backupId = "99500000-0000-4000-8000-000000000004";
const bucketId = "transaction-proofs";
const objectPath = "protected-persons/dossier/transactions/operation/proof.pdf";
const backupPath = `account-deletion/${operationId}/proof.pdf`;
const bytes = new TextEncoder().encode("document durable");
const digest = createHash("sha256").update(bytes).digest("hex");

afterEach(() => delete process.env[flag]);

test("active le parcours durable uniquement pour la valeur exacte true", () => {
  for (const value of [undefined, "TRUE", "1", " true", "false"]) {
    if (value === undefined) delete process.env[flag];
    else process.env[flag] = value;
    assert.equal(isAccountDeletionDurableNeutralizationEnabled(), false);
  }
  process.env[flag] = "true";
  assert.equal(isAccountDeletionDurableNeutralizationEnabled(), true);
});

function stored(id, version, content = bytes) {
  return {
    id,
    version,
    bytes: new Uint8Array(content),
    contentType: "application/pdf",
    cacheControl: "max-age=3600",
    metadata: { origin: "test" },
  };
}

function durableHarness({ initialPhase = "reserved", divergentOriginal = false } = {}) {
  const objects = new Map();
  const key = (bucket, path) => `${bucket}:${path}`;
  if (initialPhase !== "original_deleted") {
    objects.set(
      key(bucketId, objectPath),
      stored(originalId, divergentOriginal ? "unexpected" : "version-1"),
    );
  }
  if (initialPhase === "original_deleted") {
    objects.set(key("document-operation-backups", backupPath), stored(backupId, "backup-1"));
  }
  const calls = [];
  const state = {
    phase: initialPhase,
    revision: initialPhase === "original_deleted" ? 2 : 0,
    recreatedObjectId: null,
    recreatedObjectVersion: null,
  };
  const progress = () => ({
    operationId,
    state: state.phase === "finalized" ? "completed" : "executing",
    operationRevision: state.revision,
    targetId,
    bucketId,
    objectPath,
    phase: state.phase,
    resumePhase: null,
    revision: state.revision,
    backupState: state.phase === "reserved" ? null : "verified",
    objectPresent: objects.has(key(bucketId, objectPath)),
    verifiedBackupPresent: objects.has(key("document-operation-backups", backupPath)),
    recoveryRequired: state.phase === "original_deleted",
    uncertain: state.phase === "attention_required",
    expectedObjectId: originalId,
    expectedObjectVersion: "version-1",
    recreatedObjectId: state.recreatedObjectId,
    recreatedObjectVersion: state.recreatedObjectVersion,
    expectedSha256: digest,
    expectedByteSize: bytes.byteLength,
  });
  const client = {
    storage: {
      from(bucket) {
        return {
          async exists(path) {
            return { data: objects.has(key(bucket, path)), error: null };
          },
          async info(path) {
            const value = objects.get(key(bucket, path));
            return value
              ? { data: {
                  id: value.id,
                  version: value.version,
                  contentType: value.contentType,
                  cacheControl: value.cacheControl,
                  metadata: value.metadata,
                  size: value.bytes.byteLength,
                }, error: null }
              : { data: null, error: { status: 404 } };
          },
          async download(path) {
            const value = objects.get(key(bucket, path));
            return value
              ? { data: new Blob([value.bytes], { type: value.contentType }), error: null }
              : { data: null, error: { status: 404 } };
          },
          async upload(path, body, options) {
            const objectKey = key(bucket, path);
            if (objects.has(objectKey) && !options.upsert) {
              return { data: null, error: { status: 409 } };
            }
            objects.set(objectKey, stored(randomUUID(), randomUUID(), body));
            calls.push(["upload", bucket, path]);
            return { data: { path }, error: null };
          },
          async remove(paths) {
            for (const path of paths) objects.delete(key(bucket, path));
            calls.push(["remove", bucket, ...paths]);
            return { data: paths, error: null };
          },
        };
      },
    },
    async rpc(name, args = {}) {
      calls.push(["rpc", name, args]);
      if (name === "get_account_storage_neutralization_progress") {
        return { data: progress(), error: null };
      }
      if (name === "reserve_account_storage_neutralization_backup") {
        return { data: {
          backupId,
          bucketId: "document-operation-backups",
          objectPath: backupPath,
          state: "reserved",
          revision: 0,
        }, error: null };
      }
      if (name === "confirm_account_storage_neutralization_backup") {
        state.phase = "backup_verified";
        state.revision = 1;
      } else if (name === "record_account_storage_neutralization_original_deleted") {
        state.phase = "original_deleted";
        state.revision = 2;
      } else if (name === "authorize_account_storage_neutralization_recovery") {
        return { data: {
          backupId,
          sourceBucketId: "document-operation-backups",
          sourceObjectPath: backupPath,
          destinationBucketId: bucketId,
          destinationObjectPath: objectPath,
          expectedSha256: digest,
          expectedByteSize: bytes.byteLength,
          mimeType: "application/pdf",
          revision: state.revision,
        }, error: null };
      } else if (name === "confirm_account_storage_neutralization_recovery") {
        const recreated = objects.get(key(bucketId, objectPath));
        state.recreatedObjectId = recreated.id;
        state.recreatedObjectVersion = recreated.version;
        state.phase = "recreated";
        state.revision = 3;
      } else if (name === "verify_account_storage_neutralization_content") {
        state.phase = "verified";
        state.revision = 4;
      } else if (name === "authorize_account_storage_neutralization_backup_cleanup") {
        if (state.phase === "verified") {
          state.phase = "backup_cleanup_authorized";
          state.revision = 5;
        }
        return { data: {
          backupId,
          bucketId: "document-operation-backups",
          objectPath: backupPath,
          state: "cleanup_authorized",
          revision: 1,
        }, error: null };
      } else if (name === "confirm_account_storage_neutralization_backup_cleanup") {
        state.phase = "backup_cleaned";
        state.revision = 6;
      } else if (name === "finalize_account_storage_neutralization") {
        state.phase = "finalized";
        state.revision = 7;
        return { data: { operationId, phase: "finalized", revision: 7 }, error: null };
      } else if (name === "mark_account_storage_neutralization_attention_required") {
        state.phase = "attention_required";
        state.revision += 1;
      }
      return { data: { operationId, phase: state.phase, revision: state.revision }, error: null };
    },
  };
  return { client, calls, objects, state, key };
}

test("neutralise un objet par sauvegarde durable et reprend jusqu’à finalisation", async () => {
  const harness = durableHarness();
  const result = await resumeAccountStorageNeutralization(harness.client, operationId);
  assert.equal(result.phase, "finalized");
  assert.equal(harness.objects.has(harness.key("document-operation-backups", backupPath)), false);
  const restored = harness.objects.get(harness.key(bucketId, objectPath));
  assert.deepEqual(restored.bytes, bytes);
  assert.notEqual(restored.id, originalId);
  assert.equal(harness.calls.some((call) => call.includes(".sec02-backup-")), false);
});

test("reprend après suppression à partir de la sauvegarde durable existante", async () => {
  const harness = durableHarness({ initialPhase: "original_deleted" });
  const result = await resumeAccountStorageNeutralization(harness.client, operationId);
  assert.equal(result.phase, "finalized");
  assert.deepEqual(
    harness.objects.get(harness.key(bucketId, objectPath)).bytes,
    bytes,
  );
  assert.equal(
    harness.calls.some((call) => call[1] === "reserve_account_storage_neutralization_backup"),
    false,
  );
});

test("place une divergence Storage en attention_required sans effacer l’objet", async () => {
  const harness = durableHarness({ divergentOriginal: true });
  await assert.rejects(
    resumeAccountStorageNeutralization(harness.client, operationId),
    AccountDeletionDurableStorageError,
  );
  assert.equal(harness.state.phase, "attention_required");
  assert.equal(harness.objects.has(harness.key(bucketId, objectPath)), true);
  assert.equal(harness.objects.has(harness.key("document-operation-backups", backupPath)), false);
});

test("dérive un identifiant d’idempotence stable de la tentative et de l’objet", async () => {
  const requests = [];
  const client = {
    async rpc(name, args) {
      assert.equal(name, "begin_account_storage_neutralization");
      requests.push(args.p_client_request_id);
      return { data: { operationId, targetId, phase: "reserved", revision: 0 }, error: null };
    },
  };
  const attemptId = "99500000-0000-4000-8000-000000000010";
  const object = { bucket_id: bucketId, name: objectPath, metadata: {}, user_metadata: {} };
  const observed = {
    objectId: originalId,
    objectVersion: "version-1",
    bytes,
    byteSize: bytes.byteLength,
    mimeType: "application/pdf",
    sha256: digest,
    metadata: {},
  };
  await beginAccountStorageNeutralization(client, randomUUID(), attemptId, object, observed);
  await beginAccountStorageNeutralization(client, randomUUID(), attemptId, object, observed);
  assert.equal(requests[0], requests[1]);
  assert.match(requests[0], /^[0-9a-f-]{36}$/);
});
