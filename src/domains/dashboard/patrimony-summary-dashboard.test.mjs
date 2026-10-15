import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const service = readFileSync(new URL("./services/dossier-dashboard-service.ts", import.meta.url), "utf8");
const page = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/tableau-de-bord/page.tsx", import.meta.url), "utf8");

test("le service charge en parallèle les données patrimoniales minimales sans historiques immobiliers ou de dettes", () => {
  assert.match(service, /Promise\.all\(\[/);
  assert.match(service, /select\("status,estimated_value,archived_at"\)/);
  assert.match(service, /\.is\("archived_at", null\)/);
  assert.match(service, /select\("status,current_balance"\)/);
  assert.match(service, /from\("patrimony_absence_confirmations"\)/);
  assert.match(service, /select\("protected_person_id,category,confirmed_at,confirmed_by,confirmed_by_name"\)/);
  assert.doesNotMatch(service, /getProperties|getDebts|property_events|debt_balances/);
});

test("chaque erreur Supabase patrimoniale est propagée avant tout calcul", () => {
  const firstCalculation = service.indexOf("const confirmations = buildPatrimonyAbsenceConfirmationState");
  for (const errorCheck of ["propertiesResult.error", "debtsResult.error", "confirmationsResult.error"]) {
    const position = service.indexOf(errorCheck);
    assert.ok(position >= 0 && position < firstCalculation, `${errorCheck} doit être contrôlée avant le calcul`);
  }
  assert.doesNotMatch(service, /propertiesResult\.data \?\?|debtsResult\.data \?\?|confirmationsResult\.data \?\?/);
});

test("le service réutilise les confirmations et le calcul 5F sans conserver les anciens compteurs", () => {
  assert.match(service, /buildPatrimonyAbsenceConfirmationState\(confirmationsResult\.data\)/);
  assert.match(service, /getPatrimonySummary\(\{ accounts, properties, debts, confirmations \}\)/);
  assert.match(service, /patrimonySummary,/);
  assert.doesNotMatch(service, /activePropertyCount|disposedPropertyCount|activeDebtCount/);
});

test("la synthèse affiche exactement les quatre indicateurs et aucun doublon bancaire", () => {
  assert.match(page, />Synthèse patrimoniale</);
  for (const title of ["Avoirs bancaires", "Patrimoine immobilier", "Dettes", "Patrimoine net estimé"]) {
    assert.match(page, new RegExp(`title="${title}"`));
  }
  assert.equal((page.match(/title="Avoirs bancaires"/g) ?? []).length, 1);
  assert.equal((page.match(/title="Patrimoine immobilier"/g) ?? []).length, 1);
  assert.equal((page.match(/title="Dettes"/g) ?? []).length, 1);
  for (const linkLabel of ["Voir les comptes", "Voir les biens", "Voir les dettes"]) {
    assert.match(page, new RegExp(`linkLabel="${linkLabel}"`));
  }
  assert.doesNotMatch(page, /title="Immobilier"|Patrimoine immobilier et dettes|CountCard|propertyCountsLabel/);
  assert.doesNotMatch(page, /title="Patrimoine financier"/);
  assert.match(page, /formatCurrency\(summary\.netEstimatedValue!\)/);
  assert.match(page, /formatCurrency\(component\.amount\)/);
});

test("aucun montant partiel ne remplace le patrimoine net et les motifs mènent aux rubriques utiles", () => {
  assert.match(page, /summary\.netEstimatedValue !== null/);
  assert.match(page, /Données incomplètes/);
  assert.match(page, /summary\.incompleteReasons\.map/);
  assert.match(page, /no_financial_accounts/);
  assert.match(page, /missing_real_estate_estimates/);
  assert.match(page, /patrimoine-immobilier/);
  assert.match(page, /Compléter l’immobilier/);
  assert.match(page, /Compléter les dettes/);
  assert.doesNotMatch(page, /component\.amount \?\? 0|netEstimatedValue \?\? 0/);
});

test("la grille est responsive en une, deux puis quatre colonnes", () => {
  assert.match(page, /grid grid-cols-1 items-start gap-3 sm:grid-cols-2 xl:grid-cols-4/);
  assert.match(page, /sm:flex-row sm:items-center sm:justify-between/);
  assert.match(page, /className="auth-link shrink-0"/);
});

test("les cartes opérationnelles, opérations, tâches et liens historiques restent présents", () => {
  for (const content of [
    "Comptes actifs",
    "Compte de gestion",
    "Dernières opérations",
    "Voir le journal",
    "À faire (",
    "Voir les exercices",
  ]) assert.ok(page.includes(content), `${content} doit rester présent`);
  assert.ok(page.indexOf("<PatrimonySummarySection") < page.indexOf("<RecentTransactions"));
});
