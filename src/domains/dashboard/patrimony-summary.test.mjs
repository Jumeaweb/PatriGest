import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { assemblePatrimonySummary } from "./patrimony-summary-core.ts";
import { getDossierDebtState, getDossierPropertyState } from "../protected-persons/dossier-information-states.ts";

const noConfirmations = { realEstate: null, activeDebt: null };
const confirmations = { realEstate: {}, activeDebt: {} };

function summary(overrides = {}) {
  const { bankingAmount = 1_000, properties = [], debts = [], confirmations: confirmationsInput = confirmations } = overrides;
  const propertyState = getDossierPropertyState(properties, confirmationsInput.realEstate !== null);
  const debtState = getDossierDebtState(debts, confirmationsInput.activeDebt !== null);
  return assemblePatrimonySummary({
    bankingAmount,
    propertyState,
    propertyKnownValues: properties.flatMap((property) =>
      property.archived_at == null && property.status === "active" && property.estimated_value !== null ? [property.estimated_value] : [],
    ),
    debtState,
    debtKnownBalances: debts.flatMap((debt) => debt.status === "active" && debt.current_balance !== null ? [debt.current_balance] : []),
  });
}

test("un inventaire entièrement vide reste non renseigné et détaille les trois motifs", () => {
  const result = summary({ bankingAmount: null, confirmations: noConfirmations });
  assert.equal(result.netEstimatedValue, null);
  assert.deepEqual([result.banking.state, result.realEstate.state, result.activeDebts.state], ["unreported", "unreported", "unreported"]);
  assert.deepEqual(result.incompleteReasons.map((reason) => reason.code), [
    "no_financial_accounts",
    "unconfirmed_real_estate_absence",
    "unconfirmed_active_debt_absence",
  ]);
});

test("les confirmations indépendantes rendent uniquement leur composante connue à zéro", () => {
  const realEstateOnly = summary({ bankingAmount: null, confirmations: { realEstate: {}, activeDebt: null } });
  assert.deepEqual({ state: realEstateOnly.realEstate.state, amount: realEstateOnly.realEstate.amount }, { state: "confirmed_absent", amount: 0 });
  assert.equal(realEstateOnly.activeDebts.state, "unreported");
  assert.equal(realEstateOnly.netEstimatedValue, null);

  const debtOnly = summary({ bankingAmount: null, confirmations: { realEstate: null, activeDebt: {} } });
  assert.equal(debtOnly.realEstate.state, "unreported");
  assert.deepEqual({ state: debtOnly.activeDebts.state, amount: debtOnly.activeDebts.amount }, { state: "confirmed_absent", amount: 0 });
});

test("aucun compte n’est pas assimilé à zéro, mais des comptes uniquement clôturés établissent un avoir courant nul", () => {
  assert.equal(summary({ bankingAmount: null }).banking.amount, null);
  const closed = summary({ bankingAmount: 0 });
  assert.deepEqual({ state: closed.banking.state, amount: closed.banking.amount }, { state: "complete", amount: 0 });
  assert.equal(closed.netEstimatedValue, 0);

  const wrapper = readFileSync(new URL("./patrimony-summary.ts", import.meta.url), "utf8");
  assert.match(wrapper, /bankingAmount: accounts\.length \? getCurrentPatrimonyValue\(\[\.\.\.accounts\]\) : null/);
});

test("le calcul complet exclut biens cédés, biens archivés, dettes soldées et comptes clôturés", () => {
  const result = summary({
    bankingAmount: 1_000.11,
    properties: [
      { status: "active", estimated_value: 2_000.22, archived_at: null },
      { status: "disposed", estimated_value: 40_000, archived_at: null },
      { status: "active", estimated_value: 30_000, archived_at: "2026-10-01T00:00:00Z" },
    ],
    debts: [
      { status: "active", current_balance: 500.05 },
      { status: "settled", current_balance: 10_000 },
    ],
    confirmations: noConfirmations,
  });
  assert.deepEqual({ bank: result.banking.amount, property: result.realEstate.amount, debt: result.activeDebts.amount }, {
    bank: 1_000.11, property: 2_000.22, debt: 500.05,
  });
  assert.equal(result.netEstimatedValue, 2_500.28);
  assert.deepEqual(result.incompleteReasons, []);
});

test("une estimation égale à zéro est complète, tandis qu’une estimation absente bloque le net", () => {
  const zero = summary({
    properties: [{ status: "active", estimated_value: 0, archived_at: null }],
    confirmations: { realEstate: null, activeDebt: {} },
  });
  assert.deepEqual({ state: zero.realEstate.state, amount: zero.realEstate.amount }, { state: "complete", amount: 0 });
  assert.equal(zero.netEstimatedValue, 1_000);

  const missing = summary({ properties: [
    { status: "active", estimated_value: 0, archived_at: null },
    { status: "active", estimated_value: null, archived_at: null },
  ] });
  assert.equal(missing.realEstate.state, "incomplete");
  assert.equal(missing.realEstate.amount, 0);
  assert.equal(missing.netEstimatedValue, null);
  assert.deepEqual(missing.realEstate.incompleteReasons[0], {
    code: "missing_real_estate_estimates",
    message: "1 bien immobilier actif ne dispose pas d’une estimation.",
    missingCount: 1,
  });
});

test("un solde de dette nul est complet, tandis qu’un solde absent bloque le net", () => {
  const zero = summary({
    debts: [{ status: "active", current_balance: 0 }],
    confirmations: { realEstate: {}, activeDebt: null },
  });
  assert.deepEqual({ state: zero.activeDebts.state, amount: zero.activeDebts.amount }, { state: "complete", amount: 0 });
  assert.equal(zero.netEstimatedValue, 1_000);

  const missing = summary({ debts: [
    { status: "active", current_balance: 125.25 },
    { status: "active", current_balance: null },
    { status: "settled", current_balance: 900 },
  ] });
  assert.equal(missing.activeDebts.state, "incomplete");
  assert.equal(missing.activeDebts.amount, 125.25);
  assert.equal(missing.netEstimatedValue, null);
  assert.equal(missing.activeDebts.incompleteReasons[0].code, "missing_active_debt_balances");
  assert.equal(missing.activeDebts.incompleteReasons[0].missingCount, 1);
});

test("les soldes bancaires et patrimoines nets négatifs sont conservés", () => {
  const result = summary({
    bankingAmount: -100.25,
    debts: [{ status: "active", current_balance: 50.25 }],
    confirmations: { realEstate: {}, activeDebt: null },
  });
  assert.equal(result.banking.amount, -100.25);
  assert.equal(result.netEstimatedValue, -150.5);
});

test("les calculs conservent les centimes sans exposer les erreurs binaires", () => {
  const result = summary({
    bankingAmount: 0.1,
    properties: [{ status: "active", estimated_value: 0.2 }],
    debts: [{ status: "active", current_balance: 0.1 }],
    confirmations: noConfirmations,
  });
  assert.equal(result.netEstimatedValue, 0.2);
});

test("les données actives priment sur des confirmations devenues obsolètes", () => {
  const result = summary({
    properties: [{ status: "active", estimated_value: null, archived_at: null }],
    debts: [{ status: "active", current_balance: 80 }],
  });
  assert.equal(result.realEstate.state, "incomplete");
  assert.equal(result.activeDebts.state, "complete");
  assert.equal(result.activeDebts.amount, 80);
  assert.equal(result.netEstimatedValue, null);
});

test("la composante bancaire réutilise le calcul canonique, y compris la valorisation des placements", () => {
  const result = summary({ bankingAmount: 125.55 });
  assert.equal(result.banking.amount, 125.55);
  assert.equal(result.netEstimatedValue, 125.55);

  const implementation = readFileSync(new URL("./patrimony-summary.ts", import.meta.url), "utf8");
  const canonicalBanking = readFileSync(new URL("../financial-accounts/utils/financial-account-utils.ts", import.meta.url), "utf8");
  assert.match(implementation, /getCurrentPatrimonyValue\(\[\.\.\.accounts\]\)/);
  assert.doesNotMatch(implementation, /calculateClassicBalance|transferLegs|transaction_type/);
  assert.match(canonicalBanking, /accounts\.filter\(\(account\) => account\.status === "active"\)/);
  assert.match(canonicalBanking, /placementTransferAdjustment/);
});
