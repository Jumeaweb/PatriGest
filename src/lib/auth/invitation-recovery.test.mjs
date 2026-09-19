import assert from "node:assert/strict";
import test from "node:test";

import {
  getInvitationRecoveryDestination,
  selectRecoverableInvitations,
} from "./invitation-recovery.ts";

const invitationA = { id: "11111111-1111-4111-8111-111111111111", dossierName: "A" };
const invitationB = { id: "22222222-2222-4222-8222-222222222222", dossierName: "B" };

test("reprend exactement l'invitation ayant initié le parcours Auth", () => {
  assert.equal(
    getInvitationRecoveryDestination([invitationA, invitationB], invitationA.id),
    `/invitations?invitation=${invitationA.id}`,
  );
  assert.deepEqual(selectRecoverableInvitations([invitationA, invitationB], invitationA.id), [invitationA]);
});

test("une invitation d'origine devenue invalide ne sélectionne pas arbitrairement une autre invitation", () => {
  assert.equal(getInvitationRecoveryDestination([invitationA, invitationB], "33333333-3333-4333-8333-333333333333"), "/invitations");
  assert.deepEqual(
    selectRecoverableInvitations([invitationA, invitationB], "33333333-3333-4333-8333-333333333333"),
    [invitationA, invitationB],
  );
});

test("la perte de la référence avec une seule invitation conserve la récupération unique", () => {
  assert.equal(getInvitationRecoveryDestination([invitationB], null), "/invitations");
  assert.deepEqual(selectRecoverableInvitations([invitationB], null), [invitationB]);
});

test("aucune invitation récupérable ne produit de destination", () => {
  assert.equal(getInvitationRecoveryDestination([], invitationA.id), null);
});
