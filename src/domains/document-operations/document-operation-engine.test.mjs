import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  bankStatementOperation,
  managementReportFinalizationOperation,
  managementReportGenerationOperation,
  managementReportResumeOperation,
  transactionProofOperation,
} from "./domain-adapters.ts";
import {
  DocumentOperationEngine,
  DocumentOperationError,
  DocumentOperationRpcError,
  describeDocumentContent,
} from "./engine.ts";

const bytes = (value, mimeType = "application/pdf") => ({
  bytes: new TextEncoder().encode(value),
  mimeType,
});

const stored = (value, mimeType = "application/pdf") => describeDocumentContent(bytes(value, mimeType));

function target(overrides = {}) {
  return {
    id: overrides.id ?? "target-1",
    ordinal: overrides.ordinal ?? 1,
    bucketId: overrides.bucketId ?? "transaction-proofs",
    objectPath: overrides.objectPath ?? "person/transaction/proof.pdf",
    role: overrides.role ?? "primary",
    forwardAction: overrides.forwardAction ?? "insert",
    compensationAction: overrides.compensationAction ?? "delete",
    state: overrides.state ?? "pending",
    revision: overrides.revision ?? 0,
    expectedObjectId: null,
    expectedObjectVersion: null,
    appliedObjectId: null,
    appliedObjectVersion: null,
    compensatedObjectId: null,
    compensatedObjectVersion: null,
  };
}

function progress(overrides = {}) {
  return {
    operationId: "operation-1",
    workflow: "transaction_proof_create",
    state: "reserved",
    revision: 0,
    safeErrorCode: null,
    targets: [target()],
    ...overrides,
  };
}

function clone(value) {
  return structuredClone(value);
}

function createRpc(initial, options = {}) {
  let current = clone(initial);
  let progressDenied = false;
  const calls = [];
  return {
    calls,
    current: () => clone(current),
    async getProgress() {
      calls.push("progress");
      if (progressDenied) throw new DocumentOperationRpcError("authorization_lost");
      return clone(current);
    },
    async start(_id, revision) {
      calls.push("start");
      assert.equal(revision, current.revision);
      current.state = "executing";
      current.revision += 1;
      return clone(current);
    },
    async recordApplied(_id, targetId, operationRevision, targetRevision) {
      calls.push(`applied:${targetId}`);
      if (options.failRecord) throw new DocumentOperationRpcError("revision_conflict");
      assert.equal(operationRevision, current.revision);
      const item = current.targets.find(({ id }) => id === targetId);
      assert.equal(targetRevision, item.revision);
      item.state = "applied";
      item.revision += 1;
      return { operationRevision: current.revision, targetRevision: item.revision };
    },
    async finalize() {
      calls.push("finalize");
      if (options.failFinalize) {
        progressDenied = options.loseRightsAfterFinalize ?? false;
        throw new Error("private SQL detail");
      }
      current.state = "completed";
      current.revision += 1;
      return current.revision;
    },
    async beginCompensation() {
      calls.push("begin-compensation");
      if (options.failCompensationStart) throw new Error("rights lost");
      current.state = "compensating";
      current.revision += 1;
      for (const item of current.targets) {
        if (item.state === "applied") {
          item.state = "compensating";
          item.revision += 1;
        }
      }
      return clone(current);
    },
    async recordCompensated(_id, targetId, operationRevision, targetRevision) {
      calls.push(`compensated:${targetId}`);
      assert.equal(operationRevision, current.revision);
      const item = current.targets.find(({ id }) => id === targetId);
      assert.equal(targetRevision, item.revision);
      item.state = "compensated";
      item.revision += 1;
      return { operationRevision: current.revision, targetRevision: item.revision };
    },
    async completeCompensation() {
      calls.push("complete-compensation");
      current.state = "compensated";
      current.revision += 1;
      return current.revision;
    },
    async markAttention() {
      calls.push("attention");
      current.state = "attention_required";
      current.revision += 1;
      return current.revision;
    },
  };
}

function createStorage(entries = [], options = {}) {
  const objects = new Map(entries);
  const calls = [];
  return {
    calls,
    objects,
    async inspect(item) {
      calls.push(`inspect:${item.id}`);
      return objects.get(item.id) ?? null;
    },
    async upload(item, content, upsert) {
      calls.push(`upload:${item.id}:${upsert}`);
      if (options.failBeforeUpload) throw new Error("network");
      const value = options.corruptUpload ? stored("corrupt") : describeDocumentContent(content);
      objects.set(item.id, value);
      if (options.failAfterUpload) throw new Error("network response lost");
    },
    async remove(item) {
      calls.push(`remove:${item.id}`);
      objects.delete(item.id);
    },
  };
}

function createBackups() {
  const values = new Map();
  return {
    available: true,
    values,
    async save(key, value) { values.set(`${key.operationId}:${key.targetId}`, clone(value)); },
    async load(key) { return clone(values.get(`${key.operationId}:${key.targetId}`) ?? null); },
    async remove(key) { values.delete(`${key.operationId}:${key.targetId}`); },
  };
}

const proofInput = (document = bytes("new")) => transactionProofOperation("operation-1", document, {
  fileName: "proof.pdf",
  mimeType: "application/pdf",
  fileSize: document?.bytes.byteLength ?? null,
});

test("démarre, vérifie les octets créés, enregistre la cible et finalise", async () => {
  const rpc = createRpc(progress());
  const storage = createStorage();
  const result = await new DocumentOperationEngine({ rpc, storage }).execute(proofInput());
  assert.equal(result.state, "completed");
  assert.deepEqual(rpc.calls.filter((call) => call !== "progress"), ["start", "applied:target-1", "finalize"]);
  assert.equal(storage.objects.get("target-1").sha256, stored("new").sha256);
});

test("bloque remplacement et suppression avant démarrage sans sauvegarde durable", async () => {
  for (const action of ["update", "delete"]) {
    const rpc = createRpc(progress({
      workflow: `transaction_proof_${action === "update" ? "replace" : "delete"}`,
      targets: [target({ forwardAction: action, compensationAction: "update" })],
    }));
    const storage = createStorage([["target-1", stored("old")]]);
    await assert.rejects(
      new DocumentOperationEngine({ rpc, storage }).execute(proofInput(action === "delete" ? null : bytes("new"))),
      (error) => error instanceof DocumentOperationError && error.code === "backup_unavailable",
    );
    assert.equal(rpc.calls.includes("start"), false);
    assert.equal(storage.calls.some((call) => call.startsWith("upload:") || call.startsWith("remove:")), false);
  }
});

test("l’API de démarrage sauvegarde aussi les opérations destructives avant la RPC", async () => {
  const rpc = createRpc(progress({
    workflow: "transaction_proof_replace",
    targets: [target({ forwardAction: "update", compensationAction: "update" })],
  }));
  const storage = createStorage([["target-1", stored("old")]]);
  const backups = createBackups();
  const started = await new DocumentOperationEngine({ rpc, storage, backups }).start("operation-1");
  assert.equal(started.state, "executing");
  assert.equal((await backups.load({ operationId: "operation-1", targetId: "target-1" })).sha256, stored("old").sha256);
});

test("remplace un objet après sauvegarde vérifiée", async () => {
  const rpc = createRpc(progress({
    workflow: "transaction_proof_replace",
    targets: [target({ forwardAction: "update", compensationAction: "update" })],
  }));
  const storage = createStorage([["target-1", stored("old")]]);
  const backups = createBackups();
  const result = await new DocumentOperationEngine({ rpc, storage, backups }).execute(proofInput());
  assert.equal(result.state, "completed");
  assert.equal(storage.objects.get("target-1").sha256, stored("new").sha256);
  assert.equal(backups.values.size, 0);
});

test("supprime un objet après sauvegarde vérifiée", async () => {
  const rpc = createRpc(progress({
    workflow: "transaction_proof_delete",
    targets: [target({ forwardAction: "delete", compensationAction: "insert" })],
  }));
  const storage = createStorage([["target-1", stored("old")]]);
  const result = await new DocumentOperationEngine({ rpc, storage, backups: createBackups() })
    .execute(proofInput(null));
  assert.equal(result.state, "completed");
  assert.equal(storage.objects.has("target-1"), false);
});

test("une réponse réseau perdue n’entraîne pas une seconde création", async () => {
  const rpc = createRpc(progress());
  const storage = createStorage([], { failAfterUpload: true });
  const result = await new DocumentOperationEngine({ rpc, storage }).execute(proofInput());
  assert.equal(result.state, "completed");
  assert.equal(storage.calls.filter((call) => call.startsWith("upload:")).length, 1);
});

test("une création déjà matérialisée est reprise sans double mutation", async () => {
  const rpc = createRpc(progress({ state: "executing", revision: 1 }));
  const storage = createStorage([["target-1", stored("new")]]);
  const result = await new DocumentOperationEngine({ rpc, storage }).execute(proofInput());
  assert.equal(result.state, "completed");
  assert.equal(storage.calls.some((call) => call.startsWith("upload:")), false);
});

test("une finalisation refusée compense la création et ne retourne pas un faux succès", async () => {
  const rpc = createRpc(progress(), { failFinalize: true });
  const storage = createStorage();
  await assert.rejects(
    new DocumentOperationEngine({ rpc, storage }).execute(proofInput()),
    (error) => error instanceof DocumentOperationError && error.code === "rpc_rejected",
  );
  assert.equal(rpc.current().state, "compensated");
  assert.equal(storage.objects.size, 0);
});

test("un conflit de révision après mutation est compensé et distingué", async () => {
  const rpc = createRpc(progress(), { failRecord: true });
  const storage = createStorage();
  await assert.rejects(
    new DocumentOperationEngine({ rpc, storage }).execute(proofInput()),
    (error) => error instanceof DocumentOperationError && error.code === "revision_conflict",
  );
  assert.equal(rpc.current().state, "compensated");
  assert.equal(storage.objects.size, 0);
});

test("une divergence d’octets exige une intervention et n’est jamais finalisée", async () => {
  const rpc = createRpc(progress());
  const storage = createStorage([], { corruptUpload: true });
  await assert.rejects(
    new DocumentOperationEngine({ rpc, storage }).execute(proofInput()),
    (error) => error instanceof DocumentOperationError,
  );
  assert.equal(rpc.current().state, "attention_required");
  assert.equal(rpc.calls.includes("finalize"), false);
});

test("une divergence avant remplacement n’est jamais écrasée par la compensation", async () => {
  const rpc = createRpc(progress({
    workflow: "transaction_proof_replace",
    state: "executing",
    revision: 1,
    targets: [target({ forwardAction: "update", compensationAction: "update" })],
  }));
  const storage = createStorage([["target-1", stored("concurrent")]]);
  const backups = createBackups();
  await backups.save({ operationId: "operation-1", targetId: "target-1" }, stored("old"));
  await assert.rejects(
    new DocumentOperationEngine({ rpc, storage, backups }).execute(proofInput()),
    (error) => error instanceof DocumentOperationError && error.code === "storage_diverged",
  );
  assert.equal(storage.objects.get("target-1").sha256, stored("concurrent").sha256);
  assert.equal(rpc.current().state, "attention_required");
});

test("une perte de droits pendant la compensation est signalée pour intervention", async () => {
  const rpc = createRpc(progress(), { failFinalize: true, loseRightsAfterFinalize: true });
  await assert.rejects(
    new DocumentOperationEngine({ rpc, storage: createStorage() }).execute(proofInput()),
    (error) => error instanceof DocumentOperationError && error.code === "compensation_failed",
  );
  assert.equal(rpc.current().state, "attention_required");
});

test("une opération terminale est idempotente et ne touche pas Storage", async () => {
  const rpc = createRpc(progress({ state: "completed", revision: 4 }));
  const storage = createStorage();
  const result = await new DocumentOperationEngine({ rpc, storage }).execute(proofInput());
  assert.equal(result.state, "completed");
  assert.deepEqual(storage.calls, []);
});

test("une finalisation de compte de gestion orchestre plusieurs cibles", async () => {
  const targets = [
    target({ id: "destination", bucketId: "management-reports", objectPath: "p/r/final.pdf", role: "destination" }),
    target({ id: "source", ordinal: 2, bucketId: "management-reports", objectPath: "p/r/draft.pdf", role: "source", forwardAction: "delete", compensationAction: "insert" }),
  ];
  const rpc = createRpc(progress({ workflow: "management_report_finalize", targets }));
  const storage = createStorage([["source", stored("draft")]]);
  const result = await new DocumentOperationEngine({ rpc, storage, backups: createBackups() }).execute(
    managementReportFinalizationOperation("operation-1", bytes("final"), {
      fileName: "final.pdf",
      mimeType: "application/pdf",
      fileSize: 5,
      previewSnapshot: { report: { id: "report" } },
      snapshotSchemaVersion: 1,
    }),
  );
  assert.equal(result.state, "completed");
  assert.equal(storage.objects.has("destination"), true);
  assert.equal(storage.objects.has("source"), false);
});

test("les adaptateurs métier lient le contenu au rôle SQL attendu", () => {
  const metadata = { fileName: "report.pdf", mimeType: "application/pdf", fileSize: 3, previewSnapshot: {}, snapshotSchemaVersion: 1 };
  assert.equal(managementReportGenerationOperation("id", bytes("pdf"), metadata).contents[0].targetRole, "primary");
  assert.equal(managementReportFinalizationOperation("id", bytes("pdf"), metadata).contents[0].targetRole, "destination");
  assert.equal(managementReportResumeOperation("id", metadata).contents.length, 0);
  assert.equal(bankStatementOperation("id", bytes("pdf"), {
    statementStartDate: "2026-01-01", statementEndDate: "2026-01-31", statementBalance: 10,
    note: null, fileName: "statement.pdf", mimeType: "application/pdf", fileSize: 3,
  }).finalization.kind, "bank_statement");
});

test("l’adaptateur serveur sépare RPC authentifiées et mutations privilégiées", async () => {
  const source = await readFile(new URL("./server.ts", import.meta.url), "utf8");
  assert.match(source, /userClient\.auth\.getClaims\(\)/);
  assert.match(source, /createRpcGateway\(userClient/);
  assert.match(source, /const admin = createAdminClient\(\)/);
  assert.doesNotMatch(source, /createRpcGateway\(admin/);
  assert.doesNotMatch(source, /console\.|SUPABASE_SERVICE_ROLE_KEY/);
});
