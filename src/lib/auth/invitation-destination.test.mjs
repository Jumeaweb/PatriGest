import assert from "node:assert/strict";
import test from "node:test";

import { getDossierInvitationLoginPath, getDossierInvitationPath } from "./invitation-destination.ts";

test("construit le chemin dédié à une invitation", () => {
  assert.equal(getDossierInvitationPath("jeton/avec espace"), "/invitation/jeton%2Favec%20espace");
});

test("conserve l'invitation dans la destination de connexion", () => {
  assert.equal(getDossierInvitationLoginPath("jeton"), "/connexion?next=%2Finvitation%2Fjeton");
});
