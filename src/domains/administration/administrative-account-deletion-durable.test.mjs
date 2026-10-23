import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { afterEach, test } from "node:test";
import {
  AdministrativeAccountDeletionAuthOutcomeUnknownError,
  AdministrativeAccountDeletionError,
  deletePlatformUserWithDurableNeutralization,
  prepareAdministrativeAccountDeletionPlan,
} from "./administrative-account-deletion-durable.ts";
import { AccountDeletionDurableAttentionError } from "../account/account-deletion-durable.ts";
import { isAdminAccountDeletionDurableNeutralizationEnabled } from "./administrative-account-deletion-durable-availability.ts";

const flag = "PATRIGEST_ENABLE_ADMIN_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION";
const administratorId = "a1000000-0000-4000-8000-000000000001";
const targetId = "a1000000-0000-4000-8000-000000000002";
const attemptId = "a1000000-0000-4000-8000-000000000003";
const authorizationId = "a1000000-0000-4000-8000-000000000004";
const planHash = "a".repeat(64);

afterEach(() => delete process.env[flag]);

test("active le parcours administratif durable uniquement avec la valeur exacte true", () => {
  for (const value of [undefined, "TRUE", "1", " true", "false"]) {
    if (value === undefined) delete process.env[flag];
    else process.env[flag] = value;
    assert.equal(isAdminAccountDeletionDurableNeutralizationEnabled(), false);
  }
  process.env[flag] = "true";
  assert.equal(isAdminAccountDeletionDurableNeutralizationEnabled(), true);
});

function diagnostic(storageObjects = [], blockingAnomalies = []) {
  return {
    targetUserId: targetId,
    eligible: true,
    businessBlockers: [],
    blockingAnomalies,
    storageObjects,
    nonTerminalOperationCount: 0,
    unfinishedNeutralizationCount: 0,
    unclearedBackupCount: 0,
  };
}

function harness({ deleteResult, getResult, barrier = { ready: true, targetAuthExists: true } } = {}) {
  const calls = [];
  const session = {
    async rpc(name, args) {
      calls.push(["session", name, args]);
      if (name === "get_administrative_account_deletion_attempt") return { data: null, error: null };
      if (name === "get_administrative_account_deletion_diagnostic") return { data: diagnostic(), error: null };
      if (name === "issue_administrative_account_deletion_authorization") return { data: {
        authorizationId, administratorUserId: administratorId, targetUserId: targetId,
        attemptId, planHash, documentCount: 0, expiresAt: new Date(Date.now() + 60_000).toISOString(),
        state: "active", revision: 0,
      }, error: null };
      if (name === "assert_administrative_account_deletion_barrier") return { data: barrier, error: null };
      throw new Error(`RPC inattendue: ${name}`);
    },
  };
  const admin = {
    storage: { from() { throw new Error("Storage ne doit pas être utilisé sans document"); } },
    async rpc(name, args) {
      calls.push(["admin", name, args]);
      if (name === "list_administrative_account_storage_neutralization_operations") return { data: [], error: null };
      throw new Error(`RPC privilégiée inattendue: ${name}`);
    },
    auth: { admin: {
      async deleteUser() {
        calls.push(["auth", "deleteUser"]);
        if (deleteResult instanceof Error) throw deleteResult;
        return deleteResult ?? { data: { user: { id: targetId } }, error: null };
      },
      async getUserById() {
        calls.push(["auth", "getUserById"]);
        if (getResult instanceof Error) throw getResult;
        return getResult ?? { data: { user: { id: targetId } }, error: null };
      },
    } },
  };
  return { session, admin, calls };
}

test("scelle la barrière juste avant la suppression Auth", async () => {
  const value = harness();
  const result = await deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Compte de test arrivé à échéance",
  });
  assert.deepEqual(result, { accountDeleted: true, alreadyAbsent: false });
  const barrierIndex = value.calls.findIndex((call) => call[1] === "assert_administrative_account_deletion_barrier");
  const deletionIndex = value.calls.findIndex((call) => call[1] === "deleteUser");
  assert.ok(barrierIndex >= 0 && deletionIndex > barrierIndex);
});

test("qualifie une réponse Auth perdue par une lecture autoritaire", async () => {
  const value = harness({
    deleteResult: new Error("réponse perdue"),
    getResult: { data: { user: null }, error: { code: "user_not_found", status: 404 } },
  });
  const result = await deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Suppression autorisée",
  });
  assert.equal(result.accountDeleted, true);
  assert.equal(value.calls.some((call) => call[1] === "getUserById"), true);
});

test("refuse de déclarer un succès lorsque la cible Auth existe encore", async () => {
  const value = harness({
    deleteResult: { data: { user: null }, error: { code: "refused" } },
    getResult: { data: { user: { id: targetId } }, error: null },
  });
  await assert.rejects(deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Suppression autorisée",
  }), AdministrativeAccountDeletionError);
});

test("conserve un résultat inconnu si la vérification Auth échoue", async () => {
  const value = harness({ deleteResult: new Error("réseau"), getResult: new Error("réseau") });
  await assert.rejects(deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Suppression autorisée",
  }), AdministrativeAccountDeletionAuthOutcomeUnknownError);
});

test("ne rappelle pas Auth lorsque la barrière démontre que la cible est déjà absente", async () => {
  const value = harness({ barrier: { ready: true, targetAuthExists: false } });
  const result = await deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Reprise après réponse perdue",
  });
  assert.deepEqual(result, { accountDeleted: true, alreadyAbsent: true });
  assert.equal(value.calls.some((call) => call[0] === "auth"), false);
});

test("reprend une tentative existante sans reconstruire son plan depuis un inventaire transitoire", async () => {
  const value = harness();
  value.session.rpc = async (name, args) => {
    value.calls.push(["session", name, args]);
    if (name === "get_administrative_account_deletion_attempt") return { data: {
      authorizationId, administratorUserId: administratorId, targetUserId: targetId,
      attemptId, reason: "Reprise stable", planHash, documentCount: 0, documentPlan: [],
      expiresAt: new Date(Date.now() + 60_000).toISOString(), state: "sealed", revision: 1,
    }, error: null };
    if (name === "assert_administrative_account_deletion_barrier") return { data: { ready: true, targetAuthExists: false }, error: null };
    throw new Error(`RPC inattendue: ${name}`);
  };
  const result = await deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Reprise stable",
  });
  assert.equal(result.alreadyAbsent, true);
  assert.equal(value.calls.some((call) => call[1] === "get_administrative_account_deletion_diagnostic"), false);
  assert.equal(value.calls.some((call) => call[1] === "issue_administrative_account_deletion_authorization"), false);
});

test("reprend une neutralisation existante après annulation sans en ouvrir une nouvelle", async () => {
  const operationId = "a1000000-0000-4000-8000-000000000020";
  const clientRequestId = "a1000000-0000-4000-8000-000000000021";
  const value = harness();
  value.session.rpc = async (name, args) => {
    value.calls.push(["session", name, args]);
    if (name === "get_administrative_account_deletion_attempt") return { data: {
      authorizationId, administratorUserId: administratorId, targetUserId: targetId,
      attemptId, reason: "Tentative annulée", planHash, documentCount: 1,
      documentPlan: [{
        ordinal: 1, bucketId: "transaction-proofs", objectPath: "protected-persons/a/transactions/b/proof",
        objectId: "a1000000-0000-4000-8000-000000000022", objectVersion: "v1",
        sha256: "b".repeat(64), byteSize: 10, mimeType: "application/pdf",
        protectedPersonId: "a1000000-0000-4000-8000-000000000023",
        businessEntityType: "transaction", businessEntityId: "a1000000-0000-4000-8000-000000000024",
      }],
      expiresAt: new Date(Date.now() - 60_000).toISOString(), state: "cancelled", revision: 1,
    }, error: null };
    throw new Error(`RPC inattendue: ${name}`);
  };
  value.admin.rpc = async (name, args) => {
    value.calls.push(["admin", name, args]);
    if (name === "list_administrative_account_storage_neutralization_operations") return { data: [{
      operation_id: operationId, client_request_id: clientRequestId, state: "attention_required",
      phase: "attention_required", created_at: new Date().toISOString(),
    }], error: null };
    if (name === "get_account_storage_neutralization_progress") return { data: {
      operationId, state: "attention_required", operationRevision: 2,
      targetId: "a1000000-0000-4000-8000-000000000025",
      bucketId: "transaction-proofs", objectPath: "protected-persons/a/transactions/b/proof",
      phase: "attention_required", resumePhase: "backup_verified", revision: 2,
      backupState: "verified", objectPresent: true, verifiedBackupPresent: true,
      recoveryRequired: false, uncertain: true,
      expectedObjectId: "a1000000-0000-4000-8000-000000000022",
      expectedObjectVersion: "v1", recreatedObjectId: null, recreatedObjectVersion: null,
      expectedSha256: "b".repeat(64), expectedByteSize: 10,
    }, error: null };
    throw new Error(`RPC privilégiée inattendue: ${name}`);
  };
  await assert.rejects(deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: administratorId, targetUserId: targetId, attemptId, reason: "Tentative annulée",
  }), AccountDeletionDurableAttentionError);
  assert.equal(value.calls.some((call) => call[1] === "get_account_storage_neutralization_progress"), true);
  assert.equal(value.calls.some((call) => call[1] === "begin_administrative_account_storage_neutralization"), false);
  assert.equal(value.calls.some((call) => call[1] === "assert_administrative_account_deletion_barrier"), false);
  assert.equal(value.calls.some((call) => call[1] === "deleteUser"), false);
});

test("refuse l’auto-suppression et les anomalies documentaires", async () => {
  const value = harness();
  await assert.rejects(deletePlatformUserWithDurableNeutralization(value.session, value.admin, {
    administratorUserId: targetId, targetUserId: targetId, attemptId, reason: "Interdit",
  }), AdministrativeAccountDeletionError);
  const anomalous = {
    rpc: async () => ({ data: diagnostic([], ["NON_CANONICAL_STORAGE_OBJECT"]), error: null }),
  };
  await assert.rejects(
    prepareAdministrativeAccountDeletionPlan(anomalous, value.admin, targetId),
    AdministrativeAccountDeletionError,
  );
});

test("construit le plan depuis l’identité et les octets Storage réels", async () => {
  const bytes = new TextEncoder().encode("%PDF-1.4\ncontenu\n%%EOF");
  const object = {
    bucketId: "transaction-proofs", objectPath: "protected-persons/a/transactions/b/proof",
    objectId: "a1000000-0000-4000-8000-000000000010", objectVersion: "v1",
    catalogByteSize: bytes.byteLength, catalogMimeType: "application/pdf", canonical: true,
    protectedPersonId: "a1000000-0000-4000-8000-000000000011",
    businessEntityType: "transaction", businessEntityId: "a1000000-0000-4000-8000-000000000012",
  };
  const session = { rpc: async () => ({ data: diagnostic([object]), error: null }) };
  const admin = { storage: { from: () => ({
    exists: async () => ({ data: true, error: null }),
    info: async () => ({ data: { id: object.objectId, version: "v1", contentType: "application/pdf", cacheControl: "max-age=3600", metadata: {}, size: bytes.byteLength }, error: null }),
    download: async () => ({ data: new Blob([bytes], { type: "application/pdf" }), error: null }),
  }) } };
  const result = await prepareAdministrativeAccountDeletionPlan(session, admin, targetId);
  assert.equal(result.plan[0].sha256, createHash("sha256").update(bytes).digest("hex"));
  assert.equal(result.plan[0].byteSize, bytes.byteLength);
  assert.equal(result.plan[0].ordinal, 1);
});
