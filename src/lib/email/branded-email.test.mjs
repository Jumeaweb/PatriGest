import assert from "node:assert/strict";
import test from "node:test";

import { buildBrandedEmailHtml } from "./branded-email.mjs";

test("le gabarit partagé applique l’identité PatriGest et une structure mobile", () => {
  const html = buildBrandedEmailHtml({
    appName: "PatriGest",
    actionUrl: "https://patrigest.fr/action?a=1&b=2",
    actionLabel: "Continuer",
    title: "Titre",
    paragraphs: ["Contenu"],
  });
  assert.match(html, /https:\/\/patrigest\.fr\/logos\/patrigest-symbol\.png/);
  assert.match(html, /background:#f8f6e9/);
  assert.match(html, /background:#dcecea/);
  assert.match(html, /color:#214660/);
  assert.match(html, /background:#ea580c/);
  assert.match(html, /max-width:600px/);
  assert.match(html, /name="viewport"/);
  assert.match(html, /a=1&amp;b=2/);
});

test("le gabarit échappe tout contenu dynamique", () => {
  const html = buildBrandedEmailHtml({
    appName: "PatriGest <test>",
    actionUrl: "https://patrigest.fr/action",
    actionLabel: "<Continuer>",
    title: "<script>",
    greeting: "Bonjour A & B,",
    paragraphs: ["Texte <dangereux>"],
    items: ["Dossier A & B"],
  });
  assert.doesNotMatch(html, /<script>|<dangereux>|<Continuer>/);
  assert.match(html, /PatriGest &lt;test&gt;/);
  assert.match(html, /Bonjour A &amp; B,/);
  assert.match(html, /Dossier A &amp; B/);
});
