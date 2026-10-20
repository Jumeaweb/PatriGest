import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { createDurableDocumentBackupStore } from "./durable-backup-store.ts";

const OPERATION_ID = "11111111-1111-4111-8111-111111111111";
const TARGET_ID = "22222222-2222-4222-8222-222222222222";
const BACKUP_ID = "33333333-3333-4333-8333-333333333333";
const PATH = `operations/${OPERATION_ID}/targets/${TARGET_ID}/backup`;
const KEY = { operationId: OPERATION_ID, targetId: TARGET_ID };

function stored(value = "document", mimeType = "application/pdf") {
  const bytes = new TextEncoder().encode(value);
  return {
    bytes,
    byteSize: bytes.byteLength,
    mimeType,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

function createHarness(options = {}) {
  const files = new Map();
  const calls = [];
  let record = null;
  let terminal = options.terminal ?? false;

  const user = {
    async rpc(name, args) {
      calls.push(`user:${name}`);
      if (name === "reserve_document_operation_backup") {
        const next = {
          backupId: BACKUP_ID,
          state: "upload_pending",
          revision: 0,
          byteSize: args.p_byte_size,
          mimeType: args.p_mime_type,
          sha256: args.p_sha256,
        };
        if (record && (
          record.byteSize !== next.byteSize
          || record.mimeType !== next.mimeType
          || record.sha256 !== next.sha256
        )) return { data: null, error: { code: "P4B05" } };
        record ??= next;
        return { data: { backupId: record.backupId, state: record.state, revision: record.revision }, error: null };
      }
      if (name === "confirm_document_operation_backup") {
        record = { ...record, state: "verified", revision: record.revision + 1 };
        return { data: record, error: null };
      }
      if (name === "get_document_operation_backup") {
        return { data: record, error: null };
      }
      if (name === "mark_document_operation_backup_restored") {
        record = { ...record, state: "restored", revision: record.revision + 1 };
        return { data: record, error: null };
      }
      throw new Error(`RPC utilisateur inattendue: ${name}`);
    },
  };

  const bucket = {
    async exists(path) {
      calls.push(`exists:${path}`);
      return { data: files.has(path), error: null };
    },
    async download(path) {
      calls.push(`download:${path}`);
      return { data: files.get(path) ?? null, error: files.has(path) ? null : { code: "not-found" } };
    },
    async upload(path, bytes, uploadOptions) {
      calls.push(`upload:${path}:${uploadOptions.upsert}`);
      if (files.has(path) && !uploadOptions.upsert) return { data: null, error: { code: "exists" } };
      const body = options.corruptUpload ? new TextEncoder().encode("corrompu") : bytes;
      files.set(path, new Blob([body], { type: uploadOptions.contentType }));
      return { data: {}, error: null };
    },
    async remove(paths) {
      calls.push(`remove:${paths.join(",")}`);
      for (const path of paths) files.delete(path);
      return { data: {}, error: null };
    },
  };

  const privileged = {
    storage: {
      from(name) {
        assert.equal(name, "document-operation-backups");
        return bucket;
      },
    },
    async rpc(name) {
      calls.push(`admin:${name}`);
      if (name === "get_document_operation_backup_storage_descriptor") {
        return { data: {
          ...record,
          operationId: OPERATION_ID,
          targetId: TARGET_ID,
          bucketId: "document-operation-backups",
          objectPath: options.descriptorPath ?? PATH,
        }, error: null };
      }
      if (name === "authorize_document_operation_backup_cleanup") {
        if (!terminal) return { data: null, error: { code: "P4B06" } };
        return { data: {
          backupId: BACKUP_ID,
          bucketId: "document-operation-backups",
          objectPath: PATH,
          state: record.state,
          revision: record.revision,
        }, error: null };
      }
      if (name === "complete_document_operation_backup_cleanup") {
        record = { ...record, state: "deleted", revision: record.revision + 1 };
        return { data: null, error: null };
      }
      throw new Error(`RPC privilégiée inattendue: ${name}`);
    },
  };

  return {
    user,
    privileged,
    files,
    calls,
    current: () => record,
    terminal: () => { terminal = true; },
    store: () => createDurableDocumentBackupStore(user, privileged),
  };
}

test("crée, retélécharge et confirme une sauvegarde SHA-256", async () => {
  const harness = createHarness();
  const object = stored();
  await harness.store().save(KEY, object);
  assert.equal(harness.current().state, "verified");
  assert.equal((await harness.store().load(KEY)).sha256, object.sha256);
  assert.ok(harness.calls.includes(`upload:${PATH}:false`));
});

test("refuse des métadonnées locales incohérentes avant tout appel", async () => {
  const harness = createHarness();
  await assert.rejects(
    harness.store().save(KEY, { ...stored(), sha256: "0".repeat(64) }),
    /métadonnées/,
  );
  assert.deepEqual(harness.calls, []);
});

test("ne confirme jamais des octets corrompus", async () => {
  const harness = createHarness({ corruptUpload: true });
  await assert.rejects(harness.store().save(KEY, stored()), /intégrité/);
  assert.equal(harness.current().state, "upload_pending");
  assert.equal(harness.calls.includes("user:confirm_document_operation_backup"), false);
});

test("refuse un objet de récupération existant dont l’empreinte diffère", async () => {
  const harness = createHarness();
  harness.files.set(PATH, new Blob(["autre"], { type: "application/pdf" }));
  await assert.rejects(harness.store().save(KEY, stored()), /intégrité/);
  assert.equal(harness.calls.some((call) => call.startsWith("upload:")), false);
});

test("reprend une sauvegarde vérifiée après recréation du store", async () => {
  const harness = createHarness();
  const object = stored("persistant");
  await harness.store().save(KEY, object);
  const restartedStore = harness.store();
  assert.deepEqual(await restartedStore.load(KEY), object);
});

test("trace la restauration vérifiée via la cible exacte", async () => {
  const harness = createHarness();
  await harness.store().save(KEY, stored());
  await harness.store().markRestored(KEY);
  assert.equal(harness.current().state, "restored");
  assert.ok(harness.calls.includes("user:mark_document_operation_backup_restored"));
});

test("préserve la sauvegarde si l’opération n’est pas terminale", async () => {
  const harness = createHarness();
  await harness.store().save(KEY, stored());
  await assert.rejects(harness.store().remove(KEY), /n’a pas pu être confirmée/);
  assert.equal(harness.files.has(PATH), true);
});

test("supprime puis confirme le nettoyage uniquement après autorisation terminale", async () => {
  const harness = createHarness();
  await harness.store().save(KEY, stored());
  harness.terminal();
  await harness.store().remove(KEY);
  assert.equal(harness.files.has(PATH), false);
  assert.equal(harness.current().state, "deleted");
});

test("rejette un descripteur privilégié contenant un chemin arbitraire", async () => {
  const harness = createHarness({ descriptorPath: "../secret" });
  await assert.rejects(harness.store().save(KEY, stored()));
  assert.equal(harness.files.size, 0);
});
