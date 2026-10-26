import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import {
  AdministrativeDocumentRepairEngine,
  AdministrativeDocumentRepairError,
// @ts-expect-error Node's strip-types runner loads the source directly.
} from "../../src/domains/administration/administrative-document-repair.ts";

const apiUrl = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!apiUrl || !anonKey || !serviceKey || !password) throw new Error("Configuration locale incomplète.");
const endpoint = new URL(apiUrl);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Refus d’utiliser une API Supabase non locale.");
}

const adminId = "9b500000-0000-4000-8000-000000000001";
const personId = "9b500000-0000-4000-8100-000000000001";
const cases = {
  restore: {
    operationId: "9b500000-0000-4000-8200-000000000001",
    targetId: "9b500000-0000-4000-8500-000000000001",
    attemptId: "9b500000-0000-4000-8600-000000000001",
    transactionId: "9b500000-0000-4000-8300-000000000001",
  },
  missing: {
    operationId: "9b500000-0000-4000-8200-000000000002",
    targetId: "9b500000-0000-4000-8500-000000000002",
    attemptId: "9b500000-0000-4000-8600-000000000002",
    transactionId: "9b500000-0000-4000-8300-000000000002",
  },
  divergent: {
    operationId: "9b500000-0000-4000-8200-000000000003",
    targetId: "9b500000-0000-4000-8500-000000000003",
    attemptId: "9b500000-0000-4000-8600-000000000003",
    transactionId: "9b500000-0000-4000-8300-000000000003",
  },
};

const service = createClient(apiUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const user = createClient(apiUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
const bytes = (value) => new TextEncoder().encode(value);
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const originalPath = (entry) => `protected-persons/${personId}/transactions/${entry.transactionId}/proof`;
const backupPath = (entry) => `operations/${entry.operationId}/targets/${entry.targetId}/backup`;
const unrelatedPath = `protected-persons/${personId}/transactions/9b500000-0000-4000-8300-000000000099/proof`;

async function upload(bucket, path, content, upsert = false) {
  const result = await service.storage.from(bucket).upload(path, bytes(content), { contentType: "application/pdf", upsert });
  if (result.error) throw result.error;
  const info = await service.storage.from(bucket).info(path);
  if (info.error || !info.data?.id || !info.data.version) throw info.error ?? new Error("Métadonnées Storage absentes.");
  return { id: info.data.id, version: info.data.version, byteSize: bytes(content).byteLength, sha256: sha256(bytes(content)) };
}

async function inspect(bucket, path) {
  const store = service.storage.from(bucket);
  const exists = await store.exists(path);
  if (!exists.data) return null;
  const [info, download] = await Promise.all([store.info(path), store.download(path)]);
  if (info.error || !info.data?.id || !info.data.version || download.error || !download.data) throw new Error("Lecture Storage réelle impossible.");
  const content = new Uint8Array(await download.data.arrayBuffer());
  return {
    bytes: content,
    byteSize: content.byteLength,
    mimeType: download.data.type || "application/octet-stream",
    sha256: sha256(content),
    objectId: info.data.id,
    objectVersion: info.data.version,
  };
}

async function rpc(client, name, args) {
  const result = await client.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

function rpcGateway({ loseFirstObservation = false } = {}) {
  let shouldLose = loseFirstObservation;
  return {
    progress: (context) => rpc(service, "get_administrative_document_repair_progress_for_service", {
      p_authorization_id: context.authorizationId, p_administrator_subject_id: context.administratorSubjectId,
      p_attempt_id: context.attemptId, p_expected_plan_hash: context.planHash,
    }),
    start: (context, item, executionId, authorizationRevision) => rpc(service, "start_administrative_document_repair_item", {
      p_authorization_id: context.authorizationId, p_item_id: item.itemId,
      p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
      p_expected_plan_hash: context.planHash, p_expected_action: item.action,
      p_execution_id: executionId, p_expected_authorization_revision: authorizationRevision,
      p_expected_item_revision: item.revision,
    }),
    async observe(context, item, executionId, observation) {
      if (shouldLose) { shouldLose = false; throw new Error("Perte de réponse simulée après mutation."); }
      return rpc(service, "record_administrative_document_repair_observation", {
        p_authorization_id: context.authorizationId, p_item_id: item.itemId,
        p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
        p_expected_plan_hash: context.planHash, p_expected_action: item.action,
        p_execution_id: executionId, p_expected_item_revision: item.revision,
        p_observation_kind: observation.kind, p_object_exists: observation.object !== null,
        p_object_id: observation.object?.objectId ?? null, p_object_version: observation.object?.objectVersion ?? null,
        p_byte_size: observation.physicalBytesVerified ? observation.object?.byteSize ?? null : null,
        p_sha256: observation.physicalBytesVerified ? observation.object?.sha256 ?? null : null,
        p_backup_present: observation.backupPresent, p_backup_id: observation.backup?.backupId ?? null,
        p_backup_revision: observation.backup?.revision ?? null, p_backup_state: observation.backup?.state ?? null,
      });
    },
    verify: (context, item, executionId, result) => rpc(service, "verify_administrative_document_repair_item", {
      p_authorization_id: context.authorizationId, p_item_id: item.itemId,
      p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
      p_expected_plan_hash: context.planHash, p_expected_action: item.action,
      p_execution_id: executionId, p_expected_item_revision: item.revision,
      p_result_kind: result.resultKind, p_backup_disposition: result.backupDisposition,
    }),
    markBackupRestored: (context, item, executionId) => rpc(service, "mark_administrative_document_repair_backup_restored", {
      p_authorization_id: context.authorizationId, p_item_id: item.itemId,
      p_administrator_subject_id: context.administratorSubjectId, p_attempt_id: context.attemptId,
      p_expected_plan_hash: context.planHash, p_execution_id: executionId,
      p_expected_item_revision: item.revision, p_expected_backup_revision: item.backup?.revision,
    }),
    authorizeBackupCleanup: () => { throw new Error("Nettoyage inattendu."); },
    completeBackupCleanup: () => { throw new Error("Nettoyage inattendu."); },
  };
}

const storageGateway = {
  inspect,
  async upload(bucket, path, content, mimeType, upsert) {
    const result = await service.storage.from(bucket).upload(path, content, { contentType: mimeType, upsert });
    if (result.error) throw result.error;
  },
  async remove(bucket, path) {
    const result = await service.storage.from(bucket).remove([path]);
    if (result.error) throw result.error;
  },
};

async function authorize(entry, reason) {
  const diagnostic = await rpc(user, "get_administrative_document_repair_diagnostic", { p_operation_id: entry.operationId });
  const target = diagnostic.targets[0];
  const response = await rpc(user, "issue_administrative_document_repair_authorization", {
    p_operation_id: entry.operationId,
    p_expected_operation_revision: diagnostic.revision,
    p_attempt_id: entry.attemptId,
    p_reason: reason,
    p_repair_plan: [{
      targetId: target.targetId, action: "restore_original",
      expectedTargetRevision: target.targetRevision, expectedApplicationState: target.applicationState,
      expectedObjectExists: target.catalogObservation.exists,
      expectedObjectId: target.catalogObservation.objectId,
      expectedObjectVersion: target.catalogObservation.objectVersion,
      backupId: target.backup.backupId, expectedBackupRevision: target.backup.revision,
      expectedBackupState: target.backup.state,
    }],
  });
  return {
    response,
    context: {
      authorizationId: response.authorizationId, administratorSubjectId: adminId,
      attemptId: entry.attemptId, planHash: response.planHash,
      compensationActions: new Map([[entry.targetId, target.compensationAction]]),
      expectedObjects: new Map([[entry.targetId, {
        exists: target.catalogObservation.exists, objectId: target.catalogObservation.objectId,
        objectVersion: target.catalogObservation.objectVersion,
      }]]),
    },
  };
}

if (process.argv[2] === "seed") {
  const seeded = {};
  for (const [name, entry] of Object.entries(cases)) {
    seeded[name] = {
      original: await upload("transaction-proofs", originalPath(entry), `original-${name}`),
      backup: name === "missing" ? null : await upload("document-operation-backups", backupPath(entry), `restored-${name}`),
    };
  }
  seeded.unrelated = await upload("transaction-proofs", unrelatedPath, "unrelated-document");
  process.stdout.write(JSON.stringify(seeded));
} else if (process.argv[2] === "execute") {
  const login = await user.auth.signInWithPassword({ email: "repair-physical-admin@example.test", password });
  if (login.error || login.data.user?.id !== adminId) throw login.error ?? new Error("Authentification locale incorrecte.");

  const unrelatedBefore = await inspect("transaction-proofs", unrelatedPath);
  const removedFixture = await service.storage.from("transaction-proofs").remove([originalPath(cases.restore)]);
  if (removedFixture.error) throw removedFixture.error;
  const restore = await authorize(cases.restore, "Restauration réelle locale après interruption simulée");
  const interrupted = new AdministrativeDocumentRepairEngine(rpcGateway({ loseFirstObservation: true }), storageGateway);
  await assert.rejects(() => interrupted.execute(restore.context), AdministrativeDocumentRepairError);
  const resumed = new AdministrativeDocumentRepairEngine(rpcGateway(), storageGateway);
  let progress = await resumed.execute(restore.context);
  assert.equal(progress.items[0].progressState, "verified");
  progress = await resumed.execute(restore.context);
  assert.equal(progress.items[0].progressState, "verified");
  const restored = await inspect("transaction-proofs", originalPath(cases.restore));
  assert.equal(restored.sha256, sha256(bytes("restored-restore")));
  const independentDownload = await service.storage.from("transaction-proofs").download(originalPath(cases.restore));
  assert.equal(independentDownload.error, null);
  assert.equal(sha256(new Uint8Array(await independentDownload.data.arrayBuffer())), restored.sha256);
  const sealed = await rpc(user, "seal_administrative_document_repair", {
    p_authorization_id: restore.response.authorizationId,
    p_expected_revision: progress.revision,
    p_expected_plan_hash: restore.response.planHash,
  });
  assert.equal(sealed.state, "sealed");

  const missing = await authorize(cases.missing, "Constat local d’une sauvegarde physiquement absente");
  await assert.rejects(
    () => new AdministrativeDocumentRepairEngine(rpcGateway(), storageGateway).execute(missing.context),
    (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "BACKUP_MISSING",
  );

  const divergent = await authorize(cases.divergent, "Constat local d’une sauvegarde physiquement divergente");
  await upload("document-operation-backups", backupPath(cases.divergent), "divergent-bytes", true);
  await assert.rejects(
    () => new AdministrativeDocumentRepairEngine(rpcGateway(), storageGateway).execute(divergent.context),
    (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "BACKUP_DIVERGED",
  );

  const unrelatedAfter = await inspect("transaction-proofs", unrelatedPath);
  assert.equal(unrelatedAfter.sha256, unrelatedBefore.sha256);
  process.stdout.write("Réparation administrative réelle locale validée.\n");
} else {
  throw new Error("Mode attendu: seed ou execute.");
}
