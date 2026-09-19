import assert from "node:assert/strict";
import test from "node:test";

import { buildDossierInvitationEmail } from "./invitation-presentation.ts";

test("l'e-mail identifie l'invitant, le dossier et le rôle", () => {
  const content = buildDossierInvitationEmail({
    appName: "PatriGest",
    inviterName: "Jean DUPONT",
    dossierName: "Pierre DUVAL",
    role: "read_only",
    invitationUrl: "https://patrigest.fr/invitation/secret",
    expirationLabel: "20 septembre 2026 à 12:00",
  });
  for (const value of ["Jean DUPONT", "Pierre DUVAL", "Lecture seule"]) {
    assert.match(content.text, new RegExp(value));
    assert.match(content.html, new RegExp(value));
  }
  assert.equal(content.subject, "Invitation à accéder à un dossier PatriGest");
});

test("le contenu HTML échappe les noms et conserve uniquement l'URL d'invitation fournie", () => {
  const content = buildDossierInvitationEmail({
    appName: "PatriGest",
    inviterName: "Jean <script>",
    dossierName: "Pierre & Paul",
    role: "manager",
    invitationUrl: "https://patrigest.fr/invitation/secret?a=1&b=2",
    expirationLabel: "demain",
  });
  assert.doesNotMatch(content.html, /<script>/);
  assert.match(content.html, /Jean &lt;script&gt;/);
  assert.match(content.html, /Pierre &amp; Paul/);
  assert.match(content.html, /a=1&amp;b=2/);
  assert.doesNotMatch(content.html, /token_hash|protected_person_id|invited_by/);
});
