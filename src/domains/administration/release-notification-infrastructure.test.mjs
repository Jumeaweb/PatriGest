import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = read("./services/release-notification-service.ts");
const actions = read("./actions.ts");
const panel = read("./components/release-notification-panel.tsx");
const transport = read("../../lib/email/resend-transport.ts");
const invitation = read("../access/invitation-email.ts");
const activation = read("./registration-email.ts");
const migration = read("../../../supabase/migrations/20260923100000_create_release_notifications.sql");

test("le transport Resend partagé reste strictement serveur et conserve l'expéditeur", () => {
  assert.match(transport, /import "server-only"/);
  assert.match(transport, /process\.env\.RESEND_API_KEY/);
  assert.match(transport, /noreply@patrigest\.fr/);
  assert.doesNotMatch(transport, /replyTo|reply_to/);
  assert.match(invitation, /sendEmailWithResend/);
  assert.match(activation, /sendEmailWithResend/);
});

test("les actions test et globale revérifient l'administration dans le service", () => {
  assert.match(actions, /sendTestReleaseNotification/);
  assert.match(actions, /sendGlobalReleaseNotifications/);
  assert.ok((service.match(/requirePlatformAdministrator\(\)/g) ?? []).length >= 3);
  assert.match(service, /Version PatriGest inconnue/);
});

test("le test n'accepte qu'un userId éligible et possède une idempotence distincte", () => {
  assert.match(actions, /userId: z\.uuid\(\)/);
  assert.doesNotMatch(actions, /email: z\.email/);
  assert.match(service, /recipients\.find\(\(candidate\) => candidate\.userId === targetUserId\)/);
  assert.match(service, /delivery_kind: "test"/);
  assert.match(service, /release-test:\$\{version\}:\$\{notification\.id\}/);
  assert.match(service, /getReleaseMessage\(version, recipient\)/);
});

test("l'envoi global réserve en DB, relance seulement failed et utilise une clé stable", () => {
  assert.match(service, /delivery_kind: "global"/);
  assert.match(service, /error\.code !== "23505"/);
  assert.match(service, /existing\.status !== "failed"/);
  assert.match(service, /\.eq\("status", "failed"\)/);
  assert.match(service, /release:\$\{version\}:\$\{recipient\.userId\}/);
  assert.match(migration, /where delivery_kind = 'global'/);
});

test("le test et chaque envoi global utilisent le même générateur avec leur destinataire", () => {
  assert.match(service, /buildReleaseEmail\(\{ appName: APP_NAME, release, changelogUrl, recipient \}\)/);
  assert.match(service, /send: async \(recipient, idempotencyKey\) => \{[\s\S]*?getReleaseMessage\(version, recipient\)/);
  assert.doesNotMatch(service, /const message = buildReleaseEmail[\s\S]*?return runReleaseNotificationBatch/);
});

test("l'interface n'envoie rien à l'affichage et exige deux confirmations", () => {
  assert.match(panel, /Envoyer un e-mail de test/);
  assert.match(panel, /Informer les utilisateurs/);
  assert.match(panel, /dialog === "test" && <TestReleaseDialog/);
  assert.match(panel, /dialog === "global" && <GlobalReleaseDialog/);
  assert.match(panel, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(panel, /actions=\{succeeded \? null : <SubmitButton/);
  assert.doesNotMatch(panel, /useEffect/);
});
