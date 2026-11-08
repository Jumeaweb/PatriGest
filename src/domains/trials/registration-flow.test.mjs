import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function read(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const actions = read("../../app/(auth)/actions.ts");
const form = read("../../components/auth/auth-forms.tsx");
const signupPage = read("../../app/(auth)/inscription/page.tsx");
const callback = read("../../app/auth/callback/route.ts");
const waitingPage = read("../../app/acces-en-attente/page.tsx");
const administrationService = read("../administration/services/administration-service.ts");

test("l'inscription autonome conserve le consentement explicite et le depart a l'activation", () => {
  assert.match(actions, /registrationIntent === "autonomous" && parsed\.data\.trialTermsAccepted !== "on"/);
  assert.match(actions, /patrigest_trial_terms_version: ACCOUNT_TRIAL_TERMS_VERSION/);
  assert.match(actions, /recordAccountTrialTermsAcceptance\(signupData\.user\.id\)/);
  assert.match(signupPage, /commenceront uniquement lors de l.activation de votre accès/);
  assert.match(waitingPage, /commencera seulement à cette activation/);
});

test("une invitation dossier utilise le parcours collaborateur sans conditions d'essai", () => {
  assert.match(actions, /invitation\?\.kind === "dossier" \? "collaborator" : "autonomous"/);
  assert.match(actions, /registrationIntent === "autonomous"\) \{/);
  assert.match(form, /!collaboratorInvitation && <div>/);
  assert.match(signupPage, /collaboratorInvitation=\{invitation\.kind === "dossier"\}/);
});

test("la reprise du consentement reste authentifiee et ne cree pas de second compte", () => {
  assert.match(callback, /complete_own_autonomous_trial_registration/);
  assert.match(actions, /complete_own_autonomous_trial_registration/);
  assert.match(waitingPage, /sans créer un second compte/);
  assert.doesNotMatch(actions, /admin\.createUser/);
});

test("la file administrative suit le statut autonome distinct", () => {
  assert.match(administrationService, /\.eq\("registration_intent", "autonomous"\)/);
  assert.match(administrationService, /\.eq\("autonomous_registration_status", "pending"\)/);
});

test("les textes annoncent deux dossiers et les exports pendant l'essai", () => {
  assert.match(form, /limité à 2 dossiers actifs/);
  assert.match(form, /exports compris/);
  assert.doesNotMatch(form, /L.export d.archive n.est pas disponible pendant l.essai/);
});
