import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("les lecteurs comptables demandent explicitement les opérations actives", () => {
  const accounts = source("../financial-accounts/services/financial-account-service.ts");
  const reports = source("../management-reports/services.ts");
  const classification = source("../management-reports/classification-issue-service.ts");

  assert.ok((accounts.match(/\.is\("cancelled_at", null\)/g) ?? []).length >= 3);
  assert.match(reports, /from\("transactions"\)[\s\S]*\.is\("cancelled_at", null\)/);
  assert.match(classification, /includeCancelled: false/);
});

test("les agrégateurs conservent une défense locale contre les annulations", () => {
  const transactionUtils = source("./utils/transaction-utils.ts");
  const accountUtils = source("../financial-accounts/utils/financial-account-utils.ts");
  const stableReports = source("../management-reports/stable-calculations.ts");
  const reports = source("../management-reports/calculations.ts");

  assert.match(transactionUtils, /item\.cancelled_at \? balance/);
  assert.match(accountUtils, /filter\(\(transaction\) => !transaction\.cancelled_at\)/);
  assert.match(stableReports, /if \(transaction\.cancelled_at\) continue/);
  assert.ok((reports.match(/!item\.cancelled_at/g) ?? []).length >= 2);
});

test("la migration préserve les snapshots validés et bloque les annulations en brouillon", () => {
  const migration = source("../../../supabase/migrations/20261101500000_enforce_cancelled_transaction_accounting_consistency.sql");

  assert.match(migration, /if reconciliation_record\.status='validated'[\s\S]*transaction_id_snapshot/);
  assert.match(migration, /transaction\.cancelled_at is null/);
  assert.match(migration, /transaction_banking_impact_acknowledgements/);
  assert.match(migration, /Le brouillon contient une opération annulée ou indisponible/);
  assert.match(migration, /transaction_banking_impacts_for_reconciliation/);
});
