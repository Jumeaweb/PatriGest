import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./services/transaction-service.ts");
const transferService = source("../transfers/services/transfer-service.ts");
const actions = source("./actions.ts");
const form = source("./components/transaction-form.tsx");
const deletion = source("./components/transaction-delete-button.tsx");
const route = source("../../app/api/dossiers/[protectedPersonId]/operations/[transactionId]/justificatif/route.ts");
const reads = source("./services/transaction-proof-read-service.ts");

test("les mutations ordinaires utilisent exclusivement les trois RPC sécurisées", () => {
  assert.match(service, /rpc\("create_financial_transaction"/);
  assert.match(service, /rpc\("correct_financial_transaction"/);
  assert.match(service, /rpc\("cancel_financial_transaction"/);
  assert.doesNotMatch(service, /from\("transactions"\)\.insert|from\("transactions"\)\.update|delete_transaction_with_document/);
  assert.doesNotMatch(service, /storage\.from\("transaction-proofs"\)\.remove/);
});

test("les virements utilisent exclusivement les RPC atomiques et versionnées", () => {
  assert.match(transferService, /rpc\("create_internal_transfer_v2"/);
  assert.match(transferService, /rpc\("cancel_internal_transfer_v2"/);
  assert.doesNotMatch(transferService, /rpc\("create_internal_transfer"|rpc\("delete_internal_transfer"/);
  assert.match(actions, /await createTransfer\(personId, parsed\.data, \{ requestId: requestId\.data \}\)/);
  assert.match(actions, /expectedRevision: revision\.data, requestId: requestId\.data, reason: reason\.data/);
  assert.match(deletion, /Annuler le virement/);
  assert.doesNotMatch(deletion, /Supprimer le virement/);
});

test("révision, motif et clé idempotente traversent les actions", () => {
  assert.match(actions, /expectedRevision: revision\.data/);
  assert.match(actions, /requestId: requestId\.data/);
  assert.ok((actions.match(/transactionMutationReasonSchema\.safeParse\(formData\.get\("reason"\)\)/g) ?? []).length >= 2);
  assert.match(actions, /reason: reason\.data/);
  assert.match(form, /name="clientRequestId"/);
  assert.match(form, /name="expectedRevision" value=\{transaction\.revision\}/);
  assert.match(deletion, /name="clientRequestId"/);
  assert.match(deletion, /name="expectedRevision" value=\{transactionRevision\}/);
  assert.match(deletion, /name="reason" required minLength=\{3\}/);
});

test("le journal conserve les annulations visibles et permet leur exclusion explicite", () => {
  assert.equal((service.match(/if \(filters\.includeCancelled === false\) query = query\.is\("cancelled_at", null\)/g) ?? []).length, 2);
});

test("la route expose les versions courantes et historiques sans chemin public", () => {
  assert.match(route, /searchParams\.get\("history"\) === "1"/);
  assert.match(route, /searchParams\.get\("versionId"\)/);
  assert.match(route, /createSignedUrl\(proof\.storagePath/);
  assert.match(reads, /transaction_proof_versions/);
  assert.match(reads, /transaction_document_history/);
  assert.match(reads, /can|readableTransaction/);
  assert.match(reads, /void storagePath/);
});
