import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { calculateClassicBalance } from "../transactions/utils/transaction-utils.ts";
import { getCurrentValuationValue } from "./utils/account-valuation-utils.ts";
import { calculateValuationTransferAdjustment } from "./utils/valuation-transfer-adjustment.ts";

const accountUtilsSource = readFileSync(
  new URL("./utils/financial-account-utils.ts", import.meta.url),
  "utf8",
);
const accountListSource = readFileSync(
  new URL("../../app/dossiers/[protectedPersonId]/comptes/page.tsx", import.meta.url),
  "utf8",
);
const accountDetailSource = readFileSync(
  new URL("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/page.tsx", import.meta.url),
  "utf8",
);

function account(overrides = {}) {
  return {
    id: "account",
    protected_person_id: "person",
    account_type: "checking",
    institution_name: "Banque",
    account_name: "Compte",
    account_reference: null,
    initial_balance: 1_000,
    initial_balance_date: "2026-01-01",
    opening_date: "2026-01-01",
    closing_date: null,
    status: "active",
    notes: null,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    valuations: [],
    transactions: [],
    ...overrides,
  };
}

function movement(overrides = {}) {
  return {
    id: "movement",
    financial_account_id: "account",
    transaction_date: "2026-02-01",
    transaction_type: "transfer_in",
    label: "Virement",
    amount: 100,
    category_id: null,
    transfer_id: "transfer",
    proof_reference: null,
    comment: null,
    accounting_nature: null,
    official_category_id: null,
    classification_precision: null,
    created_at: "2026-02-01T00:00:00Z",
    updated_at: "2026-02-01T00:00:00Z",
    revision: 1,
    cancelled_at: null,
    cancelled_by: null,
    ...overrides,
  };
}

function valuation(accountId, date, value) {
  return {
    id: `${accountId}-${date}`,
    financial_account_id: accountId,
    valuation_date: date,
    value,
    comment: null,
    created_at: `${date}T00:00:00Z`,
  };
}

function valuationValue(accountInput) {
  const current = getCurrentValuationValue(accountInput.initial_balance, accountInput.valuations);
  const baselineDate = current.valuation?.valuation_date
    ?? (accountInput.opening_date && accountInput.opening_date > accountInput.initial_balance_date
      ? accountInput.opening_date
      : accountInput.initial_balance_date);
  return current.value + calculateValuationTransferAdjustment(accountInput.transactions, baselineDate);
}

test("les comptes ordinaires conservent leur calcul intégral par opérations", () => {
  for (const accountType of ["checking", "livret_a", "ldds", "csl", "lep", "pel", "term_account"]) {
    const transactions = [
      movement({ id: "out", transaction_type: "transfer_out", amount: 120 }),
      movement({ id: "in", transaction_type: "transfer_in", amount: 40 }),
    ];
    assert.equal(calculateClassicBalance(1_000, transactions), 920, accountType);
  }
});

test("les virements compte courant vers compte courant ou livret restent neutres", () => {
  for (const [sourceType, destinationType] of [
    ["checking", "checking"],
    ["checking", "ldds"],
    ["ldds", "checking"],
  ]) {
    const sourceBalance = calculateClassicBalance(1_000, [movement({ transaction_type: "transfer_out", amount: 125 })]);
    const destinationBalance = calculateClassicBalance(500, [movement({ transaction_type: "transfer_in", amount: 125 })]);
    assert.equal(sourceBalance, 875, sourceType);
    assert.equal(destinationBalance, 625, destinationType);
    assert.equal(sourceBalance + destinationBalance, 1_500, `${sourceType} -> ${destinationType}`);
  }
});

test("cumule les versements et retraits postérieurs à la dernière valorisation", () => {
  const lifeInsurance = account({ id: "life", account_type: "life_insurance" });
  const valuations = [valuation("life", "2026-01-31", 1_200)];
  const transactions = [
    movement({ id: "monthly-1", financial_account_id: "life", transaction_date: "2026-02-05", amount: 100 }),
    movement({ id: "monthly-2", financial_account_id: "life", transaction_date: "2026-03-05", amount: 100 }),
    movement({ id: "withdrawal", financial_account_id: "life", transaction_date: "2026-03-10", transaction_type: "transfer_out", amount: 30 }),
  ];
  assert.equal(valuationValue({ ...lifeInsurance, valuations, transactions }), 1_370);
});

test("une nouvelle valorisation remplace la référence et absorbe les virements antérieurs", () => {
  const lifeInsurance = account({ id: "life", account_type: "life_insurance" });
  const latest = valuation("life", "2026-03-15", 1_500);
  const valuations = [valuation("life", "2026-01-31", 1_200), latest];
  const transactions = [
    movement({ id: "before", financial_account_id: "life", transaction_date: "2026-03-05", amount: 100 }),
    movement({ id: "after", financial_account_id: "life", transaction_date: "2026-03-20", transaction_type: "transfer_out", amount: 40 }),
  ];
  assert.equal(valuationValue({ ...lifeInsurance, valuations, transactions }), 1_460);
});

test("sans valorisation, utilise le solde initial après la date de référence la plus tardive", () => {
  const lifeInsurance = account({
    id: "life",
    account_type: "life_insurance",
    initial_balance: 500,
    initial_balance_date: "2026-01-15",
    opening_date: "2026-02-01",
  });
  const transactions = [
    movement({ id: "before-opening", financial_account_id: "life", transaction_date: "2026-01-20", amount: 90 }),
    movement({ id: "after-opening", financial_account_id: "life", transaction_date: "2026-02-02", amount: 40 }),
  ];
  assert.equal(valuationValue({ ...lifeInsurance, transactions }), 540);
});

test("un virement entre deux assurances-vie modifie les deux montants sans modifier le total", () => {
  const transferId = "life-to-life";
  const source = account({
    id: "source",
    account_type: "life_insurance",
    valuations: [valuation("source", "2026-01-31", 1_000)],
    transactions: [movement({ id: "source-leg", financial_account_id: "source", transfer_id: transferId, transaction_type: "transfer_out", amount: 100 })],
  });
  const destination = account({
    id: "destination",
    account_type: "life_insurance",
    valuations: [valuation("destination", "2026-01-31", 500)],
    transactions: [movement({ id: "destination-leg", financial_account_id: "destination", transfer_id: transferId, transaction_type: "transfer_in", amount: 100 })],
  });
  assert.equal(valuationValue(source), 900);
  assert.equal(valuationValue(destination), 600);
  assert.equal(valuationValue(source) + valuationValue(destination), 1_500);
});

test("gère séparément les références de valorisation de deux placements", () => {
  const transferId = "asymmetric-valuations";
  const source = account({
    id: "source",
    account_type: "life_insurance",
    valuations: [valuation("source", "2026-01-31", 1_000)],
    transactions: [movement({ id: "source-leg", financial_account_id: "source", transfer_id: transferId, transaction_date: "2026-02-15", transaction_type: "transfer_out", amount: 100 })],
  });
  const destination = account({
    id: "destination",
    account_type: "other_investment",
    valuations: [valuation("destination", "2026-02-28", 600)],
    transactions: [movement({ id: "destination-leg", financial_account_id: "destination", transfer_id: transferId, transaction_date: "2026-02-15", transaction_type: "transfer_in", amount: 100 })],
  });
  assert.equal(valuationValue(source), 900);
  assert.equal(valuationValue(destination), 600);
  assert.equal(valuationValue(source) + valuationValue(destination), 1_500);
});

test("préserve la neutralité d'un virement entre compte classique et placement", () => {
  const transferId = "checking-to-life";
  const checking = account({
    id: "checking",
    transactions: [movement({ id: "checking-leg", financial_account_id: "checking", transfer_id: transferId, transaction_type: "transfer_out", amount: 100 })],
  });
  const lifeInsurance = account({
    id: "life",
    account_type: "life_insurance",
    initial_balance: 500,
    valuations: [valuation("life", "2026-01-31", 500)],
    transactions: [movement({ id: "life-leg", financial_account_id: "life", transfer_id: transferId, transaction_type: "transfer_in", amount: 100 })],
  });
  assert.equal(calculateClassicBalance(checking.initial_balance, checking.transactions) + valuationValue(lifeInsurance), 1_500);
});

test("préserve aussi la neutralité d'un rachat de placement vers un compte classique", () => {
  const transferId = "life-to-checking";
  const checking = account({
    id: "checking",
    transactions: [movement({ id: "checking-leg", financial_account_id: "checking", transfer_id: transferId, transaction_type: "transfer_in", amount: 100 })],
  });
  const lifeInsurance = account({
    id: "life",
    account_type: "life_insurance",
    initial_balance: 500,
    valuations: [valuation("life", "2026-01-31", 500)],
    transactions: [movement({ id: "life-leg", financial_account_id: "life", transfer_id: transferId, transaction_type: "transfer_out", amount: 100 })],
  });
  assert.equal(calculateClassicBalance(checking.initial_balance, checking.transactions), 1_100);
  assert.equal(valuationValue(lifeInsurance), 400);
  assert.equal(calculateClassicBalance(checking.initial_balance, checking.transactions) + valuationValue(lifeInsurance), 1_500);
});

test("ignore une jambe annulée et une jambe datée le jour de la valorisation", () => {
  const lifeInsurance = account({ id: "life", account_type: "life_insurance" });
  const valuations = [valuation("life", "2026-02-01", 1_200)];
  const transactions = [
    movement({ id: "same-day", financial_account_id: "life", transaction_date: "2026-02-01", amount: 100 }),
    movement({ id: "cancelled", financial_account_id: "life", transaction_date: "2026-02-02", amount: 80, cancelled_at: "2026-02-03T00:00:00Z" }),
  ];
  assert.equal(valuationValue({ ...lifeInsurance, valuations, transactions }), 1_200);
});

test("le calcul canonique applique l'ajustement par compte et somme directement les valeurs", () => {
  assert.match(accountUtilsSource, /calculateValuationTransferAdjustment\(movements, baselineDate\)/);
  assert.match(accountUtilsSource, /current\.value \+ transferAdjustment/);
  assert.match(accountUtilsSource, /\.reduce\(\(total, account\) => total \+ getCurrentAccountValue/);
  assert.doesNotMatch(accountUtilsSource, /placementTransferAdjustment|transferLegs/);
});

test("distingue visuellement une valeur calculée de la valorisation officielle", () => {
  for (const source of [accountListSource, accountDetailSource]) {
    assert.match(source, /Valeur calculée après virements depuis la valorisation/);
    assert.match(source, /Valeur calculée après virements depuis le solde initial/);
    assert.match(source, /current\.transferAdjustment === 0 \? "Valorisation"/);
  }
});
