import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getDebtCompleteness, getPropertyCompleteness } from "./completeness.ts";
import {
  debtBalanceSchema,
  debtSchema,
  propertyEventSchema,
  propertySchema,
} from "./schemas.ts";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

function propertyInput(overrides = {}) {
  return {
    propertyType: "house",
    designation: "Maison principale",
    addressLine1: "1 rue du Test",
    addressLine2: "",
    postalCode: "37000",
    city: "Tours",
    country: "France",
    entryDate: "2020-01-01",
    entryMode: "acquisition",
    estimatedValue: "180000",
    valuationDate: "2026-01-31",
    status: "active",
    disposalDate: "",
    notes: "",
    ...overrides,
  };
}

function debtInput(overrides = {}) {
  return {
    creditor: "Banque de test",
    debtType: "bank_loan",
    designation: "Prêt immobilier",
    startDate: "2020-01-01",
    initialAmount: "120000",
    initialDurationMonths: "240",
    monthlyPayment: "650",
    interestRate: "1.8",
    status: "active",
    settledAt: "",
    notes: "",
    ...overrides,
  };
}

function debt(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    status: "active",
    balances: [],
    ...overrides,
  };
}

function balance(balanceDate, remainingBalance = 1_000) {
  return {
    id: crypto.randomUUID(),
    debt_id: crypto.randomUUID(),
    balance_date: balanceDate,
    remaining_balance: remainingBalance,
    remaining_duration_months: 12,
    created_at: `${balanceDate}T00:00:00Z`,
  };
}

test("une estimation datée exige une valeur, tandis qu'une valeur sans date reste admise", () => {
  assert.equal(propertySchema.safeParse(propertyInput()).success, true);
  assert.equal(propertySchema.safeParse(propertyInput({ estimatedValue: "", valuationDate: "2026-01-31" })).success, false);

  const withoutDate = propertySchema.parse(propertyInput({ valuationDate: "" }));
  assert.equal(withoutDate.estimatedValue, 180000);
  assert.equal(withoutDate.valuationDate, null);
});

test("caractérisation : statut et date de cession peuvent actuellement se contredire", () => {
  // PAT-PATRIMOINE-01D devra remplacer ces succès par des invariants métier.
  assert.equal(propertySchema.safeParse(propertyInput({ status: "disposed", disposalDate: "" })).success, true);
  assert.equal(propertySchema.safeParse(propertyInput({ status: "active", disposalDate: "2026-02-15" })).success, true);
});

test("une vente exige son prix et sa persistance est synchronisée par le trigger transactionnel", () => {
  const parsed = propertyEventSchema.parse({
    eventType: "sale",
    eventDate: "2026-02-15",
    description: "Vente du bien",
    amount: "195000",
    documentReference: "ACTE-2026-15",
  });
  assert.equal(parsed.amount, 195000);
  assert.equal(propertyEventSchema.safeParse({
    eventType: "sale",
    eventDate: "2026-02-15",
    description: "Vente du bien",
    amount: "",
    documentReference: "",
  }).success, false);

  const services = source("./services.ts");
  const start = services.indexOf("export async function addPropertyEvent");
  const end = services.indexOf("export async function getDebts", start);
  const saleService = services.slice(start, end);
  assert.match(saleService, /from\("property_events"\)\.insert/);
  assert.doesNotMatch(saleService, /from\("real_estate_properties"\)\.update/);

  const migration = source("../../../supabase/migrations/20261011100000_synchronize_property_sales.sql");
  assert.match(migration, /before insert on public\.property_events/);
  assert.match(migration, /before update on public\.property_events/);
  assert.match(migration, /before update on public\.real_estate_properties/);
  assert.match(migration, /security invoker/);
  assert.match(migration, /for update/);
  assert.match(migration, /get diagnostics updated_property_count = row_count/);
  assert.match(migration, /new\.event_date > current_date/);
  assert.match(migration, /set status = 'disposed',[\s\S]*disposal_date = new\.event_date/);
});

test("la complétude immobilière dépend seulement de la désignation, du type et de la ville", () => {
  const complete = {
    id: "10000000-0000-4000-8000-000000000001",
    designation: "Maison",
    property_type: "house",
    city: "Tours",
    status: "disposed",
    estimated_value: null,
    disposal_date: null,
  };
  assert.deepEqual(getPropertyCompleteness([complete]), {
    state: "present",
    incompleteIds: [],
  });
  assert.deepEqual(getPropertyCompleteness([{ ...complete, city: null }]), {
    state: "incomplete",
    incompleteIds: [complete.id],
  });
});

test("caractérisation : une dette soldée sans date de clôture reste valide", () => {
  // PAT-PATRIMOINE-01F devra faire évoluer cette attente avec la règle de solde.
  const parsed = debtSchema.parse(debtInput({ status: "settled", settledAt: "" }));
  assert.equal(parsed.status, "settled");
  assert.equal(parsed.settledAt, null);
});

test("une situation datée accepte un capital restant dû nul", () => {
  assert.deepEqual(debtBalanceSchema.parse({
    balanceDate: "2026-03-31",
    remainingBalance: "0",
    remainingDurationMonths: "0",
  }), {
    balanceDate: "2026-03-31",
    remainingBalance: 0,
    remainingDurationMonths: 0,
  });
});

test("la fraîcheur d'une dette active utilise sa situation la plus récente", () => {
  const now = new Date("2026-10-11T12:00:00Z");
  const current = debt({
    balances: [balance("2025-01-01"), balance("2026-06-30")],
  });
  const stale = debt({ balances: [balance("2025-10-10")] });

  assert.deepEqual(getDebtCompleteness([current, stale], now), {
    state: "active",
    activeCount: 2,
    missingRecentBalanceIds: [stale.id],
  });
});

test("une dette soldée est exclue du contrôle de fraîcheur, même avec un ancien solde positif", () => {
  const settled = debt({
    status: "settled",
    balances: [balance("2020-01-01", 4_500)],
  });
  assert.deepEqual(getDebtCompleteness([settled], new Date("2026-10-11T12:00:00Z")), {
    state: "settled",
    activeCount: 0,
    missingRecentBalanceIds: [],
  });
});

test("le compte de gestion filtre actuellement les biens par dates, pas par statut", () => {
  // PAT-PATRIMOINE-01I devra réviser ce contrat temporel et la valeur retenue.
  const preview = source("../management-reports/preview-model.ts");
  assert.match(preview, /!property\.entry_date \|\| property\.entry_date <= snapshot\.report\.period_end/);
  assert.match(preview, /!property\.disposal_date \|\| property\.disposal_date >= snapshot\.report\.period_start/);
  assert.doesNotMatch(
    preview,
    /properties[\s\S]*?\.filter\([\s\S]*?property\.status[\s\S]*?\.map\(\(property\)/,
  );
  assert.match(preview, /estimatedValue: property\.estimated_value/);
  assert.match(preview, /valuationDate: property\.valuation_date/);
});

test("le compte de gestion retient la dernière situation de dette au plus tard à la fin de période", () => {
  const services = source("../management-reports/services.ts");
  assert.match(services, /!debt\.start_date \|\| debt\.start_date <= report\.period_end/);
  assert.match(services, /!debt\.settled_at \|\| debt\.settled_at >= report\.period_start/);
  assert.match(services, /debt\.balances\.find\([\s\S]*?balance\.balance_date <= report\.period_end/);
  assert.match(services, /complete: relevantDebts\.every\(\(item\) => Boolean\(item\.balance\)\)/);

  const assetServices = source("./services.ts");
  assert.match(assetServices, /from\("debt_balances"\)[\s\S]*?order\("balance_date",\{ascending:false\}\)/);
});
