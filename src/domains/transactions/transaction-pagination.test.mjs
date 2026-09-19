import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { calculateRunningBalances } from "./utils/transaction-utils.ts";
import {
  getTransactionJournalPageHref,
  getTransactionPageMetadata,
  parseTransactionPage,
  TRANSACTION_JOURNAL_PAGE_SIZE,
} from "./transaction-pagination.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./services/transaction-service.ts");
const globalPage = source("../../app/dossiers/[protectedPersonId]/operations/page.tsx");
const accountPage = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/operations/page.tsx");
const globalFilters = source("./components/transaction-filters.tsx");
const journal = source("./components/transaction-journal.tsx");
const pagination = source("./components/transaction-pagination.tsx");

test("la taille fixe et les bornes couvrent 0, 1, 50, 51 et plusieurs pages", () => {
  assert.equal(TRANSACTION_JOURNAL_PAGE_SIZE, 50);
  assert.deepEqual(getTransactionPageMetadata(0, 1), { page: 1, pageSize: 50, totalCount: 0, totalPages: 0 });
  assert.equal(getTransactionPageMetadata(1, 1).totalPages, 1);
  assert.equal(getTransactionPageMetadata(50, 1).totalPages, 1);
  assert.equal(getTransactionPageMetadata(51, 1).totalPages, 2);
  assert.deepEqual(getTransactionPageMetadata(251, 99), { page: 6, pageSize: 50, totalCount: 251, totalPages: 6 });
});

test("une page absente, invalide, décimale ou non positive revient à 1", () => {
  for (const value of [undefined, "", "0", "-1", "1.5", "abc", "9007199254740992"]) {
    assert.equal(parseTransactionPage(value), 1);
  }
  assert.equal(parseTransactionPage("2"), 2);
});

test("la requête paginée impose count exact, ordre stable et range de 50", () => {
  const pagedService = service.match(/export async function getTransactionJournalPage[\s\S]*?(?=\nexport async function getTransaction\()/)?.[0];
  assert.ok(pagedService);
  assert.match(pagedService, /select\("\*", \{ count: "exact" \}\)/);
  assert.match(pagedService, /order\("transaction_date", \{ ascending: false \}\)[\s\S]*order\("created_at", \{ ascending: false \}\)[\s\S]*order\("id", \{ ascending: false \}\)/);
  assert.match(pagedService, /range\(offset, offset \+ TRANSACTION_JOURNAL_PAGE_SIZE - 1\)/);
  assert.match(pagedService, /if \(filters\.query\)[^\n]+\.ilike\("label"/);
  assert.match(pagedService, /enrichTransactions\(supabase, accounts, data \?\? \[\]\)/);
});

test("les filtres et la recherche restent présents dans les liens", () => {
  const pathname = "/dossiers/personne/operations";
  const href = getTransactionJournalPageHref(pathname, {
    start: "2026-01-01",
    end: "2026-12-31",
    account: "compte",
    type: "expense",
    category: "categorie",
    q: "assurance habitation",
  }, 3);
  const url = new URL(href, "https://patrigest.internal");
  assert.equal(url.searchParams.get("page"), "3");
  assert.equal(url.searchParams.get("q"), "assurance habitation");
  assert.deepEqual([...url.searchParams.keys()], ["start", "end", "account", "type", "category", "q", "page"]);
  assert.equal(getTransactionJournalPageHref(pathname, { q: "test" }, 1), `${pathname}?q=test`);
});

test("un nouveau filtrage repart page 1", () => {
  assert.doesNotMatch(globalFilters, /name="page"/);
  assert.doesNotMatch(accountPage, /name="page"/);
});

test("les journaux global et compte utilisent le service paginé partagé", () => {
  assert.match(globalPage, /getTransactionJournalPage\(protectedPersonId/);
  assert.match(accountPage, /getTransactionJournalPage\(protectedPersonId/);
  assert.match(globalPage, /<TransactionPagination/);
  assert.match(accountPage, /<TransactionPagination/);
  assert.equal((globalPage.match(/<TransactionPagination/g) ?? []).length, 2);
  assert.equal((accountPage.match(/<TransactionPagination/g) ?? []).length, 2);
  assert.match(pagination, /Première page/);
  assert.match(pagination, /Page précédente/);
  assert.match(pagination, /Page \{page\} sur \{totalPages\}/);
  assert.match(pagination, /Page suivante/);
  assert.match(pagination, /Dernière page/);
  assert.match(pagination, /page > 1[\s\S]*page - 1/);
  assert.match(pagination, /page < totalPages[\s\S]*page \+ 1/);
  assert.match(pagination, /page < totalPages[\s\S]*totalPages/);
});

test("desktop et mobile reçoivent exactement les mêmes items paginés", () => {
  assert.equal((journal.match(/ordered\.map\(\(item\)/g) ?? []).length, 2);
  assert.match(journal, /ordered\.map\(\(item\) => <Row/);
  assert.match(journal, /ordered\.map\(\(item\) => <Card/);
});

test("les soldes de la page restent issus de l'historique complet", () => {
  const transactions = Array.from({ length: 75 }, (_, index) => ({
    id: `transaction-${String(index).padStart(3, "0")}`,
    transaction_date: `2026-${String(Math.floor(index / 28) + 1).padStart(2, "0")}-${String(index % 28 + 1).padStart(2, "0")}`,
    created_at: `2026-01-01T00:${String(index).padStart(2, "0")}:00Z`,
    transaction_type: index % 2 ? "expense" : "income",
    amount: index + 1,
  }));
  const completeBalances = calculateRunningBalances(1000, transactions);
  const displayedPage = [...transactions].sort((left, right) => right.id.localeCompare(left.id)).slice(50);
  for (const transaction of displayedPage) {
    assert.equal(completeBalances.get(transaction.id), calculateRunningBalances(1000, transactions).get(transaction.id));
  }
  assert.match(accountPage, /calculateRunningBalances\(account\.initial_balance, account\.transactions\)/);
  assert.match(accountPage, /account\.status === "active"/);
});

test("enrichissements, classification et erreurs restent limités aux lignes de page", () => {
  assert.match(service, /const transactionIds = data\.map/);
  assert.match(service, /const transferIds = \[\.\.\.new Set\(data\.map/);
  assert.match(service, /loadTransactionDocumentsInBatches\(transactionIds/);
  assert.match(service, /resolveEffectiveTransactionClassification/);
  assert.match(service, /throw new Error\("Impossible de charger les justificatifs\."\)/);
});

test("le mode correctif conserve son chemin complet non paginé", () => {
  assert.match(globalPage, /correctiveRequested[\s\S]*getReportClassificationIssueJournal/);
  assert.match(globalPage, /const journalPage = corrective \? null : await getTransactionJournalPage/);
  assert.match(globalPage, /const items = corrective \? corrective\.items : journalPage!\.items/);
});
