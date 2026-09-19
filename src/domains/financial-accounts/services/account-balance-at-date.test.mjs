import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  calculateAccountBalanceAtDate,
  getMinimumAccountBalanceDate,
  validateAccountBalanceDate,
  validateAccountBalanceContext,
} from "./account-balance-at-date.ts";
import {
  loadCompleteTransactionHistory,
  TRANSACTION_HISTORY_PAGE_SIZE,
} from "../../transactions/services/transaction-history.ts";

const serviceSource = readFileSync(new URL("./financial-account-service.ts", import.meta.url), "utf8");

function movement(transactionType, amount, transactionDate = "2026-05-31") {
  return { amount, transaction_date: transactionDate, transaction_type: transactionType };
}

const openAccount = {
  initial_balance_date: "2026-01-01",
  opening_date: null,
  closing_date: null,
};

test("calcule le solde initial sans opération et conserve les centimes", () => {
  assert.deepEqual(calculateAccountBalanceAtDate(125.37, [], "2026-05-31"), {
    balance: 125.37,
    balanceInCents: 12537,
  });
  assert.equal(calculateAccountBalanceAtDate(-42.19, [], "2026-05-31").balanceInCents, -4219);
});

test("additionne recettes et virements entrants et soustrait dépenses et virements sortants", () => {
  const transactions = [
    movement("income", 100.01),
    movement("transfer_in", 50.02),
    movement("expense", 20.03),
    movement("transfer_out", 10.04),
  ];
  assert.deepEqual(calculateAccountBalanceAtDate(0.05, transactions, "2026-05-31"), {
    balance: 120.01,
    balanceInCents: 12001,
  });
});

test("inclut toutes les opérations de D et exclut D+1", () => {
  const transactions = [
    movement("income", 10, "2026-05-31"),
    movement("expense", 3, "2026-05-31"),
    movement("income", 999, "2026-06-01"),
  ];
  assert.equal(calculateAccountBalanceAtDate(1, transactions, "2026-05-31").balance, 8);
});

test("applique la plus tardive des dates initiale et d'ouverture", () => {
  assert.equal(getMinimumAccountBalanceDate(openAccount), "2026-01-01");
  assert.equal(getMinimumAccountBalanceDate({ ...openAccount, opening_date: "2026-02-01" }), "2026-02-01");
  assert.equal(getMinimumAccountBalanceDate({ ...openAccount, opening_date: "2025-12-01" }), "2026-01-01");
  assert.throws(
    () => validateAccountBalanceDate({ ...openAccount, opening_date: "2026-02-01" }, "2026-01-31"),
    /antérieure au début du compte/,
  );
  assert.doesNotThrow(() => validateAccountBalanceDate(openAccount, "2026-01-01"));
});

test("autorise l'historique d'un compte clôturé jusqu'à sa date de clôture incluse", () => {
  const closedAccount = { ...openAccount, closing_date: "2026-06-30" };
  assert.doesNotThrow(() => validateAccountBalanceDate(closedAccount, "2026-06-01"));
  assert.doesNotThrow(() => validateAccountBalanceDate(closedAccount, "2026-06-30"));
  assert.throws(
    () => validateAccountBalanceDate(closedAccount, "2026-07-01"),
    /postérieure à la clôture du compte/,
  );
});

test("rejette une date civile invalide", () => {
  assert.throws(() => validateAccountBalanceDate(openAccount, "2026-02-30"), /Date de solde invalide/);
});

test("rejette un compte appartenant à un autre dossier", () => {
  const account = { ...openAccount, protected_person_id: "dossier-a" };
  assert.doesNotThrow(() => validateAccountBalanceContext(account, "dossier-a"));
  assert.throws(() => validateAccountBalanceContext(account, "dossier-b"), /Compte introuvable/);
});

async function loadMovements(count) {
  const rows = Array.from({ length: count }, (_, index) => ({
    id: `transaction-${index}`,
    ...movement(index % 2 === 0 ? "income" : "expense", 1),
  }));
  const ranges = [];
  const loaded = await loadCompleteTransactionHistory(async (from, to) => {
    ranges.push([from, to]);
    return { data: rows.slice(from, to + 1), error: null };
  });
  return { loaded, ranges };
}

for (const count of [999, 1000, 1001, 1201, 5000, 10000]) {
  test(`calcule exactement l'historique exhaustif de ${count} opérations`, async () => {
    const { loaded, ranges } = await loadMovements(count);
    assert.equal(loaded.length, count);
    assert.equal(new Set(loaded.map((row) => row.id)).size, count);
    assert.ok(ranges.every(([from, to]) => to - from + 1 === TRANSACTION_HISTORY_PAGE_SIZE));
    const expected = count % 2 === 0 ? 0 : 100;
    assert.equal(calculateAccountBalanceAtDate(0, loaded, "2026-05-31").balanceInCents, expected);
  });
}

test("le service valide dossier, lecture RLS, date et historique complet sans période de gestion", () => {
  assert.match(serviceSource, /requireOwnedAccount\(financialAccountId\)/);
  assert.match(serviceSource, /validateAccountBalanceContext\(account, protectedPersonId\)/);
  assert.match(serviceSource, /validateAccountBalanceDate\(account, date\)/);
  assert.match(serviceSource, /loadCompleteTransactionHistory/);
  assert.match(serviceSource, /\.eq\("financial_account_id", financialAccountId\)/);
  assert.match(serviceSource, /\.lte\("transaction_date", date\)/);
  assert.doesNotMatch(serviceSource, /management_period/);
});

test("un mauvais compte ou un compte d'un autre dossier ne peut pas produire un solde", () => {
  assert.match(serviceSource, /validateAccountBalanceContext\(account, protectedPersonId\)/);
  assert.match(serviceSource, /if \(error \|\| !account\) throw new Error\("Compte introuvable\."\)/);
});
