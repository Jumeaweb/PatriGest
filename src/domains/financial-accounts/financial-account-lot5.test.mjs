import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const detail = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/page.tsx");
const operations = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/operations/page.tsx");
const reconciliation = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/rapprochements/page.tsx");
const quickActions = source("../transactions/transaction-quick-actions.ts");
const filters = source("../transactions/components/transaction-filters.tsx");
const accountList = source("../../app/dossiers/[protectedPersonId]/comptes/page.tsx");

test("le journal ne duplique plus les destinations portées par les onglets", () => {
  assert.doesNotMatch(operations, />\s*Relevés\s*<\/Link>/);
  assert.doesNotMatch(operations, />\s*Informations du compte\s*<\/Link>/);
  assert.match(operations, /<TransactionQuickActions/);
  for (const label of ["Ajouter une recette", "Ajouter une dépense", "Effectuer un virement"]) {
    assert.match(quickActions, new RegExp(label));
  }
  assert.match(source("../transactions/components/transaction-quick-actions.tsx"), /Saisie successive/);
});

test("Informations conserve les données et Modifier sans résumé ni liens redondants", () => {
  assert.match(detail, /Solde actuel calculé/);
  assert.match(detail, /<h2 className="text-base font-bold">Informations<\/h2>/);
  assert.match(detail, /account\.account_reference && <Data label="Référence"/);
  assert.match(detail, />Modifier<\/Link>/);
  assert.doesNotMatch(detail, /Dernières opérations|Ajouter un autre compte/);
  assert.doesNotMatch(detail, />Relevés<\/Link>/);
});

test("la gestion courante et la suppression destructive restent distinctes selon les rôles", () => {
  assert.match(detail, />Gestion du compte<\/h2>/);
  assert.doesNotMatch(detail, /Cycle de vie du compte/);
  assert.match(detail, /person\.accessRole !== "read_only" && <section[^\n]+Gestion du compte/);
  assert.match(detail, /person\.accessRole === "owner" && <section className="mt-4 rounded-xl border border-red-200 bg-red-50\/50 p-4"/);
  assert.match(detail, />Suppression du compte<\/h2>/);
  assert.match(detail, /<CloseAccountForm[\s\S]*?<ReopenAccountForm/);
  assert.match(detail, /<DeleteAccountForm/);
});

test("Rapprochements est une destination réelle préparatoire sans fonctions documentaires dupliquées", () => {
  assert.match(reconciliation, /export default async function AccountReconciliationsPage/);
  assert.match(reconciliation, /current="reconciliations"/);
  assert.match(reconciliation, /getBankReconciliationListStates/);
  assert.match(reconciliation, /Non commencés/);
  assert.match(reconciliation, /Brouillons/);
  assert.match(reconciliation, /Validés/);
  assert.match(reconciliation, /Accéder aux contrôles dans Relevés/);
  assert.doesNotMatch(reconciliation, /Ajouter un relevé|Voir le PDF|Télécharger|BankStatementManager/);
});

test("les points d'entrée réutilisent le choix transactionnel ou valorisé partagé", () => {
  assert.match(accountList, /getFinancialAccountEntryHref\(protectedPersonId, account\.id, isValuationAccount\(account\.account_type\)\)/);
  assert.match(filters, /getFinancialAccountEntryHref\(personId, account\.id, isValuationAccount\(account\.account_type\)\)/);
});
