import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { transactionProofOperation } from "../../src/domains/document-operations/domain-adapters.ts";
import { createDurableDocumentBackupStore } from "../../src/domains/document-operations/durable-backup-store.ts";
import {
  describeDocumentContent,
  DocumentOperationEngine,
  DocumentOperationError,
  DocumentOperationRpcError,
} from "../../src/domains/document-operations/engine.ts";

const url = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!url || !anonKey || !serviceRoleKey || !password) throw new Error("Configuration locale absente.");
const endpoint = new URL(url);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Exécution refusée hors de Supabase local.");
}

const ids = {
  owner: "99e00000-0000-4000-8000-000000000001",
  manager: "99e00000-0000-4000-8000-000000000002",
  reader: "99e00000-0000-4000-8000-000000000003",
  outsider: "99e00000-0000-4000-8000-000000000004",
  person: "99e00000-0000-4000-8100-000000000001",
  account: "99e00000-0000-4000-8200-000000000001",
  transactions: Array.from({ length: 7 }, (_, index) => `99e00000-0000-4000-8300-${String(index + 1).padStart(12, "0")}`),
};
const emails = {
  owner: "proof-3e-owner@example.test",
  manager: "proof-3e-manager@example.test",
  reader: "proof-3e-reader@example.test",
  outsider: "proof-3e-outsider@example.test",
};
const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
const storagePaths = new Set();
const backupPaths = new Set();
let lastSafeFailure = null;

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const pdf = new TextEncoder().encode("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n");
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0xff, 0xd9]);
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x00]);
const documentPath = (transactionId) => `protected-persons/${ids.person}/transactions/${transactionId}/proof`;

function client() {
  return createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function authenticate(email) {
  const authenticated = client();
  const { data, error } = await authenticated.auth.signInWithPassword({ email, password });
  assert.ifError(error);
  assert.ok(data.session?.access_token);
  return authenticated;
}

function rpcError(error) {
  if (error?.code === "P4O01") throw new DocumentOperationRpcError("authorization_lost");
  if (error?.code === "P4O06" || error?.code === "P4S05") throw new DocumentOperationRpcError("revision_conflict");
  if (error?.code === "P4S04") throw new DocumentOperationRpcError("storage_diverged");
  throw new DocumentOperationRpcError("rpc_rejected");
}

async function invoke(clientValue, name, args) {
  const { data, error } = await clientValue.rpc(name, args);
  if (error) {
    lastSafeFailure = { component: "rpc", operation: name, code: error.code ?? "unknown" };
    rpcError(error);
  }
  return data;
}

function rpcGateway(user) {
  const getProgress = (operationId) => invoke(user, "get_document_operation_progress", { p_operation_id: operationId });
  return {
    getProgress,
    async start(operationId, expectedRevision) {
      await invoke(user, "start_document_operation", { p_operation_id: operationId, p_expected_revision: expectedRevision });
      return getProgress(operationId);
    },
    async recordApplied(operationId, targetId, expectedOperationRevision, expectedTargetRevision) {
      const value = await invoke(user, "record_document_operation_target_applied", {
        p_operation_id: operationId, p_target_id: targetId,
        p_expected_operation_revision: expectedOperationRevision,
        p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    async finalize(operationId, expectedRevision, finalization) {
      return invoke(user, "finalize_transaction_proof_document_operation", {
        p_operation_id: operationId, p_expected_revision: expectedRevision,
        p_file_name: finalization.fileName, p_mime_type: finalization.mimeType,
        p_file_size: finalization.fileSize,
      });
    },
    async beginCompensation(operationId, expectedRevision, safeCode) {
      await invoke(user, "begin_document_operation_compensation", {
        p_operation_id: operationId, p_expected_revision: expectedRevision, p_safe_code: safeCode,
      });
      return getProgress(operationId);
    },
    async recordCompensated(operationId, targetId, expectedOperationRevision, expectedTargetRevision) {
      const value = await invoke(user, "record_document_operation_target_compensated", {
        p_operation_id: operationId, p_target_id: targetId,
        p_expected_operation_revision: expectedOperationRevision,
        p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    completeCompensation: (operationId, expectedRevision) => invoke(user, "complete_document_operation_compensation", { p_operation_id: operationId, p_expected_revision: expectedRevision }),
    markAttention: (operationId, expectedRevision, safeCode) => invoke(user, "mark_document_operation_attention_required", { p_operation_id: operationId, p_expected_revision: expectedRevision, p_safe_code: safeCode }),
  };
}

function storageGateway(options = {}) {
  const bucket = admin.storage.from("transaction-proofs");
  let uploadCount = 0;
  return {
    get uploadCount() { return uploadCount; },
    async inspect(target) {
      const exists = await bucket.exists(target.objectPath);
      if (!exists.data) return null;
      if (exists.error) {
        lastSafeFailure = { component: "storage", operation: "exists", code: exists.error.statusCode ?? "unknown" };
        throw exists.error;
      }
      const [info, downloaded] = await Promise.all([bucket.info(target.objectPath), bucket.download(target.objectPath)]);
      if (info.error || downloaded.error || !downloaded.data) {
        const failure = info.error ?? downloaded.error;
        lastSafeFailure = { component: "storage", operation: info.error ? "info" : "download", code: failure?.statusCode ?? "unknown" };
        throw failure;
      }
      const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
      return {
        ...describeDocumentContent({ bytes, mimeType: downloaded.data.type || "application/octet-stream" }),
        objectId: info.data.id,
        objectVersion: info.data.version,
      };
    },
    async upload(target, content, upsert) {
      uploadCount += 1;
      storagePaths.add(target.objectPath);
      const result = await bucket.upload(target.objectPath, content.bytes, { contentType: content.mimeType, upsert });
      if (result.error) {
        lastSafeFailure = { component: "storage", operation: "upload", code: result.error.statusCode ?? "unknown" };
        throw result.error;
      }
      if (options.afterUpload) await options.afterUpload();
      if (options.throwAfterUpload) throw new Error("Réponse réseau locale simulée comme perdue.");
    },
    async remove(target) {
      const result = await bucket.remove([target.objectPath]);
      if (result.error) {
        lastSafeFailure = { component: "storage", operation: "remove", code: result.error.statusCode ?? "unknown" };
        throw result.error;
      }
    },
  };
}

function engine(user, storage = storageGateway(), rpc = rpcGateway(user)) {
  return {
    engine: new DocumentOperationEngine({
      rpc,
      storage,
      backups: createDurableDocumentBackupStore(user, admin),
    }),
    rpc,
    storage,
  };
}

async function reserve(user, transactionId, intent, requestId = randomUUID()) {
  const { data, error } = await user.rpc("begin_transaction_proof_document_operation", {
    p_protected_person_id: ids.person,
    p_transaction_id: transactionId,
    p_intent: intent,
    p_client_request_id: requestId,
  });
  if (error) throw error;
  return data;
}

const input = (operationId, bytes, mimeType, name) => transactionProofOperation(
  operationId,
  bytes ? { bytes, mimeType } : null,
  { fileName: name, mimeType: bytes ? mimeType : null, fileSize: bytes?.byteLength ?? null },
);

async function assertStored(path, expectedBytes, expectedMime) {
  const [info, download] = await Promise.all([
    admin.storage.from("transaction-proofs").info(path),
    admin.storage.from("transaction-proofs").download(path),
  ]);
  assert.ifError(info.error);
  assert.ifError(download.error);
  const bytes = new Uint8Array(await download.data.arrayBuffer());
  assert.equal(sha256(bytes), sha256(expectedBytes));
  assert.equal(download.data.type, expectedMime);
  assert.ok(info.data.id && info.data.version);
  return info.data;
}

async function metadata(transactionId) {
  const result = await admin.from("transaction_documents").select("*").eq("transaction_id", transactionId).maybeSingle();
  assert.ifError(result.error);
  return result.data;
}

async function rememberBackupPath(user, operationId, targetId) {
  const backup = await invoke(user, "get_document_operation_backup", {
    p_operation_id: operationId,
    p_target_id: targetId,
  });
  const descriptor = await admin.rpc("get_document_operation_backup_storage_descriptor", {
    p_backup_id: backup.backupId,
  });
  assert.ifError(descriptor.error);
  backupPaths.add(descriptor.data.objectPath);
  return backup;
}

async function main() {
  const [owner, manager, reader, outsider] = await Promise.all(Object.values(emails).map(authenticate));

  await assert.rejects(reserve(reader, ids.transactions[0], "create"));
  await assert.rejects(reserve(outsider, ids.transactions[0], "create"));
  const arbitrary = await owner.storage.from("transaction-proofs").upload(`${documentPath(ids.transactions[0])}/extra`, pdf, { contentType: "application/pdf" });
  assert.ok(arbitrary.error);
  const backupAccess = await owner.storage.from("document-operation-backups").list("operations", { limit: 1 });
  assert.ifError(backupAccess.error);
  assert.deepEqual(backupAccess.data, []);
  const guessedBackup = await owner.storage.from("document-operation-backups").download(
    `operations/${randomUUID()}/targets/${randomUUID()}/backup`,
  );
  assert.ok(guessedBackup.error);

  const createId = await reserve(owner, ids.transactions[0], "create");
  const createProgress = await rpcGateway(owner).getProgress(createId);
  assert.equal(createProgress.targets[0].objectPath, documentPath(ids.transactions[0]));
  assert.equal(createProgress.targets[0].bucketId, "transaction-proofs");
  try {
    await engine(owner).engine.execute(input(createId, pdf, "application/pdf", "preuve.pdf"));
  } catch (error) {
    console.error("Échec sûr du scénario création", lastSafeFailure, error instanceof DocumentOperationError ? { stage: error.stage, code: error.code } : null);
    throw error;
  }
  await assertStored(documentPath(ids.transactions[0]), pdf, "application/pdf");
  const managerDownload = await manager.storage.from("transaction-proofs").download(documentPath(ids.transactions[0]));
  assert.ifError(managerDownload.error);
  const readerDownload = await reader.storage.from("transaction-proofs").download(documentPath(ids.transactions[0]));
  assert.ifError(readerDownload.error);
  const outsiderDownload = await outsider.storage.from("transaction-proofs").download(documentPath(ids.transactions[0]));
  assert.ok(outsiderDownload.error);
  assert.deepEqual(Object.assign({}, await metadata(ids.transactions[0]), { id: undefined, created_at: undefined, updated_at: undefined, created_by: undefined }), {
    id: undefined, transaction_id: ids.transactions[0], storage_path: documentPath(ids.transactions[0]),
    file_name: "preuve.pdf", mime_type: "application/pdf", file_size: pdf.byteLength,
    created_by: undefined, created_at: undefined, updated_at: undefined,
  });

  const replaceId = await reserve(owner, ids.transactions[0], "replace");
  const firstEngine = engine(owner);
  await firstEngine.engine.start(replaceId);
  const replacementProgress = await firstEngine.rpc.getProgress(replaceId);
  const backup = await rememberBackupPath(owner, replaceId, replacementProgress.targets[0].id);
  assert.equal(backup.state, "verified");
  assert.equal(backup.sha256, sha256(pdf));
  await engine(owner).engine.execute(input(replaceId, jpeg, "image/jpeg", "preuve.jpg"));
  await assertStored(documentPath(ids.transactions[0]), jpeg, "image/jpeg");
  const cleanedBackup = await invoke(owner, "get_document_operation_backup", { p_operation_id: replaceId, p_target_id: replacementProgress.targets[0].id });
  assert.equal(cleanedBackup.state, "deleted");

  const pngReplaceId = await reserve(owner, ids.transactions[0], "replace");
  await engine(owner).engine.execute(input(pngReplaceId, png, "image/png", "preuve.png"));
  const beforeSameBytes = await assertStored(documentPath(ids.transactions[0]), png, "image/png");
  const sameBytesId = await reserve(owner, ids.transactions[0], "replace");
  const sameBytesEngine = engine(owner);
  await sameBytesEngine.engine.execute(input(sameBytesId, png, "image/png", "preuve-identique.png"));
  const afterSameBytes = await assertStored(documentPath(ids.transactions[0]), png, "image/png");
  assert.notEqual(afterSameBytes.version, beforeSameBytes.version);
  assert.equal(sameBytesEngine.storage.uploadCount, 1);

  const deleteId = await reserve(owner, ids.transactions[0], "delete");
  const deleteStart = engine(owner);
  await deleteStart.engine.start(deleteId);
  const deleteProgress = await deleteStart.rpc.getProgress(deleteId);
  await rememberBackupPath(owner, deleteId, deleteProgress.targets[0].id);
  await engine(owner).engine.execute(input(deleteId, null, null, null));
  assert.equal((await admin.storage.from("transaction-proofs").exists(documentPath(ids.transactions[0]))).data, false);
  assert.equal(await metadata(ids.transactions[0]), null);

  const ambiguousId = await reserve(manager, ids.transactions[1], "create");
  const ambiguousStorage = storageGateway({ throwAfterUpload: true });
  await engine(manager, ambiguousStorage).engine.execute(input(ambiguousId, pdf, "application/pdf", "ambigu.pdf"));
  assert.equal(ambiguousStorage.uploadCount, 1);
  await assertStored(documentPath(ids.transactions[1]), pdf, "application/pdf");

  const failureId = await reserve(owner, ids.transactions[2], "create");
  const baseRpc = rpcGateway(owner);
  const failingRpc = { ...baseRpc, async finalize() { throw new DocumentOperationRpcError("rpc_rejected"); } };
  await assert.rejects(engine(owner, storageGateway(), failingRpc).engine.execute(input(failureId, jpeg, "image/jpeg", "echec.jpg")), DocumentOperationError);
  assert.equal((await baseRpc.getProgress(failureId)).state, "compensated");
  assert.equal((await admin.storage.from("transaction-proofs").exists(documentPath(ids.transactions[2]))).data, false);

  const originalId = await reserve(owner, ids.transactions[3], "create");
  await engine(owner).engine.execute(input(originalId, pdf, "application/pdf", "original.pdf"));
  const interruptedId = await reserve(owner, ids.transactions[3], "replace");
  const interrupted = engine(owner);
  await interrupted.engine.start(interruptedId);
  let progress = await interrupted.rpc.getProgress(interruptedId);
  const target = progress.targets[0];
  await rememberBackupPath(owner, interruptedId, target.id);
  await interrupted.storage.upload(target, { bytes: jpeg, mimeType: "image/jpeg" }, true);
  const recorded = await interrupted.rpc.recordApplied(interruptedId, target.id, progress.revision, target.revision);
  progress = await interrupted.rpc.beginCompensation(interruptedId, recorded.operationRevision, "TEST_RESTART");
  assert.equal(progress.state, "compensating");
  const resumed = await engine(owner).engine.execute(input(interruptedId, jpeg, "image/jpeg", "interrompu.jpg"));
  assert.equal(resumed.state, "compensated");
  await assertStored(documentPath(ids.transactions[3]), pdf, "application/pdf");

  const idempotencyKey = randomUUID();
  const simultaneous = await Promise.all([
    reserve(owner, ids.transactions[4], "create", idempotencyKey),
    reserve(owner, ids.transactions[4], "create", idempotencyKey),
  ]);
  assert.equal(simultaneous[0], simultaneous[1]);
  const staleRpc = rpcGateway(owner);
  const staleProgress = await staleRpc.getProgress(simultaneous[0]);
  await staleRpc.start(simultaneous[0], staleProgress.revision);
  await assert.rejects(staleRpc.start(simultaneous[0], staleProgress.revision), (error) => error instanceof DocumentOperationRpcError && error.reason === "revision_conflict");

  const divergenceOriginalId = await reserve(owner, ids.transactions[6], "create");
  await engine(owner).engine.execute(input(divergenceOriginalId, pdf, "application/pdf", "divergence-original.pdf"));
  const divergenceId = await reserve(owner, ids.transactions[6], "replace");
  const divergenceEngine = engine(owner);
  await divergenceEngine.engine.start(divergenceId);
  const divergenceProgress = await divergenceEngine.rpc.getProgress(divergenceId);
  await rememberBackupPath(owner, divergenceId, divergenceProgress.targets[0].id);
  const externalMutation = await admin.storage.from("transaction-proofs").upload(
    documentPath(ids.transactions[6]), jpeg, { contentType: "image/jpeg", upsert: true },
  );
  assert.ifError(externalMutation.error);
  await assert.rejects(
    divergenceEngine.engine.execute(input(divergenceId, png, "image/png", "divergence.png")),
    (error) => error instanceof DocumentOperationError && error.code === "storage_diverged",
  );
  assert.equal((await divergenceEngine.rpc.getProgress(divergenceId)).state, "attention_required");
  await assertStored(documentPath(ids.transactions[6]), jpeg, "image/jpeg");

  const managerId = await reserve(manager, ids.transactions[5], "create");
  const rightsStorage = storageGateway({ afterUpload: async () => {
    const removal = await admin.from("protected_person_access").delete().eq("user_id", ids.manager).eq("protected_person_id", ids.person);
    assert.ifError(removal.error);
  } });
  await assert.rejects(engine(manager, rightsStorage).engine.execute(input(managerId, png, "image/png", "droits.png")), DocumentOperationError);
  const restoredAccess = await admin.from("protected_person_access").insert({
    id: randomUUID(),
    protected_person_id: ids.person,
    user_id: ids.manager,
    role: "manager",
    invited_by: ids.owner,
  });
  assert.ifError(restoredAccess.error);
  const operation = await rpcGateway(manager).getProgress(managerId);
  assert.equal(operation.state, "attention_required");

  console.log("PASS: chaîne réelle Storage/PostgreSQL, permissions, reprises, compensations et idempotence validées localement.");
}

try {
  await main();
} finally {
  for (const transactionId of ids.transactions) storagePaths.add(documentPath(transactionId));
  if (storagePaths.size) await admin.storage.from("transaction-proofs").remove([...storagePaths]);
  if (backupPaths.size) await admin.storage.from("document-operation-backups").remove([...backupPaths]);
}
