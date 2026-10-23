import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import {
  AccountDeletionAdminError,
  AccountDeletionAuthOutcomeUnknownError,
  AccountDeletionBlockedError,
  AccountDeletionReauthenticationError,
  deleteAccountWithVerifiedDependencies,
  listOwnedStorageObjects,
} from "../../src/domains/account/account-deletion-operations.ts";
import {
  AccountDeletionDurableStorageError,
  beginAccountStorageNeutralization,
  cancelAccountDeletionAuthorization,
  inspectAccountOwnedStorageObject,
  issueAccountDeletionAuthorization,
  listAccountStorageNeutralizations,
  resumeAccountStorageNeutralization,
} from "../../src/domains/account/account-deletion-durable.ts";
import { isAccountDeletionDurableNeutralizationEnabled } from "../../src/domains/account/account-deletion-durable-availability.ts";

const url = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!url || !anonKey || !serviceRoleKey || !password) throw new Error("Configuration locale absente.");
const endpoint = new URL(url);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Exécution refusée hors de Supabase local.");
}
assert.equal(isAccountDeletionDurableNeutralizationEnabled(), true);

const ids = {
  owner: "9b000000-0000-4000-8000-000000000001",
  manager: "9b000000-0000-4000-8000-000000000002",
  reader: "9b000000-0000-4000-8000-000000000003",
  platform: "9b000000-0000-4000-8000-000000000004",
  interrupt: "9b000000-0000-4000-8000-000000000005",
  freeze: "9b000000-0000-4000-8000-000000000006",
  state: "9b000000-0000-4000-8000-000000000007",
  refused: "9b000000-0000-4000-8000-000000000008",
  ambiguous: "9b000000-0000-4000-8000-000000000009",
  absent: "9b000000-0000-4000-8000-000000000010",
  signout: "9b000000-0000-4000-8000-000000000011",
  divergence: "9b000000-0000-4000-8000-000000000012",
  sha: "9b000000-0000-4000-8000-000000000013",
  backup: "9b000000-0000-4000-8000-000000000014",
  lost: "9b000000-0000-4000-8000-000000000015",
  concurrent: "9b000000-0000-4000-8000-000000000016",
  person: "9b000000-0000-4000-8100-000000000001",
  account: "9b000000-0000-4000-8200-000000000001",
  transactions: Array.from({ length: 24 }, (_, index) => `9b000000-0000-4000-8300-${String(index + 1).padStart(12, "0")}`),
  statements: Array.from({ length: 2 }, (_, index) => `9b000000-0000-4000-8400-${String(index + 1).padStart(12, "0")}`),
  reports: Array.from({ length: 2 }, (_, index) => `9b000000-0000-4000-8500-${String(index + 1).padStart(12, "0")}`),
  expiredAttempt: "9b000000-0000-4000-9100-000000000001",
  expiredOperation: "9b000000-0000-4000-9300-000000000001",
};
const emails = Object.fromEntries(Object.entries(ids)
  .filter(([key]) => !["person", "account", "transactions", "statements", "reports", "expiredAttempt", "expiredOperation"].includes(key))
  .map(([key]) => [key, `deletion-${key}@example.test`]));

const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
const client = () => createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const pdf = (label) => new TextEncoder().encode(`%PDF-1.4\n1 0 obj\n<<>>\nendobj\n% ${label}\n%%EOF\n`);
const transactionPath = (index) => `protected-persons/${ids.person}/transactions/${ids.transactions[index]}/proof`;
const statementPath = (index) => `protected-persons/${ids.person}/accounts/${ids.account}/statements/${ids.statements[index]}/statement`;
const reportPath = (index) => `protected-persons/${ids.person}/management-reports/${ids.reports[index]}/management-report-draft.pdf`;

async function authenticate(key) {
  const value = client();
  const { data, error } = await value.auth.signInWithPassword({ email: emails[key], password });
  assert.ifError(error);
  assert.equal(data.user?.id, ids[key]);
  return value;
}

async function waitForLocalDataApiClock(session) {
  let consecutiveSuccesses = 0;
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const result = await session.from("profiles").select("id").limit(1);
    if (!result.error) {
      consecutiveSuccesses += 1;
      if (consecutiveSuccesses === 2) return;
      continue;
    }
    consecutiveSuccesses = 0;
    if (result.error.code !== "PGRST303") throw result.error;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("L’horloge de la Data API locale n’a pas accepté les JWT de test.");
}

async function upload(user, bucketId, path, bytes) {
  const result = await user.storage.from(bucketId).upload(path, bytes, {
    contentType: "application/pdf",
    cacheControl: "3600",
    metadata: { integration: "account-deletion" },
    upsert: false,
  });
  assert.ifError(result.error);
  return inspect(bucketId, path);
}

async function inspect(bucketId, path) {
  const bucket = admin.storage.from(bucketId);
  const [info, download] = await Promise.all([bucket.info(path), bucket.download(path)]);
  assert.ifError(info.error);
  assert.ifError(download.error);
  const bytes = new Uint8Array(await download.data.arrayBuffer());
  return {
    id: info.data.id,
    version: info.data.version,
    bytes,
    sha256: sha256(bytes),
  };
}

async function exists(bucketId, path) {
  const result = await admin.storage.from(bucketId).exists(path);
  if (result.error && String(result.error.statusCode) !== "400") throw result.error;
  return Boolean(result.data);
}

async function progress(operationId) {
  const result = await admin.rpc("get_account_storage_neutralization_progress", {
    p_operation_id: operationId,
  });
  assert.ifError(result.error);
  return result.data;
}

async function prepare(user, userId, bucketId, path, attemptId = randomUUID(), observedOverride = {}) {
  const owned = (await listOwnedStorageObjects(user)).find((item) => item.bucket_id === bucketId && item.name === path);
  assert.ok(owned, `Objet possédé introuvable : ${bucketId}/${path}`);
  const observed = { ...(await inspectAccountOwnedStorageObject(admin, owned)), ...observedOverride };
  const authorization = await issueAccountDeletionAuthorization(admin, userId, attemptId);
  const operationId = await beginAccountStorageNeutralization(user, authorization.authorizationId, attemptId, owned, observed);
  return { attemptId, authorization, object: owned, observed, operationId };
}

function rpcFault(name, timing = "after") {
  let injected = false;
  return {
    storage: admin.storage,
    async rpc(rpcName, args) {
      if (!injected && rpcName === name && timing === "before") {
        injected = true;
        throw new Error(`Interruption avant ${name}`);
      }
      const result = await admin.rpc(rpcName, args);
      if (!injected && rpcName === name && timing === "after" && !result.error) {
        injected = true;
        throw new Error(`Interruption après ${name}`);
      }
      return result;
    },
  };
}

function storageUploadFault({ bucketId, path = null }) {
  let injected = false;
  return {
    rpc: admin.rpc.bind(admin),
    storage: {
      from(selectedBucket) {
        const bucket = admin.storage.from(selectedBucket);
        return {
          download: bucket.download.bind(bucket),
          info: bucket.info.bind(bucket),
          exists: bucket.exists.bind(bucket),
          remove: bucket.remove.bind(bucket),
          async upload(objectPath, bytes, options) {
            const result = await bucket.upload(objectPath, bytes, options);
            if (!injected && selectedBucket === bucketId && (!path || objectPath === path) && !result.error) {
              injected = true;
              throw new Error("Réponse Storage locale simulée comme perdue.");
            }
            return result;
          },
        };
      },
    },
  };
}

async function finishAndCheck(operation, bucketId, path, expectedBytes, previousId) {
  const terminal = await resumeAccountStorageNeutralization(admin, operation.operationId);
  assert.equal(terminal.phase, "finalized");
  const recreated = await inspect(bucketId, path);
  assert.notEqual(recreated.id, previousId);
  assert.equal(recreated.sha256, sha256(expectedBytes));
  const remaining = await listOwnedStorageObjects(operation.user);
  assert.equal(remaining.some((item) => item.bucket_id === bucketId && item.name === path), false);
  await cancelAccountDeletionAuthorization(admin, operation.authorization.authorizationId);
}

function accountInput(attemptId = randomUUID(), currentPassword = password) {
  return { currentPassword, confirmation: "on", attemptId };
}

function adminAuthWrapper({ deleteUser, getUserById, afterBarrier }) {
  return {
    storage: admin.storage,
    rpc: async (name, args) => {
      const result = await admin.rpc(name, args);
      if (name === "assert_account_deletion_document_barrier" && !result.error && afterBarrier) {
        await afterBarrier(result.data);
      }
      return result;
    },
    auth: {
      admin: {
        deleteUser: deleteUser ?? admin.auth.admin.deleteUser.bind(admin.auth.admin),
        getUserById: getUserById ?? admin.auth.admin.getUserById.bind(admin.auth.admin),
      },
    },
  };
}

function sessionSignOutFailure(session) {
  return {
    from: session.from.bind(session),
    rpc: session.rpc.bind(session),
    storage: session.storage,
    auth: {
      getUser: session.auth.getUser.bind(session.auth),
      signInWithPassword: session.auth.signInWithPassword.bind(session.auth),
      async signOut() { return { error: { message: "local signout failure" } }; },
    },
  };
}

async function assertAuthMissing(userId) {
  const result = await admin.auth.admin.getUserById(userId);
  assert.ok(result.error || !result.data.user);
}

async function main() {
  const keys = Object.keys(emails);
  const sessions = Object.fromEntries(await Promise.all(keys.map(async (key) => [key, await authenticate(key)])));
  // Docker Desktop peut exposer brièvement un décalage entre Auth et PostgREST.
  // Deux lectures successives garantissent que la Data API locale accepte le JWT.
  await Promise.all(Object.values(sessions).map(waitForLocalDataApiClock));

  await assert.rejects(
    deleteAccountWithVerifiedDependencies(sessions.owner, admin, ids.owner, accountInput()),
    AccountDeletionBlockedError,
  );
  await assert.rejects(
    deleteAccountWithVerifiedDependencies(sessions.platform, admin, ids.platform, accountInput()),
    AccountDeletionBlockedError,
  );
  await assert.rejects(
    deleteAccountWithVerifiedDependencies(sessions.reader, admin, ids.reader, accountInput(randomUUID(), "incorrect")),
    AccountDeletionReauthenticationError,
  );

  const mainDocuments = [
    { bucket: "transaction-proofs", path: transactionPath(0), bytes: pdf("principal-transaction") },
    { bucket: "transaction-proofs", path: transactionPath(1), bytes: pdf("principal-transaction-2") },
    { bucket: "bank-statements", path: statementPath(0), bytes: pdf("principal-releve") },
    { bucket: "management-reports", path: reportPath(0), bytes: pdf("principal-compte-gestion") },
  ];
  const initialMain = [];
  for (const document of mainDocuments) {
    initialMain.push(await upload(sessions.manager, document.bucket, document.path, document.bytes));
  }
  const reportSnapshot = {
    report: {
      id: ids.reports[0], protected_person_id: ids.person, report_year: 2198,
      period_start: "2198-01-01", period_end: "2198-12-31", status: "generated",
    },
    person: { id: ids.person },
  };
  const reportMetadata = await sessions.manager.rpc("finalize_management_report_draft_generation", {
    p_report_id: ids.reports[0], p_storage_path: reportPath(0),
    p_file_name: "compte-projet.pdf", p_mime_type: "application/pdf",
    p_file_size: mainDocuments[3].bytes.byteLength,
    p_preview_snapshot: reportSnapshot, p_snapshot_schema_version: 1,
  });
  assert.ifError(reportMetadata.error);
  assert.equal((await listOwnedStorageObjects(sessions.manager)).length, 4);

  const interruptionPaths = Array.from({ length: 6 }, (_, index) => transactionPath(index + 2));
  const interruptionBytes = interruptionPaths.map((_, index) => pdf(`interruption-${index}`));
  for (let index = 0; index < interruptionPaths.length; index += 1) {
    await upload(sessions.interrupt, "transaction-proofs", interruptionPaths[index], interruptionBytes[index]);
  }
  const interruptionCases = [
    { rpc: null, timing: null, phase: "reserved" },
    { rpc: "confirm_account_storage_neutralization_backup", timing: "after", phase: "backup_verified" },
    { rpc: "record_account_storage_neutralization_original_deleted", timing: "after", phase: "original_deleted" },
    { storage: true, phase: "original_deleted" },
    { rpc: "confirm_account_storage_neutralization_recovery", timing: "after", phase: "verified" },
    { rpc: "authorize_account_storage_neutralization_backup_cleanup", timing: "before", phase: "verified" },
  ];
  for (let index = 0; index < interruptionCases.length; index += 1) {
    const attemptId = randomUUID();
    const prepared = await prepare(sessions.interrupt, ids.interrupt, "transaction-proofs", interruptionPaths[index], attemptId);
    prepared.user = sessions.interrupt;
    if (interruptionCases[index].rpc) {
      await assert.rejects(
        resumeAccountStorageNeutralization(rpcFault(interruptionCases[index].rpc, interruptionCases[index].timing), prepared.operationId),
      );
    } else if (interruptionCases[index].storage) {
      await assert.rejects(
        resumeAccountStorageNeutralization(storageUploadFault({ bucketId: "transaction-proofs", path: interruptionPaths[index] }), prepared.operationId),
      );
    }
    assert.equal((await progress(prepared.operationId)).phase, interruptionCases[index].phase);
    const resumed = (await listAccountStorageNeutralizations(admin, ids.interrupt))
      .find((item) => item.operation_id === prepared.operationId);
    assert.ok(resumed);
    await finishAndCheck(prepared, "transaction-proofs", interruptionPaths[index], interruptionBytes[index], prepared.observed.objectId);
  }

  const lostPath = transactionPath(8);
  const lostBytes = pdf("réponse-storage-perdue");
  await upload(sessions.lost, "transaction-proofs", lostPath, lostBytes);
  const lost = await prepare(sessions.lost, ids.lost, "transaction-proofs", lostPath);
  lost.user = sessions.lost;
  await assert.rejects(
    resumeAccountStorageNeutralization(storageUploadFault({ bucketId: "document-operation-backups" }), lost.operationId),
  );
  await finishAndCheck(lost, "transaction-proofs", lostPath, lostBytes, lost.observed.objectId);

  const freezePath = transactionPath(9);
  const freezeNewPath = transactionPath(10);
  const otherPath = transactionPath(11);
  const freezeBytes = pdf("gel-storage");
  await upload(sessions.freeze, "transaction-proofs", freezePath, freezeBytes);
  const freezeAuthorization = await issueAccountDeletionAuthorization(admin, ids.freeze, randomUUID());
  assert.ifError((await sessions.freeze.storage.from("transaction-proofs").download(freezePath)).error);
  assert.ok((await sessions.freeze.storage.from("transaction-proofs").upload(freezeNewPath, pdf("refus-insert"), { contentType: "application/pdf" })).error);
  assert.ok((await sessions.freeze.storage.from("transaction-proofs").upload(freezePath, pdf("refus-update"), { contentType: "application/pdf", upsert: true })).error);
  // L'API Storage peut traduire un DELETE filtré par une politique restrictive
  // en succès sans ligne supprimée. L'invariant de sécurité est donc vérifié
  // sur l'existence persistante de l'objet, pas uniquement sur l'erreur HTTP.
  await sessions.freeze.storage.from("transaction-proofs").remove([freezePath]);
  assert.equal(await exists("transaction-proofs", freezePath), true);
  await upload(sessions.owner, "transaction-proofs", otherPath, pdf("autre-utilisateur"));
  assert.ifError((await sessions.owner.storage.from("transaction-proofs").remove([otherPath])).error);
  await cancelAccountDeletionAuthorization(admin, freezeAuthorization.authorizationId);

  const cancelledAttempt = randomUUID();
  const cancelled = await prepare(sessions.freeze, ids.freeze, "transaction-proofs", freezePath, cancelledAttempt);
  await cancelAccountDeletionAuthorization(admin, cancelled.authorization.authorizationId);
  assert.ok((await sessions.freeze.storage.from("transaction-proofs").upload(freezeNewPath, pdf("refus-annule"), { contentType: "application/pdf" })).error);
  await resumeAccountStorageNeutralization(admin, cancelled.operationId);
  assert.equal((await progress(cancelled.operationId)).phase, "finalized");

  assert.equal((await progress(ids.expiredOperation)).phase, "reserved");
  assert.ok((await sessions.state.storage.from("transaction-proofs").upload(transactionPath(23), pdf("refus-expire"), { contentType: "application/pdf" })).error);
  const expiredAuthorization = await issueAccountDeletionAuthorization(admin, ids.state, ids.expiredAttempt);
  assert.equal(expiredAuthorization.expiresAt < new Date().toISOString(), true);
  await assert.rejects(
    beginAccountStorageNeutralization(
      sessions.state, expiredAuthorization.authorizationId, ids.expiredAttempt,
      { bucket_id: "transaction-proofs", name: transactionPath(23), metadata: {}, user_metadata: {} },
      { objectId: randomUUID(), objectVersion: "invalid", bytes: pdf("x"), byteSize: 1, mimeType: "application/pdf", sha256: "a".repeat(64), metadata: {} },
    ),
  );

  const concurrentPath = transactionPath(12);
  const concurrentBytes = pdf("double-soumission");
  await upload(sessions.concurrent, "transaction-proofs", concurrentPath, concurrentBytes);
  const concurrentOwned = (await listOwnedStorageObjects(sessions.concurrent)).find((item) => item.name === concurrentPath);
  const concurrentObserved = await inspectAccountOwnedStorageObject(admin, concurrentOwned);
  const concurrentAttempt = randomUUID();
  const concurrentAuthorization = await issueAccountDeletionAuthorization(admin, ids.concurrent, concurrentAttempt);
  const submissions = await Promise.allSettled([
    beginAccountStorageNeutralization(sessions.concurrent, concurrentAuthorization.authorizationId, concurrentAttempt, concurrentOwned, concurrentObserved),
    beginAccountStorageNeutralization(sessions.concurrent, concurrentAuthorization.authorizationId, concurrentAttempt, concurrentOwned, concurrentObserved),
  ]);
  const successfulOperations = submissions.filter((item) => item.status === "fulfilled").map((item) => item.value);
  assert.ok(successfulOperations.length >= 1);
  assert.equal(new Set(successfulOperations).size, 1);
  const concurrentOperation = successfulOperations[0];
  await resumeAccountStorageNeutralization(admin, concurrentOperation);
  await cancelAccountDeletionAuthorization(admin, concurrentAuthorization.authorizationId);

  const lockPath = transactionPath(13);
  await upload(sessions.concurrent, "transaction-proofs", lockPath, pdf("verrou-concurrent"));
  const lockOwned = (await listOwnedStorageObjects(sessions.concurrent)).find((item) => item.name === lockPath);
  const lockObserved = await inspectAccountOwnedStorageObject(admin, lockOwned);
  const lockAttempts = [randomUUID(), randomUUID()];
  const lockAuthorizations = await Promise.all(lockAttempts.map((attempt) => issueAccountDeletionAuthorization(admin, ids.concurrent, attempt)));
  const lockResults = await Promise.allSettled(lockAttempts.map((attempt, index) => beginAccountStorageNeutralization(
    sessions.concurrent, lockAuthorizations[index].authorizationId, attempt, lockOwned, lockObserved,
  )));
  assert.equal(lockResults.filter((item) => item.status === "fulfilled").length, 1);
  const lockOperation = lockResults.find((item) => item.status === "fulfilled").value;
  await resumeAccountStorageNeutralization(admin, lockOperation);
  for (const authorization of lockAuthorizations) {
    await cancelAccountDeletionAuthorization(admin, authorization.authorizationId).catch(() => {});
  }

  const divergencePath = transactionPath(14);
  const divergenceBytes = pdf("divergence-version");
  await upload(sessions.divergence, "transaction-proofs", divergencePath, divergenceBytes);
  const divergent = await prepare(sessions.divergence, ids.divergence, "transaction-proofs", divergencePath);
  const changed = await admin.storage.from("transaction-proofs").upload(divergencePath, pdf("mutation-externe"), {
    contentType: "application/pdf", upsert: true,
  });
  assert.ifError(changed.error);
  await assert.rejects(resumeAccountStorageNeutralization(admin, divergent.operationId), AccountDeletionDurableStorageError);
  assert.equal((await progress(divergent.operationId)).phase, "attention_required");

  const shaPath = transactionPath(15);
  await upload(sessions.sha, "transaction-proofs", shaPath, pdf("divergence-sha"));
  const shaDivergent = await prepare(sessions.sha, ids.sha, "transaction-proofs", shaPath, randomUUID(), { sha256: "b".repeat(64) });
  await assert.rejects(resumeAccountStorageNeutralization(admin, shaDivergent.operationId), AccountDeletionDurableStorageError);
  assert.equal((await progress(shaDivergent.operationId)).phase, "attention_required");

  const backupPath = transactionPath(16);
  const backupBytes = pdf("sauvegarde-manquante");
  await upload(sessions.backup, "transaction-proofs", backupPath, backupBytes);
  const missingBackup = await prepare(sessions.backup, ids.backup, "transaction-proofs", backupPath);
  await assert.rejects(
    resumeAccountStorageNeutralization(rpcFault("confirm_account_storage_neutralization_backup", "after"), missingBackup.operationId),
  );
  const missingBackupProgress = await progress(missingBackup.operationId);
  const missingBackupPath = `operations/${missingBackup.operationId}/targets/${missingBackupProgress.targetId}/backup`;
  assert.ifError((await admin.storage.from("document-operation-backups").remove([missingBackupPath])).error);
  await assert.rejects(resumeAccountStorageNeutralization(admin, missingBackup.operationId));
  assert.equal((await progress(missingBackup.operationId)).phase, "attention_required");
  assert.equal(await exists("transaction-proofs", backupPath), true);

  const refusedAttempt = randomUUID();
  const refusingAdmin = adminAuthWrapper({
    async deleteUser() { return { data: { user: null }, error: { message: "refused locally" } }; },
  });
  await assert.rejects(
    deleteAccountWithVerifiedDependencies(sessions.refused, refusingAdmin, ids.refused, accountInput(refusedAttempt)),
    AccountDeletionAdminError,
  );
  await deleteAccountWithVerifiedDependencies(sessions.refused, admin, ids.refused, accountInput(refusedAttempt));
  await assertAuthMissing(ids.refused);

  const ambiguousAdmin = adminAuthWrapper({
    async deleteUser() { throw new Error("lost delete response"); },
    async getUserById() { throw new Error("verification unavailable"); },
  });
  await assert.rejects(
    deleteAccountWithVerifiedDependencies(sessions.ambiguous, ambiguousAdmin, ids.ambiguous, accountInput()),
    AccountDeletionAuthOutcomeUnknownError,
  );
  sessions.ambiguous = await authenticate("ambiguous");
  await deleteAccountWithVerifiedDependencies(sessions.ambiguous, admin, ids.ambiguous, accountInput());

  const absentAdmin = adminAuthWrapper({
    afterBarrier: async () => {
      const deleted = await admin.auth.admin.deleteUser(ids.absent);
      assert.ifError(deleted.error);
    },
  });
  const absentOutcome = await deleteAccountWithVerifiedDependencies(sessions.absent, absentAdmin, ids.absent, accountInput());
  assert.equal(absentOutcome.accountDeleted, true);
  await assertAuthMissing(ids.absent);

  const signoutOutcome = await deleteAccountWithVerifiedDependencies(
    sessionSignOutFailure(sessions.signout), admin, ids.signout, accountInput(),
  );
  assert.deepEqual(signoutOutcome, { accountDeleted: true, sessionClosed: false });
  await assertAuthMissing(ids.signout);

  const beforeAuthAttempt = randomUUID();
  const firstMainObject = mainDocuments[0];
  const preparedBeforeAuth = await prepare(sessions.manager, ids.manager, firstMainObject.bucket, firstMainObject.path, beforeAuthAttempt);
  await resumeAccountStorageNeutralization(admin, preparedBeforeAuth.operationId);
  const managerOutcome = await deleteAccountWithVerifiedDependencies(
    sessions.manager, admin, ids.manager, accountInput(beforeAuthAttempt),
  );
  assert.equal(managerOutcome.accountDeleted, true);
  await assertAuthMissing(ids.manager);
  for (let index = 0; index < mainDocuments.length; index += 1) {
    const actual = await inspect(mainDocuments[index].bucket, mainDocuments[index].path);
    assert.equal(actual.sha256, sha256(mainDocuments[index].bytes));
    assert.notEqual(actual.id, initialMain[index].id);
    assert.ifError((await sessions.owner.storage.from(mainDocuments[index].bucket).download(mainDocuments[index].path)).error);
    assert.ifError((await sessions.reader.storage.from(mainDocuments[index].bucket).download(mainDocuments[index].path)).error);
  }

  const readerOutcome = await deleteAccountWithVerifiedDependencies(
    sessions.reader, admin, ids.reader, accountInput(),
  );
  assert.equal(readerOutcome.accountDeleted, true);
  await assertAuthMissing(ids.reader);

  const sealedAuthorization = await issueAccountDeletionAuthorization(admin, ids.owner, randomUUID()).catch((error) => error);
  assert.ok(sealedAuthorization instanceof Error);

  console.log("PASS: suppression durable Auth/PostgreSQL/Storage, reprises, gel, divergences et documents partagés validés localement.");
}

await main();
