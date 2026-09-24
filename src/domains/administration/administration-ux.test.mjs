import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getAdministrationUsersPageHref, parseAdministrationUsersPage } from "./administration-user-pagination.ts";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const navigation = read("../../components/layout/private-navigation.tsx");
const dashboardPage = read("../../app/administration/page.tsx");
const dashboard = read("./components/administration-dashboard.tsx");
const requests = read("../../app/administration/demandes/page.tsx");
const usersPage = read("../../app/administration/utilisateurs/page.tsx");
const communicationPage = read("../../app/administration/communication/page.tsx");
const service = read("./services/administration-service.ts");
const registrationActions = read("./components/registration-review-actions.tsx");
const deletion = read("./components/delete-user-button.tsx");
const releasePanel = read("./components/release-notification-panel.tsx");

test("le menu ADMINISTRATION expose les quatre entrées dans l’ordre validé", () => {
  const labels = ["Tableau de bord", "Inscriptions à valider", "Comptes utilisateurs", "Communication utilisateurs"];
  let previous = -1;
  for (const label of labels) {
    const index = navigation.indexOf(`label: "${label}"`, previous + 1);
    assert.ok(index > previous, `${label} doit suivre l’entrée précédente`);
    previous = index;
  }
  const adminItems = navigation.slice(navigation.indexOf("isPlatformAdmin ? ["), navigation.indexOf("] : ["));
  assert.doesNotMatch(adminItems, /label: "Administration"/);
  assert.match(navigation, /principalLabel=\{isPlatformAdmin \? "Administration" : "Principal"\}/);
});

test("utilise le menu gauche sans onglets redondants et sans breadcrumb à la racine", () => {
  assert.doesNotMatch(dashboardPage, /AppBreadcrumb/);
  for (const source of [dashboardPage, requests, usersPage, communicationPage]) {
    assert.doesNotMatch(source, /role="tablist"|NavigationTabs|AdministrationTabs/);
  }
});

test("conserve les trois indicateurs et qualifie les invitations de partage en attente", () => {
  assert.match(dashboard, /Comptes utilisateurs/);
  assert.match(dashboard, /Inscriptions à valider/);
  assert.match(dashboard, /Invitations en attente/);
  assert.match(dashboard, /partages valides et non acceptés/);
  assert.match(service, /from\("protected_person_invitations"\)[\s\S]*?is\("accepted_at", null\)[\s\S]*?is\("revoked_at", null\)[\s\S]*?gt\("expires_at", now\)/);
  assert.doesNotMatch(dashboard, /ReleaseNotificationPanel/);
});

test("affiche uniquement des libellés français pour l’historique des inscriptions", () => {
  assert.match(requests, /Approuvée/);
  assert.match(requests, /Refusée/);
  assert.doesNotMatch(requests, />Approved<|>Rejected</);
});

test("regroupe le tableau utilisateurs en cinq colonnes et conserve toutes les informations", () => {
  assert.match(service, /select\("user_id,status,account_mode"\)/);
  assert.match(service, /select\("user_id,protected_person_id,role"\)/);
  const tableHeader = usersPage.match(/<thead[\s\S]*?<\/thead>/)?.[0] ?? "";
  const headings = ["Utilisateur", "Statut / type", "Dossiers possédés", "Accès partagés", "Actions"];
  assert.equal((tableHeader.match(/<th\b/g) ?? []).length, 5);
  let previous = -1;
  for (const heading of headings) {
    const index = tableHeader.indexOf(heading, previous + 1);
    assert.ok(index > previous, `${heading} doit suivre la colonne précédente`);
    previous = index;
  }
  assert.match(usersPage, /function UserIdentity[\s\S]*?user\.email[\s\S]*?Inscription :/);
  assert.match(usersPage, /function StatusAndMode[\s\S]*?AuthorizationStatusBadge[\s\S]*?AccountModeBadge/);
  const accountModeBadge = usersPage.match(/function AccountModeBadge[\s\S]*?\n}/)?.[0] ?? "";
  assert.match(accountModeBadge, /Administration de la plateforme", classes: "bg-\[#214660\] text-white"/);
  assert.match(accountModeBadge, /Compte autonome", classes: "bg-\[#DDECEA\] text-\[#214660\]/);
  assert.match(accountModeBadge, /Compte collaborateur", classes: "bg-\[#F4EAD5\] text-\[#6F531E\]/);
  assert.equal(new Set(accountModeBadge.match(/classes: "[^"]+"/g)?.slice(0, 3)).size, 3);
  assert.match(usersPage, /function SharedAccessList[\s\S]*?protectedPersonName[\s\S]*?Gestionnaire[\s\S]*?Lecture seule/);
  assert.match(usersPage, /if \(!accesses\.length\) return [^;]*>Aucun</);
  assert.match(usersPage, /hidden[^\"]*xl:block/);
  assert.match(usersPage, /xl:hidden/);
  assert.match(usersPage, /function UserActions/);
});

test("pagine Auth côté serveur et charge les dépendances de la page en lots", () => {
  assert.match(service, /ADMIN_USERS_PAGE_SIZE = 25/);
  assert.match(service, /listUsers\(\{ page: requestedPage, perPage: ADMIN_USERS_PAGE_SIZE \}\)/);
  assert.match(service, /\.in\("id", ids\)/);
  assert.match(service, /\.in\("user_id", ids\)/);
  assert.doesNotMatch(service.match(/export async function getPlatformUsers[\s\S]*?\n}\n\nexport async function deletePlatformUser/)?.[0] ?? "", /getAllAuthUsers/);
  assert.equal(parseAdministrationUsersPage(undefined), 1);
  assert.equal(parseAdministrationUsersPage("3"), 3);
  assert.equal(parseAdministrationUsersPage("0"), 1);
  assert.equal(getAdministrationUsersPageHref(1), "/administration/utilisateurs");
  assert.equal(getAdministrationUsersPageHref(4), "/administration/utilisateurs?page=4");
});

test("expose les motifs backend connus avant de proposer la suppression", () => {
  for (const reason of ["Administrateur PatriGest", "Relation d’administration conservée", "Dossier possédé", "Accès à un dossier partagé", "Invitation de partage active", "Données métier associées"]) {
    assert.match(service, new RegExp(reason));
  }
  assert.match(usersPage, /Suppression indisponible/);
  assert.match(usersPage, /deletionBlockReasons\.map/);
  assert.match(deletion, /button-danger/);
  assert.match(deletion, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(deletion, /actions=\{succeeded \? null : <DeleteSubmitButton/);
});

test("confirme le renvoi d’activation et conserve seulement Fermer après réussite", () => {
  assert.match(registrationActions, /Renvoyer l’e-mail d’activation \?/);
  assert.match(registrationActions, /subject=\{email\}/);
  assert.match(registrationActions, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(registrationActions, /actions=\{succeeded \? null : <ResendSubmit/);
  assert.match(service, /authorization\?\.status !== "active"/);
});

test("déplace la communication de release sans toucher à ses règles", () => {
  assert.match(communicationPage, /getReleaseNotificationDashboard\(APP_VERSION\)/);
  assert.match(communicationPage, /<ReleaseNotificationPanel/);
  assert.match(releasePanel, /sendTestReleaseNotificationAction/);
  assert.match(releasePanel, /sendGlobalReleaseNotificationsAction/);
  assert.match(releasePanel, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
});
