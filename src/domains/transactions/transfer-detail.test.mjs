import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { resolveUnifiedTransferDetail } from "./transfer-detail.ts";

const transferId = "11111111-1111-4111-8111-111111111111";
const sourceId = "22222222-2222-4222-8222-222222222222";
const destinationId = "33333333-3333-4333-8333-333333333333";
const sourceAccountId = "44444444-4444-4444-8444-444444444444";
const destinationAccountId = "55555555-5555-4555-8555-555555555555";
const transfer = { id: transferId, source_account_id: sourceAccountId, destination_account_id: destinationAccountId, transfer_date: "2026-11-05", amount: 20, revision: 2, cancelled_at: "2026-11-05T10:00:00Z" };
const source = { id: sourceId, transfer_id: transferId, transfer, transaction_type: "transfer_out", financial_account_id: sourceAccountId, amount: 20, label: "Épargne", account: { id: sourceAccountId, account_name: "Compte courant" } };
const destination = { id: destinationId, transfer_id: transferId, transfer, transaction_type: "transfer_in", financial_account_id: destinationAccountId, amount: 20, label: "Épargne", account: { id: destinationAccountId, account_name: "Livret" } };

test("les deux mouvements résolvent le même virement unifié", () => {
  const fromSource = resolveUnifiedTransferDetail([source, destination], sourceId);
  const fromDestination = resolveUnifiedTransferDetail([source, destination], destinationId);
  assert.ok(fromSource);
  assert.ok(fromDestination);
  assert.equal(fromSource.transfer.id, transferId);
  assert.equal(fromDestination.transfer.id, transferId);
  assert.equal(fromSource.sourceMovement.id, sourceId);
  assert.equal(fromDestination.sourceMovement.id, sourceId);
  assert.equal(fromSource.destinationMovement.id, destinationId);
  assert.equal(fromDestination.destinationMovement.id, destinationId);
});

test("un mouvement isolé ne produit pas une fiche partielle", () => {
  assert.equal(resolveUnifiedTransferDetail([source], sourceId), null);
});

test("la fiche présente les deux mouvements, le statut et l'historique global", () => {
  const page = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/[transactionId]/page.tsx", import.meta.url), "utf8");
  const history = readFileSync(new URL("./components/transfer-change-history.tsx", import.meta.url), "utf8");
  const service = readFileSync(new URL("./services/transaction-change-service.ts", import.meta.url), "utf8");
  assert.match(page, /resolveUnifiedTransferDetail\(transactions, transactionId\)/);
  assert.match(page, /Compte de départ/);
  assert.match(page, /Compte d’arrivée/);
  assert.match(page, /direction="out"/);
  assert.match(page, /direction="in"/);
  assert.match(page, /cancelled \? "Annulé" : "Actif"/);
  assert.match(page, /Mouvement historique — sans effet sur le solde actuel/);
  assert.match(page, /cancellation\?\.reason/);
  assert.match(page, /transactionRevision=\{transfer\.revision\}/);
  assert.match(page, /transferId=\{transfer\.id\}/);
  assert.match(history, /Historique du virement/);
  assert.match(history, /Annulation du virement/);
  assert.match(service, /from\("transfer_changes"\)/);
});

test("l'annulation unique reste masquée pour les états non modifiables", () => {
  const page = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/[transactionId]/page.tsx", import.meta.url), "utf8");
  assert.match(page, /person\.accessRole !== "read_only" && !archived && !closed && !cancelled/);
  assert.match(page, /canManage && <TransactionDeleteButton/);
  assert.match(page, /cancel_internal_transfer_v2|TransactionDeleteButton/);
});
