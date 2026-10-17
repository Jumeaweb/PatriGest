import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

test("le destinataire connecté peut refuser depuis les deux parcours d’invitation", async () => {
  const [directPage, recoveredPage, decisionActions] = await Promise.all([
    source("app/invitation/[token]/page.tsx"),
    source("app/invitations/page.tsx"),
    source("domains/access/components/invitation-decision-actions.tsx"),
  ]);
  assert.match(directPage, /connectedEmail\.toLowerCase\(\) === invitation\.email\.toLowerCase\(\)[\s\S]*<InvitationDecisionActions reference=\{\{ token \}\}/);
  assert.match(recoveredPage, /<InvitationDecisionActions reference=\{\{ invitationId: invitation\.id \}\}/);
  assert.match(decisionActions, /Refuser l’invitation/);
  assert.match(decisionActions, /title="Refuser cette invitation \?"/);
  assert.match(decisionActions, /Confirmer le refus/);
});

test("le refus utilise l’unique action serveur et ne transmet jamais le hash au client", async () => {
  const [actions, decisionActions, recoveredPage] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/components/invitation-decision-actions.tsx"),
    source("app/invitations/page.tsx"),
  ]);
  assert.match(decisionActions, /declineDossierInvitationAction\.bind\(null, reference\)/);
  assert.match(actions, /const tokenHash = "token" in parsedReference/);
  assert.match(actions, /getRecoverableInvitationTokenHash\(userId, parsedReference\.invitationId\)/);
  assert.match(actions, /rpc\("decline_protected_person_invitation"/);
  assert.doesNotMatch(decisionActions, /token_hash|tokenHash/);
  assert.doesNotMatch(recoveredPage, /token_hash|tokenHash/);
});

test("un refus réussi retire l’acceptation et propose une navigation sûre", async () => {
  const [actions, decisionActions, directPage] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/components/invitation-decision-actions.tsx"),
    source("app/invitation/[token]/page.tsx"),
  ]);
  assert.match(decisionActions, /if \(declineState\.status === "success"\)/);
  assert.match(actions, /Invitation refusée\. Aucun accès au dossier n’a été créé\./);
  assert.match(decisionActions, /href="\/tableau-de-bord"/);
  assert.match(directPage, /result\.status === "declined"/);
  assert.match(directPage, /Cette invitation a été refusée et ne peut plus être acceptée\./);
});

test("l’historique propriétaire conserve Refusée sans action inappropriée", async () => {
  const [status, ownerPage, invitationActions] = await Promise.all([
    source("domains/access/invitation-status.ts"),
    source("app/dossiers/[protectedPersonId]/acces/page.tsx"),
    source("domains/access/components/invitation-actions.tsx"),
  ]);
  assert.match(status, /declined: "Refusée"/);
  assert.match(ownerPage, /dossierInvitationStatusLabels\[invitation\.status\]/);
  assert.match(invitationActions, /status === "pending" \|\| status === "expired"/);
  assert.match(invitationActions, /status === "pending"/);
  assert.doesNotMatch(invitationActions, /status === "declined"/);
});

test("les erreurs de refus restent perceptibles et sans détail technique", async () => {
  const [actions, decisionActions] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/components/invitation-decision-actions.tsx"),
  ]);
  assert.match(actions, /return \{ status: "error", message: "Invitation invalide ou expirée\." \}/);
  assert.match(decisionActions, /role="alert" aria-live="assertive"/);
  assert.doesNotMatch(decisionActions, /console\.|p_token_hash|SQL/);
});
