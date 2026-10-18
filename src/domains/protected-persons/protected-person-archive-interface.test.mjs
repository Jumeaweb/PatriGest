import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  canChangeProtectedPersonArchiveState,
  isProtectedPersonArchiveLifecycleEnabled,
  PROTECTED_PERSON_ARCHIVE_LIFECYCLE_ENV,
} from "./archive-lifecycle-availability.ts";
import {
  getProtectedPersonListView,
  partitionProtectedPersons,
} from "./protected-person-list-view.ts";

const source = (relativePath) => readFileSync(new URL(relativePath, import.meta.url), "utf8");
const list = source("./components/protected-person-list.tsx");
const detail = source("../../app/dossiers/[protectedPersonId]/page.tsx");
const dialog = source("./components/protected-person-archive-action.tsx");
const actions = source("./actions.ts");
const historyService = source("./services/protected-person-archive-history-service.ts");

test("la vue active est le défaut et les deux inventaires restent séparés", () => {
  assert.equal(getProtectedPersonListView(undefined), "active");
  assert.equal(getProtectedPersonListView("inconnue"), "active");
  assert.equal(getProtectedPersonListView(["archives", "active"]), "archived");
  assert.deepEqual(partitionProtectedPersons([
    { id: "active", status: "active" },
    { id: "archived", status: "archived" },
  ]), {
    active: [{ id: "active", status: "active" }],
    archived: [{ id: "archived", status: "archived" }],
  });
  assert.match(list, /Dossiers actifs/);
  assert.match(list, /Dossiers archivés/);
  assert.match(list, /partition\.active\.length/);
  assert.match(list, /partition\.archived\.length/);
  assert.match(list, /href="\/dossiers\?vue=archives"/);
  assert.match(list, /aria-current=\{active \? "page" : undefined\}/);
});

test("les listes possèdent leurs états vides et une présentation responsive", () => {
  assert.match(list, /Aucun dossier actif accessible/);
  assert.match(list, /Aucun dossier archivé/);
  assert.match(list, /overflow-x-auto/);
  assert.match(list, /sm:grid-cols-2 lg:grid-cols-3/);
  assert.match(list, /person\.status === "active" \? "Actif" : "Archivé"/);
});

test("l'activation centralisée est explicite, stricte et désactivée par défaut", () => {
  assert.equal(PROTECTED_PERSON_ARCHIVE_LIFECYCLE_ENV, "PATRIGEST_ENABLE_DOSSIER_ARCHIVE_LIFECYCLE");
  assert.equal(isProtectedPersonArchiveLifecycleEnabled(undefined), false);
  assert.equal(isProtectedPersonArchiveLifecycleEnabled("false"), false);
  assert.equal(isProtectedPersonArchiveLifecycleEnabled("TRUE"), false);
  assert.equal(isProtectedPersonArchiveLifecycleEnabled("true"), true);
  assert.equal(canChangeProtectedPersonArchiveState(true, "owner"), true);
  assert.equal(canChangeProtectedPersonArchiveState(true, "manager"), false);
  assert.equal(canChangeProtectedPersonArchiveState(true, "read_only"), false);
  assert.equal(canChangeProtectedPersonArchiveState(false, "owner"), false);
  assert.match(actions, /if \(!isProtectedPersonArchiveLifecycleEnabled\(\)\)/);
  assert.ok(
    actions.indexOf("if (!isProtectedPersonArchiveLifecycleEnabled())")
      < actions.indexOf("protectedPersonArchiveTransitionSchema.safeParse"),
  );
  assert.match(detail, /archiveLifecycleEnabled[\s\S]*?getProtectedPersonArchiveChanges/);
  assert.match(detail, /: Promise\.resolve\(\[\]\)/);
});

test("le propriétaire dispose d'un dialogue motivé, borné et protégé contre le double envoi", () => {
  assert.match(detail, /canChangeArchiveState && <ProtectedPersonArchiveAction/);
  assert.match(detail, /archiveRevision=\{person\.archive_revision\}/);
  assert.match(dialog, /Ce dossier sera conservé avec ses données et documents\. Il ne comptera plus dans votre capacité de dossiers actifs\./);
  assert.match(dialog, /Ce dossier redeviendra actif et comptera dans votre capacité de dossiers\. La restauration sera refusée si votre plafond est atteint\./);
  assert.match(dialog, /name="reason"/);
  assert.match(dialog, /required/);
  assert.match(dialog, /maxLength=\{2000\}/);
  assert.match(dialog, /disabled=\{pending\}/);
  assert.match(dialog, /requireExplicitClose=\{pending\}/);
  assert.match(dialog, /if \(pending\) return/);
  assert.match(dialog, /router\.refresh\(\)/);
  assert.doesNotMatch(dialog, /stale_revision|réessay|retry/i);
});

test("la fiche archivée devient visuellement consultative sans retirer les accès de lecture", () => {
  assert.match(detail, /Dossier archivé — consultation uniquement/);
  assert.match(detail, /Restaurez le dossier avant toute modification/);
  assert.match(detail, /const canManage = person\.accessRole !== "read_only" && !isArchived/);
  assert.match(detail, /const canDelete = isOwner && !isArchived/);
  assert.match(detail, /Voir les comptes/);
  assert.match(detail, /Voir les exercices/);
  assert.match(detail, /Voir le compte de gestion/);
});

test("l'historique accessible vient exclusivement de la table auditée", () => {
  assert.match(historyService, /import "server-only"/);
  assert.match(historyService, /getAuthenticatedUser\(\)/);
  assert.match(historyService, /\.from\("protected_person_archive_changes"\)/);
  assert.match(historyService, /\.eq\("protected_person_id", protectedPersonId\)/);
  assert.doesNotMatch(historyService, /createAdminClient|service_role|SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(detail, /archiveChanges\.map/);
  assert.match(detail, /change\.changed_at/);
  assert.match(detail, /change\.reason/);
  assert.match(detail, /change\.changed_by === person\.owner_id \? "Propriétaire du dossier" : "Auteur non disponible"/);
  assert.doesNotMatch(detail, /archiveChanges\.length === 0[\s\S]*?Historique/);
});

test("les erreurs de concurrence et de capacité restent celles du lot service", () => {
  const lifecycle = source("./archive-lifecycle.ts");
  assert.match(lifecycle, /stale_revision: "Ce dossier a changé depuis l’ouverture du formulaire\. Actualisez la page puis réessayez\."/);
  assert.match(lifecycle, /quota_reached: "Vous avez atteint le nombre maximal de dossiers actifs autorisé par votre abonnement\."/);
  assert.match(actions, /error instanceof ProtectedPersonArchiveTransitionError/);
});
