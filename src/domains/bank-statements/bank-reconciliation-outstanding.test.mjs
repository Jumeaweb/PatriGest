import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { calculateDetailedReconciliation } from "./reconciliation-calculations.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("calcule le solde expliqué et l'écart résiduel exactement en cents", () => {
  assert.deepEqual(calculateDetailedReconciliation(100, 12300, 700, 3000), {
    calculatedBalance: 123,
    outstandingDebits: 7,
    outstandingCredits: 30,
    explainedBankBalance: 100,
    residualDifference: 0,
  });
});

test("refuse les agrégats monétaires non sûrs", () => {
  assert.throws(() => calculateDetailedReconciliation(0, Number.MAX_SAFE_INTEGER, 1, 0), /hors limites/);
});

test("pagine les candidates par 50 avec un curseur stable", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /OUTSTANDING_TRANSACTION_PAGE_SIZE = 50/);
  assert.match(service, /p_limit: OUTSTANDING_TRANSACTION_PAGE_SIZE \+ 1/);
  assert.match(service, /date: item\.transactionDate, createdAt: item\.transactionCreatedAt, id: item\.transactionId/);
  assert.match(service, /nextCursor: hasMore/);
});

test("charge les candidates et les agrégats exhaustifs sans N+1", () => {
  const service = source("./reconciliation-service.ts");
  const page = service.slice(service.indexOf("export async function getOutstandingTransactionPage"));
  assert.match(page, /Promise\.all/);
  assert.match(page, /list_bank_reconciliation_candidate_transactions/);
  assert.match(page, /get_bank_reconciliation_detailed_summary/);
  assert.doesNotMatch(page, /for \(|forEach\(|\.map\([^)]*supabase/s);
});

test("la pagination SQL ne dépend pas de la limite PostgREST de 1000", () => {
  const migration = source("../../../supabase/migrations/20260922100000_add_bank_reconciliation_outstanding_transactions.sql");
  assert.match(migration, /\(transaction\.transaction_date, transaction\.created_at, transaction\.id\)\s*>/);
  assert.match(migration, /limit safe_limit/);
  assert.match(migration, /order by transaction\.transaction_date, transaction\.created_at, transaction\.id/);
});

test("les anciennes opérations et le report précédent restent proposés", () => {
  const migration = source("../../../supabase/migrations/20260922100000_add_bank_reconciliation_outstanding_transactions.sql");
  assert.doesNotMatch(migration, /transaction\.transaction_date\s*>=\s*statement_record\.statement_start_date/);
  assert.match(migration, /previous_outstanding\.id is not null/);
  assert.match(migration, /carried_from_previous boolean/);
});

test("l'API réserve l'activation et les mutations aux gestionnaires", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/rapprochement/pointage/route.ts");
  assert.match(route, /export async function GET/);
  assert.match(route, /export async function POST/);
  assert.match(route, /export async function PATCH/);
  assert.equal((route.match(/accessRole === "read_only"/g) ?? []).length, 2);
  assert.match(route, /mutationSchema = z\.object\(\{ transactionId: z\.uuid\(\), outstanding: z\.boolean\(\) \}\)/);
});

test("le client n'envoie aucun montant faisant autorité", () => {
  const component = source("./components/outstanding-transactions-dialog.tsx");
  assert.match(component, /JSON\.stringify\(\{ transactionId, outstanding \}\)/);
  assert.doesNotMatch(component, /JSON\.stringify\(\{[^}]*amount/);
});

test("le panneau est chargé uniquement à la demande", () => {
  const manager = source("./components/bank-reconciliation-manager.tsx");
  assert.match(manager, /onClick=\{\(\) => openPointing\(true\)\}>Rapprochement détaillé/);
  assert.match(manager, /onClick=\{\(\) => openPointing\(false\)\}>Opérations en circulation/);
  assert.doesNotMatch(source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/releves/page.tsx"), /getOutstandingTransactionPage/);
});

test("l'interface détaillée couvre desktop et mobile", () => {
  const component = source("./components/outstanding-transactions-dialog.tsx");
  assert.match(component, /md:block/);
  assert.match(component, /md:hidden/);
  assert.match(component, /Débit/);
  assert.match(component, /Crédit/);
  assert.match(component, /En circulation/);
  assert.match(component, /Reportée du rapprochement précédent/);
});

test("le mode simple reste le défaut et ses colonnes détaillées restent nulles", () => {
  const migration = source("../../../supabase/migrations/20260922100000_add_bank_reconciliation_outstanding_transactions.sql");
  assert.match(migration, /reconciliation_mode text not null default 'simple'/);
  assert.match(migration, /reconciliation_mode = 'simple'[\s\S]*outstanding_debits is null/);
  assert.match(migration, /case when reconciliation_mode = 'complete'.*else null end/s);
});

test("les snapshots historiques survivent à la suppression de la source", () => {
  const migration = source("../../../supabase/migrations/20260922100000_add_bank_reconciliation_outstanding_transactions.sql");
  assert.match(migration, /transaction_id uuid references public\.transactions\(id\) on delete set null/);
  assert.match(migration, /transaction_id_snapshot uuid not null/);
  assert.match(migration, /transaction_date_snapshot = transaction\.transaction_date/);
  assert.match(migration, /label_snapshot = transaction\.label/);
});
