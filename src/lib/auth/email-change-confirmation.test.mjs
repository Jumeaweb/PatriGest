import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  DEFAULT_EMAIL_CHANGE_NEXT_PATH,
  getEmailChangeConfirmationState,
  getEmailChangeResultPath,
  getSafeEmailChangeNextPath,
  parseEmailChangeConfirmationParams,
} from "./email-change-confirmation.ts";

const tokenHash = "a".repeat(64);

test("accepte uniquement un TokenHash email_change complet", () => {
  assert.deepEqual(parseEmailChangeConfirmationParams(new URLSearchParams({
    token_hash: tokenHash,
    type: "email_change",
    next: DEFAULT_EMAIL_CHANGE_NEXT_PATH,
  })), { tokenHash, nextPath: DEFAULT_EMAIL_CHANGE_NEXT_PATH });

  for (const params of [
    {},
    { token_hash: tokenHash },
    { token_hash: tokenHash, type: "recovery" },
    { token_hash: "court", type: "email_change" },
    { token_hash: `${tokenHash} espace`, type: "email_change" },
  ]) {
    assert.equal(parseEmailChangeConfirmationParams(new URLSearchParams(params)), null);
  }
});

test("refuse les open redirects et limite next à l’onglet e-mail du compte", () => {
  for (const unsafe of ["https://evil.example", "//evil.example", "/administration", "/parametres/compte?vue=profil"]) {
    assert.equal(getSafeEmailChangeNextPath(unsafe), DEFAULT_EMAIL_CHANGE_NEXT_PATH);
  }
  assert.equal(getSafeEmailChangeNextPath(DEFAULT_EMAIL_CHANGE_NEXT_PATH), DEFAULT_EMAIL_CHANGE_NEXT_PATH);
});

test("distingue première confirmation, finalisation et vraie erreur dans les deux ordres", () => {
  for (const order of ["ancienne-puis-nouvelle", "nouvelle-puis-ancienne"]) {
    assert.equal(getEmailChangeConfirmationState(null, null), "first-confirmed", order);
    assert.equal(getEmailChangeConfirmationState(null, { id: "user" }), "completed", order);
  }
  assert.equal(getEmailChangeConfirmationState({ code: "otp_expired" }, null), "error");
});

test("le handler TokenHash ne dépend ni d’un code PKCE ni de claims", () => {
  const route = readFileSync(new URL("../../app/auth/email-change/confirm/route.ts", import.meta.url), "utf8");
  assert.match(route, /verifyOtp\(\{[\s\S]*token_hash: confirmation\.tokenHash,[\s\S]*type: "email_change"/);
  assert.doesNotMatch(route, /exchangeCodeForSession|getClaims|code_verifier/);
  assert.match(route, /Cache-Control", "private, no-store"/);
});

test("la première confirmation reste un succès sans session et la seconde a un retour sûr", () => {
  assert.match(getEmailChangeResultPath("first-confirmed"), /state=first-confirmed/);
  assert.match(getEmailChangeResultPath("completed"), /state=completed/);
  assert.equal(getEmailChangeResultPath("error"), "/changement-adresse-email?state=error");

  const page = readFileSync(new URL("../../app/(auth)/changement-adresse-email/page.tsx", import.meta.url), "utf8");
  assert.match(page, /Première confirmation enregistrée/);
  assert.match(page, /Confirmez maintenant le lien envoyé à l’autre adresse/);
  assert.match(page, /Adresse e-mail modifiée/);
  assert.match(page, /invalide ou a expiré/);
});

test("le callback générique conserve les flux PKCE existants", () => {
  const callback = readFileSync(new URL("../../app/auth/callback/route.ts", import.meta.url), "utf8");
  assert.match(callback, /exchangeCodeForSession\(code\)/);
  assert.match(callback, /nouveau-mot-de-passe/);
  assert.match(callback, /invitation/);
});
