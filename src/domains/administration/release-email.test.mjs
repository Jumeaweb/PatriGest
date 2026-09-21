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

test("l'e-mail de release reprend la source AppRelease en texte et HTML", () => {
  const content = buildReleaseEmail({ appName: "PatriGest", release, changelogUrl: "https://patrigest.fr/historique-versions" });
  assert.equal(content.subject, "PatriGest v0.8.0 — Découvrez les nouveautés");
  for (const expected of [release.title, release.summary, ...release.changes]) {
    assert.match(content.text, new RegExp(expected));
    assert.match(content.html, new RegExp(expected));
  }
  assert.match(content.text, /https:\/\/patrigest\.fr\/historique-versions/);
  assert.match(content.html, /https:\/\/patrigest\.fr\/historique-versions/);
});

test("l'e-mail de release échappe tout contenu éditorial", () => {
  const content = buildReleaseEmail({ appName: "PatriGest", release: { ...release, title: "<script>", changes: ["Dossier A & B"] }, changelogUrl: "https://patrigest.fr/historique-versions?a=1&b=2" });
  assert.doesNotMatch(content.html, /<script>/);
  assert.match(content.html, /&lt;script&gt;/);
  assert.match(content.html, /A &amp; B/);
  assert.match(content.html, /a=1&amp;b=2/);
});

test("le générateur n'ajoute aucune donnée de dossier ou jargon technique", () => {
  const content = buildReleaseEmail({ appName: "PatriGest", release, changelogUrl: "https://patrigest.fr/historique-versions" });
  assert.doesNotMatch(`${content.text}${content.html}`, /protected_person|token|RPC|migration|commit|RAPP-/i);
});
