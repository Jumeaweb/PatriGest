import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  getAccessPageHref,
  getInvitationHistoryPageMetadata,
  INVITATION_HISTORY_PAGE_SIZE,
  parseInvitationHistoryPage,
} from "./access-pagination.ts";
import { isCompletedAccessAction } from "./state.ts";

const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

test("la pagination de l’historique est bornée à dix éléments", () => {
  assert.equal(INVITATION_HISTORY_PAGE_SIZE, 10);
  assert.equal(parseInvitationHistoryPage(undefined), 1);
  assert.equal(parseInvitationHistoryPage("0"), 1);
  assert.equal(parseInvitationHistoryPage("invalide"), 1);
  assert.equal(parseInvitationHistoryPage(["4", "8"]), 4);
  assert.deepEqual(getInvitationHistoryPageMetadata(1001, 999), {
    page: 101,
    pageSize: 10,
    totalCount: 1001,
    totalPages: 101,
  });
});

test("les liens conservent les paramètres utiles et pilotent les deux vues", () => {
  const pathname = "/dossiers/personne/acces";
  const values = { vue: "collaborateurs", historiquePage: "7", filtre: "actif" };
  assert.equal(getAccessPageHref(pathname, values, { view: "invite", historyPage: 1 }), `${pathname}?filtre=actif`);
  assert.equal(getAccessPageHref(pathname, values, { view: "invite", historyPage: 3 }), `${pathname}?filtre=actif&historiquePage=3`);
  assert.equal(getAccessPageHref(pathname, values, { view: "collaborators" }), `${pathname}?filtre=actif&vue=collaborateurs`);
});

test("la page expose exactement les deux onglets et ouvre Inviter par défaut", async () => {
  const [page, tabs] = await Promise.all([
    source("app/dossiers/[protectedPersonId]/acces/page.tsx"),
    source("domains/access/components/access-tabs.tsx"),
  ]);
  assert.match(tabs, /label: "Inviter un collaborateur"/);
  assert.match(tabs, /label: "Collaborateurs"/);
  assert.match(page, /first\(query\.vue\) === "collaborateurs" \? "collaborators" as const : "invite" as const/);
  assert.match(page, /<AccessTabs[^>]+current=\{view\}/);
});

test("les invitations pending et historiques sont chargées séparément côté serveur", async () => {
  const services = await source("domains/access/services.ts");
  assert.match(services, /\.is\("accepted_at", null\)[\s\S]*\.is\("revoked_at", null\)[\s\S]*\.gt\("expires_at", now\)/);
  assert.match(services, /accepted_at\.not\.is\.null,revoked_at\.not\.is\.null,expires_at\.lte/);
  assert.match(services, /select\("id", \{ count: "exact", head: true \}\)/);
  assert.match(services, /\.order\("created_at", \{ ascending: false \}\)[\s\S]*\.order\("id", \{ ascending: false \}\)/);
  assert.match(services, /\.range\(from, from \+ INVITATION_HISTORY_PAGE_SIZE - 1\)/);
  assert.doesNotMatch(services, /invitationResult\.data\.map/);
});

test("la page sépare visuellement les invitations actives et l’historique paginé", async () => {
  const [page, pagination] = await Promise.all([
    source("app/dossiers/[protectedPersonId]/acces/page.tsx"),
    source("domains/access/components/invitation-history-pagination.tsx"),
  ]);
  assert.match(page, /Invitations en attente/);
  assert.match(page, /Historique des invitations/);
  assert.equal((page.match(/<InvitationHistoryPagination/g) ?? []).length, 2);
  for (const label of ["Première page", "Page précédente", "Page suivante", "Dernière page"]) assert.match(pagination, new RegExp(label));
  assert.match(pagination, /Page \{page\} sur \{totalPages\}/);
});

test("le chargement groupé supprime les appels Auth et profils par collaborateur", async () => {
  const services = await source("domains/access/services.ts");
  assert.match(services, /auth\.admin\.listUsers\(\{ page, perPage \}\)/);
  assert.match(services, /profiles[\s\S]*\.in\("id", batch\)/);
  assert.doesNotMatch(services, /Promise\.all\(\(access \?\? \[\]\)\.map/);
  assert.doesNotMatch(services, /getUserById\(entry\.user_id\)/);
});

test("la liste affiche le rôle réel en badge et aucun sélecteur permanent", async () => {
  const [page, roleDialog] = await Promise.all([
    source("app/dossiers/[protectedPersonId]/acces/page.tsx"),
    source("domains/access/components/collaborator-role-button.tsx"),
  ]);
  assert.match(page, /entry\.role === "manager" \? "Gestionnaire" : "Lecture seule"/);
  assert.doesNotMatch(page, /<select/);
  assert.match(roleDialog, /useState\(persistedRole\)/);
  assert.match(roleDialog, /setRole\(persistedRole\)/);
  assert.doesNotMatch(roleDialog, /defaultValue="read_only"/);
});

test("les fenêtres d’accès passent au message et au bouton Fermer après succès", async () => {
  const [roleDialog, removeDialog, invitationActions] = await Promise.all([
    source("domains/access/components/collaborator-role-button.tsx"),
    source("domains/access/components/collaborator-remove-button.tsx"),
    source("domains/access/components/invitation-actions.tsx"),
  ]);
  assert.match(roleDialog, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(roleDialog, /actions=\{succeeded \? null : <SaveRoleButton/);
  assert.match(removeDialog, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(removeDialog, /actions=\{succeeded \? null : <RemoveButton/);
  assert.match(invitationActions, /cancelLabel=\{reissueFinished \? "Fermer" : "Annuler"\}/);
  assert.match(invitationActions, /actions=\{revokeFinished \? null : <PendingButton/);
});

test("les états terminés distinguent succès, avertissement final et erreur réessayable", () => {
  assert.equal(isCompletedAccessAction({ status: "idle" }), false);
  assert.equal(isCompletedAccessAction({ status: "error", message: "Erreur" }), false);
  assert.equal(isCompletedAccessAction({ status: "success", message: "Terminé" }), true);
  assert.equal(isCompletedAccessAction({ status: "warning", message: "E-mail non envoyé" }), false);
  assert.equal(isCompletedAccessAction({ status: "warning", message: "Invitation créée" }, true), true);
});

test("les mutations de dialogue attendent Fermer avant de rafraîchir la page", async () => {
  const [actions, roleDialog, removeDialog, invitationActions] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/components/collaborator-role-button.tsx"),
    source("domains/access/components/collaborator-remove-button.tsx"),
    source("domains/access/components/invitation-actions.tsx"),
  ]);
  const functionBody = (name, nextName) => actions.slice(actions.indexOf(`export async function ${name}`), actions.indexOf(`export async function ${nextName}`));
  assert.doesNotMatch(functionBody("reissueDossierInvitationAction", "revokeDossierInvitationAction"), /revalidatePath/);
  assert.doesNotMatch(functionBody("revokeDossierInvitationAction", "acceptDossierInvitationAction"), /revalidatePath/);
  assert.doesNotMatch(functionBody("updateCollaboratorRoleAction", "removeCollaboratorAction"), /revalidatePath/);
  assert.doesNotMatch(actions.slice(actions.indexOf("export async function removeCollaboratorAction")), /revalidatePath/);
  assert.match(roleDialog, /function closeDialog\(\)[\s\S]*if \(succeeded\) router\.refresh\(\)/);
  assert.match(removeDialog, /function closeDialog\(\)[\s\S]*if \(succeeded\) router\.refresh\(\)/);
  assert.match(invitationActions, /function closeDialog\(\)[\s\S]*if \(refresh\) router\.refresh\(\)/);
  assert.match(roleDialog, /onClose=\{closeDialog\}/);
  assert.match(removeDialog, /onClose=\{closeDialog\}/);
  assert.equal((invitationActions.match(/onClose=\{closeDialog\}/g) ?? []).length, 2);
});

test("les protections d’accès et LOT 0A existantes restent utilisées", async () => {
  const [services, actions] = await Promise.all([
    source("domains/access/services.ts"),
    source("domains/access/actions.ts"),
  ]);
  assert.match(services, /person\.accessRole === "read_only"\) notFound\(\)/);
  assert.match(actions, /actor\.role === "manager" && input\.role !== "read_only"/);
  assert.match(actions, /issue_protected_person_invitation/);
  assert.match(actions, /reissue_protected_person_invitation/);
  assert.match(actions, /revoke_protected_person_invitation/);
  assert.match(actions, /remove_protected_person_access/);
  assert.match(actions, /Un compte autonome ne peut pas être invité comme collaborateur/);
});
