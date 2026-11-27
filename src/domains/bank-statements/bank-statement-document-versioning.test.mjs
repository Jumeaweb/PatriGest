import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./bank-statement-document-versioning.ts");
const component = source("./components/bank-statement-manager.tsx");
const currentRoute = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/route.ts");
const versionsRoute = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/versions/route.ts");
const historicalRoute = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/versions/[versionId]/route.ts");
const protectedResponse = source("../../lib/supabase/protected-storage-response.ts");
const migration = source("../../../supabase/migrations/20261115100000_version_bank_statement_documents.sql");
const reportPage = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/page.tsx");
const reportPreview = source("../management-reports/preview.tsx");
const reportServices = source("../management-reports/services.ts");
const databaseTypes = source("../../types/database.ts");

test("la correction exige un PDF, un motif, une confirmation et une révision", () => {
  assert.match(component, /Corriger le document/);
  assert.match(component, /name="reason" required minLength=\{3\}/);
  assert.match(component, /Je confirme que seul le PDF doit être corrigé/);
  assert.match(component, /expectedActiveRevision/);
  assert.match(versionsRoute, /readPdf\(form, true\)/);
  assert.match(versionsRoute, /reason: z\.string\(\)\.trim\(\)\.min\(3/);
});
test("les droits, le dossier archivé et le rapprochement validé sont contrôlés côté serveur", () => {
  assert.match(versionsRoute, /accessRole === "read_only"/);
  assert.match(versionsRoute, /person\.archived_at/);
  assert.match(versionsRoute, /reconciliation\.status !== "validated"/);
  assert.match(migration, /public\.can_manage_protected_person/);
  assert.match(migration, /person\.archived_at is null/);
});

test("le téléversement est immuable, vérifié et relançable avec la même demande", () => {
  assert.match(service, /upsert: false/);
  assert.match(service, /clientRequestId/);
  assert.match(service, /existingHash !== sha256/);
  assert.match(service, /finalize_bank_statement_document_correction/);
  assert.doesNotMatch(service, /\.remove\(/);
  assert.match(migration, /correction\.requested_by = auth\.uid\(\)/);
  assert.match(migration, /correction\.state = 'reserved'/);
});

test("les routes servent les octets sans exposer le chemin Storage", () => {
  assert.match(currentRoute, /downloadBankStatementDocument/);
  assert.match(historicalRoute, /downloadBankStatementDocument/);
  assert.match(historicalRoute, /protectedStorageResponse/);
  assert.match(protectedResponse, /Cache-Control": "private, no-store/);
  assert.doesNotMatch(component, /storagePath/);
  assert.doesNotMatch(versionsRoute, /storagePath/);
});

test("l’historique et les comptes de gestion utilisent des versions explicites", () => {
  assert.match(component, /Historique du document/);
  assert.match(component, /versions\/\$\{version\.versionId\}/);
  assert.match(reportPage, /getManagementReportBankStatementDocumentVersions/);
  assert.match(reportPreview, /pinnedStatementVersions/);
  assert.match(reportPreview, /versions\/\$\{pinnedVersion\}/);
  assert.match(migration, /management_report_bank_statement_document_versions/);
});

test("la lecture des versions figées et les types suivent les colonnes SQL déployées", () => {
  assert.match(reportServices, /select\("bank_statement_id,document_version_id"\)/);
  assert.match(reportServices, /item\.document_version_id/);
  assert.doesNotMatch(reportServices, /item\.version_id/);
  assert.match(databaseTypes, /management_report_bank_statement_document_versions:[\s\S]*document_version_id: string; pinned_at: string/);
  assert.match(databaseTypes, /bank_statement_document_corrections:[\s\S]*safe_error_code: string \| null/);
  assert.doesNotMatch(
    databaseTypes.slice(
      databaseTypes.indexOf("bank_statement_document_corrections:"),
      databaseTypes.indexOf("management_report_bank_statement_document_versions:"),
    ),
    /cancelled_at/,
  );
});

test("l’empreinte des versions initiales est calculée uniquement pendant une lecture binaire", () => {
  assert.match(service, /verifyInitialVersionIfNeeded/);
  assert.match(service, /verify_bank_statement_document_version_integrity/);
  assert.match(service, /downloadBankStatementDocument[\s\S]*verifyInitialVersionIfNeeded/);
  assert.doesNotMatch(service.slice(service.indexOf("getBankStatementDocumentHistory"), service.indexOf("getBankStatementDocumentVersion")), /createHash|download/);
});

test("le cycle pré-validation synchronise la version initiale sans affaiblir les documents figés", () => {
  assert.match(migration, /assert_bank_statement_initial_document_mutable/);
  assert.match(migration, /integrity_status = 'pending_hash'/);
  assert.match(migration, /sha256 = null/);
  assert.match(migration, /cleanup_unfrozen_bank_statement_document_versions/);
  assert.match(migration, /bank_statements_zz_cleanup_unfrozen_document_versions/);
  assert.match(migration, /protect_bank_statement_document_storage_version/);
  assert.match(migration, /management_report_bank_statement_document_versions pinned/);
  assert.match(migration, /reconciliation\.status = 'validated'/);
});
