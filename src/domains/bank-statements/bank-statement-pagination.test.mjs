import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  BANK_STATEMENT_PAGE_SIZE,
  getBankStatementPageHref,
  getBankStatementPageMetadata,
  parseBankStatementPage,
} from "./bank-statement-pagination.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./services.ts");
const statementsPage = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/releves/page.tsx");
const reconciliationsPage = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/rapprochements/page.tsx");
const statementManager = source("./components/bank-statement-manager.tsx");
const reconciliationManager = source("./components/bank-reconciliation-manager.tsx");
const pagination = source("./components/bank-statement-pagination.tsx");

test("la pagination fixe des relevés normalise les pages et couvre plus de 1 000 lignes", () => {
  assert.equal(BANK_STATEMENT_PAGE_SIZE, 25);
  assert.deepEqual(getBankStatementPageMetadata(0, 1), {
    page: 1,
    pageSize: 25,
    totalCount: 0,
    totalPages: 0,
  });
  assert.equal(getBankStatementPageMetadata(25, 1).totalPages, 1);
  assert.equal(getBankStatementPageMetadata(26, 1).totalPages, 2);
  assert.deepEqual(getBankStatementPageMetadata(2501, 999), {
    page: 101,
    pageSize: 25,
    totalCount: 2501,
    totalPages: 101,
  });
  for (const value of [undefined, "", "0", "-1", "1.5", "abc", "9007199254740992"]) {
    assert.equal(parseBankStatementPage(value), 1);
  }
  assert.equal(parseBankStatementPage(["3", "4"]), 3);
});

test("la requête serveur normalise avec un total exact avant le triple tri et le range", () => {
  const pagedService = service.match(/export async function getBankStatementPage[\s\S]*?(?=\nexport async function getBankStatement\()/)?.[0];
  assert.ok(pagedService);
  assert.match(pagedService, /select\("id", \{ count: "exact", head: true \}\)/);
  assert.match(pagedService, /getBankStatementPageMetadata\(countResult\.count \?\? 0, requestedPage\)/);
  assert.match(pagedService, /order\("statement_end_date", \{ ascending: false \}\)[\s\S]*order\("created_at", \{ ascending: false \}\)[\s\S]*order\("id", \{ ascending: false \}\)/);
  assert.match(pagedService, /range\(offset, offset \+ BANK_STATEMENT_PAGE_SIZE - 1\)/);
  assert.match(pagedService, /metadata\.page - 1/);
});

test("les liens précédent et suivant conservent les paramètres utiles", () => {
  const pathname = "/dossiers/personne/comptes/compte/releves";
  const href = getBankStatementPageHref(pathname, { page: "2", vue: "archive", filtre: ["a", "b"] }, 3);
  const url = new URL(href, "https://patrigest.internal");
  assert.equal(url.searchParams.get("page"), "3");
  assert.equal(url.searchParams.get("vue"), "archive");
  assert.deepEqual(url.searchParams.getAll("filtre"), ["a", "b"]);
  assert.equal(getBankStatementPageHref(pathname, { page: "8" }, 1), pathname);
  assert.equal(getBankStatementPageHref(pathname, { vue: "archive" }, 101), `${pathname}?vue=archive&page=101`);
  assert.match(pagination, /label="Première page"[\s\S]*?>\s*\|&lt;\s*</);
  assert.match(pagination, /label="Dernière page"[\s\S]*?>\s*&gt;\|\s*</);
  assert.doesNotMatch(pagination, />\s*(?:Début|Fin)\s*</);
  assert.match(pagination, /page > 1 \? getBankStatementPageHref\(pathname, values, 1\)/);
  assert.match(pagination, /Page \{page\} sur \{totalPages\}/);
  assert.match(pagination, /page > 1[\s\S]*page - 1/);
  assert.match(pagination, /page < totalPages[\s\S]*page \+ 1/);
  assert.match(pagination, /page < totalPages \? getBankStatementPageHref\(pathname, values, totalPages\)/);
});

test("les deux vues chargent seulement la page courante et ses états en lot", () => {
  for (const page of [statementsPage, reconciliationsPage]) {
    assert.match(page, /getBankStatementPage\(accountId, parseBankStatementPage\(query\.page\)\)/);
    assert.match(page, /statementPage\.items\.map\(\((?:item|statement)\) => (?:item|statement)\.id\)/);
    assert.equal((page.match(/<BankStatementPagination/g) ?? []).length, 2);
    assert.doesNotMatch(page, /getBankStatements\(/);
  }
  assert.match(source("./reconciliation-service.ts"), /RECONCILIATION_QUERY_BATCH_SIZE = 100/);
  assert.doesNotMatch(reconciliationsPage, /\.map\([^)]*getBankReconciliationListStates/s);
});

test("Relevés reste documentaire et protège les relevés validés", () => {
  for (const label of ["Ajouter un relevé", "Voir", "Télécharger", "Modifier", "Supprimer"]) {
    assert.match(statementManager, new RegExp(label));
  }
  assert.match(statementManager, /reconciliation\?\.status === "validated"/);
  assert.match(statementManager, /canManage && !isValidated/);
  assert.match(statementManager, /Contrôle validé/);
  for (const label of ["Contrôler le solde", "Afficher le contrôle", "Rapprochement détaillé", "Opérations en circulation", "Valider le contrôle"]) {
    assert.doesNotMatch(statementManager, new RegExp(label));
  }
});

test("Rapprochements réutilise toutes les actions et distingue les états et écarts par du texte", () => {
  for (const label of ["Contrôle indisponible", "Contrôle non commencé", "Brouillon", "Contrôler le solde", "Afficher le contrôle", "Recalculer", "Rapprochement détaillé", "Opérations en circulation", "Valider le contrôle", "montants figés"]) {
    assert.match(reconciliationManager, new RegExp(label));
  }
  assert.match(reconciliationManager, /control\.status === "draft" && canManage/);
  assert.match(reconciliationManager, /Les soldes concordent/);
  assert.match(reconciliationManager, /Un écart subsiste/);
  assert.match(reconciliationManager, /Rapprochement équilibré/);
  assert.match(reconciliationManager, /Un écart résiduel subsiste/);
  assert.match(reconciliationManager, /sm:grid-cols-3/);
  assert.match(reconciliationManager, /lg:grid-cols-4/);
});
