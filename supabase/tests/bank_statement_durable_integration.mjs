import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { bankStatementOperation } from "../../src/domains/document-operations/domain-adapters.ts";
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
  owner: "99f00000-0000-4000-8000-000000000001",
  manager: "99f00000-0000-4000-8000-000000000002",
  reader: "99f00000-0000-4000-8000-000000000003",
  outsider: "99f00000-0000-4000-8000-000000000004",
  person: "99f00000-0000-4000-8100-000000000001",
  account: "99f00000-0000-4000-8200-000000000001",
  statements: Array.from({ length: 7 }, (_, index) => `99f00000-0000-4000-8300-${String(index + 1).padStart(12, "0")}`),
};
const emails = {
  owner: "statement-3f-owner@example.test",
  manager: "statement-3f-manager@example.test",
  reader: "statement-3f-reader@example.test",
  outsider: "statement-3f-outsider@example.test",
};
const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
let lastSafeFailure = null;
const pdfA = new TextEncoder().encode("%PDF-1.4\n% relevé A\n%%EOF\n");
const pdfB = new TextEncoder().encode("%PDF-1.4\n% relevé B\n%%EOF\n");
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const path = (statementId) => `protected-persons/${ids.person}/accounts/${ids.account}/statements/${statementId}/statement`;

const client = () => createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
async function authenticate(email) {
  const value = client();
  const { data, error } = await value.auth.signInWithPassword({ email, password });
  assert.ifError(error);
  assert.ok(data.session?.access_token);
  return value;
}

function rpcError(error) {
  if (error?.code === "P4O01") throw new DocumentOperationRpcError("authorization_lost");
  if (error?.code === "P4O06" || error?.code === "P4S05") throw new DocumentOperationRpcError("revision_conflict");
  if (error?.code === "P4S04") throw new DocumentOperationRpcError("storage_diverged");
  throw new DocumentOperationRpcError("rpc_rejected");
}
async function invoke(user, name, args) {
  const { data, error } = await user.rpc(name, args);
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
        p_expected_operation_revision: expectedOperationRevision, p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    finalize(operationId, expectedRevision, finalization) {
      return invoke(user, "finalize_bank_statement_document_operation", {
        p_operation_id: operationId, p_expected_revision: expectedRevision,
        p_statement_start_date: finalization.statementStartDate,
        p_statement_end_date: finalization.statementEndDate,
        p_statement_balance: finalization.statementBalance, p_note: finalization.note,
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
        p_expected_operation_revision: expectedOperationRevision, p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    completeCompensation: (operationId, expectedRevision) => invoke(user, "complete_document_operation_compensation", { p_operation_id: operationId, p_expected_revision: expectedRevision }),
    markAttention: (operationId, expectedRevision, safeCode) => invoke(user, "mark_document_operation_attention_required", { p_operation_id: operationId, p_expected_revision: expectedRevision, p_safe_code: safeCode }),
  };
}

function storageGateway(options = {}) {
  const bucket = admin.storage.from("bank-statements");
  return {
    async inspect(target) {
      const exists = await bucket.exists(target.objectPath);
      if (!exists.data) return null;
      if (exists.error) { lastSafeFailure = { component: "storage", operation: "exists", code: exists.error.statusCode }; throw exists.error; }
      const [info, download] = await Promise.all([bucket.info(target.objectPath), bucket.download(target.objectPath)]);
      if (info.error || download.error || !download.data) { const failure = info.error ?? download.error; lastSafeFailure = { component: "storage", operation: info.error ? "info" : "download", code: failure?.statusCode }; throw failure; }
      const bytes = new Uint8Array(await download.data.arrayBuffer());
      return { ...describeDocumentContent({ bytes, mimeType: download.data.type }), objectId: info.data.id, objectVersion: info.data.version };
    },
    async upload(target, content, upsert) {
      const result = await bucket.upload(target.objectPath, content.bytes, { contentType: content.mimeType, upsert });
      if (result.error) { lastSafeFailure = { component: "storage", operation: "upload", code: result.error.statusCode }; throw result.error; }
      if (options.afterUpload) await options.afterUpload();
      if (options.throwAfterUpload) throw new Error("Réponse locale simulée comme perdue.");
    },
    async remove(target) {
      const result = await bucket.remove([target.objectPath]);
      if (result.error) { lastSafeFailure = { component: "storage", operation: "remove", code: result.error.statusCode }; throw result.error; }
    },
  };
}
function engine(user, storage = storageGateway(), rpc = rpcGateway(user)) {
  return new DocumentOperationEngine({ rpc, storage, backups: createDurableDocumentBackupStore(user, admin) });
}
async function reserve(user, statementId, intent, requestId = randomUUID()) {
  const { data, error } = await user.rpc("begin_bank_statement_document_operation", {
    p_protected_person_id: ids.person,
    p_financial_account_id: ids.account,
    p_statement_id: statementId,
    p_intent: intent,
    p_client_request_id: requestId,
  });
  if (error) throw error;
  return data;
}
const finalization = (index, fileName) => ({
  statementStartDate: `2026-0${index + 1}-01`,
  statementEndDate: `2026-0${index + 1}-28`,
  statementBalance: 100 + index + 0.25,
  note: `Intégration ${index + 1}`,
  fileName,
  mimeType: fileName ? "application/pdf" : null,
  fileSize: fileName ? pdfA.byteLength : null,
});
const operation = (operationId, bytes, values) => bankStatementOperation(
  operationId,
  bytes ? { bytes, mimeType: "application/pdf" } : null,
  { ...values, fileSize: bytes?.byteLength ?? null },
);
async function statement(statementId) {
  const result = await admin.from("bank_statements").select("*").eq("id", statementId).maybeSingle();
  assert.ifError(result.error);
  return result.data;
}
async function assertStored(statementId, expected) {
  const result = await admin.storage.from("bank-statements").download(path(statementId));
  assert.ifError(result.error);
  assert.equal(sha256(new Uint8Array(await result.data.arrayBuffer())), sha256(expected));
}

async function main() {
  const [owner, manager, reader, outsider] = await Promise.all(Object.values(emails).map(authenticate));
  await assert.rejects(reserve(reader, ids.statements[0], "create"));
  await assert.rejects(reserve(outsider, ids.statements[0], "create"));

  const createId = await reserve(owner, ids.statements[0], "create");
  const progress = await rpcGateway(owner).getProgress(createId);
  assert.equal(progress.targets[0].objectPath, path(ids.statements[0]));
  try {
    await engine(owner).execute(operation(createId, pdfA, finalization(0, "septembre.pdf")));
  } catch (error) {
    const current = await admin.from("document_operations")
      .select("state,safe_error_code,row_revision").eq("id", createId).maybeSingle();
    console.error("Échec sûr de la création locale", {
      stage: error instanceof DocumentOperationError ? error.stage : "unknown",
      code: error instanceof DocumentOperationError ? error.code : "unknown",
      lastSafeFailure,
      operation: current.data,
    });
    throw error;
  }
  await assertStored(ids.statements[0], pdfA);
  assert.equal((await statement(ids.statements[0])).original_file_name, "septembre.pdf");
  assert.ifError((await manager.storage.from("bank-statements").download(path(ids.statements[0]))).error);
  assert.ifError((await reader.storage.from("bank-statements").download(path(ids.statements[0]))).error);
  assert.ok((await outsider.storage.from("bank-statements").download(path(ids.statements[0]))).error);

  const attachId = await reserve(manager, ids.statements[1], "attach");
  await engine(manager).execute(operation(attachId, pdfA, finalization(1, "octobre.pdf")));
  await assertStored(ids.statements[1], pdfA);

  const replaceId = await reserve(owner, ids.statements[0], "replace");
  const replaceEngine = engine(owner);
  await replaceEngine.start(replaceId);
  const replaceProgress = await rpcGateway(owner).getProgress(replaceId);
  const backupBefore = await invoke(owner, "get_document_operation_backup", {
    p_operation_id: replaceId, p_target_id: replaceProgress.targets[0].id,
  });
  assert.equal(backupBefore.state, "verified");
  assert.equal(backupBefore.sha256, sha256(pdfA));
  await replaceEngine.execute(operation(replaceId, pdfB, finalization(0, "septembre-corrige.pdf")));
  await assertStored(ids.statements[0], pdfB);
  const backupAfter = await invoke(owner, "get_document_operation_backup", {
    p_operation_id: replaceId, p_target_id: replaceProgress.targets[0].id,
  });
  assert.equal(backupAfter.state, "deleted");

  const requestId = randomUUID();
  const [first, repeated] = await Promise.all([
    reserve(owner, ids.statements[2], "create", requestId),
    reserve(owner, ids.statements[2], "create", requestId),
  ]);
  assert.equal(repeated, first);
  await assert.rejects(reserve(manager, ids.statements[2], "create"));
  const staleRpc = rpcGateway(owner);
  const staleProgress = await staleRpc.getProgress(first);
  await staleRpc.start(first, staleProgress.revision);
  await assert.rejects(
    staleRpc.start(first, staleProgress.revision),
    (error) => error instanceof DocumentOperationRpcError && error.reason === "revision_conflict",
  );
  await engine(owner).execute(operation(first, pdfA, finalization(2, "novembre.pdf")));

  const failedId = await reserve(owner, ids.statements[3], "create");
  const baseRpc = rpcGateway(owner);
  const failingRpc = { ...baseRpc, async finalize() { throw new DocumentOperationRpcError("rpc_rejected"); } };
  await assert.rejects(engine(owner, storageGateway(), failingRpc).execute(operation(failedId, pdfA, finalization(3, "decembre.pdf"))), DocumentOperationError);
  assert.equal((await baseRpc.getProgress(failedId)).state, "compensated");
  assert.equal((await admin.storage.from("bank-statements").exists(path(ids.statements[3]))).data, false);
  assert.equal(await statement(ids.statements[3]), null);

  const ambiguousId = await reserve(manager, ids.statements[4], "create");
  await engine(manager, storageGateway({ throwAfterUpload: true })).execute(operation(ambiguousId, pdfA, finalization(4, "janvier.pdf")));
  await assertStored(ids.statements[4], pdfA);

  const interruptedId = await reserve(owner, ids.statements[1], "replace");
  const interruptedRpc = rpcGateway(owner);
  const interruptedStorage = storageGateway();
  const interruptedEngine = engine(owner, interruptedStorage, interruptedRpc);
  await interruptedEngine.start(interruptedId);
  let interruptedProgress = await interruptedRpc.getProgress(interruptedId);
  const interruptedTarget = interruptedProgress.targets[0];
  await interruptedStorage.upload(interruptedTarget, { bytes: pdfB, mimeType: "application/pdf" }, true);
  const recorded = await interruptedRpc.recordApplied(
    interruptedId,
    interruptedTarget.id,
    interruptedProgress.revision,
    interruptedTarget.revision,
  );
  interruptedProgress = await interruptedRpc.beginCompensation(
    interruptedId,
    recorded.operationRevision,
    "TEST_RESTART",
  );
  assert.equal(interruptedProgress.state, "compensating");
  const resumed = await engine(owner).execute(operation(interruptedId, pdfB, finalization(1, "octobre-corrige.pdf")));
  assert.equal(resumed.state, "compensated");
  await assertStored(ids.statements[1], pdfA);

  const divergenceOriginalId = await reserve(owner, ids.statements[5], "create");
  await engine(owner).execute(operation(divergenceOriginalId, pdfA, finalization(5, "fevrier.pdf")));
  const divergenceId = await reserve(owner, ids.statements[5], "replace");
  const divergenceRpc = rpcGateway(owner);
  const divergenceEngine = engine(owner, storageGateway(), divergenceRpc);
  await divergenceEngine.start(divergenceId);
  const externalMutation = await admin.storage.from("bank-statements").upload(
    path(ids.statements[5]), pdfB, { contentType: "application/pdf", upsert: true },
  );
  assert.ifError(externalMutation.error);
  await assert.rejects(
    divergenceEngine.execute(operation(divergenceId, pdfA, finalization(5, "fevrier-corrige.pdf"))),
    (error) => error instanceof DocumentOperationError && error.code === "storage_diverged",
  );
  assert.equal((await divergenceRpc.getProgress(divergenceId)).state, "attention_required");
  await assertStored(ids.statements[5], pdfB);

  const rightsId = await reserve(manager, ids.statements[6], "create");
  const rightsStorage = storageGateway({ afterUpload: async () => {
    const removal = await admin.from("protected_person_access").delete()
      .eq("user_id", ids.manager).eq("protected_person_id", ids.person);
    assert.ifError(removal.error);
  } });
  await assert.rejects(
    engine(manager, rightsStorage).execute(operation(rightsId, pdfA, finalization(6, "mars.pdf"))),
    DocumentOperationError,
  );
  const restoredAccess = await admin.from("protected_person_access").insert({
    id: randomUUID(), protected_person_id: ids.person, user_id: ids.manager,
    role: "manager", invited_by: ids.owner,
  });
  assert.ifError(restoredAccess.error);
  assert.equal((await rpcGateway(manager).getProgress(rightsId)).state, "attention_required");

  const deleteId = await reserve(owner, ids.statements[0], "delete");
  await engine(owner).execute(operation(deleteId, null, finalization(0, null)));
  assert.equal((await admin.storage.from("bank-statements").exists(path(ids.statements[0]))).data, false);
  const afterDelete = await statement(ids.statements[0]);
  assert.ok(afterDelete);
  assert.equal(afterDelete.original_file_name, null);
  assert.equal(afterDelete.mime_type, null);
  assert.equal(afterDelete.file_size, null);

  console.log("PASS: relevés, droits, reprises, conflits, sauvegardes et compensations validés localement.");
}

await main();
