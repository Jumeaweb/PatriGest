import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  isTransactionProofDurableOperationsEnabled,
  runTransactionProofWrite,
  TRANSACTION_PROOF_DURABLE_OPERATIONS_ENV,
} from "./transaction-proof-durable-availability.ts";
import {
  createTransactionProofRequestId,
  reserveTransactionProofOperation,
} from "./transaction-proof-durable-reservation.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./transaction-proof-service.ts");
const durable = source("./transaction-proof-durable.ts");
const route = source("../../../app/api/dossiers/[protectedPersonId]/operations/[transactionId]/justificatif/route.ts");
const transactionService = source("./transaction-service.ts");
const actions = source("../actions.ts");
const component = source("../components/transaction-proof.tsx");
const editPage = source("../../../app/dossiers/[protectedPersonId]/operations/[transactionId]/modifier/page.tsx");

test("l’indicateur serveur est indépendant, strict et désactivé par défaut", () => {
  assert.equal(
    TRANSACTION_PROOF_DURABLE_OPERATIONS_ENV,
    "PATRIGEST_ENABLE_TRANSACTION_PROOF_DURABLE_OPERATIONS",
  );
  assert.equal(isTransactionProofDurableOperationsEnabled(undefined), false);
  assert.equal(isTransactionProofDurableOperationsEnabled("false"), false);
  assert.equal(isTransactionProofDurableOperationsEnabled("TRUE"), false);
  assert.equal(isTransactionProofDurableOperationsEnabled("true"), true);
});

test("le mode désactivé exécute exclusivement le parcours historique", async () => {
  const calls = [];
  const result = await runTransactionProofWrite(
    false,
    async () => { calls.push("historical"); return "legacy"; },
    async () => { calls.push("durable"); return "new"; },
  );
  assert.equal(result, "legacy");
  assert.deepEqual(calls, ["historical"]);
});

test("le mode activé ne retombe jamais sur l’ancien parcours", async () => {
  const calls = [];
  await assert.rejects(runTransactionProofWrite(
    true,
    async () => { calls.push("historical"); },
    async () => { calls.push("durable"); throw new Error("durable failed"); },
  ));
  assert.deepEqual(calls, ["durable"]);
});

test("la réservation utilise la signature SQL exacte et un identifiant d’idempotence", async () => {
  const calls = [];
  const operationId = "11111111-1111-4111-8111-111111111111";
  const reservation = { operationId, operationRevision: 1, state: "reserved", intent: "replace", documentId: "55555555-5555-4555-8555-555555555555", versionId: "66666666-6666-4666-8666-666666666666", versionNumber: 2, storagePath: "protected-persons/person/transactions/transaction/proofs/document/versions/version", transactionRevision: 1, proofReference: "2026-0001", idempotent: false };
  const result = await reserveTransactionProofOperation({
    async rpc(name, args) {
      calls.push({ name, args });
      return { data: reservation, error: null };
    },
  }, {
    personId: "22222222-2222-4222-8222-222222222222",
    transactionId: "33333333-3333-4333-8333-333333333333",
    intent: "replace",
    clientRequestId: "44444444-4444-4444-8444-444444444444",
  });
  assert.deepEqual(result, reservation);
  assert.deepEqual(calls, [{
    name: "reserve_transaction_proof_version",
    args: {
      p_protected_person_id: "22222222-2222-4222-8222-222222222222",
      p_transaction_id: "33333333-3333-4333-8333-333333333333",
      p_intent: "replace",
      p_client_request_id: "44444444-4444-4444-8444-444444444444",
    },
  }]);
});

test("l’identifiant d’idempotence permet une reprise et distingue une nouvelle écriture", () => {
  const base = {
    personId: "22222222-2222-4222-8222-222222222222",
    transactionId: "33333333-3333-4333-8333-333333333333",
    intent: "replace",
    existingDocumentId: "55555555-5555-4555-8555-555555555555",
    existingUpdatedAt: "2026-10-20T10:00:00.000Z",
    bytes: new Uint8Array([1, 2, 3]),
  };
  const first = createTransactionProofRequestId(base);
  assert.match(first, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(createTransactionProofRequestId({ ...base, bytes: new Uint8Array([1, 2, 3]) }), first);
  assert.notEqual(createTransactionProofRequestId({ ...base, bytes: new Uint8Array([1, 2, 4]) }), first);
  assert.notEqual(createTransactionProofRequestId({ ...base, existingUpdatedAt: "2026-10-20T10:01:00.000Z" }), first);
});

test("une réservation refusée ou invalide ne lance pas une opération ambiguë", async () => {
  await assert.rejects(reserveTransactionProofOperation({
    async rpc() { return { data: null, error: { code: "P4O01" } }; },
  }, {
    personId: "22222222-2222-4222-8222-222222222222",
    transactionId: "33333333-3333-4333-8333-333333333333",
    intent: "create",
    clientRequestId: "44444444-4444-4444-8444-444444444444",
  }), /réservation/);
  await assert.rejects(reserveTransactionProofOperation({
    async rpc() { return { data: "not-an-id", error: null }; },
  }, {
    personId: "22222222-2222-4222-8222-222222222222",
    transactionId: "33333333-3333-4333-8333-333333333333",
    intent: "create",
    clientRequestId: "44444444-4444-4444-8444-444444444444",
  }), /invalide/);
});

test("création et remplacement utilisent exclusivement le contrat DOC2 authentifié", () => {
  assert.match(service, /intent: existing \? "replace" : "create"/);
  assert.match(durable, /reserveTransactionProofOperation\(input\.client, input\)/);
  assert.match(durable, /\.storage\.from\("transaction-proofs"\)\.upload\(/);
  assert.match(durable, /upsert: false/);
  assert.match(durable, /metadata: \{ sha256 \}/);
  assert.match(durable, /finalize_transaction_proof_version/);
  assert.match(durable, /storageObjectId = reservation\.storageObjectId \?\? null/);
  assert.match(durable, /if \(response\.error\) response = await client\.rpc\("finalize_transaction_proof_version", args\)/);
  assert.doesNotMatch(durable, /storage\.info|service_role|createServerDocumentOperationEngine/);
  assert.match(service, /createTransactionProofRequestId\(/);
});

test("la suppression dédiée reste inaccessible par défaut et conserve les lectures", () => {
  assert.match(route, /export async function GET/);
  assert.match(route, /createSignedUrl/);
  assert.match(route, /export async function DELETE/);
  assert.match(service, /Le retrait sécurisé des anciennes versions n’est pas encore disponible\./);
  assert.match(route, /headers: error\.status === 405 \? \{ Allow: "GET, POST" \}/);
  assert.match(editPage, /durableOperationsEnabled=\{isTransactionProofDurableOperationsEnabled\(\)\}/);
  assert.match(component, /canManage && durableOperationsEnabled && <button/);
  assert.match(component, /window\.confirm\("Supprimer définitivement ce justificatif \?"\)/);
  assert.match(component, /fetch\(endpoint, \{ method: "DELETE" \}\)/);
});

test("la suppression indirecte ne contourne pas le moteur en mode durable", () => {
  assert.match(transactionService, /rpc\("cancel_financial_transaction"/);
  assert.doesNotMatch(transactionService, /delete_transaction_with_document|\.from\("transaction-proofs"\)\.remove/);
  assert.match(actions, /transactionMutationReasonSchema\.safeParse\(formData\.get\("reason"\)\)/);
  assert.match(actions, /reason: reason\.data/);
  assert.doesNotMatch(actions, /Annulation confirmée depuis la fiche/);
});
