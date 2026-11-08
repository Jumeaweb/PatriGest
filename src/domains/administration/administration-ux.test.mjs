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
const usersTable = read("./components/administration-users-table.tsx");
const communicationPage = read("../../app/administration/communication/page.tsx");
const infrastructurePage = read("../../app/administration/infrastructure/page.tsx");
const service = read("./services/administration-service.ts");
const registrationActions = read("./components/registration-review-actions.tsx");
const deletion = read("./components/delete-user-button.tsx");
const releasePanel = read("./components/release-notification-panel.tsx");
const actions = read("./actions.ts");
const administrativeTrialMigration = read("../../../supabase/migrations/20261107100000_expose_administrative_account_trial_states.sql");
const administrativeTrialTest = read("../../../supabase/tests/administrative_account_trial_states_test.sql");
const administrativeEntitlementMigration = read("../../../supabase/migrations/20261108110000_expose_administrative_account_entitlement_states.sql");
const administrativeEntitlementTest = read("../../../supabase/tests/administrative_account_entitlement_states_test.sql");

test("le menu ADMINISTRATION expose les cinq entrées dans l’ordre validé", () => {
  const labels = ["Tableau de bord", "Inscriptions à valider", "Comptes utilisateurs", "Communication utilisateurs", "Infrastructure"];
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
  for (const source of [dashboardPage, requests, usersPage, communicationPage, infrastructurePage]) {
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

test("affiche séparément les quatre catégories de droits et conserve les actions existantes", () => {
  assert.match(service, /select\("user_id,status,account_mode"\)/);
  assert.match(service, /select\("user_id,protected_person_id,role"\)/);
  assert.match(service, /select\("id,owner_id,plan_key,dossier_capacity_key,custom_active_dossier_limit,status,current_period_started_at,current_period_ends_at,canceled_at"\)/);
  assert.match(usersTable, />Utilisateur<\/th>/);
  for (const heading of ["Essai gratuit", "Abonnement commercial", "Attribution administrative", "Dérogation active", "Droits effectifs", "Accès partagés", "Dossiers", "Résiliation", "Actions"]) {
    assert.ok(usersTable.includes(heading), `${heading} doit rester visible`);
  }
  assert.match(usersPage, /<AdministrationUsersTable users=\{result\.users\}/);
  assert.match(usersTable, /overflow-x-auto/);
  assert.equal(usersTable.match(/overflow-x-auto/g)?.length, 1);
  assert.match(usersTable, /\[scrollbar-color:#94A3B8_#E2E8F0\]/);
  assert.match(usersTable, /sticky left-0 z-30 bg-slate-50/);
  assert.match(usersTable, /sticky left-0 z-10 bg-white/);
  assert.match(usersTable, /Inscription : \{formatDate\(user\.createdAt\)\}/);
  assert.match(usersTable, /lg:hidden/);
  assert.match(usersTable, /<ResendActivationEmailButton/);
  assert.match(usersTable, /<DeleteUserButton/);
  assert.match(usersTable, /Droits des comptes en lecture seule/);
  assert.match(usersTable, /Modification des droits non activée/);
  assert.match(usersTable, /Accès historique/);
  assert.match(usersTable, /Compte administrateur non modifiable/);
  assert.doesNotMatch(usersTable, /Confirmer l’enregistrement|assign_administrative_plan|replace_administrative_plan/);
});

test("lit les droits administratifs par une projection paginée et fermée", () => {
  assert.match(service, /rpc\("list_administrative_account_entitlement_states", \{ p_user_ids: ids \}\)/);
  assert.match(service, /administrativeAssignment: entitlement\.administrative_assignment_id/);
  assert.match(service, /administrativeOverride: entitlement\.administrative_override_id/);
  assert.match(administrativeEntitlementMigration, /security definer[\s\S]*?set search_path = ''/);
  assert.match(administrativeEntitlementMigration, /cardinality\(p_user_ids\) > 25/);
  assert.match(administrativeEntitlementMigration, /resolve_effective_account_entitlements/);
  assert.match(administrativeEntitlementMigration, /revoke all on function public\.list_administrative_account_entitlement_states\(uuid\[\]\)[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(administrativeEntitlementMigration, /grant execute on function public\.list_administrative_account_entitlement_states\(uuid\[\]\)[\s\S]*?to authenticated/);
  assert.doesNotMatch(administrativeEntitlementMigration, /returns table \([\s\S]*?reason text/);
  assert.match(administrativeEntitlementTest, /un utilisateur ordinaire ne peut pas lire les droits/);
  assert.match(administrativeEntitlementTest, /la projection ne retourne aucun compte non demande/);
});

test("lit les essais par une projection administrative fermée et conserve la priorité commerciale", () => {
  assert.match(service, /rpc\("list_administrative_account_trial_states", \{ p_user_ids: ids \}\)/);
  assert.match(service, /trial\?\.state === "subscribed"/);
  assert.doesNotMatch(service, /trial\?\.state === "subscribed" \|\| subscription\?\.plan_key/);
  assert.match(service, /trial\?\.state === "active"/);
  assert.match(service, /trial\?\.state === "suspended" \|\| trial\?\.state === "deletion_due"/);
  assert.match(service, /trial\?\.state === "legacy_access"/);
  assert.match(administrativeTrialMigration, /security definer[\s\S]*?set search_path = ''/);
  assert.match(administrativeTrialMigration, /platform_administrators[\s\S]*?administrator\.user_id = auth\.uid\(\)/);
  assert.match(administrativeTrialMigration, /cardinality\(p_user_ids\) > 25/);
  assert.match(administrativeTrialMigration, /revoke all on function public\.list_administrative_account_trial_states\(uuid\[\]\)[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(administrativeTrialMigration, /grant execute on function public\.list_administrative_account_trial_states\(uuid\[\]\)[\s\S]*?to authenticated/);
  for (const state of ["active", "suspended", "legacy_access", "subscribed"]) {
    assert.match(administrativeTrialTest, new RegExp(`'${state}'`));
  }
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
  assert.match(usersTable, /Suppression indisponible/);
  assert.match(usersTable, /deletionBlockReasons\.map/);
  assert.match(deletion, /button-danger/);
  assert.match(deletion, /cancelLabel=\{succeeded \? "Fermer" : "Annuler"\}/);
  assert.match(deletion, /actions=\{succeeded \? null : <DeleteSubmitButton/);
  assert.match(deletion, /Motif de la suppression/);
  assert.match(deletion, /name="confirmation" required/);
  assert.match(deletion, /attemptId\.current \?\?= crypto\.randomUUID\(\)/);
  assert.match(actions, /reason: z\.string\(\)\.trim\(\)\.min\(1/);
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
