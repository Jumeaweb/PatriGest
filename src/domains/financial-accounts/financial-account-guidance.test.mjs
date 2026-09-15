import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getCurrentValuationValue } from "./utils/account-valuation-utils.ts";

const form = readFileSync(new URL("./components/financial-account-form.tsx", import.meta.url), "utf8");
const detail = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/page.tsx", import.meta.url), "utf8");
const newPage = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/comptes/nouveau/page.tsx", import.meta.url), "utf8");
const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
const accountUtils = readFileSync(new URL("./utils/financial-account-utils.ts", import.meta.url), "utf8");

test("le solde initial est expliqué comme valeur réelle au point de départ", () => {
  assert.match(form, /valeur réelle du compte à la date du solde initial/);
  assert.match(form, /point de départ au suivi dans PatriGest/);
});

test("la valeur 0,00 reste proposée mais n'est pas présentée comme calculée", () => {
  assert.match(form, /defaultValue=\{account\?\.initial_balance \?\? "0\.00"\}/);
  assert.match(form, /0,00 est proposé par défaut, mais n’est pas une valeur calculée/);
});

test("la date et le solde sont explicitement liés sans changer leurs champs", () => {
  assert.match(form, /id="initialBalanceDate"[^\n]+date à laquelle correspond le solde initial/);
  assert.match(form, /ensemble, ils décrivent le point de départ du compte/);
  assert.match(form, /defaultValue=\{account\?\.initial_balance_date \?\? new Date\(\)\.toISOString\(\)\.slice\(0, 10\)\}/);
});

test("la création conserve la redirection vers la fiche du nouveau compte", () => {
  assert.match(actions, /redirect\(`\/dossiers\/\$\{protectedPersonId\}\/comptes\/\$\{account\.id\}`\)/);
});

test("owner et manager voient Ajouter un autre compte vers le même dossier", () => {
  assert.match(detail, /person\.accessRole !== "read_only" && <>/);
  assert.match(detail, /href=\{`\/dossiers\/\$\{protectedPersonId\}\/comptes\/nouveau`\}[^\n]+Ajouter un autre compte/);
  assert.match(newPage, /person\.accessRole === "read_only"\) notFound\(\)/);
});

test("le bouton Ajouter un autre compte est absent du bloc read_only", () => {
  const gatedActions = detail.match(/person\.accessRole !== "read_only" && <>(.*?)<\/>{1}/);
  assert.ok(gatedActions);
  assert.match(gatedActions[1], /Ajouter un autre compte/);
});

test("la première valorisation décrit la valeur globale datée sans modèle de titres", () => {
  assert.match(detail, /account\.valuations\.length === 0 && <p[^\n]+valeur globale du compte à une date donnée/);
  assert.match(detail, /person\.accessRole !== "read_only" && " Ajoutez une première valorisation/);
  assert.doesNotMatch(detail, /ISIN|positions|cours de marché/i);
  assert.match(detail, /person\.accessRole !== "read_only" && <details[^\n]+Ajouter une valorisation/);
});

test("le compte-titres reçoit la même aide et les calculs valorisés restent inchangés", () => {
  assert.match(detail, /isValuationAccount\(account\.account_type\) && <section/);
  assert.match(accountUtils, /type === "life_insurance" \|\| type === "other_investment" \|\| type === "securities_account"/);
  assert.match(accountUtils, /getCurrentValuationValue\(account\.initial_balance, valuations\)/);
  assert.match(accountUtils, /return displayedValue \+ placementTransferAdjustment/);
  assert.deepEqual(getCurrentValuationValue(1000, []), { value: 1000, valuation: null });
  assert.equal(getCurrentValuationValue(1000, [{ id: "v1", valuation_date: "2026-01-01", value: 1200 }]).value, 1200);
});
