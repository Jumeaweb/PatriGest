import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  ADMIN_DOCUMENT_REPAIR_ENV,
  AdministrativeDocumentRepairEngine,
  AdministrativeDocumentRepairError,
  isAdminDocumentRepairEnabled,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "./administrative-document-repair.ts";

const ids = {
  authorization: "11111111-1111-4111-8111-111111111111",
  operation: "22222222-2222-4222-8222-222222222222",
  admin: "33333333-3333-4333-8333-333333333333",
  attempt: "44444444-4444-4444-8444-444444444444",
  item: "55555555-5555-4555-8555-555555555555",
  target: "66666666-6666-4666-8666-666666666666",
  object: "77777777-7777-4777-8777-777777777777",
  backup: "88888888-8888-4888-8888-888888888888",
  backupObject: "99999999-9999-4999-8999-999999999999",
};

function object(text, id = ids.object, version = "v1") {
  const bytes = new TextEncoder().encode(text);
  return { bytes, byteSize: bytes.length, mimeType: "application/pdf", sha256: createHash("sha256").update(bytes).digest("hex"), objectId: id, objectVersion: version };
}

function harness(action, options = {}) {
  const originalPath = "protected-persons/test/document.pdf";
  const backupPath = "operations/test/targets/test/backup";
  const backupRequired = ["restore_original", "complete_backup_cleanup"].includes(action)
    || (action === "resume_compensation" && options.compensationAction !== "delete")
    || options.withBackup;
  const objects = new Map();
  if (options.original !== null) objects.set(`management-reports:${originalPath}`, options.original ?? object("original"));
  if (backupRequired && !options.missingBackup) objects.set(`document-operation-backups:${backupPath}`, options.backup ?? object("backup", ids.backupObject, "backup-v1"));
  const item = {
    itemId: ids.item, targetId: ids.target, ordinal: 1, action,
    progressState: "authorized", revision: 0, executionId: null,
    bucketId: "management-reports", objectPath: originalPath,
    targetRevision: 0, applicationState: action === "resume_compensation" ? "compensating" : "pending",
    observedObjectExists: null, observedObjectId: null, observedObjectVersion: null,
    observedByteSize: null, observedSha256: null,
    backup: backupRequired ? {
      backupId: ids.backup, state: "verified", revision: 0,
      byteSize: object("backup").byteSize, sha256: object("backup").sha256,
      recoveryObjectPath: backupPath, recoveryObjectId: ids.backupObject,
      recoveryObjectVersion: "backup-v1",
    } : null,
  };
  const state = {
    progress: {
      authorizationId: ids.authorization, operationId: ids.operation,
      administratorSubjectId: ids.admin, attemptId: ids.attempt,
      planHash: "a".repeat(64), state: "active", revision: 0,
      expiresAt: new Date(Date.now() + 60_000).toISOString(), expired: false,
      items: [item],
    },
    mutations: [], observations: [], verifies: 0, starts: 0,
  };
  const storage = {
    async inspect(bucket, path) { return objects.get(`${bucket}:${path}`) ?? null; },
    async upload(bucket, path, bytes, mimeType) {
      state.mutations.push("upload");
      objects.set(`${bucket}:${path}`, { bytes, byteSize: bytes.length, mimeType, sha256: createHash("sha256").update(bytes).digest("hex"), objectId: ids.object, objectVersion: "v2" });
    },
    async remove(bucket, path) { state.mutations.push("remove"); objects.delete(`${bucket}:${path}`); },
  };
  const rpc = {
    async progress() { return structuredClone(state.progress); },
    async start(_context, current, executionId) { state.starts += 1; current = state.progress.items[0]; current.progressState = "executing"; current.executionId = executionId; current.revision += 1; },
    async observe(_context, _current, _executionId, observation) {
      state.observations.push(observation);
      const current = state.progress.items[0];
      current.progressState = "verification_required"; current.revision += 1;
      current.observedObjectExists = observation.object !== null;
      if (observation.object) {
        current.observedObjectId = observation.object.objectId; current.observedObjectVersion = observation.object.objectVersion;
        current.observedByteSize = observation.object.byteSize; current.observedSha256 = observation.object.sha256;
      }
      if (options.loseObservationResponse) throw new Error("network lost");
    },
    async verify() { state.progress.items[0].progressState = "verified"; state.progress.items[0].revision += 1; state.verifies += 1; },
    async markBackupRestored() { state.progress.items[0].backup.state = "restored"; state.progress.items[0].backup.revision += 1; },
    async authorizeBackupCleanup() {
      const backup = state.progress.items[0].backup;
      return { bucketId: "document-operation-backups", objectPath: backupPath, objectId: ids.backupObject, objectVersion: "backup-v1", byteSize: backup.byteSize, mimeType: "application/pdf", sha256: backup.sha256, state: backup.state, revision: backup.revision };
    },
    async completeBackupCleanup() { state.progress.items[0].backup.state = "deleted"; state.progress.items[0].backup.revision += 1; },
  };
  const expected = options.original === null ? { exists: false, objectId: null, objectVersion: null } : { exists: true, objectId: ids.object, objectVersion: "v1" };
  const context = {
    authorizationId: ids.authorization, administratorSubjectId: ids.admin,
    attemptId: ids.attempt, planHash: "a".repeat(64),
    compensationActions: new Map([[ids.target, options.compensationAction ?? null]]),
    expectedObjects: new Map([[ids.target, expected]]),
    storageGuardEnabled: options.storageGuardEnabled ?? false,
  };
  return { engine: new AdministrativeDocumentRepairEngine(rpc, storage), context, state, objects };
}

test("active le moteur uniquement pour la valeur exacte true", () => {
  const previous = process.env[ADMIN_DOCUMENT_REPAIR_ENV];
  process.env[ADMIN_DOCUMENT_REPAIR_ENV] = "TRUE";
  assert.equal(isAdminDocumentRepairEnabled(), false);
  process.env[ADMIN_DOCUMENT_REPAIR_ENV] = "true";
  assert.equal(isAdminDocumentRepairEnabled(), true);
  if (previous === undefined) delete process.env[ADMIN_DOCUMENT_REPAIR_ENV]; else process.env[ADMIN_DOCUMENT_REPAIR_ENV] = previous;
});

test("confirme un état conforme sans mutation Storage", async () => {
  const value = harness("confirm_already_conform");
  const result = await value.engine.execute(value.context);
  assert.equal(result.items[0].progressState, "verified");
  assert.deepEqual(value.state.mutations, []);
  assert.equal(value.state.observations[0].kind, "physical_verified");
});

test("restaure et vérifie les octets exacts de la sauvegarde", async () => {
  const value = harness("restore_original", { original: null });
  await value.engine.execute(value.context);
  assert.deepEqual(value.state.mutations, ["upload"]);
  assert.equal(value.state.progress.items[0].backup.state, "restored");
  assert.equal(value.state.observations[0].object.sha256, object("backup").sha256);
});

test("refuse une restauration lorsque la sauvegarde physique manque", async () => {
  const value = harness("restore_original", { missingBackup: true, original: null });
  await assert.rejects(() => value.engine.execute(value.context), (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "BACKUP_MISSING");
  assert.deepEqual(value.state.mutations, []);
  assert.equal(value.state.observations[0].kind, "backup_missing");
});

test("bloque le nettoyage avant la garde Storage conditionnelle", async () => {
  const value = harness("complete_backup_cleanup");
  await assert.rejects(() => value.engine.execute(value.context), (error) => error.safeCode === "STORAGE_GUARD_REQUIRED");
  assert.deepEqual(value.state.mutations, []);
  assert.equal(value.state.starts, 0);
});

test("refuse de supprimer la dernière copie récupérable", async () => {
  const value = harness("complete_backup_cleanup", { original: null });
  await assert.rejects(() => value.engine.execute(value.context), (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "STORAGE_GUARD_REQUIRED");
  assert.deepEqual(value.state.mutations, []);
});

test("bloque une compensation de suppression avant la garde Storage", async () => {
  const value = harness("resume_compensation", { compensationAction: "delete" });
  await assert.rejects(() => value.engine.execute(value.context), (error) => error.safeCode === "STORAGE_GUARD_REQUIRED");
  assert.deepEqual(value.state.mutations, []);
  assert.equal(value.state.starts, 0);
});

test("refuse avant démarrage une restauration qui écraserait une cible présente", async () => {
  const value = harness("restore_original");
  await assert.rejects(() => value.engine.execute(value.context), (error) => error.safeCode === "STORAGE_GUARD_REQUIRED");
  assert.equal(value.state.starts, 0);
  assert.deepEqual(value.state.mutations, []);
});

test("conserve la garde du moteur même si la garde Storage est annoncée active", async () => {
  const value = harness("complete_backup_cleanup", { storageGuardEnabled: true });
  await assert.rejects(() => value.engine.execute(value.context), (error) => error.safeCode === "STORAGE_GUARD_REQUIRED");
  assert.equal(value.state.starts, 1);
  assert.deepEqual(value.state.mutations, []);
});

test("refuse avant démarrage une compensation de suppression même si une sauvegarde existe", async () => {
  const value = harness("resume_compensation", { compensationAction: "delete", withBackup: true });
  await assert.rejects(
    () => value.engine.execute(value.context),
    (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "STORAGE_GUARD_REQUIRED",
  );
  assert.equal(value.state.starts, 0);
  assert.deepEqual(value.state.mutations, []);
});

test("accepte explicitement un état résiduel sans mutation", async () => {
  const value = harness("accept_residual_state", { withBackup: true });
  await value.engine.execute(value.context);
  assert.deepEqual(value.state.mutations, []);
  assert.equal(value.state.verifies, 1);
});

test("reprend après perte de la réponse d'observation", async () => {
  const value = harness("confirm_already_conform", { loseObservationResponse: true });
  const result = await value.engine.execute(value.context);
  assert.equal(result.items[0].progressState, "verified");
  assert.equal(value.state.observations.length, 1);
});

test("refuse une autorisation expirée sans repli non protégé", async () => {
  const value = harness("confirm_already_conform");
  value.state.progress.expired = true;
  await assert.rejects(() => value.engine.execute(value.context), (error) => error instanceof AdministrativeDocumentRepairError && error.safeCode === "AUTHORIZATION_EXPIRED");
  assert.deepEqual(value.state.mutations, []);
});

test("l’interface exige une décision et une confirmation explicites", () => {
  const panel = readFileSync(new URL("./components/administrative-document-repair-panel.tsx", import.meta.url), "utf8");
  assert.match(panel, /action: ""/);
  assert.match(panel, /Choisir une action/);
  assert.match(panel, /name="confirmation" required/);
  assert.match(panel, /Justification de l’état résiduel/);
  assert.doesNotMatch(panel, /objectPath/);
});

test("le mode OFF masque l’entrée et ne charge pas les anomalies", () => {
  const dashboard = readFileSync(new URL("./components/administration-dashboard.tsx", import.meta.url), "utf8");
  const service = readFileSync(new URL("./services/administrative-document-repair-service.ts", import.meta.url), "utf8");
  assert.match(dashboard, /isAdminDocumentRepairEnabled\(\) && <Link href="\/administration\/reparations-documentaires"/);
  assert.ok(service.indexOf("if (!isAdminDocumentRepairEnabled())") < service.indexOf("const admin = createAdminClient()"));
});
