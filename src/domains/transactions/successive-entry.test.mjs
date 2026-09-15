import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { nextSuccessiveDraft } from "./successive-draft.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const links = source("./components/transaction-quick-actions.tsx");
const route = source("../../app/dossiers/[protectedPersonId]/operations/saisie-successive/page.tsx");
const action = source("./successive-actions.ts");
const component = source("./components/successive-transaction-entry.tsx");
const eligibility = source("./successive-entry.ts");

test("owner et manager disposent du lien de saisie successive sur les journaux", () => {
  assert.match(links, /accessRole !== "read_only" && ordinaryAllowed && <Link/);
  assert.match(links, /Saisie successive/);
  assert.match(route, /person\.accessRole === "read_only"\) notFound\(\)/);
});

test("un compte de valorisation ou inactif n'est pas éligible", () => {
  assert.match(eligibility, /account\.status === "active" && !isValuationAccount\(account\.account_type\)/);
  assert.match(route, /isSuccessiveAccountEligible\(account\)/);
  assert.match(route, /search\.account !== undefined.*notFound\(\)/);
  assert.match(action, /account\.protected_person_id !== personId \|\| !isSuccessiveAccountEligible\(account\)/);
});

test("le journal de compte transmet et présélectionne son compte", () => {
  assert.match(links, /account=\$\{encodeURIComponent\(accountId\)\}/);
  assert.match(route, /defaultAccountId=\{accountId\}/);
  assert.match(component, /financialAccountId: defaultAccountId \?\? ""/);
});

test("le journal global permet le choix du compte transactionnel", () => {
  assert.match(component, /accounts\.filter\(isSuccessiveAccountEligible\)/);
  assert.match(component, /name="financialAccountId" value=\{draft\.financialAccountId\}/);
});

test("une ligne utilise le schéma et le service de création ordinaires", () => {
  assert.match(action, /transactionSchema\.safeParse/);
  assert.match(action, /await createTransaction\(personId, parsed\.data\)/);
  assert.doesNotMatch(action, /createTransfer|rpc\(/);
});

test("le type virement est absent du formulaire et rejeté par le schéma ordinaire", () => {
  assert.match(component, /\["income", "expense"\] as const/);
  assert.doesNotMatch(component, /"transfer"/);
  assert.match(source("./schemas/transaction-schema.ts"), /z\.enum\(\["income", "expense"\]\)/);
});

test("classification stable et précision obligatoire restent dans createTransaction", () => {
  const service = source("./services/transaction-service.ts");
  assert.match(service, /resolveTransactionClassification\(\{ supabase, userId, transactionType: input\.transactionType, categoryId: input\.categoryId, classificationPrecision: input\.classificationPrecision, requirePrecision: true \}\)/);
  assert.match(service, /accounting_nature: classification\.accountingNature, official_category_id: classification\.officialCategoryId, classification_precision: classification\.classificationPrecision/);
  assert.match(component, /getEffectiveOfficialCategory\(categories, draft\.categoryId\)/);
});

test("l'exercice clôturé reste protégé par le trigger et donne une erreur sûre", () => {
  assert.match(action, /isClosedPeriodError\(error\)/);
  assert.match(source("../../../supabase/migrations/20260809120000_create_financial_transactions.sql"), /create trigger transactions_protect_closed_period\s+before insert or update or delete/);
});

test("une soumission produit une seule création et désactive la resoumission UI", () => {
  assert.equal((action.match(/await createTransaction\(/g) ?? []).length, 1);
  assert.match(component, /if \(submitted\.current \|\| pending\) event\.preventDefault\(\)/);
  assert.match(component, /disabled=\{pending\}/);
});

test("le succès confirme la ligne et l'ajoute une fois à l'historique local", () => {
  assert.match(component, /reported\.current !== state\.created\.id/);
  assert.match(component, /setHistory\(\(rows\) => \[transaction, \.\.\.rows\]\)/);
  assert.match(component, /Opération enregistrée/);
  assert.match(component, /Opérations enregistrées \(\{history\.length\}\)/);
});

test("la suivante conserve compte, date et type mais vide les autres champs", () => {
  const draft = { transactionType: "expense", financialAccountId: "account", transactionDate: "2026-09-15", label: "Pain", amount: "12", categoryId: "category", classificationPrecision: "détail" };
  assert.deepEqual(nextSuccessiveDraft(draft), { transactionType: "expense", financialAccountId: "account", transactionDate: "2026-09-15", label: "", amount: "", categoryId: "", classificationPrecision: "" });
  assert.match(component, /transactionType: mode, categoryId: "", classificationPrecision: ""/);
});

test("une erreur conserve le brouillon et ne modifie pas l'historique", () => {
  assert.match(component, /value=\{draft\.label\}/);
  assert.match(component, /value=\{draft\.amount\}/);
  assert.match(component, /if \(state\.status === "error"\) submitted\.current = false/);
  assert.match(component, /if \(state\.created && reported\.current/);
});

test("le justificatif est distinct de la création et réservé à la dépense réussie", () => {
  assert.doesNotMatch(action, /prepareProofFile|saveTransactionProof|proofFile/);
  assert.match(component, /transaction\.transaction_type === "expense" && transaction\.proof_reference/);
  assert.match(component, /method: "POST", body: new FormData\(event\.currentTarget\)/);
  assert.match(component, /\/justificatif`/);
});

test("un échec de justificatif conserve l'opération et permet réessai ou continuation", () => {
  assert.match(component, /La dépense reste enregistrée ; réessayez ou continuez/);
  assert.match(component, /Réessayer l’ajout/);
  assert.match(component, /Saisir la suivante/);
  assert.equal((component.match(/createSuccessiveTransactionAction/g) ?? []).length, 2);
});

test("terminer ramène au journal par la destination interne sûre", () => {
  assert.match(route, /getSafeTransactionReturnTo\(protectedPersonId/);
  assert.match(component, /href=\{returnHref\} aria-disabled=\{pending\}/);
  assert.match(component, /href=\{onFinishHref\}/);
  assert.match(links, /withTransactionReturnTo\(/);
});
