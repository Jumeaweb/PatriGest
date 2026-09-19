import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { calculateClassicBalance, calculateRunningBalances } from "../utils/transaction-utils.ts";
import { loadCompleteTransactionHistory, TRANSACTION_HISTORY_PAGE_SIZE } from "./transaction-history.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

function transactions(count, accountId = "account-open") {
  return Array.from({ length: count }, (_, index) => ({
    id: `transaction-${String(index).padStart(5, "0")}`,
    financial_account_id: accountId,
    transaction_date: "2026-01-01",
    created_at: "2026-01-01T00:00:00.000Z",
    transaction_type: "income",
    amount: 1,
    transfer_id: null,
  }));
}

async function load(rows) {
  const ranges = [];
  const result = await loadCompleteTransactionHistory(async (from, to) => {
    ranges.push([from, to]);
    return { data: rows.slice(from, to + 1), error: null };
  });
  return { result, ranges };
}

for (const count of [999, 1000, 1001, 1201, 5000, 10000]) {
  test(`charge sans perte ni doublon un historique de ${count} opérations`, async () => {
    const rows = transactions(count);
    const { result, ranges } = await load(rows);
    assert.equal(result.length, count);
    assert.equal(new Set(result.map((row) => row.id)).size, count);
    assert.deepEqual(result.map((row) => row.id), rows.map((row) => row.id));
    assert.ok(ranges.every(([from, to]) => to - from + 1 === TRANSACTION_HISTORY_PAGE_SIZE));
  });
}

test("les soldes et la valeur financière sous-jacente utilisent les 1201 opérations", async () => {
  const loaded = (await load(transactions(1201))).result;
  const balances = calculateRunningBalances(100, loaded);
  assert.equal(balances.get("transaction-01200"), 1301);
  assert.equal(calculateClassicBalance(100, loaded), 1301);

  const financialUtils = source("../../financial-accounts/utils/financial-account-utils.ts");
  assert.match(financialUtils, /calculateClassicBalance\(account\.initial_balance, movements\)/);
  assert.match(financialUtils, /getCurrentAccountValue\(account, account\.valuations, account\.transactions\)\.value/);
});

test("toutes les lectures financières exhaustives utilisent le chargeur interne paginé", () => {
  const accounts = source("../../financial-accounts/services/financial-account-service.ts");
  const transactionsService = source("./transaction-service.ts");
  const reports = source("../../management-reports/services.ts");
  assert.ok((accounts.match(/loadCompleteTransactionHistory/g) ?? []).length >= 3);
  assert.match(transactionsService, /loadCompleteTransactionHistory\(\(from, to\) => buildQuery\(\)\.range\(from, to\)\)/);
  assert.match(reports, /loadCompleteTransactionHistory[\s\S]*\.range\(from, to\)/);
  for (const code of [accounts, transactionsService, reports]) {
    assert.match(code, /order\("transaction_date", \{ ascending: false \}\)[\s\S]*order\("created_at", \{ ascending: false \}\)[\s\S]*order\("id", \{ ascending: false \}\)/);
  }
});

test("une erreur de page interrompt la lecture exhaustive", async () => {
  await assert.rejects(
    loadCompleteTransactionHistory(async (from) => from === 0
      ? { data: transactions(TRANSACTION_HISTORY_PAGE_SIZE), error: null }
      : { data: null, error: new Error("page failure") }),
    /page failure/,
  );
});
