import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  buildRegistrationReviewNotification,
  REGISTRATION_REVIEW_NOTIFICATION_RECIPIENT,
  REGISTRATION_REVIEW_NOTIFICATION_SUBJECT,
  REGISTRATION_REVIEW_URL,
} from "./registration-review-notification.ts";
import { runRegistrationReviewNotificationDelivery } from "./registration-review-notification-runner.ts";

test("l'alerte contient uniquement les informations administratives attendues", () => {
  const message = buildRegistrationReviewNotification({
    firstName: "Alice",
    lastName: "Martin",
    email: "alice@example.test",
    requestedAt: "2026-11-09T08:00:00.000Z",
  });

  assert.equal(REGISTRATION_REVIEW_NOTIFICATION_RECIPIENT, "support@jumeaweb.fr");
  assert.equal(REGISTRATION_REVIEW_NOTIFICATION_SUBJECT, "PatriGest — Nouvelle inscription à valider");
  assert.equal(REGISTRATION_REVIEW_URL, "https://patrigest.fr/administration/inscriptions");
  assert.match(message.text, /Alice Martin/);
  assert.match(message.text, /alice@example\.test/);
  assert.match(message.text, /9 novembre 2026/);
  assert.match(message.html, /Examiner l’inscription/);
  assert.doesNotMatch(message.text + message.html, /token|dossier|document/i);
});

test("une réservation déjà traitée ne provoque aucun nouvel envoi", async () => {
  let sends = 0;
  const result = await runRegistrationReviewNotificationDelivery({
    reserve: async () => ({ status: "skipped" }),
    send: async () => { sends += 1; return { providerMessageId: null }; },
    markSent: async () => undefined,
    markFailed: async () => undefined,
  });
  assert.equal(result, "skipped");
  assert.equal(sends, 0);
});

test("un échec est enregistré sans remonter dans le parcours de confirmation", async () => {
  let failed = 0;
  const result = await runRegistrationReviewNotificationDelivery({
    reserve: async () => ({ status: "reserved", idempotencyKey: "registration-review:user" }),
    send: async () => { throw new Error("provider secret detail"); },
    markSent: async () => assert.fail("aucun succès attendu"),
    markFailed: async () => { failed += 1; },
  });
  assert.equal(result, "failed");
  assert.equal(failed, 1);
});

test("callback et connexion tentent l'alerte après authentification sans changer l'activation", () => {
  const callback = readFileSync(new URL("../../app/auth/callback/route.ts", import.meta.url), "utf8");
  const actions = readFileSync(new URL("../../app/(auth)/actions.ts", import.meta.url), "utf8");
  const service = readFileSync(new URL("./services/registration-review-notification-service.ts", import.meta.url), "utf8");

  assert.match(callback, /trySendPendingRegistrationNotification\(userId\)/);
  assert.match(actions, /trySendPendingRegistrationNotification\(data\.user\.id\)/);
  assert.match(service, /email_confirmed_at/);
  assert.match(service, /registration_intent !== "autonomous"/);
  assert.match(service, /autonomous_registration_status !== "pending"/);
  assert.match(service, /idempotencyKey: `registration-review:\$\{userId\}`/);
  assert.doesNotMatch(service, /throw new Error\("\[PatriGest\] Alerte/);
});
