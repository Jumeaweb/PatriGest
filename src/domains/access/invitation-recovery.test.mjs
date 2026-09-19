import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { canRecoverDossierInvitations } from "./invitation-recovery-policy.ts";

const read = (relativePath) => readFileSync(new URL(relativePath, import.meta.url), "utf8");
const services = read("./services.ts");
const actions = read("./actions.ts");
const recoveryPage = read("../../app/invitations/page.tsx");
const invitationPage = read("../../app/invitation/[token]/page.tsx");
const authActions = read("../../app/(auth)/actions.ts");
const callback = read("../../app/auth/callback/route.ts");
const waitingPage = read("../../app/acces-en-attente/page.tsx");

test("une identité confirmée pending ou active peut reprendre ses invitations", () => {
  for (const authorizationStatus of ["pending", "active"]) {
    assert.equal(canRecoverDossierInvitations({ emailConfirmed: true, authorizationStatus, platformAdministrator: false }), true);
  }
});

test("un compte non confirmé, rejeté ou administrateur ne contourne pas l'activation", () => {
  assert.equal(canRecoverDossierInvitations({ emailConfirmed: false, authorizationStatus: "pending", platformAdministrator: false }), false);
  assert.equal(canRecoverDossierInvitations({ emailConfirmed: true, authorizationStatus: "rejected", platformAdministrator: false }), false);
  assert.equal(canRecoverDossierInvitations({ emailConfirmed: true, authorizationStatus: null, platformAdministrator: false }), false);
  assert.equal(canRecoverDossierInvitations({ emailConfirmed: true, authorizationStatus: "pending", platformAdministrator: true }), false);
});

test("la reprise ne charge que les invitations exactes encore valides", () => {
  assert.match(services, /\.eq\("email", identity\.email\)/);
  assert.match(services, /\.is\("accepted_at", null\)/);
  assert.match(services, /\.is\("revoked_at", null\)/);
  assert.match(services, /\.gt\("expires_at", new Date\(\)\.toISOString\(\)\)/);
});

test("aucun hash d'invitation n'est renvoyé par le modèle de reprise", () => {
  const publicModel = services.slice(services.indexOf("export type RecoverableDossierInvitation"), services.indexOf("async function getVerifiedInvitationIdentity"));
  assert.doesNotMatch(publicModel, /token_hash/);
  assert.doesNotMatch(recoveryPage, /token_hash/);
});

test("l'acceptation retrouvée exige que l'id appartienne aux invitations de l'identité vérifiée", () => {
  assert.match(actions, /getRecoverableDossierInvitations\(userId\)/);
  assert.match(actions, /\.some\(\(invitation\) => invitation\.id === parsedInvitationId\)/);
  assert.match(actions, /rpc\("accept_protected_person_invitation", \{ p_token_hash: invitation\.token_hash \}\)/);
});

test("plusieurs invitations sont toutes présentées sans sélection arbitraire", () => {
  assert.match(recoveryPage, /invitations\.map\(\(invitation\)/);
  assert.match(recoveryPage, /Choisissez explicitement l’invitation à accepter/);
  assert.doesNotMatch(recoveryPage, /invitations\[0\]/);
});

test("la session d'une autre identité propose une déconnexion avec reprise", () => {
  assert.match(invitationPage, /Se déconnecter et continuer avec/);
  assert.match(invitationPage, /continueDossierInvitationAsIntendedUserAction\.bind\(null, token\)/);
  assert.match(actions, /auth\.signOut\(\{ scope: "local" \}\)[\s\S]*if \(error\) throw new Error\("Impossible de changer de compte pour le moment\."\)/);
  assert.match(actions, /redirect\(getDossierInvitationPath\(parsedToken\)\)/);
});

test("la page publique n'énumère plus l'existence d'un compte Auth", () => {
  assert.doesNotMatch(invitationPage, /accountExists/);
  assert.match(invitationPage, /J’ai déjà un compte/);
  assert.match(invitationPage, /Créer ou finaliser mon compte/);
});

test("callback, login ultérieur et écran d'attente reprennent l'invitation", () => {
  assert.match(callback, /hasRecoverableDossierInvitations\(userId\)/);
  assert.match(authActions, /hasRecoverableDossierInvitations\(data\.user\.id\)/);
  assert.match(waitingPage, /authorization\?\.status === "pending"/);
  assert.match(waitingPage, /hasRecoverableDossierInvitations\(userId\)/);
});

test("l'inscription ordinaire conserve l'écran d'approbation", () => {
  assert.match(callback, /hasApplicationAccess \? "\/tableau-de-bord" : "\/acces-en-attente"/);
  assert.match(waitingPage, /Votre inscription est en cours de validation/);
});

test("l'acceptation retrouvée conserve la redirection vers le tableau de bord du dossier", () => {
  assert.match(actions, /acceptRecoveredDossierInvitationAction[\s\S]*redirect\(`\/dossiers\/\$\{data\}\/tableau-de-bord`\)/);
});
