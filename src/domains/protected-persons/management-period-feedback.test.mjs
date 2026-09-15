import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { managementPeriodSchema } from "./schemas/management-period-schema.ts";
import { classifyManagementPeriodWriteFailure, ManagementPeriodWriteError, managementPeriodUserMessage } from "./services/management-period-feedback.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const actions = source("./actions.ts");
const service = source("./services/protected-person-service.ts");
const manager = source("./components/management-period-manager.tsx");
const page = source("../../app/dossiers/[protectedPersonId]/exercices/page.tsx");

test("un exercice valide accepte une période d'un jour, sans changer l'ordre métier", () => {
  assert.equal(managementPeriodSchema.safeParse({ startDate: "2026-09-15", endDate: "2026-09-15" }).success, true);
  assert.match(service, /management_periods"\)\.insert\(\{/);
  assert.match(actions, /L’exercice de gestion a été créé/);
});

test("dates inexistantes et fin avant début présentent des erreurs par champ", () => {
  const invalid = managementPeriodSchema.safeParse({ startDate: "2026-02-30", endDate: "2026-03-01" });
  assert.equal(invalid.success, false);
  if (!invalid.success) assert.match(invalid.error.flatten().fieldErrors.startDate[0], /date de début valide/);
  const reversed = managementPeriodSchema.safeParse({ startDate: "2026-09-16", endDate: "2026-09-15" });
  assert.equal(reversed.success, false);
  if (!reversed.success) assert.match(reversed.error.flatten().fieldErrors.endDate[0], /postérieure ou égale/);
});

test("l'exclusion SQL existante est reconnue comme chevauchement", () => {
  assert.match(source("../../../supabase/migrations/20260811110000_prevent_management_period_overlap.sql"), /constraint management_periods_no_overlap\s+exclude using gist/);
  const failure = classifyManagementPeriodWriteFailure({ code: "23P01", message: "conflicting key value" });
  assert.equal(failure.reason, "overlap");
  assert.match(managementPeriodUserMessage(failure, "create"), /chevauchent un exercice existant/);
  assert.match(managementPeriodUserMessage(failure, "update"), /chevauchent un exercice existant/);
});

test("dates strictement identiques sont couvertes par l'index unique existant", () => {
  assert.equal(classifyManagementPeriodWriteFailure({ code: "23505", message: "management_periods_unique_dates_idx" }).reason, "overlap");
  assert.equal(classifyManagementPeriodWriteFailure({ code: "23505", message: "other_constraint" }).reason, "generic");
});

test("permission RLS refusée devient un message sûr", () => {
  assert.equal(managementPeriodUserMessage(classifyManagementPeriodWriteFailure({ code: "42501" }), "create"), "Vous ne pouvez pas gérer les exercices de ce dossier.");
  assert.doesNotMatch(managementPeriodUserMessage(classifyManagementPeriodWriteFailure({ code: "42501", message: "SQL detail secret" }), "update"), /SQL|42501|secret/);
  assert.equal((actions.match(/person\?\.accessRole === "read_only"/g) ?? []).length, 2);
  assert.match(source("../../../supabase/migrations/20260809180000_create_multi_user_access.sql"), /management_periods_insert_manage[\s\S]*?can_manage_protected_person/);
});

test("erreur technique n'expose ni SQL ni code Supabase", () => {
  for (const operation of ["create", "update"]) {
    const safe = managementPeriodUserMessage(classifyManagementPeriodWriteFailure({ code: "XX999", message: "raw SQL and token" }), operation);
    assert.doesNotMatch(safe, /SQL|XX999|token/);
    assert.match(safe, /Impossible/);
  }
});

test("modification valide utilise les mêmes filtres open et dossier et confirme son succès", () => {
  assert.match(service, /management_periods"\)\.update\(\{ start_date: input\.startDate, end_date: input\.endDate \}\)\.eq\("id", periodId\)\.eq\("protected_person_id", protectedPersonId\)\.eq\("status", "open"\)/);
  assert.match(actions, /L’exercice a été modifié/);
});

test("exercice absent ou clôturé ne produit plus une modification silencieuse", () => {
  assert.match(service, /if \(!data\) throw new ManagementPeriodWriteError\("unavailable"\)/);
  assert.match(managementPeriodUserMessage(new ManagementPeriodWriteError("unavailable"), "update"), /introuvable ou clôturé/);
});

test("actions réutilisent les messages sûrs de création et modification", () => {
  assert.match(actions, /managementPeriodUserMessage\(error, "create"\)/);
  assert.match(actions, /managementPeriodUserMessage\(error, "update"\)/);
  assert.doesNotMatch(actions, /Vérifiez qu’il n’existe pas déjà/);
  assert.match(service, /throw classifyManagementPeriodWriteFailure\(error\)/);
});

test("dates contrôlées restent saisies après erreur et les boutons sont bloqués pendant l'envoi", () => {
  assert.match(manager, /value=\{startDate\} onChange=\{setStartDate\}/);
  assert.match(manager, /value=\{endDate\} onChange=\{setEndDate\}/);
  assert.match(manager, /disabled=\{pending\}/);
  assert.match(manager, /<FormMessage state=\{state\}/);
});

test("l'état vide est explicite pour gestionnaire et lecture seule", () => {
  assert.match(manager, /Aucun exercice de gestion/);
  assert.match(page, /person\.accessRole === "read_only"/);
  assert.match(page, /Aucun exercice de gestion/);
  assert.match(manager, /Créer un exercice/);
  assert.doesNotMatch(page.split('person.accessRole === "read_only" ?')[1].split(': <ManagementPeriodManager')[0], /Créer un exercice/);
});

test("l'accès depuis Informations du dossier et NAV-04 restent inchangés", () => {
  assert.match(source("../../app/dossiers/[protectedPersonId]/page.tsx"), /Gérer les exercices/);
  const nav = source("./components/dossier-navigation.tsx");
  assert.doesNotMatch(nav, /label: "Exercices de gestion"/);
});
