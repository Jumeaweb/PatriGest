import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getDossierInvitationSentence, getInvitationRoleLabel } from "./invitation-presentation.ts";

const read = (relativePath) => readFileSync(new URL(relativePath, import.meta.url), "utf8");
const services = read("./services.ts");
const invitationPage = read("../../app/invitation/[token]/page.tsx");
const signupPage = read("../../app/(auth)/inscription/page.tsx");
const recoveryPage = read("../../app/invitations/page.tsx");
const actions = read("./actions.ts");

test("la formulation identifie l'invitant, le dossier et le rôle", () => {
  assert.equal(
    getDossierInvitationSentence({ inviterName: "Jean DUPONT", dossierName: "Pierre DUVAL" }),
    "Jean DUPONT vous invite à accéder au dossier PatriGest de Pierre DUVAL.",
  );
  assert.equal(getInvitationRoleLabel("read_only"), "Lecture seule");
  assert.equal(getInvitationRoleLabel("manager"), "Gestionnaire");
});

test("l'aperçu public ne charge le nom du dossier qu'après validation complète de l'invitation", () => {
  const statusGuard = services.indexOf('if (status !== "pending") return { status };');
  const contextLoad = services.indexOf("getDossierInvitationDisplayContext(data.protected_person_id, data.invited_by)");
  assert.ok(statusGuard >= 0 && contextLoad > statusGuard);
  assert.match(invitationPage, /getDossierInvitationSentence\(invitation\)/);
  assert.match(invitationPage, /getInvitationRoleLabel\(invitation\.role\)/);
  assert.doesNotMatch(invitationPage.slice(0, invitationPage.indexOf("const invitation = result.invitation")), /dossierName|inviterName/);
});

test("la finalisation et la récupération présentent le même contexte explicite", () => {
  assert.match(signupPage, /getDossierInvitationSentence\(invitation\)/);
  assert.match(signupPage, /getInvitationRoleLabel\(invitation\.role\)/);
  assert.match(recoveryPage, /invitation\.inviterName/);
  assert.match(recoveryPage, /invitation\.dossierName/);
  assert.match(recoveryPage, /getInvitationRoleLabel\(invitation\.role\)/);
});

test("l'e-mail reçoit uniquement le contexte d'affichage issu des données existantes", () => {
  assert.match(actions, /getDossierInvitationDisplayContext\(actor\.protectedPersonId, actor\.userId\)/);
  assert.match(actions, /getDossierInvitationDisplayContext\(actor\.protectedPersonId, source\.invited_by\)/);
  assert.match(actions, /sendDossierInvitationEmail\(\{ email: input\.email, role: input\.role, \.\.\.displayContext/);
  assert.doesNotMatch(invitationPage, /token_hash|protected_person_id|invited_by/);
  assert.doesNotMatch(recoveryPage, /token_hash|protected_person_id|invited_by/);
});
