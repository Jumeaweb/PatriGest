import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  loadTransactionDocumentsInBatches,
  TRANSACTION_DOCUMENT_BATCH_SIZE,
} from "./transaction-document-batches.ts";

const service = readFileSync(new URL("./transaction-service.ts", import.meta.url), "utf8");

test("les justificatifs sont chargés par lots de 100 puis fusionnés", async () => {
  const transactionIds = Array.from({ length: 205 }, (_, index) => `transaction-${index}`);
  const calls = [];

  const documents = await loadTransactionDocumentsInBatches(transactionIds, async (batch) => {
    calls.push([...batch]);
    return batch.map((transaction_id) => ({ transaction_id }));
  });

  assert.equal(TRANSACTION_DOCUMENT_BATCH_SIZE, 100);
  assert.deepEqual(calls.map((batch) => batch.length), [100, 100, 5]);
  assert.ok(calls.every((batch) => batch.length <= 100));
  assert.deepEqual(documents.map((document) => document.transaction_id), transactionIds);
});

test("les documents fusionnés conservent le comptage par transaction", async () => {
  const transactionIds = Array.from({ length: 101 }, (_, index) => `transaction-${index}`);
  const documents = await loadTransactionDocumentsInBatches(transactionIds, async (batch) =>
    batch.flatMap((transaction_id) => transaction_id === "transaction-100"
      ? [{ transaction_id }, { transaction_id }]
      : [{ transaction_id }]),
  );
  const attachmentCounts = new Map();
  for (const document of documents) {
    attachmentCounts.set(document.transaction_id, (attachmentCounts.get(document.transaction_id) ?? 0) + 1);
  }

  assert.equal(attachmentCounts.get("transaction-0"), 1);
  assert.equal(attachmentCounts.get("transaction-100"), 2);
  assert.match(service, /attachmentCount: attachmentCounts\.get\(transaction\.id\) \?\? 0/);
});

test("l'échec d'un lot interrompt le chargement avec l'erreur utilisateur existante", async () => {
  const transactionIds = Array.from({ length: 205 }, (_, index) => `transaction-${index}`);
  let calls = 0;

  await assert.rejects(
    loadTransactionDocumentsInBatches(transactionIds, async () => {
      calls += 1;
      if (calls === 2) throw new Error("Impossible de charger les justificatifs.");
      return [];
    }),
    /Impossible de charger les justificatifs\./,
  );
  assert.equal(calls, 2);
});

test("le service utilise le chargement par lots sans journal diagnostic", () => {
  assert.match(service, /loadTransactionDocumentsInBatches\(transactionIds/);
  assert.match(service, /\.in\("transaction_id", batchTransactionIds\)/);
  assert.doesNotMatch(service, /\[PatriGest\]\[diagnostic\]|queryLength|transactionDocumentsQueryLength/);
});
