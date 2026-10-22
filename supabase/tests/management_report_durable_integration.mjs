import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import {
  managementReportFinalizationOperation,
  managementReportGenerationOperation,
  managementReportResumeOperation,
} from "../../src/domains/document-operations/domain-adapters.ts";
import { createDurableDocumentBackupStore } from "../../src/domains/document-operations/durable-backup-store.ts";
import {
  describeDocumentContent,
  DocumentOperationEngine,
  DocumentOperationError,
  DocumentOperationRpcError,
} from "../../src/domains/document-operations/engine.ts";
import { isManagementReportDurableOperationsEnabled } from "../../src/domains/management-reports/management-report-durable-availability.ts";

const url = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!url || !anonKey || !serviceRoleKey || !password) throw new Error("Configuration locale absente.");
const endpoint = new URL(url);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Exécution refusée hors de Supabase local.");
}
assert.equal(isManagementReportDurableOperationsEnabled(), true);

const ids = {
  owner: "9a000000-0000-4000-8000-000000000001",
  manager: "9a000000-0000-4000-8000-000000000002",
  reader: "9a000000-0000-4000-8000-000000000003",
  outsider: "9a000000-0000-4000-8000-000000000004",
  person: "9a000000-0000-4000-8100-000000000001",
  reports: Array.from({ length: 12 }, (_, index) => `9a000000-0000-4000-8600-${String(index + 1).padStart(12, "0")}`),
};
const emails = {
  owner: "report-3g2c-owner@example.test",
  manager: "report-3g2c-manager@example.test",
  reader: "report-3g2c-reader@example.test",
  outsider: "report-3g2c-outsider@example.test",
};
const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
const storagePaths = new Set();
const backupPaths = new Set();
let lastSafeFailure = null;

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const encodePdf = (label) => new TextEncoder().encode(
  `%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n% ${label}\n%%EOF\n`,
);
const draftPdf = (reportId, version = "A") => encodePdf(`PROJET ${reportId} ${version}`);
const finalPdf = (reportId) => encodePdf(`DEFINITIF ${reportId}`);
const draftPath = (reportId) => `protected-persons/${ids.person}/management-reports/${reportId}/management-report-draft.pdf`;
const finalPath = (reportId) => `protected-persons/${ids.person}/management-reports/${reportId}/management-report.pdf`;

function snapshot(reportId, status = "generated") {
  const index = ids.reports.indexOf(reportId);
  const year = 2100 + index;
  return {
    complete: true,
    report: {
      id: reportId,
      protected_person_id: ids.person,
      report_year: year,
      period_start: `${year}-01-01`,
      period_end: `${year}-12-31`,
      status,
    },
    person: { id: ids.person, first_name: "Intégration", last_name: "Comptes de gestion" },
    accounting: { resources_cents: 123456, expenses_cents: 23456, result_cents: 100000 },
    patrimony: { bank_cents: 456789, real_estate_cents: 0, debts_cents: 0 },
  };
}

const finalSnapshot = (reportId) => snapshot(reportId, "finalized");
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
        p_operation_id: operationId,
        p_target_id: targetId,
        p_expected_operation_revision: expectedOperationRevision,
        p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    finalize(operationId, expectedRevision, finalization) {
      return invoke(user, "finalize_management_report_document_operation", {
        p_operation_id: operationId,
        p_expected_revision: expectedRevision,
        p_file_name: finalization.fileName,
        p_mime_type: finalization.mimeType,
        p_file_size: finalization.fileSize,
        p_preview_snapshot: finalization.previewSnapshot,
        p_snapshot_schema_version: finalization.snapshotSchemaVersion,
      });
    },
    async beginCompensation(operationId, expectedRevision, safeCode) {
      await invoke(user, "begin_document_operation_compensation", {
        p_operation_id: operationId,
        p_expected_revision: expectedRevision,
        p_safe_code: safeCode,
      });
      return getProgress(operationId);
    },
    async recordCompensated(operationId, targetId, expectedOperationRevision, expectedTargetRevision) {
      const value = await invoke(user, "record_document_operation_target_compensated", {
        p_operation_id: operationId,
        p_target_id: targetId,
        p_expected_operation_revision: expectedOperationRevision,
        p_expected_target_revision: expectedTargetRevision,
      });
      return { operationRevision: value.revision, targetRevision: value.targetRevision };
    },
    completeCompensation: (operationId, expectedRevision) => invoke(user, "complete_document_operation_compensation", {
      p_operation_id: operationId,
      p_expected_revision: expectedRevision,
    }),
    markAttention: (operationId, expectedRevision, safeCode) => invoke(user, "mark_document_operation_attention_required", {
      p_operation_id: operationId,
      p_expected_revision: expectedRevision,
      p_safe_code: safeCode,
    }),
  };
}

function storageGateway(options = {}) {
  const bucket = admin.storage.from("management-reports");
  let uploadCount = 0;
  let removeCount = 0;
  return {
    get uploadCount() { return uploadCount; },
    get removeCount() { return removeCount; },
    async inspect(target) {
      const exists = await bucket.exists(target.objectPath);
      if (!exists.data && (!exists.error || String(exists.error.statusCode) === "400")) return null;
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
      if (options.afterUpload) await options.afterUpload(target);
      if (options.throwAfterUpload) throw new Error("Réponse réseau locale simulée comme perdue.");
    },
    async remove(target) {
      removeCount += 1;
      const result = await bucket.remove([target.objectPath]);
      if (result.error) {
        lastSafeFailure = { component: "storage", operation: "remove", code: result.error.statusCode ?? "unknown" };
        throw result.error;
      }
      if (options.afterRemove) await options.afterRemove(target);
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

async function reserve(user, reportId, intent, requestId = randomUUID()) {
  const { data, error } = await user.rpc("begin_management_report_document_operation", {
    p_protected_person_id: ids.person,
    p_report_id: reportId,
    p_intent: intent,
    p_client_request_id: requestId,
  });
  if (error) throw error;
  return data;
}

function operation(operationId, reportId, intent, bytes = null) {
  if (intent === "generate") {
    return managementReportGenerationOperation(
      operationId,
      { bytes, mimeType: "application/pdf" },
      {
        fileName: `compte-${reportId}-projet.pdf`,
        mimeType: "application/pdf",
        fileSize: bytes.byteLength,
        previewSnapshot: snapshot(reportId),
        snapshotSchemaVersion: 1,
      },
    );
  }
  if (intent === "finalize") {
    return managementReportFinalizationOperation(
      operationId,
      { bytes, mimeType: "application/pdf" },
      {
        fileName: `compte-${reportId}.pdf`,
        mimeType: "application/pdf",
        fileSize: bytes.byteLength,
        previewSnapshot: finalSnapshot(reportId),
        snapshotSchemaVersion: 1,
      },
    );
  }
  return managementReportResumeOperation(operationId, {
    fileName: null,
    mimeType: null,
    fileSize: null,
    previewSnapshot: null,
    snapshotSchemaVersion: null,
  });
}

async function report(reportId) {
  const result = await admin.from("management_reports").select("*").eq("id", reportId).maybeSingle();
  assert.ifError(result.error);
  return result.data;
}

async function document(reportId, type) {
  const result = await admin.from("management_report_documents").select("*")
    .eq("management_report_id", reportId).eq("document_type", type).maybeSingle();
  assert.ifError(result.error);
  return result.data;
}

async function stored(path, expectedBytes) {
  const [info, download] = await Promise.all([
    admin.storage.from("management-reports").info(path),
    admin.storage.from("management-reports").download(path),
  ]);
  assert.ifError(info.error);
  assert.ifError(download.error);
  const bytes = new Uint8Array(await download.data.arrayBuffer());
  assert.equal(sha256(bytes), sha256(expectedBytes));
  assert.equal(download.data.type, "application/pdf");
  assert.ok(info.data.id && info.data.version);
  return { ...info.data, bytes };
}

async function absent(path) {
  const result = await admin.storage.from("management-reports").exists(path);
  if (result.error && String(result.error.statusCode) !== "400") assert.ifError(result.error);
  assert.equal(result.data, false);
}

async function backup(user, operationId, targetId) {
  const value = await invoke(user, "get_document_operation_backup", {
    p_operation_id: operationId,
    p_target_id: targetId,
  });
  const descriptor = await admin.rpc("get_document_operation_backup_storage_descriptor", {
    p_backup_id: value.backupId,
  });
  assert.ifError(descriptor.error);
  backupPaths.add(descriptor.data.objectPath);
  return value;
}

async function generate(user, reportId, bytes = draftPdf(reportId)) {
  const operationId = await reserve(user, reportId, "generate");
  let result;
  try {
    result = await engine(user).engine.execute(operation(operationId, reportId, "generate", bytes));
  } catch (error) {
    const operationState = await admin.from("document_operations")
      .select("state,safe_error_code,row_revision").eq("id", operationId).maybeSingle();
    console.error("Échec sûr de la génération locale", {
      stage: error instanceof DocumentOperationError ? error.stage : "unknown",
      code: error instanceof DocumentOperationError ? error.code : "unknown",
      lastSafeFailure,
      operation: operationState.data,
    });
    throw error;
  }
  assert.equal(result.state, "completed");
  return operationId;
}

async function markReady(user, reportId) {
  const result = await user.from("management_reports").update({ status: "ready" }).eq("id", reportId);
  assert.ifError(result.error);
}

async function main() {
  const [owner, manager, reader, outsider] = await Promise.all(Object.values(emails).map(authenticate));
  const bucket = admin.storage.from("management-reports");

  await assert.rejects(reserve(reader, ids.reports[0], "generate"));
  await assert.rejects(reserve(outsider, ids.reports[0], "generate"));

  const primary = ids.reports[0];
  const primaryDraft = draftPdf(primary);
  assert.ok(new TextDecoder().decode(primaryDraft).includes("PROJET"));
  await generate(owner, primary, primaryDraft);
  assert.equal((await report(primary)).status, "generated");
  const firstDraftDocument = await document(primary, "management_report_draft");
  assert.deepEqual(firstDraftDocument.preview_snapshot, snapshot(primary));
  assert.equal(firstDraftDocument.snapshot_schema_version, 1);
  await stored(draftPath(primary), primaryDraft);
  assert.ifError((await manager.storage.from("management-reports").download(draftPath(primary))).error);
  assert.ifError((await reader.storage.from("management-reports").download(draftPath(primary))).error);
  assert.ok((await outsider.storage.from("management-reports").download(draftPath(primary))).error);

  const resumeId = await reserve(manager, primary, "resume");
  const resumeEngine = engine(manager);
  await resumeEngine.engine.start(resumeId);
  const resumeProgress = await resumeEngine.rpc.getProgress(resumeId);
  const resumeBackup = await backup(manager, resumeId, resumeProgress.targets[0].id);
  assert.equal(resumeBackup.state, "verified");
  assert.equal(resumeBackup.sha256, sha256(primaryDraft));
  assert.equal((await resumeEngine.engine.execute(operation(resumeId, primary, "resume"))).state, "completed");
  assert.equal((await report(primary)).status, "draft");
  assert.equal(await document(primary, "management_report_draft"), null);
  await absent(draftPath(primary));
  assert.equal((await backup(manager, resumeId, resumeProgress.targets[0].id)).state, "deleted");

  await markReady(owner, primary);
  const regeneratedDraft = draftPdf(primary, "B");
  await generate(manager, primary, regeneratedDraft);
  const capturedProjectSnapshot = (await document(primary, "management_report_draft")).preview_snapshot;
  const primaryFinal = finalPdf(primary);
  assert.ok(!new TextDecoder().decode(primaryFinal).includes("PROJET"));
  const finalizeId = await reserve(owner, primary, "finalize");
  const finalizeEngine = engine(owner);
  await finalizeEngine.engine.start(finalizeId);
  const finalizeProgress = await finalizeEngine.rpc.getProgress(finalizeId);
  const sourceTarget = finalizeProgress.targets.find((target) => target.role === "source");
  const finalizeBackup = await backup(owner, finalizeId, sourceTarget.id);
  assert.equal(finalizeBackup.state, "verified");
  assert.equal(finalizeBackup.sha256, sha256(regeneratedDraft));
  assert.equal((await finalizeEngine.engine.execute(operation(finalizeId, primary, "finalize", primaryFinal))).state, "completed");
  assert.equal((await report(primary)).status, "finalized");
  assert.equal(await document(primary, "management_report_draft"), null);
  const finalDocument = await document(primary, "management_report");
  assert.deepEqual(finalDocument.preview_snapshot, {
    ...capturedProjectSnapshot,
    report: { ...capturedProjectSnapshot.report, status: "finalized" },
  });
  await absent(draftPath(primary));
  await stored(finalPath(primary), primaryFinal);
  assert.equal((await backup(owner, finalizeId, sourceTarget.id)).state, "deleted");
  assert.ifError((await owner.storage.from("management-reports").download(finalPath(primary))).error);
  assert.ifError((await manager.storage.from("management-reports").download(finalPath(primary))).error);
  assert.ifError((await reader.storage.from("management-reports").download(finalPath(primary))).error);
  assert.ok((await outsider.storage.from("management-reports").download(finalPath(primary))).error);

  const lostResponseReport = ids.reports[1];
  const idempotencyKey = randomUUID();
  const [firstReservation, repeatedReservation] = await Promise.all([
    reserve(owner, lostResponseReport, "generate", idempotencyKey),
    reserve(owner, lostResponseReport, "generate", idempotencyKey),
  ]);
  assert.equal(firstReservation, repeatedReservation);
  const lostResponseStorage = storageGateway({ throwAfterUpload: true });
  assert.equal((await engine(owner, lostResponseStorage).engine.execute(
    operation(firstReservation, lostResponseReport, "generate", draftPdf(lostResponseReport)),
  )).state, "completed");
  assert.equal(lostResponseStorage.uploadCount, 1);
  assert.equal((await engine(owner).engine.execute(
    operation(firstReservation, lostResponseReport, "generate", draftPdf(lostResponseReport)),
  )).state, "completed");

  const generationFailureReport = ids.reports[2];
  const generationFailureId = await reserve(owner, generationFailureReport, "generate");
  const generationFailureRpc = rpcGateway(owner);
  const failingGenerationRpc = {
    ...generationFailureRpc,
    async finalize() { throw new DocumentOperationRpcError("rpc_rejected"); },
  };
  await assert.rejects(
    engine(owner, storageGateway(), failingGenerationRpc).engine.execute(
      operation(generationFailureId, generationFailureReport, "generate", draftPdf(generationFailureReport)),
    ),
    DocumentOperationError,
  );
  assert.equal((await generationFailureRpc.getProgress(generationFailureId)).state, "compensated");
  assert.equal((await report(generationFailureReport)).status, "ready");
  assert.equal(await document(generationFailureReport, "management_report_draft"), null);
  await absent(draftPath(generationFailureReport));

  const insertInterruptionReport = ids.reports[3];
  const insertDraft = draftPdf(insertInterruptionReport);
  await generate(owner, insertInterruptionReport, insertDraft);
  const insertFinal = finalPdf(insertInterruptionReport);
  const insertInterruptionId = await reserve(owner, insertInterruptionReport, "finalize");
  const insertInterrupted = engine(owner);
  await insertInterrupted.engine.start(insertInterruptionId);
  let insertProgress = await insertInterrupted.rpc.getProgress(insertInterruptionId);
  const destination = insertProgress.targets.find((target) => target.role === "destination");
  await insertInterrupted.storage.upload(destination, { bytes: insertFinal, mimeType: "application/pdf" }, false);
  const inserted = await insertInterrupted.rpc.recordApplied(
    insertInterruptionId, destination.id, insertProgress.revision, destination.revision,
  );
  assert.ok(inserted.operationRevision > insertProgress.revision);
  assert.equal((await engine(owner).engine.execute(
    operation(insertInterruptionId, insertInterruptionReport, "finalize", insertFinal),
  )).state, "completed");
  await stored(finalPath(insertInterruptionReport), insertFinal);
  await absent(draftPath(insertInterruptionReport));

  const deleteInterruptionReport = ids.reports[4];
  const deleteDraft = draftPdf(deleteInterruptionReport);
  await generate(owner, deleteInterruptionReport, deleteDraft);
  const deleteFinal = finalPdf(deleteInterruptionReport);
  const deleteInterruptionId = await reserve(owner, deleteInterruptionReport, "finalize");
  const deleteInterrupted = engine(owner);
  await deleteInterrupted.engine.start(deleteInterruptionId);
  let deleteProgress = await deleteInterrupted.rpc.getProgress(deleteInterruptionId);
  for (const target of deleteProgress.targets) {
    if (target.role === "destination") {
      await deleteInterrupted.storage.upload(target, { bytes: deleteFinal, mimeType: "application/pdf" }, false);
    } else {
      await deleteInterrupted.storage.remove(target);
    }
    const recorded = await deleteInterrupted.rpc.recordApplied(
      deleteInterruptionId, target.id, deleteProgress.revision, target.revision,
    );
    deleteProgress = await deleteInterrupted.rpc.getProgress(deleteInterruptionId);
    assert.equal(deleteProgress.revision, recorded.operationRevision);
  }
  assert.equal((await engine(owner).engine.execute(
    operation(deleteInterruptionId, deleteInterruptionReport, "finalize", deleteFinal),
  )).state, "completed");
  await stored(finalPath(deleteInterruptionReport), deleteFinal);
  await absent(draftPath(deleteInterruptionReport));

  const finalizationFailureReport = ids.reports[5];
  const failureDraft = draftPdf(finalizationFailureReport);
  await generate(owner, finalizationFailureReport, failureDraft);
  const finalizationFailureId = await reserve(owner, finalizationFailureReport, "finalize");
  const finalizationFailureRpc = rpcGateway(owner);
  const failingFinalizationRpc = {
    ...finalizationFailureRpc,
    async finalize() { throw new DocumentOperationRpcError("rpc_rejected"); },
  };
  await assert.rejects(
    engine(owner, storageGateway(), failingFinalizationRpc).engine.execute(
      operation(finalizationFailureId, finalizationFailureReport, "finalize", finalPdf(finalizationFailureReport)),
    ),
    DocumentOperationError,
  );
  assert.equal((await finalizationFailureRpc.getProgress(finalizationFailureId)).state, "compensated");
  assert.equal((await report(finalizationFailureReport)).status, "generated");
  await stored(draftPath(finalizationFailureReport), failureDraft);
  await absent(finalPath(finalizationFailureReport));
  assert.ok(await document(finalizationFailureReport, "management_report_draft"));
  assert.equal(await document(finalizationFailureReport, "management_report"), null);

  const concurrentReport = ids.reports[6];
  await generate(owner, concurrentReport);
  const concurrentReservations = await Promise.allSettled([
    reserve(owner, concurrentReport, "finalize"),
    reserve(owner, concurrentReport, "resume"),
  ]);
  assert.equal(concurrentReservations.filter(({ status }) => status === "fulfilled").length, 1);
  assert.equal(concurrentReservations.filter(({ status }) => status === "rejected").length, 1);
  const winnerIndex = concurrentReservations.findIndex(({ status }) => status === "fulfilled");
  const winnerId = concurrentReservations[winnerIndex].value;
  const winnerIntent = winnerIndex === 0 ? "finalize" : "resume";
  const winnerBytes = winnerIntent === "finalize" ? finalPdf(concurrentReport) : null;
  assert.equal((await engine(owner).engine.execute(
    operation(winnerId, concurrentReport, winnerIntent, winnerBytes),
  )).state, "completed");

  const rightsReport = ids.reports[7];
  const rightsId = await reserve(manager, rightsReport, "generate");
  const rightsStorage = storageGateway({
    afterUpload: async () => {
      const removal = await admin.from("protected_person_access").delete()
        .eq("user_id", ids.manager).eq("protected_person_id", ids.person);
      assert.ifError(removal.error);
    },
  });
  await assert.rejects(
    engine(manager, rightsStorage).engine.execute(
      operation(rightsId, rightsReport, "generate", draftPdf(rightsReport)),
    ),
    DocumentOperationError,
  );
  const restoredAccess = await admin.from("protected_person_access").insert({
    id: randomUUID(),
    protected_person_id: ids.person,
    user_id: ids.manager,
    role: "manager",
    invited_by: ids.owner,
  });
  assert.ifError(restoredAccess.error);
  assert.equal((await rpcGateway(manager).getProgress(rightsId)).state, "attention_required");

  const divergenceReport = ids.reports[8];
  const divergenceDraft = draftPdf(divergenceReport);
  await generate(owner, divergenceReport, divergenceDraft);
  const divergenceId = await reserve(owner, divergenceReport, "resume");
  const divergenceEngine = engine(owner);
  await divergenceEngine.engine.start(divergenceId);
  const divergenceProgress = await divergenceEngine.rpc.getProgress(divergenceId);
  const retainedBackup = await backup(owner, divergenceId, divergenceProgress.targets[0].id);
  assert.equal(retainedBackup.state, "verified");
  const externalBytes = draftPdf(divergenceReport, "EXTERNE");
  assert.ifError((await bucket.upload(draftPath(divergenceReport), externalBytes, {
    contentType: "application/pdf",
    upsert: true,
  })).error);
  await assert.rejects(
    divergenceEngine.engine.execute(operation(divergenceId, divergenceReport, "resume")),
    (error) => error instanceof DocumentOperationError && error.code === "storage_diverged",
  );
  assert.equal((await divergenceEngine.rpc.getProgress(divergenceId)).state, "attention_required");
  assert.equal((await backup(owner, divergenceId, divergenceProgress.targets[0].id)).state, "verified");
  await stored(draftPath(divergenceReport), externalBytes);

  const versionReport = ids.reports[9];
  const versionDraft = draftPdf(versionReport);
  await generate(owner, versionReport, versionDraft);
  const versionId = await reserve(owner, versionReport, "resume");
  const versionEngine = engine(owner);
  await versionEngine.engine.start(versionId);
  const versionProgress = await versionEngine.rpc.getProgress(versionId);
  const beforeVersion = await stored(draftPath(versionReport), versionDraft);
  assert.ifError((await bucket.upload(draftPath(versionReport), versionDraft, {
    contentType: "application/pdf",
    upsert: true,
  })).error);
  const afterVersion = await stored(draftPath(versionReport), versionDraft);
  assert.notEqual(afterVersion.version, beforeVersion.version);
  await assert.rejects(
    versionEngine.engine.execute(operation(versionId, versionReport, "resume")),
    (error) => error instanceof DocumentOperationError && error.code === "storage_diverged",
  );
  assert.equal((await versionEngine.rpc.getProgress(versionId)).state, "attention_required");
  assert.equal((await backup(owner, versionId, versionProgress.targets[0].id)).state, "verified");

  const revisionReport = ids.reports[10];
  const revisionId = await reserve(owner, revisionReport, "generate");
  const revisionRpc = rpcGateway(owner);
  const revisionProgress = await revisionRpc.getProgress(revisionId);
  await revisionRpc.start(revisionId, revisionProgress.revision);
  await assert.rejects(
    revisionRpc.start(revisionId, revisionProgress.revision),
    (error) => error instanceof DocumentOperationRpcError && error.reason === "revision_conflict",
  );
  assert.equal((await engine(owner).engine.execute(
    operation(revisionId, revisionReport, "generate", draftPdf(revisionReport)),
  )).state, "completed");

  const archiveReport = ids.reports[11];
  const archiveOperationId = await reserve(owner, archiveReport, "generate");
  const archiveAttempt = await owner.rpc("archive_protected_person", {
    p_protected_person_id: ids.person,
    p_expected_revision: 1,
    p_reason: "Concurrence documentaire locale",
  });
  assert.ok(archiveAttempt.error);
  assert.equal((await report(archiveReport)).status, "ready");
  assert.equal((await admin.from("protected_persons").select("status").eq("id", ids.person).single()).data.status, "active");
  assert.equal((await engine(owner).engine.execute(
    operation(archiveOperationId, archiveReport, "generate", draftPdf(archiveReport)),
  )).state, "completed");

  const nonCompleted = await rpcGateway(owner).getProgress(divergenceId);
  assert.notEqual(nonCompleted.state, "completed");
  assert.equal(nonCompleted.state, "attention_required");
  assert.equal(lastSafeFailure?.component, "rpc");

  console.log("PASS: comptes de gestion, Auth, RPC, Storage, reprises, sauvegardes et compensations validés localement.");
}

try {
  await main();
} finally {
  for (const reportId of ids.reports) {
    storagePaths.add(draftPath(reportId));
    storagePaths.add(finalPath(reportId));
  }
  if (storagePaths.size) await admin.storage.from("management-reports").remove([...storagePaths]);
  if (backupPaths.size) await admin.storage.from("document-operation-backups").remove([...backupPaths]);
}
