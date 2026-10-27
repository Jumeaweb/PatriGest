import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  inspectAdministrativeDocumentPhysicalObject,
  MAX_PHYSICAL_VERIFICATION_BYTES,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "./administrative-document-physical-verification-core.ts";

const bytes = new TextEncoder().encode("preuve physique");
const hash = createHash("sha256").update(bytes).digest("hex");
const descriptor = { catalogObjectId: "11111111-1111-4111-8111-111111111111", catalogObjectVersion: "v1", expectedByteSize: bytes.length, expectedSha256: hash };
const chunks = async function* (values = [bytes]) { for (const value of values) yield value; };
const gateway = (overrides = {}) => ({
  info: async () => ({ data: { id: descriptor.catalogObjectId, version: "v1", size: bytes.length }, error: null }),
  download: async () => ({ data: { chunks: chunks(), totalByteSize: bytes.length }, error: null }),
  ...overrides,
});

test("vérifie réellement les octets et une empreinte durable", async () => {
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway(), descriptor);
  assert.equal(result.outcome, "verified_readable");
  assert.equal(result.proofLevel, "physical_integrity");
  assert.equal(result.sha256, hash);
});

test("distingue absence, accès refusé et erreur Storage", async () => {
  const missing = await inspectAdministrativeDocumentPhysicalObject(gateway({ info: async () => ({ data: null, error: { statusCode: 404 } }) }), descriptor);
  const forbidden = await inspectAdministrativeDocumentPhysicalObject(gateway({ info: async () => ({ data: null, error: { statusCode: 403 } }) }), descriptor);
  const failed = await inspectAdministrativeDocumentPhysicalObject(gateway({ info: async () => ({ data: null, error: { statusCode: 500 } }) }), descriptor);
  const missingByMessage = await inspectAdministrativeDocumentPhysicalObject(gateway({ download: async () => ({ data: null, error: { message: "Object not found" } }) }), descriptor);
  assert.equal(missing.outcome, "missing_physical_bytes");
  assert.equal(forbidden.limitationCode, "STORAGE_ACCESS_DENIED");
  assert.equal(failed.limitationCode, "STORAGE_INFO_FAILED");
  assert.equal(missingByMessage.outcome, "missing_physical_bytes");
});

test("refuse le chargement des fichiers trop volumineux avant téléchargement", async () => {
  let downloaded = false;
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway({
    info: async () => ({ data: { id: descriptor.catalogObjectId, version: "v1", size: MAX_PHYSICAL_VERIFICATION_BYTES + 1 }, error: null }),
    download: async () => { downloaded = true; return { data: { chunks: chunks(), totalByteSize: bytes.length }, error: null }; },
  }), descriptor);
  assert.equal(result.limitationCode, "OBJECT_TOO_LARGE");
  assert.equal(downloaded, false);
});

test("arrête le flux dès que les octets reçus dépassent 20 Mio", async () => {
  let chunksRead = 0;
  const oversizedChunks = async function* () {
    chunksRead += 1;
    yield new Uint8Array(MAX_PHYSICAL_VERIFICATION_BYTES);
    chunksRead += 1;
    yield new Uint8Array(1);
    chunksRead += 1;
    yield new Uint8Array(1);
  };
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway({
    info: async () => ({ data: { id: descriptor.catalogObjectId, version: "v1" }, error: null }),
    download: async () => ({ data: { chunks: oversizedChunks(), totalByteSize: null }, error: null }),
  }), { ...descriptor, expectedByteSize: null, expectedSha256: null });
  assert.equal(result.limitationCode, "OBJECT_TOO_LARGE");
  assert.equal(chunksRead, 2);
});

test("interrompt réellement le téléchargement après le délai", async () => {
  let aborted = false;
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway({
    download: (signal) => new Promise((resolve) => {
      signal.addEventListener("abort", () => {
        aborted = true;
        resolve({ data: null, error: { message: "aborted" } });
      }, { once: true });
    }),
  }), descriptor);
  assert.equal(result.limitationCode, "STORAGE_TIMEOUT");
  assert.equal(aborted, true);
});

test("ne lit pas les octets d’un objet remplacé après autorisation", async () => {
  let downloaded = false;
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway({
    info: async () => ({ data: { id: descriptor.catalogObjectId, version: "v2", size: bytes.length }, error: null }),
    download: async () => { downloaded = true; return { data: { chunks: chunks(), totalByteSize: bytes.length }, error: null }; },
  }), descriptor);
  assert.equal(result.outcome, "version_mismatch");
  assert.equal(result.proofLevel, "catalog_only");
  assert.equal(downloaded, false);
});

test("qualifie les divergences de version, taille et empreinte", async () => {
  const version = await inspectAdministrativeDocumentPhysicalObject(gateway({ info: async () => ({ data: { id: descriptor.catalogObjectId, version: "v2", size: bytes.length }, error: null }) }), descriptor);
  const size = await inspectAdministrativeDocumentPhysicalObject(gateway(), { ...descriptor, expectedByteSize: bytes.length + 1, expectedSha256: null });
  const digest = await inspectAdministrativeDocumentPhysicalObject(gateway(), { ...descriptor, expectedSha256: "0".repeat(64) });
  assert.equal(version.outcome, "version_mismatch");
  assert.equal(size.limitationCode, "REFERENCE_SIZE_MISMATCH");
  assert.equal(digest.outcome, "hash_mismatch");
});

test("une empreinte calculée sans référence ne prétend pas établir l’intégrité historique", async () => {
  const result = await inspectAdministrativeDocumentPhysicalObject(gateway(), { ...descriptor, expectedSha256: null });
  assert.equal(result.outcome, "verified_readable");
  assert.equal(result.proofLevel, "physical_readability");
  assert.equal(result.limitationCode, "NO_RELIABLE_REFERENCE_HASH");
});

test("le raccordement serveur reste confidentiel et sans mutation Storage", () => {
  const service = readFileSync(new URL("./services/administrative-document-physical-verification-service.ts", import.meta.url), "utf8");
  const component = readFileSync(new URL("./components/administrative-document-physical-verification.tsx", import.meta.url), "utf8");
  assert.match(service, /requirePlatformAdministrator/);
  assert.match(service, /createAdminClient/);
  assert.match(service, /\.info\(/);
  assert.match(service, /createSignedUrl/);
  assert.match(service, /Range:/);
  assert.match(service, /signal,/);
  assert.doesNotMatch(service, /\.upload\(|\.remove\(|arrayBuffer\(/);
  assert.doesNotMatch(component, /objectPath|bucketId|sha256|serverCapability/);
  assert.match(component, /ne prouve pas l’état physique actuel/);
});
