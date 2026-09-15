import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { aggregateStableReportOperations } from "./stable-calculations.ts";

const resourceId = "11111111-1111-4111-8111-111111111111";
const expenseId = "22222222-2222-4222-8222-222222222222";
const preciseExpenseId = "33333333-3333-4333-8333-333333333333";
const placementExpenseId = "44444444-4444-4444-8444-444444444444";
const accountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const placementAccountId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const securitiesAccountId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function category(overrides = {}) {
  return {
    id: expenseId,
    owner_id: null,
    name: "Dépense officielle",
    usage: "expense",
    is_system: true,
    active: true,
    official_code: "DEP-1-01",
    official_section: "Dépenses",
    official_group: "Vie quotidienne",
    official_order: 101,
    official_category_id: null,
    requires_precision: false,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

const officialCategories = [
  category({
    id: resourceId,
    name: "Ressource officielle",
    usage: "income",
    official_code: "RES-1-01",
    official_order: 1,
  }),
  category(),
  category({
    id: preciseExpenseId,
    name: "Autre dépense",
    official_code: "DEP-1-08",
    official_order: 108,
    requires_precision: true,
  }),
  category({
    id: placementExpenseId,
    name: "Placements mobiliers",
    official_code: "DEP-8-01",
    official_order: 801,
    requires_precision: true,
  }),
];

function account(overrides = {}) {
  return {
    id: accountId,
    account_type: "checking",
    ...overrides,
  };
}

const accounts = [
  account(),
  account({ id: placementAccountId, account_type: "life_insurance" }),
  account({ id: securitiesAccountId, account_type: "securities_account" }),
];

function transaction(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    financial_account_id: accountId,
    transaction_date: "2026-01-15",
    transaction_type: "expense",
    label: "Opération",
    amount: 10,
    category_id: null,
    transfer_id: null,
    proof_reference: null,
    comment: null,
    accounting_nature: "ordinary",
    official_category_id: expenseId,
    classification_precision: null,
    created_at: "2026-01-15T00:00:00Z",
    updated_at: "2026-01-15T00:00:00Z",
    ...overrides,
  };
}

function aggregate(transactions, categories = officialCategories) {
  return aggregateStableReportOperations(transactions, categories, accounts);
}

test("agrège une ressource ordinaire depuis official_category_id", () => {
  const result = aggregate([
    transaction({ transaction_type: "income", official_category_id: resourceId, amount: 25 }),
  ]);
  assert.equal(result.resources[0].officialCode, "RES-1-01");
  assert.equal(result.resources[0].amount, 25);
  assert.deepEqual(result.expenses, []);
});

test("agrège une dépense ordinaire depuis official_category_id", () => {
  const result = aggregate([transaction({ amount: 18 })]);
  assert.equal(result.expenses[0].officialCode, "DEP-1-01");
  assert.equal(result.expenses[0].amount, 18);
  assert.deepEqual(result.resources, []);
});

test("additionne plusieurs opérations de la même rubrique officielle", () => {
  const result = aggregate([transaction({ amount: 12 }), transaction({ amount: 8 })]);
  assert.equal(result.expenses.length, 1);
  assert.equal(result.expenses[0].amount, 20);
});

test("accepte une précision obligatoire présente", () => {
  const result = aggregate([
    transaction({ official_category_id: preciseExpenseId, classification_precision: "Coiffeur" }),
  ]);
  assert.equal(result.needsPrecision, 0);
  assert.equal(result.expenses[0].amount, 10);
});

test("signale une précision obligatoire absente sans retirer le montant", () => {
  const result = aggregate([
    transaction({ official_category_id: preciseExpenseId, classification_precision: null, amount: 31 }),
  ]);
  assert.equal(result.needsPrecision, 1);
  assert.equal(result.unclassified, 0);
  assert.equal(result.expenses[0].amount, 31);
});

test("exclut un mouvement de capital des totaux et de l'incomplétude", () => {
  const result = aggregate([
    transaction({ accounting_nature: "capital_movement", official_category_id: null, amount: 500 }),
  ]);
  assert.deepEqual(result.resources, []);
  assert.deepEqual(result.expenses, []);
  assert.equal(result.unclassified, 0);
  assert.equal(result.needsPrecision, 0);
});

test("conserve la règle transfert entrant vers placement en DEP-8-01", () => {
  const result = aggregate([
    transaction({
      financial_account_id: placementAccountId,
      transaction_type: "transfer_in",
      transfer_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      accounting_nature: null,
      official_category_id: null,
      amount: 75,
    }),
    transaction({
      transaction_type: "transfer_out",
      transfer_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      accounting_nature: null,
      official_category_id: null,
      amount: 75,
    }),
  ]);
  assert.equal(result.expenses[0].officialCode, "DEP-8-01");
  assert.equal(result.expenses[0].amount, 75);
  assert.equal(result.unclassified, 0);
});

test("applique DEP-8-01 au transfert entrant vers un compte-titres", () => {
  const result = aggregate([
    transaction({
      financial_account_id: securitiesAccountId,
      transaction_type: "transfer_in",
      transfer_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      accounting_nature: null,
      official_category_id: null,
      amount: 120,
    }),
    transaction({
      transaction_type: "transfer_out",
      transfer_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      accounting_nature: null,
      official_category_id: null,
      amount: 120,
    }),
  ]);
  assert.equal(result.expenses[0].officialCode, "DEP-8-01");
  assert.equal(result.expenses[0].amount, 120);
  assert.equal(result.unclassified, 0);
});

test("laisse une opération analogue à E01 non classifiée", () => {
  const result = aggregate([
    transaction({ accounting_nature: null, official_category_id: null, category_id: expenseId }),
  ]);
  assert.equal(result.unclassified, 1);
  assert.deepEqual(result.expenses, []);
});

test("comptabilise une opération analogue à U19 comme ressource RES-4-03", () => {
  const u19Category = category({
    id: "55555555-5555-4555-8555-555555555555",
    name: "Remboursements",
    usage: "income",
    official_code: "RES-4-03",
    official_order: 403,
  });
  const result = aggregate([
    transaction({
      transaction_type: "income",
      amount: 32,
      category_id: null,
      official_category_id: u19Category.id,
    }),
  ], [...officialCategories, u19Category]);
  assert.equal(result.resources[0].officialCode, "RES-4-03");
  assert.equal(result.resources[0].amount, 32);
});

test("ignore category_id même lorsqu'il désigne une rubrique divergente", () => {
  const result = aggregate([
    transaction({ category_id: resourceId, official_category_id: expenseId, amount: 14 }),
  ]);
  assert.deepEqual(result.resources, []);
  assert.equal(result.expenses[0].officialCode, "DEP-1-01");
  assert.equal(result.expenses[0].amount, 14);
});

test("reste identique quels que soient les presets personnels chargés", () => {
  const input = [transaction({ category_id: "preset-a", official_category_id: expenseId })];
  const presetA = category({
    id: "preset-a",
    owner_id: "user-a",
    name: "Preset A",
    is_system: false,
    official_code: null,
    official_category_id: resourceId,
  });
  const presetB = category({
    id: "preset-b",
    owner_id: "user-b",
    name: "Preset B",
    is_system: false,
    official_code: null,
    official_category_id: preciseExpenseId,
  });
  assert.deepEqual(
    aggregate(input, [...officialCategories, presetA]),
    aggregate(input, [...officialCategories, presetB]),
  );
});

test("refuse une rubrique officielle dont l'usage contredit le sens bancaire", () => {
  const result = aggregate([
    transaction({ transaction_type: "income", official_category_id: expenseId }),
  ]);
  assert.equal(result.unclassified, 1);
  assert.deepEqual(result.resources, []);
  assert.deepEqual(result.expenses, []);
});

test("branche le snapshot live sur le moteur stable et sa complétude de précision", () => {
  const source = readFileSync(new URL("./services.ts", import.meta.url), "utf8");
  const snapshotStart = source.indexOf(
    "export async function getManagementReportSnapshot",
  );
  const snapshotEnd = source.indexOf(
    "export async function getLiveManagementReportPreview",
  );
  const snapshotSource = source.slice(snapshotStart, snapshotEnd);

  assert.ok(snapshotStart >= 0 && snapshotEnd > snapshotStart);
  assert.match(
    source,
    /import \{ aggregateStableReportOperations \} from "\.\/stable-calculations";/,
  );
  assert.match(snapshotSource, /aggregateStableReportOperations\(/);
  assert.doesNotMatch(snapshotSource, /aggregateReportOperations\(/);
  assert.match(
    snapshotSource,
    /aggregation\.unclassified === 0 && needsPrecision === 0/,
  );
  assert.match(
    snapshotSource,
    /const \{ needsPrecision, \.\.\.aggregation \} = stableAggregation;/,
  );
});
