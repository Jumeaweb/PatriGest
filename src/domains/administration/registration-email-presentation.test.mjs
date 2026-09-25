import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { buildApplicationActivationEmail } from "./registration-email-presentation.ts";

const service = readFileSync(new URL("./services/administration-service.ts", import.meta.url), "utf8");

test("le contenu d'activation existant est conservé", () => {
  const content = buildApplicationActivationEmail({ appName: "PatriGest", firstName: "Camille", lastName: "Martin", loginUrl: "https://patrigest.fr/connexion" });
  assert.equal(content.subject, "Votre accès à PatriGest est activé");
  assert.match(content.text, /Bonjour Camille Martin,/);
  assert.match(content.html, /Bonjour Camille Martin,/);
  assert.match(content.text, /https:\/\/patrigest\.fr\/connexion/);
  assert.match(content.html, /Se connecter à PatriGest/);
  assert.match(content.html, /\/logos\/patrigest-symbol\.png/);
  assert.match(content.html, /background:#dcecea/);
  assert.match(content.html, /background:#ea580c/);
  assert.match(content.html, /name="viewport"/);
});

test("le contenu d'activation échappe les valeurs HTML", () => {
  const content = buildApplicationActivationEmail({ appName: "PatriGest <test>", firstName: "<script>", lastName: "Martin & Fils", loginUrl: "https://patrigest.fr/connexion?a=1&b=2" });
  assert.doesNotMatch(content.html, /<script>/);
  assert.match(content.html, /&lt;script&gt;/);
  assert.match(content.html, /a=1&amp;b=2/);
  assert.match(content.html, /Martin &amp; Fils/);
});

test("la salutation d’activation gère le prénom seul et l’absence d’identité", () => {
  const firstNameOnly = buildApplicationActivationEmail({ appName: "PatriGest", firstName: " Camille ", lastName: " ", loginUrl: "https://patrigest.fr/connexion" });
  const anonymous = buildApplicationActivationEmail({ appName: "PatriGest", firstName: " ", lastName: "", loginUrl: "https://patrigest.fr/connexion" });
  assert.match(firstNameOnly.text, /^Bonjour Camille,/);
  assert.match(anonymous.text, /^Bonjour,/);
});

test("le flux d’activation réutilise le prénom et le nom du profil déjà chargé", () => {
  assert.match(service, /select\("first_name,last_name"\)/);
  assert.match(service, /firstName: profile\?\.first_name \?\? ""/);
  assert.match(service, /lastName: profile\?\.last_name \?\? ""/);
});
