import assert from "node:assert/strict";
import test from "node:test";

import { RELEASE_NOTIFICATION_BATCH_SIZE, runReleaseNotificationBatch } from "./release-notification-runner.ts";

const recipients = Array.from({ length: 23 }, (_, index) => ({ userId: `user-${index}`, email: `user-${index}@example.test`, firstName: "", lastName: "" }));

test("l'envoi global traite tous les destinataires par petits lots individuels", async () => {
  const sent = [];
  const marked = [];
  const summary = await runReleaseNotificationBatch({
    recipients,
    reserve: async (recipient) => ({ status: "reserved", notificationId: recipient.userId, idempotencyKey: `release:0.8.0:${recipient.userId}` }),
    send: async (recipient, idempotencyKey) => { sent.push({ recipient, idempotencyKey }); return { providerMessageId: `provider-${recipient.userId}` }; },
    markSent: async (id, providerId) => { marked.push({ id, providerId }); },
    markFailed: async () => assert.fail("aucun échec attendu"),
  });
  assert.equal(RELEASE_NOTIFICATION_BATCH_SIZE, 10);
  assert.equal(sent.length, 23);
  assert.equal(marked.length, 23);
  assert.deepEqual(summary, { recipients: 23, alreadySent: 0, sent: 23, failed: 0 });
  assert.equal(sent[0].idempotencyKey, "release:0.8.0:user-0");
});

test("une réservation existante n'est jamais renvoyée", async () => {
  let sends = 0;
  const summary = await runReleaseNotificationBatch({
    recipients: recipients.slice(0, 2),
    reserve: async () => ({ status: "skipped" }),
    send: async () => { sends += 1; return { providerMessageId: null }; },
    markSent: async () => undefined,
    markFailed: async () => undefined,
  });
  assert.equal(sends, 0);
  assert.deepEqual(summary, { recipients: 2, alreadySent: 2, sent: 0, failed: 0 });
});

test("l'échec d'un destinataire est enregistré sans arrêter les suivants", async () => {
  const failed = [];
  const summary = await runReleaseNotificationBatch({
    recipients: recipients.slice(0, 3),
    reserve: async (recipient) => ({ status: "reserved", notificationId: recipient.userId, idempotencyKey: recipient.userId }),
    send: async (recipient) => { if (recipient.userId === "user-1") throw new Error("provider secret detail"); return { providerMessageId: recipient.userId }; },
    markSent: async () => undefined,
    markFailed: async (id) => { failed.push(id); },
  });
  assert.deepEqual(failed, ["user-1"]);
  assert.deepEqual(summary, { recipients: 3, alreadySent: 0, sent: 2, failed: 1 });
});
