import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  BANK_STATEMENT_DURABLE_OPERATIONS_ENV,
  isBankStatementDurableOperationsEnabled,
  runBankStatementDocumentWrite,
} from "./bank-statement-durable-availability.ts";
import {
  createBankStatementRequestId,
  reserveBankStatementOperation,
} from "./bank-statement-durable-reservation.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const writeService = source("./bank-statement-write.ts");
const durable = source("./bank-statement-durable.ts");
const collectionRoute = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/route.ts");
const itemRoute = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/route.ts");
const page = source("../../app/dossiers/[protectedPersonId]/comptes/[accountId]/releves/page.tsx");
const component = source("./components/bank-statement-manager.tsx");
const bankStatementSql = source("../../../supabase/migrations/20260815120000_create_bank_statements.sql");
const accountDeletion = source("../account/account-deletion-operations.ts");

const metadata = {
  statementStartDate: "2026-09-01",
  statementEndDate: "2026-09-30",
  statementBalance: 1234.56,
  note: "Relevé mensuel",
};

test("l’indicateur des relevés est indépendant, strict et désactivé par défaut", () => {
  assert.equal(
    BANK_STATEMENT_DURABLE_OPERATIONS_ENV,
    "PATRIGEST_ENABLE_BANK_STATEMENT_DURABLE_OPERATIONS",
  );
  assert.equal(isBankStatementDurableOperationsEnabled(undefined), false);
  assert.equal(isBankStatementDurableOperationsEnabled("false"), false);
  assert.equal(isBankStatementDurableOperationsEnabled("TRUE"), false);
  assert.equal(isBankStatementDurableOperationsEnabled("true"), true);
});

test("le mode désactivé exécute exclusivement le parcours historique", async () => {
  const calls = [];
  const result = await runBankStatementDocumentWrite(
    false,
    async () => { calls.push("historical"); return "legacy"; },
    async () => { calls.push("durable"); return "new"; },
  );
  assert.equal(result, "legacy");
  assert.deepEqual(calls, ["historical"]);
});

test("le mode activé ne retombe jamais sur l’ancien parcours", async () => {
  const calls = [];
  await assert.rejects(runBankStatementDocumentWrite(
    true,
    async () => { calls.push("historical"); },
    async () => { calls.push("durable"); throw new Error("durable failed"); },
  ));
  assert.deepEqual(calls, ["durable"]);
});

test("la réservation utilise la signature SQL exacte", async () => {
  const calls = [];
  const operationId = "11111111-1111-4111-8111-111111111111";
  const result = await reserveBankStatementOperation({
    async rpc(name, args) {
      calls.push({ name, args });
      return { data: operationId, error: null };
    },
  }, {
    personId: "22222222-2222-4222-8222-222222222222",
    accountId: "33333333-3333-4333-8333-333333333333",
    statementId: "44444444-4444-4444-8444-444444444444",
    intent: "replace",
    clientRequestId: "55555555-5555-4555-8555-555555555555",
  });
  assert.equal(result, operationId);
  assert.deepEqual(calls, [{
    name: "begin_bank_statement_document_operation",
    args: {
      p_protected_person_id: "22222222-2222-4222-8222-222222222222",
      p_financial_account_id: "33333333-3333-4333-8333-333333333333",
      p_statement_id: "44444444-4444-4444-8444-444444444444",
      p_intent: "replace",
      p_client_request_id: "55555555-5555-4555-8555-555555555555",
    },
  }]);
});

test("l’identifiant d’idempotence est stable et distingue les écritures", () => {
  const base = {
    personId: "22222222-2222-4222-8222-222222222222",
    accountId: "33333333-3333-4333-8333-333333333333",
    statementId: "44444444-4444-4444-8444-444444444444",
    intent: "replace",
    existingUpdatedAt: "2026-10-20T10:00:00.000Z",
    metadata,
    bytes: new Uint8Array([1, 2, 3]),
  };
  const first = createBankStatementRequestId(base);
  assert.match(first, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(createBankStatementRequestId({ ...base, bytes: new Uint8Array([1, 2, 3]) }), first);
  assert.notEqual(createBankStatementRequestId({ ...base, bytes: new Uint8Array([1, 2, 4]) }), first);
  assert.notEqual(createBankStatementRequestId({ ...base, metadata: { ...metadata, note: "Autre" } }), first);
  assert.notEqual(createBankStatementRequestId({ ...base, existingUpdatedAt: "2026-10-20T10:01:00.000Z" }), first);
});

test("une réservation refusée ou invalide est rejetée sans détail SQL", async () => {
  const input = {
    personId: "22222222-2222-4222-8222-222222222222",
    accountId: "33333333-3333-4333-8333-333333333333",
    statementId: "44444444-4444-4444-8444-444444444444",
    intent: "attach",
    clientRequestId: "55555555-5555-4555-8555-555555555555",
  };
  await assert.rejects(
    reserveBankStatementOperation({ async rpc() { return { data: null, error: { code: "P4O01" } }; } }, input),
    /réservation/,
  );
  await assert.rejects(
    reserveBankStatementOperation({ async rpc() { return { data: "secret-internal-path", error: null }; } }, input),
    /invalide/,
  );
});

test("création, ajout, remplacement et suppression du PDF utilisent le moteur commun", () => {
  assert.match(writeService, /intent: "create"/);
  assert.match(writeService, /intent = documentMetadata\(input\.statement\) \? "replace" : "attach"/);
  assert.match(writeService, /intent: "delete"/);
  assert.match(durable, /reserveBankStatementOperation\(input\.client, input\)/);
  assert.match(durable, /createServerDocumentOperationEngine\(\)/);
  assert.match(durable, /bankStatementOperation\(/);
  assert.doesNotMatch(durable, /storage\.from|bank_statements|objectPath|bucketId/);
  assert.match(writeService, /if \(!input\.pdf\) \{[\s\S]*?from\("bank_statements"\)\.insert/);
});

test("le parcours HTTP et l’interface conservent les lectures et séparent les suppressions", () => {
  assert.match(itemRoute, /export async function GET/);
  assert.match(itemRoute, /createSignedUrl/);
  assert.match(itemRoute, /searchParams\.get\("document"\) === "1"/);
  assert.match(itemRoute, /deleteBankStatementDocument/);
  assert.match(writeService, /Supprimez d’abord le PDF du relevé/);
  assert.match(collectionRoute, /clientRequestId/);
  assert.match(page, /durableOperationsEnabled=\{isBankStatementDurableOperationsEnabled\(\)\}/);
  assert.match(component, /Supprimer le PDF/);
  assert.match(component, /\?document=1/);
  assert.match(component, /clientRequestId\.current \?\?= crypto\.randomUUID\(\)/);
});

test("les suppressions indirectes connues sont identifiées sans élargir ce lot", () => {
  assert.match(bankStatementSql, /delete_empty_financial_account/);
  assert.match(bankStatementSql, /EXISTS[\s\S]*bank_statements/i);
  assert.match(bankStatementSql, /on delete restrict/i);
  assert.match(accountDeletion, /admin\.storage\.from\(object\.bucket_id\)/);
  assert.match(accountDeletion, /storage\.remove\(\[object\.name\]\)/);
});
