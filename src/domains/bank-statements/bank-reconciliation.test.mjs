import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  buildBankReconciliationAttentionSummary,
  calculateReconciliationDifference,
  getReconciliationUnavailableReason,
  toMoneyCents,
} from "./reconciliation-calculations.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const account = { initial_balance_date: "2026-01-01", opening_date: "2026-02-01", closing_date: "2026-12-31" };

test("calcule les écarts nul, positif et négatif exactement en cents", () => {
  assert.deepEqual(calculateReconciliationDifference(123.07, 12307), {
    statementBalance: 123.07,
    statementBalanceInCents: 12307,
    difference: 0,
    differenceInCents: 0,
  });
  assert.equal(calculateReconciliationDifference(130, 12307).differenceInCents, 693);
  assert.equal(calculateReconciliationDifference(120, 12307).differenceInCents, -307);
  assert.equal(toMoneyCents(10.01), 1001);
});

test("refuse les montants qui ne peuvent pas être représentés sûrement en cents", () => {
  assert.throws(() => toMoneyCents(Number.POSITIVE_INFINITY), /hors limites/);
  assert.throws(() => toMoneyCents(Number.MAX_SAFE_INTEGER), /hors limites/);
});

test("identifie un relevé sans solde", () => {
  assert.equal(getReconciliationUnavailableReason({ statement_balance: null, statement_end_date: "2026-03-01" }, account), "missing_statement_balance");
});

test("applique les bornes de rapprochement de manière inclusive", () => {
  assert.equal(getReconciliationUnavailableReason({ statement_balance: 0, statement_end_date: "2026-01-31" }, account), "before_minimum_date");
  assert.equal(getReconciliationUnavailableReason({ statement_balance: 0, statement_end_date: "2026-02-01" }, account), null);
  assert.equal(getReconciliationUnavailableReason({ statement_balance: 0, statement_end_date: "2026-12-31" }, account), null);
  assert.equal(getReconciliationUnavailableReason({ statement_balance: 0, statement_end_date: "2027-01-01" }, account), "after_closing_date");
});

test("le draft réutilise getAccountBalanceAtDate sans persister ses snapshots", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /getAccountBalanceAtDate\(protectedPersonId, account\.id, statement\.statement_end_date\)/);
  assert.match(service, /status: "draft"/);
  assert.doesNotMatch(service, /\.update\(\{[^}]*calculated_balance/s);
  assert.doesNotMatch(service, /\.insert\(\{[^}]*calculated_balance/s);
});

test("la création explicite du draft est idempotente", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /if \(existing\) return existing/);
  assert.match(service, /error\.code === "23505"/);
  assert.match(service, /if \(concurrent\) return concurrent/);
});

test("la liste charge seulement les états par lots sans calcul de solde", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /RECONCILIATION_QUERY_BATCH_SIZE = 100/);
  assert.match(service, /select\("id, bank_statement_id, status, reconciliation_mode, calculated_balance, difference, outstanding_debits, outstanding_credits, explained_bank_balance, residual_difference, validated_at"\)/);
  const listFunction = service.slice(service.indexOf("export async function getBankReconciliationListStates"), service.indexOf("export async function getBankReconciliation("));
  assert.doesNotMatch(listFunction, /getAccountBalanceAtDate/);
});

test("la synthèse distingue les brouillons, les écarts et les contrôles validés", () => {
  const nonZeroStatement = { id: "draft-non-zero", statement_balance: 102, statement_end_date: "2026-01-31" };
  const zeroStatement = { id: "draft-zero", statement_balance: 120, statement_end_date: "2026-01-31" };
  const unavailableStatement = { id: "draft-unavailable", statement_balance: null, statement_end_date: "2026-01-31" };

  const nonZero = buildBankReconciliationAttentionSummary(
    [nonZeroStatement],
    [{ bank_statement_id: nonZeroStatement.id, status: "draft" }],
    () => -18,
  );
  assert.equal(nonZero.pendingCount, 1);
  assert.equal(nonZero.differenceByStatementId[nonZeroStatement.id], -18);
  assert.deepEqual(nonZero.singlePending, { statementEndDate: "2026-01-31", difference: -18 });

  const zero = buildBankReconciliationAttentionSummary(
    [zeroStatement],
    [{ bank_statement_id: zeroStatement.id, status: "draft" }],
    () => 0,
  );
  assert.equal(zero.pendingCount, 1);
  assert.equal(zero.singlePending.difference, 0);

  const validated = buildBankReconciliationAttentionSummary(
    [nonZeroStatement],
    [{ bank_statement_id: nonZeroStatement.id, status: "validated" }],
    () => { throw new Error("un contrôle validé ne doit pas être recalculé"); },
  );
  assert.deepEqual(validated, { pendingCount: 0, differenceByStatementId: {}, singlePending: null });

  const multiple = buildBankReconciliationAttentionSummary(
    [nonZeroStatement, zeroStatement],
    [{ bank_statement_id: nonZeroStatement.id, status: "draft" }],
    (statement) => statement.id === nonZeroStatement.id ? -18 : 0,
  );
  assert.equal(multiple.pendingCount, 2);
  assert.equal(multiple.singlePending, null);

  const unavailable = buildBankReconciliationAttentionSummary(
    [unavailableStatement],
    [{ bank_statement_id: unavailableStatement.id, status: "draft" }],
    () => null,
  );
  assert.equal(unavailable.pendingCount, 1);
  assert.equal(unavailable.singlePending.difference, null);
});

test("l'API expose GET POST PUT PATCH et réserve les écritures aux gestionnaires", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/rapprochement/route.ts");
  assert.match(route, /export async function GET/);
  assert.match(route, /export async function POST/);
  assert.match(route, /export async function PUT/);
  assert.match(route, /export async function PATCH/);
  assert.equal((route.match(/accessRole === "read_only"/g) ?? []).length, 3);
  assert.match(route, /validateBankReconciliation\(reconciliation\.id\)/);
});

test("la validation renvoie un contrôle complet avant le rafraîchissement de la page", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/rapprochement/route.ts");
  const component = source("./components/bank-reconciliation-manager.tsx");
  const patchHandler = route.slice(route.indexOf("export async function PATCH"));
  const genericRequest = component.slice(component.indexOf("async function request"), component.indexOf("async function acknowledgeImpact"));

  assert.match(patchHandler, /NextResponse\.json\(\{ \.\.\.control, impacts: \[\] \}\)/);
  assert.match(genericRequest, /setControl\(result\)/);
  assert.match(genericRequest, /if \(result\.status === "validated"\) router\.refresh\(\)/);
});

test("une nouvelle tentative sur un rapprochement déjà validé reçoit une erreur métier explicite", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /error\.message\?\.includes\("Seul un rapprochement en brouillon"\)/);
  assert.match(service, /Ce contrôle bancaire est déjà validé ou n’est plus modifiable\./);
});

test("le client ne transmet aucune valeur métier à la validation", () => {
  const component = source("./components/bank-reconciliation-manager.tsx");
  const genericRequest = component.slice(component.indexOf("async function request"), component.indexOf("async function acknowledgeImpact"));
  assert.match(genericRequest, /fetch\(endpoint, \{ method \}\)/);
  assert.doesNotMatch(genericRequest, /body:/);
});

test("l'interface couvre desktop mobile brouillon validé et lecture seule", () => {
  const component = source("./components/bank-reconciliation-manager.tsx");
  assert.match(component, /flex flex-wrap items-start justify-between/);
  assert.match(component, /grid gap-2 sm:grid-cols-3/);
  assert.match(component, /Contrôler le solde/);
  assert.match(component, /Brouillon simple — recalculé à l’affichage/);
  assert.match(component, /Valider le contrôle/);
  assert.match(component, /montants figés/);
  assert.match(component, /control\.status === "draft" && canManage/);
  assert.match(component, /Aucun rapprochement en attente/);
  assert.match(component, /À contrôler/);
  assert.match(component, />Validé</);
  assert.match(component, /Écart indisponible/);
  assert.match(component, /role="status"/);
  assert.match(component, /bg-amber-50/);
  assert.match(source("./components/bank-statement-manager.tsx"), /canManage && !isValidated/);
});

test("les cas non rapprochables restent informatifs sans action", () => {
  const component = source("./components/bank-reconciliation-manager.tsx");
  assert.match(component, /Solde du relevé non renseigné/);
  assert.match(component, /antérieur à la première date contrôlable/);
  assert.match(component, /postérieur à la clôture/);
  assert.match(component, /if \(unavailableReason && status !== "validated"\) \{/);
});
