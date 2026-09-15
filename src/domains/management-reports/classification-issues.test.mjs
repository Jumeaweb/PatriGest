import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { aggregateStableReportOperations, getStableClassificationIssue, getStableOfficialCategoriesById, filterReportClassificationIssues } from "./stable-calculations.ts";
import { getIncludedReportAccountIds } from "./account-selection.ts";
import { getClassificationIssueActions } from "./classification-issue-actions.ts";
import { getSafeTransactionReturnTo } from "../transactions/return-to.ts";

const personId = "11111111-1111-4111-8111-111111111111";
const reportId = "22222222-2222-4222-8222-222222222222";
const otherAccountId = "33333333-3333-4333-8333-333333333333";
const autoAccountId = "44444444-4444-4444-8444-444444444444";
const includedAccountId = "55555555-5555-4555-8555-555555555555";
const excludedAccountId = "66666666-6666-4666-8666-666666666666";
const expenseId = "77777777-7777-4777-8777-777777777777";
const preciseId = "88888888-8888-4888-8888-888888888888";
const incomeId = "99999999-9999-4999-8999-999999999999";
const periodStart = "2026-01-01";
const periodEnd = "2026-12-31";
const category = (id, usage, requires_precision = false) => ({ id, name: id, is_system: true, owner_id: null, official_code: usage === "income" ? "RES-1-01" : "DEP-1-01", official_category_id: null, usage, requires_precision, official_order: 1 });
const categories = [category(expenseId, "expense"), category(preciseId, "expense", true), category(incomeId, "income")];
const account = (id, opening_date = null, closing_date = null) => ({ id, account_type: "checking", opening_date, closing_date });
const accounts = [account(autoAccountId), account(includedAccountId, "2027-01-01"), account(excludedAccountId), account(otherAccountId, "2027-01-01")];
const selections = [
  { financial_account_id: includedAccountId, selection_mode: "included_manual" },
  { financial_account_id: excludedAccountId, selection_mode: "excluded_manual" },
];
let serial = 0;
const tx = (overrides = {}) => ({ id: String(++serial), financial_account_id: autoAccountId, transaction_date: "2026-06-01", transaction_type: "expense", amount: 12, accounting_nature: "ordinary", official_category_id: expenseId, classification_precision: null, category_id: null, transfer_id: null, ...overrides });

test("les prédicats stables conservent exactement les règles des deux compteurs", () => {
  const official = getStableOfficialCategoriesById(categories);
  const cases = [
    [tx(), null],
    [tx({ official_category_id: null }), "unclassified"],
    [tx({ official_category_id: "introuvable" }), "unclassified"],
    [tx({ official_category_id: incomeId }), "unclassified"],
    [tx({ accounting_nature: null }), "unclassified"],
    [tx({ accounting_nature: null, category_id: expenseId }), "unclassified"],
    [tx({ official_category_id: null, category_id: expenseId }), "unclassified"],
    [tx({ official_category_id: preciseId, classification_precision: null }), "needs_precision"],
    [tx({ official_category_id: preciseId, classification_precision: "" }), "needs_precision"],
    [tx({ official_category_id: preciseId, classification_precision: "   " }), "needs_precision"],
    [tx({ official_category_id: preciseId, classification_precision: "Détail" }), null],
    [tx({ transaction_type: "transfer_in", transfer_id: null, official_category_id: null }), null],
    [tx({ transaction_type: "transfer_out", transfer_id: reportId, official_category_id: null }), null],
    [tx({ accounting_nature: "capital_movement", official_category_id: null }), null],
  ];
  for (const [transaction, expected] of cases) assert.equal(getStableClassificationIssue(transaction, official), expected, transaction.id);
});

test("périmètre auto/manuel et dates inclusives donnent une liste égale à chaque compteur du rapport", () => {
  const included = getIncludedReportAccountIds(accounts, selections, periodStart, periodEnd);
  assert.deepEqual(included, [autoAccountId, includedAccountId]);
  const all = [
    tx({ transaction_date: periodStart, official_category_id: null }),
    tx({ transaction_date: periodEnd, official_category_id: preciseId, classification_precision: " " }),
    tx({ financial_account_id: includedAccountId, official_category_id: null }),
    tx({ financial_account_id: includedAccountId, official_category_id: preciseId }),
    tx({ financial_account_id: excludedAccountId, official_category_id: null }),
    tx({ financial_account_id: otherAccountId, official_category_id: preciseId }),
    tx({ transaction_date: "2025-12-31", official_category_id: null }),
    tx({ transaction_date: "2027-01-01", official_category_id: preciseId }),
    tx({ transaction_type: "transfer_in", transfer_id: null, official_category_id: null }),
    tx({ accounting_nature: "capital_movement", official_category_id: null }),
    tx({ official_category_id: expenseId }),
    tx({ accounting_nature: null, category_id: expenseId }),
    tx({ official_category_id: "introuvable", category_id: expenseId }),
    tx({ official_category_id: incomeId }),
    tx({ official_category_id: preciseId, classification_precision: "" }),
    tx({ official_category_id: preciseId, classification_precision: "présente" }),
    tx({ official_category_id: null, transfer_id: reportId }),
  ];
  const reportTransactions = all.filter((item) => included.includes(item.financial_account_id) && item.transaction_date >= periodStart && item.transaction_date <= periodEnd);
  const aggregation = aggregateStableReportOperations(reportTransactions, categories, accounts.filter((item) => included.includes(item.id)));
  assert.equal(filterReportClassificationIssues(all, categories, included, periodStart, periodEnd, "unclassified").length, aggregation.unclassified);
  assert.equal(filterReportClassificationIssues(all, categories, included, periodStart, periodEnd, "needs_precision").length, aggregation.needsPrecision);
  assert.equal(aggregation.unclassified, 6);
  assert.equal(aggregation.needsPrecision, 3);
});

test("les CTA sont distinctes, limitées au brouillon et aux compteurs positifs, avec libellés selon les droits", () => {
  const counts = { unclassified: 2, needsPrecision: 1 };
  for (const canManage of [true, false]) {
    const actions = getClassificationIssueActions(personId, reportId, "draft", counts, canManage);
    assert.deepEqual(actions.map((action) => action.issue), ["unclassified", "needs_precision"]);
    assert.ok(actions.every((action) => action.href.includes(`reportId=${reportId}`)));
    assert.ok(actions.every((action) => canManage ? !action.label.startsWith("Voir") : action.label.startsWith("Voir")));
  }
  assert.deepEqual(getClassificationIssueActions(personId, reportId, "draft", { unclassified: 0, needsPrecision: 1 }, true).map((item) => item.issue), ["needs_precision"]);
  for (const status of ["ready", "generated", "finalized", "approved"]) assert.deepEqual(getClassificationIssueActions(personId, reportId, status, counts, true), []);
});

test("returnTo garde les deux paramètres contrôlés et rejette les destinations dangereuses ou incomplètes", () => {
  const root = `/dossiers/${personId}/operations`;
  for (const issue of ["unclassified", "needs_precision"]) {
    const href = `${root}?reportId=${reportId}&classificationIssue=${issue}`;
    assert.equal(getSafeTransactionReturnTo(personId, href), href);
  }
  for (const href of [
    `${root}?reportId=invalid&classificationIssue=unclassified`,
    `${root}?reportId=${reportId}&classificationIssue=other`,
    `${root}?reportId=${reportId}`,
    `${root}?classificationIssue=unclassified`,
    `${root}?reportId=${reportId}&classificationIssue=unclassified&start=2026-01-01`,
    `${root}?reportId=${reportId}&reportId=${reportId}&classificationIssue=unclassified`,
    `//attacker.example/path`,
    `https://attacker.example/path`,
  ]) assert.equal(getSafeTransactionReturnTo(personId, href), root);
});

test("la route reconstruit le report côté serveur et le journal rend les formes structurelles non cliquables", () => {
  const service = readFileSync(new URL("./classification-issue-service.ts", import.meta.url), "utf8");
  const page = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/page.tsx", import.meta.url), "utf8");
  const journal = readFileSync(new URL("../transactions/components/transaction-journal.tsx", import.meta.url), "utf8");
  const edit = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/operations/[transactionId]/modifier/page.tsx", import.meta.url), "utf8");
  assert.match(service, /\.eq\("id", reportId\)\.eq\("protected_person_id", personId\)/);
  assert.match(service, /getIncludedReportAccountIds\(accounts, selectionResult\.data, report\.period_start, report\.period_end\)/);
  assert.match(service, /filterReportClassificationIssues\(transactions, categoryResult\.data/);
  assert.match(page, /Object\.keys\(search\)\.some\(\(key\) => key !== "reportId" && key !== "classificationIssue"\)/);
  assert.match(page, /Revenir au compte de gestion/);
  assert.match(journal, /structural \? undefined : open/);
  assert.match(journal, /href && !structural/);
  assert.match(journal, /accessRole === "read_only" \|\| closed \? "Consulter uniquement"/);
  assert.match(edit, /transaction\.transfer_id/);
});

test("une opération corrigée sort naturellement du filtre sans écriture dans le parcours correctif", () => {
  const before = tx({ official_category_id: null });
  const after = { ...before, official_category_id: expenseId };
  const included = [autoAccountId];
  assert.deepEqual(filterReportClassificationIssues([before], categories, included, periodStart, periodEnd, "unclassified"), [before]);
  assert.deepEqual(filterReportClassificationIssues([after], categories, included, periodStart, periodEnd, "unclassified"), []);
});
