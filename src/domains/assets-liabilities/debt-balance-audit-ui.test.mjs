import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getDebtCompleteness } from "./completeness.ts";
import { debtBalanceCancellationSchema, debtBalanceCorrectionSchema } from "./schemas.ts";

function source(relativePath) { return readFileSync(new URL(relativePath, import.meta.url), "utf8"); }

test("les formulaires exigent des valeurs valides et un motif", () => {
  const valid = { balanceDate: "2026-11-01", remainingBalance: "0", remainingDurationMonths: "0", reason: "Erreur de saisie" };
  assert.equal(debtBalanceCorrectionSchema.safeParse(valid).success, true);
  assert.equal(debtBalanceCorrectionSchema.safeParse({ ...valid, reason: "" }).success, false);
  assert.equal(debtBalanceCorrectionSchema.safeParse({ ...valid, remainingBalance: "-1" }).success, false);
  assert.equal(debtBalanceCancellationSchema.safeParse({ reason: "Doublon" }).success, true);
  assert.equal(debtBalanceCancellationSchema.safeParse({ reason: " " }).success, false);
});

test("la révision affichée est transmise sans relecture silencieuse", () => {
  const services = source("./services.ts");
  const actions = source("./actions.ts");
  const component = source("./components/debt-balance-actions.tsx");
  assert.match(component, /balance\.id, balance\.revision/);
  assert.match(actions, /correctDebtBalance\(personId,debtId,balanceId,expectedRevision,p\.data\)/);
  assert.match(actions, /cancelDebtBalance\(personId,debtId,balanceId,expectedRevision,p\.data\)/);
  assert.match(services, /p_expected_revision:expectedRevision/);
  assert.doesNotMatch(services, /p_expected_revision:[a-zA-Z]+\.revision/);
});

test("les lectures de calcul excluent les situations annulées mais la fiche conserve tout l’historique", () => {
  const services = source("./services.ts");
  const reports = source("../management-reports/services.ts");
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");
  assert.match(services, /from\("debt_balances"\).*\.is\("cancelled_at",null\)/s);
  assert.match(reports, /!balance\.cancelled_at && balance\.balance_date <= report\.period_end/);
  assert.match(services, /getDebt\(personId:string,debtId:string\).*from\("debt_balances"\)\.select\("\*"\).*order\("balance_date"/s);
  assert.match(page, /balance\.cancelled_at \? "Annulée" : "Active"/);
  assert.match(page, /Journal des modifications/);
  assert.match(page, /change\.changed_by_name/);
});

test("une situation annulée ne satisfait pas la fraîcheur de la dette", () => {
  const item = { id: crypto.randomUUID(), status: "active", balances: [{ id: crypto.randomUUID(), debt_id: crypto.randomUUID(), balance_date: "2026-10-31", remaining_balance: 0, remaining_duration_months: 0, revision: 2, cancelled_at: "2026-11-01T10:00:00Z", cancelled_by: crypto.randomUUID(), cancellation_reason: "Erreur", created_at: "2026-10-31T00:00:00Z" }] };
  const result = getDebtCompleteness([item], new Date("2026-11-01T00:00:00Z"));
  assert.deepEqual(result.missingRecentBalanceIds, [item.id]);
});

test("les restrictions, erreurs sûres et projets obsolètes sont visibles", () => {
  const services = source("./services.ts");
  const actions = source("./actions.ts");
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");
  const component = source("./components/debt-balance-actions.tsx");
  for (const code of ["forbidden", "stale_revision", "already_cancelled", "settled", "closed_period", "duplicate_date", "archived_dossier"]) assert.match(actions, new RegExp(`${code}:`));
  assert.doesNotMatch(actions.slice(actions.indexOf("const debtBalanceMessages"), actions.indexOf("export async function settleDebtAction")), /e\.message|error\.message/);
  assert.match(services, /from\("debt_balance_changes"\)/);
  assert.match(services, /eq\("status","generated"\)\.not\("refresh_required_at","is",null\)/);
  assert.match(page, /Projets de comptes de gestion à actualiser/);
  assert.match(component, /Exercice clôturé — correction et annulation indisponibles/);
  assert.match(page, /canManage && debt\.status === "active" && balance\.cancelled_at === null/);
});
