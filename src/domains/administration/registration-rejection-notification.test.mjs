import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  buildRegistrationRejectionNotification,
  REGISTRATION_REJECTION_NOTIFICATION_SUBJECT,
  REGISTRATION_REJECTION_SUPPORT_EMAIL,
} from "./registration-rejection-notification.ts";
import { runRegistrationReviewNotificationDelivery } from "./registration-review-notification-runner.ts";

test("le message de refus reprend le contenu validé sans motif", () => {
  const message = buildRegistrationRejectionNotification();
  assert.equal(REGISTRATION_REJECTION_NOTIFICATION_SUBJECT, "PatriGest — Réponse à votre demande d'inscription");
  assert.equal(REGISTRATION_REJECTION_SUPPORT_EMAIL, "support@jumeaweb.fr");
  assert.match(message.text, /n'a pas été acceptée/);
  assert.match(message.text, /aucun essai gratuit ne sera démarré/);
  assert.match(message.text, /support@jumeaweb\.fr/);
  assert.match(message.text, /Édité par Jumeaweb/);
  assert.match(message.html, /mailto:support@jumeaweb\.fr/);
  assert.doesNotMatch(message.text + message.html, /motif|token|dossier|document/i);
});

test("un refus normal réserve, envoie et trace le succès", async () => {
  let sent = 0;
  let providerId = "";
  const result = await runRegistrationReviewNotificationDelivery({
    reserve: async () => ({ status: "reserved", idempotencyKey: "registration-rejection:user" }),
    send: async (idempotencyKey) => {
      assert.equal(idempotencyKey, "registration-rejection:user");
      sent += 1;
      return { providerMessageId: "provider-1" };
    },
    markSent: async (value) => { providerId = value ?? ""; },
    markFailed: async () => assert.fail("aucun échec attendu"),
  });
  assert.equal(result, "sent");
  assert.equal(sent, 1);
  assert.equal(providerId, "provider-1");
});

test("une répétition déjà réservée ne provoque aucun nouvel envoi", async () => {
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

test("un échec d'envoi est contenu et enregistré sans annuler le refus", async () => {
  let failed = 0;
  const result = await runRegistrationReviewNotificationDelivery({
    reserve: async () => ({ status: "reserved", idempotencyKey: "registration-rejection:user" }),
    send: async () => { throw new Error("provider secret detail"); },
    markSent: async () => assert.fail("aucun succès attendu"),
    markFailed: async () => { failed += 1; },
  });
  assert.equal(result, "failed");
  assert.equal(failed, 1);
});

test("le raccordement serveur autorise la création seulement après un nouveau refus", () => {
  const administration = readFileSync(new URL("./services/administration-service.ts", import.meta.url), "utf8");
  const service = readFileSync(new URL("./services/registration-rejection-notification-service.ts", import.meta.url), "utf8");
  const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  const component = readFileSync(new URL("./components/registration-review-actions.tsx", import.meta.url), "utf8");
  assert.match(administration, /trySendRegistrationRejectionNotification\(userId, \{ allowCreate: true \}\)/);
  assert.match(administration, /trySendRegistrationRejectionNotification\(userId, \{ allowCreate: false \}\)/);
  assert.match(service, /autonomous_registration_status !== "rejected"/);
  assert.match(service, /idempotencyKey: `registration-rejection:\$\{userId\}`/);
  assert.match(service, /\.eq\("updated_at", existing\.updated_at\)/);
  assert.match(service, /if \(!existing\) return \{ status: "skipped" as const \}/);
  assert.match(actions, /Inscription refusée, mais l’e-mail n’a pas pu être envoyé\. Vous pouvez réessayer\./);
  assert.match(component, /Réessayer l’e-mail/);
  assert.match(component, /Seul l’envoi de l’e-mail va être retenté/);
});
