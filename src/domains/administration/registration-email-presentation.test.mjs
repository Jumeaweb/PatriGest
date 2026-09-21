import assert from "node:assert/strict";
import test from "node:test";

import { buildApplicationActivationEmail } from "./registration-email-presentation.ts";

test("le contenu d'activation existant est conservé", () => {
  const content = buildApplicationActivationEmail({ appName: "PatriGest", firstName: "Camille", loginUrl: "https://patrigest.fr/connexion" });
  assert.equal(content.subject, "Votre accès à PatriGest est activé");
  assert.match(content.text, /Bonjour Camille,/);
  assert.match(content.text, /https:\/\/patrigest\.fr\/connexion/);
  assert.match(content.html, /Se connecter à PatriGest/);
});

test("le contenu d'activation échappe les valeurs HTML", () => {
  const content = buildApplicationActivationEmail({ appName: "PatriGest <test>", firstName: "<script>", loginUrl: "https://patrigest.fr/connexion?a=1&b=2" });
  assert.doesNotMatch(content.html, /<script>/);
  assert.match(content.html, /&lt;script&gt;/);
  assert.match(content.html, /a=1&amp;b=2/);
});
