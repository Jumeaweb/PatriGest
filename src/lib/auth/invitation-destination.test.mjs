import assert from "node:assert/strict";
import test from "node:test";

import {
  getDossierInvitationLoginPath,
  getDossierInvitationPath,
  getDossierInvitationTokenFromPath,
} from "./invitation-destination.ts";

test("construit le chemin dédié à une invitation", () => {
  assert.equal(getDossierInvitationPath("jeton/avec espace"), "/invitation/jeton%2Favec%20espace");
});

test("conserve l'invitation dans la destination de connexion", () => {
  assert.equal(getDossierInvitationLoginPath("jeton"), "/connexion?next=%2Finvitation%2Fjeton");
});

test("retrouve uniquement un jeton d'invitation direct et suffisamment long", () => {
  const token = "a".repeat(32);
  assert.equal(getDossierInvitationTokenFromPath(getDossierInvitationPath(token)), token);
  assert.equal(getDossierInvitationTokenFromPath("/invitation/court"), null);
  assert.equal(getDossierInvitationTokenFromPath(`/invitation/${token}?source=email`), null);
  assert.equal(getDossierInvitationTokenFromPath("https://example.test/invitation/jeton"), null);
});
