import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import {
  inspectAdministrativeDocumentPhysicalObject,
// @ts-expect-error Node's strip-types runner loads the source directly.
} from "../../src/domains/administration/administrative-document-physical-verification-core.ts";

const url = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!url || !anonKey || !serviceKey || !password) throw new Error("Configuration locale incomplète.");
const endpoint = new URL(url);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Refus d’utiliser une API Supabase non locale.");
}

const objects = {
  present: process.env.PAT_TEST_PRESENT_OBJECT_ID,
  catalogOnly: "99760000-0000-4000-8100-000000000002",
  concurrent: process.env.PAT_TEST_CONCURRENT_OBJECT_ID,
};
const backups = {
  valid: "99760000-0000-4000-8500-000000000001",
  divergent: "99760000-0000-4000-8500-000000000002",
};
const paths = {
  present: "legacy/reconciliation-present",
  concurrent: "legacy/reconciliation-concurrent",
  validBackup: "operations/99760000-0000-4000-8200-000000000001/targets/99760000-0000-4000-8300-000000000001/backup",
  divergentBackup: "operations/99760000-0000-4000-8200-000000000002/targets/99760000-0000-4000-8300-000000000002/backup",
};
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const user = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
const encode = (value) => new TextEncoder().encode(value);
const digest = (value) => createHash("sha256").update(value).digest("hex");

async function upload(bucket, path, value, upsert = false) {
  const bytes = encode(value);
  const result = await service.storage.from(bucket).upload(path, bytes, { contentType: "application/pdf", upsert });
  assert.ifError(result.error);
  const info = await service.storage.from(bucket).info(path);
  assert.ifError(info.error);
  return { id: info.data.id, version: info.data.version, size: bytes.byteLength, sha256: digest(bytes) };
}

async function invoke(client, name, args) {
  const result = await client.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

function totalSize(response) {
  const contentRange = response.headers.get("content-range");
  const match = contentRange?.match(/\/(\d+)$/);
  if (match) return Number(match[1]);
  const contentLength = response.status === 200 ? response.headers.get("content-length") : null;
  return contentLength && /^\d+$/.test(contentLength) ? Number(contentLength) : null;
}

async function* responseChunks(response) {
  const reader = response.body.getReader();
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) return;
      yield result.value;
    }
  } finally {
    await reader.cancel().catch(() => undefined);
    reader.releaseLock();
  }
}

function physicalGateway(bucket, path) {
  return {
    info: () => bucket.info(path),
    download: async (signal, maximumBytes) => {
      const signed = await bucket.createSignedUrl(path, 60);
      if (signed.error || !signed.data?.signedUrl) return { data: null, error: signed.error };
      const response = await fetch(signed.data.signedUrl, {
        headers: { Range: `bytes=0-${maximumBytes}` }, signal,
      });
      if (!response.ok || !response.body) return { data: null, error: { status: response.status } };
      return { data: { chunks: responseChunks(response), totalByteSize: totalSize(response) }, error: null };
    },
  };
}

if (process.argv[2] === "seed") {
  const result = {
    present: await upload("transaction-proofs", paths.present, "physical-present"),
    concurrent: await upload("transaction-proofs", paths.concurrent, "physical-before"),
    validBackup: await upload("document-operation-backups", paths.validBackup, "backup-valid"),
    divergentBackup: await upload("document-operation-backups", paths.divergentBackup, "backup-divergent"),
  };
  process.stdout.write(JSON.stringify(result));
  process.exit(0);
}
if (!objects.present || !objects.concurrent) throw new Error("Identités Storage locales absentes.");

const signed = await user.auth.signInWithPassword({ email: "physical-reconciliation-admin@example.test", password });
assert.ifError(signed.error);

function finding(category, anomaly, id) { return `${category}:${anomaly}:${id}`; }

async function verify(inventoryKey, requestId, beforeComplete, beforeRead) {
  const begun = await invoke(user, "begin_administrative_document_physical_verification", { p_inventory_key: inventoryKey, p_client_request_id: requestId });
  const descriptor = await invoke(service, "get_administrative_document_physical_verification_descriptor", { p_verification_request_id: begun.verificationRequestId });
  if (beforeRead) await beforeRead();
  const bucket = service.storage.from(descriptor.bucketId);
  const result = await inspectAdministrativeDocumentPhysicalObject(physicalGateway(bucket, descriptor.objectPath), descriptor);
  if (beforeComplete) await beforeComplete();
  const completed = await invoke(service, "complete_administrative_document_physical_verification", {
    p_verification_request_id: begun.verificationRequestId,
    p_server_capability: descriptor.serverCapability,
    p_outcome: result.outcome,
    p_proof_level: result.proofLevel,
    p_catalog_object_id: result.catalogObjectId,
    p_catalog_object_version: result.catalogObjectVersion,
    p_observed_byte_size: result.byteSize,
    p_observed_sha256: result.sha256,
    p_limitation_code: result.limitationCode,
  });
  return { begun, descriptor, result, completed };
}

const presentKey = finding("transaction_proof", "unresolved_catalog_path", objects.present);
const present = await verify(presentKey, "99760000-0000-4000-8600-000000000001");
assert.equal(present.result.outcome, "verified_readable");
assert.equal(present.result.proofLevel, "physical_readability");
assert.ok(!JSON.stringify(present.begun).includes(paths.present));
const replay = await invoke(user, "begin_administrative_document_physical_verification", { p_inventory_key: presentKey, p_client_request_id: "99760000-0000-4000-8600-000000000001" });
assert.equal(replay.observationId, present.completed.observationId);
assert.equal(replay.observation.id, present.completed.observationId);

const concurrentBegin = await invoke(user, "begin_administrative_document_physical_verification", {
  p_inventory_key: presentKey,
  p_client_request_id: "99760000-0000-4000-8600-000000000009",
});
const concurrentDescriptor = await invoke(service, "get_administrative_document_physical_verification_descriptor", {
  p_verification_request_id: concurrentBegin.verificationRequestId,
});
const concurrentResult = await inspectAdministrativeDocumentPhysicalObject(
  physicalGateway(service.storage.from(concurrentDescriptor.bucketId), concurrentDescriptor.objectPath),
  concurrentDescriptor,
);
const concurrentCompletionArguments = {
  p_verification_request_id: concurrentBegin.verificationRequestId,
  p_server_capability: concurrentDescriptor.serverCapability,
  p_outcome: concurrentResult.outcome,
  p_proof_level: concurrentResult.proofLevel,
  p_catalog_object_id: concurrentResult.catalogObjectId,
  p_catalog_object_version: concurrentResult.catalogObjectVersion,
  p_observed_byte_size: concurrentResult.byteSize,
  p_observed_sha256: concurrentResult.sha256,
  p_limitation_code: concurrentResult.limitationCode,
};
const [concurrentCompletionOne, concurrentCompletionTwo] = await Promise.all([
  invoke(service, "complete_administrative_document_physical_verification", concurrentCompletionArguments),
  invoke(service, "complete_administrative_document_physical_verification", concurrentCompletionArguments),
]);
assert.equal(concurrentCompletionOne.observationId, concurrentCompletionTwo.observationId);

const missing = await verify(finding("transaction_proof", "unresolved_catalog_path", objects.catalogOnly), "99760000-0000-4000-8600-000000000002");
// Le serveur Storage local répond 500 lorsque le catalogue existe mais que le
// fichier sous-jacent manque. Sans preuve 404, le moteur reste volontairement
// conservateur et n'affirme pas une absence physique.
assert.equal(missing.result.outcome, "verification_inconclusive");
assert.equal(missing.result.limitationCode, "STORAGE_DOWNLOAD_FAILED");

const validBackup = await verify(finding("backup", "backup_physical_verification_required", backups.valid), "99760000-0000-4000-8600-000000000003");
assert.equal(validBackup.result.outcome, "verified_readable");
assert.equal(validBackup.result.proofLevel, "physical_integrity");

const divergentBackup = await verify(finding("backup", "backup_physical_verification_required", backups.divergent), "99760000-0000-4000-8600-000000000004");
assert.equal(divergentBackup.result.outcome, "hash_mismatch");

const concurrent = await verify(
  finding("transaction_proof", "unresolved_catalog_path", objects.concurrent),
  "99760000-0000-4000-8600-000000000005",
  () => upload("transaction-proofs", paths.concurrent, "physical-after", true),
);
assert.equal(concurrent.completed.outcome, "stale_inventory_finding");

const replacedBeforeReadPath = "legacy/reconciliation-replaced-before-read";
const original = await upload("transaction-proofs", replacedBeforeReadPath, "original-object");
const replacedBeforeReadKey = finding("transaction_proof", "unresolved_catalog_path", original.id);
const replacedBeforeRead = await verify(
  replacedBeforeReadKey,
  "99760000-0000-4000-8600-000000000006",
  undefined,
  () => upload("transaction-proofs", replacedBeforeReadPath, "replacement-object", true),
);
assert.equal(replacedBeforeRead.result.outcome, "version_mismatch");
assert.equal(replacedBeforeRead.result.byteSize, null);

const history = await invoke(user, "get_administrative_document_physical_observations", { p_inventory_key: presentKey, p_limit: 20, p_before_observed_at: null });
assert.equal(history.items.length, 2);
assert.ok(!JSON.stringify(history).includes(paths.present));
assert.ok(!JSON.stringify(history).includes(present.result.sha256));
console.log("Réconciliation physique locale: présence, absence, sauvegarde, divergence, concurrence et idempotence validées.");
