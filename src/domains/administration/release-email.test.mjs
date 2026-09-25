import assert from "node:assert/strict";
import test from "node:test";

import { buildReleaseEmail } from "./release-email.ts";

const release = {
  version: "0.8.0",
  date: "2026-09-23",
  title: "Contrôle bancaire simplifié",
  summary: "PatriGest facilite le suivi de vos relevés.",
  changes: ["Comparez vos soldes", "Identifiez les opérations en circulation"],
};

function build(recipient = {}) {
  return buildReleaseEmail({ appName: "PatriGest", release, changelogUrl: "https://patrigest.fr/historique-versions", recipient });
}

test("l'e-mail de release reprend la source AppRelease en texte et HTML", () => {
  const content = build();
  assert.equal(content.subject, "PatriGest v0.8.0 — Découvrez les nouveautés");
  for (const expected of [release.title, release.summary, ...release.changes]) {
    assert.match(content.text, new RegExp(expected));
    assert.match(content.html, new RegExp(expected));
  }
  assert.match(content.text, /https:\/\/patrigest\.fr\/historique-versions/);
  assert.match(content.html, /https:\/\/patrigest\.fr\/historique-versions/);
  assert.match(content.text, /Voici les nouveautés de la version PatriGest v0\.8\.0\./);
  assert.match(content.html, /Voici les nouveautés de la version PatriGest v0\.8\.0\./);
  assert.match(content.html, /\/logos\/patrigest-symbol\.png/);
  assert.match(content.html, /background:#dcecea/);
  assert.match(content.html, /background:#ea580c/);
  assert.match(content.html, /name="viewport"/);
});

test("l'e-mail de release échappe tout contenu éditorial", () => {
  const content = buildReleaseEmail({ appName: "PatriGest", release: { ...release, title: "<script>", changes: ["Dossier A & B"] }, changelogUrl: "https://patrigest.fr/historique-versions?a=1&b=2", recipient: { firstName: "<Pierre>", lastName: "A & B" } });
  assert.doesNotMatch(content.html, /<script>/);
  assert.match(content.html, /&lt;script&gt;/);
  assert.match(content.html, /A &amp; B/);
  assert.match(content.html, /a=1&amp;b=2/);
  assert.match(content.html, /Bonjour &lt;Pierre&gt; A &amp; B,/);
  assert.doesNotMatch(content.html, /Bonjour <Pierre>/);
});

test("le générateur n'ajoute aucune donnée de dossier ou jargon technique", () => {
  const content = build();
  assert.doesNotMatch(`${content.text}${content.html}`, /protected_person|token|RPC|migration|commit|RAPP-/i);
});

test("la salutation utilise le prénom et le nom nettoyés en texte et HTML", () => {
  const content = build({ firstName: "  Pierre ", lastName: " LUCET  " });
  assert.match(content.text, /^Bonjour Pierre LUCET,/);
  assert.match(content.html, /Bonjour Pierre LUCET,/);
});

test("la salutation accepte le prénom seul", () => {
  const content = build({ firstName: " Pierre ", lastName: "   " });
  assert.match(content.text, /^Bonjour Pierre,/);
  assert.match(content.html, /Bonjour Pierre,/);
});

test("la salutation accepte le nom seul", () => {
  const content = build({ firstName: "", lastName: " LUCET " });
  assert.match(content.text, /^Bonjour LUCET,/);
  assert.match(content.html, /Bonjour LUCET,/);
});

test("la salutation reste sobre sans identité exploitable", () => {
  const content = build({ firstName: "  ", lastName: null });
  assert.match(content.text, /^Bonjour,/);
  assert.match(content.html, />Bonjour,<\/p>/);
});

test("deux destinataires reçoivent des salutations distinctes du même générateur", () => {
  const pierre = build({ firstName: "Pierre", lastName: "LUCET" });
  const marie = build({ firstName: "Marie", lastName: "DURAND" });
  assert.match(pierre.text, /^Bonjour Pierre LUCET,/);
  assert.match(marie.text, /^Bonjour Marie DURAND,/);
  assert.notEqual(pierre.text, marie.text);
});
