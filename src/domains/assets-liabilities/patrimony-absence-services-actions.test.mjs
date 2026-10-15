import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { buildPatrimonyAbsenceConfirmationState } from "./patrimony-absence.ts";
import { patrimonyAbsenceConfirmationSchema } from "./schemas.ts";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

function confirmation(category, overrides = {}) {
  return {
    protected_person_id: "10000000-0000-4000-8000-000000000001",
    category,
    confirmed_at: "2026-10-15T10:00:00.000Z",
    confirmed_by: "10000000-0000-4000-8000-000000000002",
    confirmed_by_name: "Gestionnaire Test",
    ...overrides,
  };
}

test("la demande valide strictement l’UUID, la catégorie et l’état", () => {
  for (const category of ["real_estate", "active_debt"]) {
    assert.equal(patrimonyAbsenceConfirmationSchema.safeParse({
      personId: "10000000-0000-4000-8000-000000000001",
      category,
      confirmed: true,
    }).success, true);
  }
  assert.equal(patrimonyAbsenceConfirmationSchema.safeParse({ personId: "invalide", category: "real_estate", confirmed: true }).success, false);
  assert.equal(patrimonyAbsenceConfirmationSchema.safeParse({ personId: "10000000-0000-4000-8000-000000000001", category: "bank_account", confirmed: true }).success, false);
  assert.equal(patrimonyAbsenceConfirmationSchema.safeParse({ personId: "10000000-0000-4000-8000-000000000001", category: "active_debt", confirmed: "true" }).success, false);
});

test("la lecture sans confirmation distingue explicitement les deux absences", () => {
  assert.deepEqual(buildPatrimonyAbsenceConfirmationState([]), {
    realEstate: null,
    activeDebt: null,
  });
});

test("la lecture d’une confirmation expose sa catégorie, sa date et son auteur", () => {
  const realEstate = confirmation("real_estate");
  assert.deepEqual(buildPatrimonyAbsenceConfirmationState([realEstate]), {
    realEstate,
    activeDebt: null,
  });
});

test("les deux confirmations sont lues indépendamment", () => {
  const realEstate = confirmation("real_estate");
  const activeDebt = confirmation("active_debt", { confirmed_at: "2026-10-15T11:00:00.000Z" });
  assert.deepEqual(buildPatrimonyAbsenceConfirmationState([activeDebt, realEstate]), {
    realEstate,
    activeDebt,
  });
});

test("le service de lecture propage l’erreur Supabase avant de construire un état", () => {
  const services = source("./services.ts");
  const read = services.slice(
    services.indexOf("export async function getPatrimonyAbsenceConfirmations"),
    services.indexOf("export async function setPatrimonyAbsenceConfirmation"),
  );
  assert.match(read, /from\("patrimony_absence_confirmations"\)/);
  assert.match(read, /\.eq\("protected_person_id", personId\)/);
  assert.match(read, /if \(error\) throw new Error\("Impossible de charger les confirmations d’absence patrimoniale\."\)/);
  assert.match(read, /buildPatrimonyAbsenceConfirmationState\(data\)/);
  assert.ok(read.indexOf("if (error)") < read.indexOf("buildPatrimonyAbsenceConfirmationState(data)"));
  assert.doesNotMatch(read, /error[\s\S]*?return\s+\{\s*realEstate:\s*null/);
});

test("le service de mutation appelle uniquement la RPC avec les paramètres validés", () => {
  const services = source("./services.ts");
  const mutation = services.slice(
    services.indexOf("export async function setPatrimonyAbsenceConfirmation"),
    services.indexOf("export async function getDebts"),
  );
  assert.match(mutation, /rpc\("set_patrimony_absence_confirmation"/);
  assert.match(mutation, /p_protected_person_id: input\.personId/);
  assert.match(mutation, /p_category: input\.category/);
  assert.match(mutation, /p_confirmed: input\.confirmed/);
  assert.doesNotMatch(mutation, /confirmed_by|confirmed_at|confirmed_by_name/);
});

test("les refus d’authentification, d’autorisation et les erreurs RPC sont classés", () => {
  const services = source("./services.ts");
  const mutation = services.slice(
    services.indexOf("export async function setPatrimonyAbsenceConfirmation"),
    services.indexOf("export async function getDebts"),
  );
  assert.match(mutation, /UNAUTHENTICATED/);
  assert.match(mutation, /APPLICATION_ACCESS_DENIED/);
  assert.match(mutation, /error\.code === "42501"/);
  assert.match(mutation, /PatrimonyAbsenceConfirmationError\("forbidden"\)/);
  assert.match(mutation, /error\.code === "23514"/);
  assert.match(mutation, /PatrimonyAbsenceConfirmationError\("invalid"\)/);
  assert.match(mutation, /PatrimonyAbsenceConfirmationError\("technical"\)/);
});

test("les quatre actions confirmer et retirer utilisent le parcours commun validé", () => {
  const actions = source("./actions.ts");
  assert.match(actions, /confirmRealEstateAbsenceAction\(personId:string\).*?"real_estate",true/s);
  assert.match(actions, /withdrawRealEstateAbsenceConfirmationAction\(personId:string\).*?"real_estate",false/s);
  assert.match(actions, /confirmActiveDebtAbsenceAction\(personId:string\).*?"active_debt",true/s);
  assert.match(actions, /withdrawActiveDebtAbsenceConfirmationAction\(personId:string\).*?"active_debt",false/s);
  assert.match(actions, /patrimonyAbsenceConfirmationSchema\.safeParse\(\{personId,category,confirmed\}\)/);
  assert.match(actions, /await setPatrimonyAbsenceConfirmation\(parsed\.data\)/);
  assert.doesNotMatch(actions, /confirmed_by|confirmed_at|confirmed_by_name/);
});

test("la revalidation couvre les synthèses et ne se produit qu’après une réussite", () => {
  const actions = source("./actions.ts");
  const mutation = actions.slice(
    actions.indexOf("export async function setPatrimonyAbsenceConfirmationAction"),
    actions.indexOf("export async function confirmRealEstateAbsenceAction"),
  );
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}`\)/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/tableau-de-bord`\)/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/patrimoine-immobilier`\)/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/dettes`\)/);
  assert.ok(mutation.indexOf("await setPatrimonyAbsenceConfirmation(parsed.data)") < mutation.indexOf("refresh(parsed.data.personId)"));
  assert.ok(mutation.indexOf("refresh(parsed.data.personId)") < mutation.indexOf("}catch(error)"));
  assert.doesNotMatch(mutation, /finally/);
});
