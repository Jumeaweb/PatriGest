import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getTransactionQuickActions } from "./transaction-quick-actions.ts";
import { getSafeTransactionReturnTo } from "./return-to.ts";

const personId = "11111111-1111-4111-8111-111111111111";
const accountId = "22222222-2222-4222-8222-222222222222";
const globalPage = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/page.tsx", import.meta.url), "utf8");
const accountPage = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/operations/page.tsx", import.meta.url), "utf8");
const newPage = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/nouvelle/page.tsx", import.meta.url), "utf8");
const quickActions = readFileSync(new URL("./components/transaction-quick-actions.tsx", import.meta.url), "utf8");
const journal = readFileSync(new URL("./components/transaction-journal.tsx", import.meta.url), "utf8");
const form = readFileSync(new URL("./components/transaction-form.tsx", import.meta.url), "utf8");

test("le journal global propose trois intentions distinctes sur la route existante", () => {
  assert.deepEqual(getTransactionQuickActions(personId, undefined, true, true).map(({ label, href }) => [label, href]), [
    ["Ajouter une recette", `/dossiers/${personId}/operations/nouvelle?mode=income`],
    ["Ajouter une dépense", `/dossiers/${personId}/operations/nouvelle?mode=expense`],
    ["Effectuer un virement", `/dossiers/${personId}/operations/nouvelle?mode=transfer`],
  ]);
});

test("le journal du compte conserve accountId dans les trois destinations", () => {
  const actions = getTransactionQuickActions(personId, accountId, true, true);
  assert.deepEqual(actions.map((action) => action.mode), ["income", "expense", "transfer"]);
  for (const action of actions) assert.equal(new URL(action.href, "https://patrigest.internal").searchParams.get("account"), accountId);
});

test("la page de saisie ouvre directement recette, dépense et virement", () => {
  assert.match(newPage, /search\.mode === "income" \|\| search\.mode === "expense" \|\| search\.mode === "transfer"/);
  assert.match(newPage, /defaultMode=\{requestedMode\}/);
  assert.match(newPage, /key=\{`\$\{requestedAccountId \?\? "global"\}:\$\{requestedMode \?\? "default"\}`\}/);
  assert.match(form, /defaultMode \?\? "expense"/);
  assert.match(form, /\[\s*\["income", "Recette"\], \["expense", "Dépense"\], \["transfer", "Virement"\]\s*\]/);
});

test("l'état vide est actionnable, sans doubler les actions dans l'en-tête", () => {
  assert.match(journal, /if \(!items\.length\)[^\n]+<TransactionQuickActions/);
  assert.match(globalPage, /items\.length > 0 && <TransactionQuickActions/);
  assert.match(accountPage, /items\.length > 0 && <TransactionQuickActions/);
  assert.doesNotMatch(globalPage + accountPage, /Ajouter une opération/);
});

test("read_only ne reçoit aucune action de création", () => {
  assert.match(quickActions, /accessRole !== "read_only" && ordinaryAllowed/);
  assert.match(quickActions, /accessRole !== "read_only" && transferAllowed/);
  assert.deepEqual(getTransactionQuickActions(personId, accountId, false, false), []);
  assert.match(globalPage, /person\.accessRole !== "read_only"/);
  assert.match(accountPage, /person\.accessRole !== "read_only" && account\.status === "active"/);
});

test("les comptes valorisés n'ouvrent pas de recette ou dépense ordinaire", () => {
  assert.match(accountPage, /&& !valuationAccount/);
  assert.deepEqual(getTransactionQuickActions(personId, accountId, false, true).map((action) => action.mode), ["transfer"]);
});

test("le retour du journal de compte et NAV-03 restent contextualisés", () => {
  const accountJournal = `/dossiers/${personId}/comptes/${accountId}/operations`;
  assert.equal(getSafeTransactionReturnTo(personId, accountJournal, accountId), accountJournal);
  assert.match(accountPage, /getSafeTransactionReturnTo\(protectedPersonId, `\/dossiers\/\$\{protectedPersonId\}\/comptes\/\$\{accountId\}\/operations/);
  assert.match(newPage, /defaultAccountId=\{requestedAccountId\}/);
  assert.match(form, /createTransferAction\.bind\(null, personId, returnHref\)/);
});

test("filtres, journal et comportement de création existants restent présents", () => {
  assert.match(globalPage, /<TransactionFilters personId=\{protectedPersonId\}/);
  assert.match(accountPage, /<AccountFilters categories=\{categories\} values=\{filterValues\}/);
  assert.match(journal, /ordered\.map\(\(item\) => <Row/);
  assert.match(form, /createTransactionAction\.bind\(null, personId\)/);
  assert.match(form, /router\.push\(returnHref\)/);
});
