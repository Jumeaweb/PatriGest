import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getSafeAuthCallbackNextPath } from "./callback-destination.ts";

test("accepte les destinations internes prévues pour les parcours Auth", () => {
  assert.equal(getSafeAuthCallbackNextPath("/parametres/compte"), "/parametres/compte");
  assert.equal(getSafeAuthCallbackNextPath("/parametres/compte?vue=email"), "/parametres/compte?vue=email");
  assert.equal(getSafeAuthCallbackNextPath("/invitations"), "/invitations");
  assert.equal(getSafeAuthCallbackNextPath("/nouveau-mot-de-passe"), "/nouveau-mot-de-passe");
  assert.equal(
    getSafeAuthCallbackNextPath("/nouveau-mot-de-passe?next=%2Finvitation%2Fjeton"),
    "/nouveau-mot-de-passe?next=%2Finvitation%2Fjeton",
  );
  assert.equal(getSafeAuthCallbackNextPath("/invitation/jeton?source=email"), "/invitation/jeton?source=email");
});

test("limite le retour Mon compte au seul onglet e-mail attendu", () => {
  for (const value of [
    "/parametres/compte?vue=security",
    "/parametres/compte?vue=email&next=/administration",
    "/parametres/compte?vue=email&vue=security",
    "/parametres/compte?vue=email#fragment",
  ]) {
    assert.equal(getSafeAuthCallbackNextPath(value), null);
  }
});

test("refuse les URL absolues et les schémas externes", () => {
  for (const value of ["https://evil.example", "http://evil.example", "javascript:alert(1)"]) {
    assert.equal(getSafeAuthCallbackNextPath(value), null);
  }
});

test("refuse les destinations relatives au protocole ou interprétables hors origine", () => {
  for (const value of ["//evil.example", "/\\evil.example", "///evil.example"]) {
    assert.equal(getSafeAuthCallbackNextPath(value), null);
  }
});

test("préserve le fallback du callback lorsque next est absent, invalide ou non autorisé", () => {
  assert.equal(getSafeAuthCallbackNextPath(null), null);
  assert.equal(getSafeAuthCallbackNextPath("/tableau-de-bord"), null);
  assert.equal(getSafeAuthCallbackNextPath("parametres/compte"), null);
});

test("le callback conserve ses destinations par défaut selon l’accès applicatif", () => {
  const source = readFileSync(new URL("../../app/auth/callback/route.ts", import.meta.url), "utf8");
  assert.match(source, /exchangeCodeForSession\(code\)/);
  assert.match(source, /hasApplicationAccess \? "\/tableau-de-bord" : "\/acces-en-attente"/);
  assert.match(source, /nextPath\?\.startsWith\("\/invitation\/"\) \|\| nextPath\?\.startsWith\("\/nouveau-mot-de-passe"\)/);
  assert.match(source, /nextPath === "\/parametres\/compte\?vue=email"/);
  assert.match(source, /&& hasApplicationAccess/);
  assert.match(source, /invitationRecoveryPath/);
});

test("le callback masque les erreurs Supabase derrière un retour générique", () => {
  const source = readFileSync(new URL("../../app/auth/callback/route.ts", import.meta.url), "utf8");
  assert.match(source, /\/connexion\?erreur=confirmation/);
  assert.doesNotMatch(source, /error_description/);
  assert.doesNotMatch(source, /error\.message/);
  assert.doesNotMatch(source, /error_code/);
});
