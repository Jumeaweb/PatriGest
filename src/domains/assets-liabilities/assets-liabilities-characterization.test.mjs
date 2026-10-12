import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getDebtCompleteness, getPropertyCompleteness } from "./completeness.ts";
import {
  debtBalanceSchema,
  debtSchema,
  editablePropertyEventTypes,
  propertyEventSchema,
  propertyEventUpdateSchema,
  propertySalePriceCorrectionSchema,
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

test("l'édition accepte uniquement les quatre types d'événements hors vente", () => {
  for (const eventType of editablePropertyEventTypes) {
    assert.equal(propertyEventUpdateSchema.safeParse({
      eventType,
      eventDate: "2026-03-15",
      description: "Événement corrigé",
      amount: "1200.50",
      documentReference: "ACTE-15",
    }).success, true);
  }
  assert.equal(propertyEventUpdateSchema.safeParse({
    eventType: "sale",
    eventDate: "2026-03-15",
    description: "Vente interdite",
    amount: "1200",
    documentReference: "",
  }).success, false);
  assert.equal(propertyEventUpdateSchema.safeParse({
    eventType: "donation",
    eventDate: "15/03/2026",
    description: "",
    amount: "-1",
    documentReference: "",
  }).success, false);
});

test("le parcours d'édition vérifie droits, rattachements, vente et périodes clôturées", () => {
  const services = source("./services.ts");
  const actions = source("./actions.ts");
  const updateAction = actions.slice(actions.indexOf("export async function updatePropertyEventAction"), actions.indexOf("export async function saveDebtAction"));
  const manager = source("./components/property-manager.tsx");
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/[propertyId]/page.tsx");

  assert.match(services, /rpc\("can_manage_protected_person"/);
  assert.match(services, /\.eq\("id",eventId\)\.eq\("property_id",propertyId\)\.eq\("protected_person_id",personId\)/);
  assert.match(services, /existing\.event_type === "sale"/);
  assert.match(services, /\.neq\("event_type","sale"\)/);
  assert.match(services, /ensurePropertyEventDateIsOpen\(supabase, personId, existing\.event_date\)/);
  assert.match(services, /ensurePropertyEventDateIsOpen\(supabase, personId, input\.eventDate\)/);
  assert.doesNotMatch(services, /property_events"\)\.update\(\{[^}]*property_id/);
  assert.doesNotMatch(services, /property_events"\)\.update\(\{[^}]*protected_person_id/);

  assert.match(actions, /propertyEventUpdateSchema\.safeParse/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/patrimoine-immobilier\/\$\{propertyId\}`\)/);
  assert.match(actions, /Les événements de vente ne sont pas modifiables/);
  assert.match(actions, /exercice clôturé et ne peut plus être modifié/);
  assert.doesNotMatch(updateAction, /e\.message/);

  assert.match(manager, /updatePropertyEventAction\.bind\(null,personId,item\.id,event\.id\)/);
  assert.match(manager, /value=\{event\?\.event_type\?\?"significant_change"\}/);
  assert.match(manager, /value=\{event\?\.event_date\}/);
  assert.match(manager, /value=\{event\?\.description\}/);
  assert.match(manager, /value=\{event\?\.amount\}/);
  assert.match(manager, /value=\{event\?\.document_reference\}/);
  assert.match(manager, /errors=\{state\.fieldErrors\?\.eventDate\}/);
  assert.match(manager, /<FieldError messages=\{errors\}/);
  assert.match(page, /person\.accessRole !== "read_only" && event\.event_type !== "sale"/);
});

test("la correction du prix exige un nouveau montant positif différent et un motif", () => {
  assert.deepEqual(propertySalePriceCorrectionSchema.parse({
    expectedPrice: 205000,
    newPrice: "210000,50",
    reason: "Erreur relevée dans l’acte authentique",
  }), {
    expectedPrice: 205000,
    newPrice: 210000.5,
    reason: "Erreur relevée dans l’acte authentique",
  });
  for (const input of [
    { expectedPrice: 205000, newPrice: "", reason: "Motif" },
    { expectedPrice: 205000, newPrice: "-1", reason: "Motif" },
    { expectedPrice: 205000, newPrice: "210000.123", reason: "Motif" },
    { expectedPrice: 205000, newPrice: "205000", reason: "Motif" },
    { expectedPrice: 205000, newPrice: "210000", reason: "   " },
  ]) assert.equal(propertySalePriceCorrectionSchema.safeParse(input).success, false);
});

test("la correction passe par une RPC transactionnelle auditée et conserve les protections de vente", () => {
  const migration = source("../../../supabase/migrations/20261012100000_correct_property_sale_prices.sql");
  const services = source("./services.ts");
  const actions = source("./actions.ts");
  const action = actions.slice(actions.indexOf("export async function correctPropertySalePriceAction"), actions.indexOf("export async function saveDebtAction"));

  assert.match(migration, /create table public\.property_sale_price_corrections/);
  assert.match(migration, /create or replace function public\.correct_property_sale_price/);
  assert.match(migration, /security invoker/);
  assert.match(migration, /for update/);
  assert.match(migration, /p_expected_price/);
  assert.match(migration, /period\.status = 'closed'/);
  assert.match(migration, /property_events_audit_sale_price_correction/);
  assert.match(migration, /property_sale_price_corrections_immutable/);
  assert.match(migration, /revoke insert, update, delete on public\.property_sale_price_corrections from authenticated/);
  assert.match(migration, /Le prix de vente doit être corrigé par le parcours dédié/);
  assert.match(migration, /if updated_event_count <> 1/);
  assert.match(migration, /La trace de correction n’a pas été enregistrée/);

  assert.match(services, /rpc\("correct_property_sale_price"/);
  assert.match(services, /p_expected_price: input\.expectedPrice/);
  assert.match(services, /p_protected_person_id: personId/);
  assert.match(services, /p_property_id: propertyId/);
  assert.match(services, /p_event_id: eventId/);
  assert.match(services, /from\("property_sale_price_corrections"\)/);
  assert.match(actions, /propertySalePriceCorrectionSchema\.safeParse/);
  assert.match(action, /refresh\(personId,propertyId\)/);
  assert.doesNotMatch(action, /e\.message/);
});

test("l’interface réserve Corriger le prix aux ventes modifiables et affiche chaque trace", () => {
  const manager = source("./components/property-manager.tsx");
  const actions = source("./actions.ts");
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/[propertyId]/page.tsx");

  assert.match(manager, /Corriger le prix/);
  assert.match(manager, /Prix actuel/);
  assert.match(manager, /name="newPrice"/);
  assert.match(manager, /name="reason"/);
  assert.match(manager, /Enregistrer la correction/);
  assert.match(manager, /disabled=\{pending\}/);
  assert.match(actions, /Le prix de vente a été corrigé/);
  assert.match(page, /person\.accessRole !== "read_only" && event\.event_type === "sale"/);
  assert.match(page, /event\.priceCorrections\.map/);
  assert.match(page, /correction\.old_price/);
  assert.match(page, /correction\.new_price/);
  assert.match(page, /correction\.reason/);
  assert.match(page, /correction\.corrected_by_name/);
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
