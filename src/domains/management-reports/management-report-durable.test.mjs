import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  MANAGEMENT_REPORT_DURABLE_OPERATIONS_ENV,
  isManagementReportDurableOperationsEnabled,
  runManagementReportDocumentWrite,
} from "./management-report-durable-availability.ts";
import {
  createManagementReportRequestId,
  reserveManagementReportOperation,
} from "./management-report-durable-reservation.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const route = source("../../app/api/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/document/route.ts");
const documentActions = source("./report-document-actions.tsx");
const durable = source("./management-report-durable.ts");
const reservationSql = source("../../../supabase/migrations/20261018400000_create_document_operation_reservations.sql");
const progressionSql = source("../../../supabase/migrations/20261018600000_create_document_operation_progression.sql");

const personId = "10000000-0000-4000-8000-000000000001";
const reportId = "10000000-0000-4000-8000-000000000002";
const operationId = "10000000-0000-4000-8000-000000000003";
const requestId = "10000000-0000-8000-8000-000000000004";

test("l’indicateur des comptes de gestion est indépendant, strict et désactivé par défaut", () => {
  assert.equal(
    MANAGEMENT_REPORT_DURABLE_OPERATIONS_ENV,
    "PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS",
  );
  assert.equal(isManagementReportDurableOperationsEnabled(undefined), false);
  assert.equal(isManagementReportDurableOperationsEnabled("false"), false);
  assert.equal(isManagementReportDurableOperationsEnabled("TRUE"), false);
  assert.equal(isManagementReportDurableOperationsEnabled("true"), true);
});

test("le répartiteur choisit un seul parcours et ne replie jamais une erreur durable", async () => {
  const calls = [];
  assert.equal(await runManagementReportDocumentWrite(
    false,
    async () => { calls.push("historical"); return "legacy"; },
    async () => { calls.push("durable"); return "new"; },
  ), "legacy");
  assert.deepEqual(calls, ["historical"]);

  calls.length = 0;
  await assert.rejects(runManagementReportDocumentWrite(
    true,
    async () => { calls.push("historical"); },
    async () => { calls.push("durable"); throw new Error("failure"); },
  ));
  assert.deepEqual(calls, ["durable"]);
});

test("la réservation utilise la RPC et sa signature exactes", async () => {
  const calls = [];
  const result = await reserveManagementReportOperation({
    async rpc(name, args) {
      calls.push({ name, args });
      return { data: operationId, error: null };
    },
  }, {
    personId,
    reportId,
    intent: "finalize",
    clientRequestId: requestId,
  });
  assert.equal(result, operationId);
  assert.deepEqual(calls, [{
    name: "begin_management_report_document_operation",
    args: {
      p_protected_person_id: personId,
      p_report_id: reportId,
      p_intent: "finalize",
      p_client_request_id: requestId,
    },
  }]);
});

test("une réservation refusée ou invalide reste une erreur sûre", async () => {
  const input = { personId, reportId, intent: "resume", clientRequestId: requestId };
  await assert.rejects(
    reserveManagementReportOperation({ async rpc() { return { data: null, error: { message: "secret" } }; } }, input),
    /réservation/,
  );
  await assert.rejects(
    reserveManagementReportOperation({ async rpc() { return { data: "internal-path", error: null }; } }, input),
    /invalide/,
  );
});

test("l’identifiant d’idempotence lie intention, révision, snapshot et octets", () => {
  const base = {
    personId,
    reportId,
    intent: "finalize",
    clientRequestNonce: "10000000-0000-4000-8000-000000000005",
    sourceDocumentRevision: "draft-id:created-at:path",
    previewSnapshot: { report: { status: "finalized", id: reportId }, total: 12.34 },
    snapshotSchemaVersion: 1,
    fileName: "compte.pdf",
    bytes: new Uint8Array([1, 2, 3]),
  };
  const first = createManagementReportRequestId(base);
  assert.match(first, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(createManagementReportRequestId({
    ...base,
    previewSnapshot: { total: 12.34, report: { id: reportId, status: "finalized" } },
    bytes: new Uint8Array([1, 2, 3]),
  }), first);
  assert.notEqual(createManagementReportRequestId({ ...base, intent: "generate" }), first);
  assert.notEqual(createManagementReportRequestId({ ...base, clientRequestNonce: "10000000-0000-4000-8000-000000000006" }), first);
  assert.notEqual(createManagementReportRequestId({ ...base, sourceDocumentRevision: "other" }), first);
  assert.notEqual(createManagementReportRequestId({ ...base, bytes: new Uint8Array([1, 2, 4]) }), first);
  assert.notEqual(createManagementReportRequestId({
    ...base,
    previewSnapshot: { report: { status: "finalized", id: reportId }, total: 12.35 },
  }), first);
});

test("la route raccorde génération, reprise et finalisation sans contourner le moteur en mode ON", () => {
  assert.equal(route.match(/runManagementReportDocumentWrite\(/g)?.length, 3);
  assert.match(route, /intent: "generate"/);
  assert.match(route, /intent: "finalize"/);
  assert.match(route, /intent: "resume"/);
  assert.match(route, /deterministicCreationDate: durableEnabled \? preview\.report\.updated_at : undefined/);
  assert.match(route, /finalizeManagementReportProjectSnapshot\(draft\.preview_snapshot, draft\.snapshot_schema_version\)/);
  assert.match(route, /Aucun repli vers l’ancien parcours n’a été effectué/);
  assert.match(route, /x-patrigest-request-id/);
  assert.match(documentActions, /clientRequestId\.current \?\?= crypto\.randomUUID\(\)/);
  assert.match(documentActions, /"x-patrigest-request-id": clientRequestId\.current/);
  assert.match(documentActions, /disabled=\{pending\}/);
  assert.match(durable, /createServerDocumentOperationEngine\(\)/);
  assert.match(durable, /managementReportGenerationOperation\(/);
  assert.match(durable, /managementReportFinalizationOperation\(/);
  assert.match(durable, /managementReportResumeOperation\(/);
  assert.doesNotMatch(durable, /storage\.from|MANAGEMENT_REPORT_BUCKET/);
});

test("les contrats SQL couvrent l’état, les droits, les cibles et la révision optimiste", () => {
  assert.match(reservationSql, /create function public\.begin_management_report_document_operation/);
  assert.match(reservationSql, /management_report_generate/);
  assert.match(reservationSql, /management_report_finalize/);
  assert.match(reservationSql, /management_report_resume/);
  assert.match(progressionSql, /create function public\.finalize_management_report_document_operation/);
  assert.match(progressionSql, /assert_document_operation_caller/);
  assert.match(progressionSql, /assert_document_operation_ready_to_finalize/);
  assert.match(progressionSql, /p_expected_revision/);
});
