import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getSafeAuthCallbackNextPath } from "./callback-destination.ts";

test("accepte les destinations internes prévues pour les parcours Auth", () => {
  assert.equal(getSafeAuthCallbackNextPath("/parametres/compte"), "/parametres/compte");
  assert.equal(getSafeAuthCallbackNextPath("/nouveau-mot-de-passe"), "/nouveau-mot-de-passe");
  assert.equal(getSafeAuthCallbackNextPath("/invitation/jeton?source=email"), "/invitation/jeton?source=email");
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
  assert.match(source, /hasApplicationAccess \? "\/tableau-de-bord" : "\/acces-en-attente"/);
  assert.match(source, /nextPath\?\.startsWith\("\/invitation\/"\) \|\| nextPath === "\/nouveau-mot-de-passe"/);
  assert.match(source, /nextPath === "\/parametres\/compte" && hasApplicationAccess/);
});
