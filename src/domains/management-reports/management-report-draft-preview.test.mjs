import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./services.ts");
const reportPage = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/page.tsx");
const previewPage = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/apercu/page.tsx");
const printButton = source("./print-preview-button.tsx");
const dashboard = source("./components.tsx");
const updateForm = source("./management-report-update-form.tsx");
const statusActions = source("./report-status-actions.tsx");
const previewModel = source("./preview-model.ts");

test("le brouillon expose un aperçu vivant sans changer son statut", () => {
  assert.match(
    service,
    /if \(report\.status === "draft"\)[\s\S]*?getManagementReportSnapshot\(personId, reportId\)[\s\S]*?buildManagementReportPreview\(liveSnapshot\)/,
  );
  assert.doesNotMatch(reportPage, /report\.status === "draft" \? "Aperçu provisoire"/);
  assert.match(previewPage, /Aperçu provisoire · données recalculées depuis la préparation/);
});

test("les trois actions du brouillon sont regroupées en bas dans l’ordre attendu", () => {
  assert.match(
    dashboard,
    /actions=\{report\.status === "draft"[\s\S]*?Aperçu provisoire[\s\S]*?<ReportStatusActions[\s\S]*?withinForm/,
  );
  assert.match(
    updateForm,
    /Enregistrer[\s\S]*?\{actions\}/,
  );
  assert.match(statusActions, /formAction=\{action\}/);
});

test("l’aperçu provisoire peut être imprimé sans action métier", () => {
  assert.match(previewPage, /<PrintPreviewButton \/>/);
  assert.match(printButton, /type="button"/);
  assert.match(printButton, /onClick=\{\(\) => window\.print\(\)\}/);
  assert.doesNotMatch(printButton, /action=|formAction|fetch\(|rpc\(/);
});

test("le snapshot PDF exclut les champs techniques du dossier", () => {
  assert.match(previewModel, /managementReports: _managementReports/);
  assert.match(previewModel, /archive_revision: _archiveRevision/);
  assert.match(previewModel, /void _managementReports/);
  assert.match(previewModel, /void _archiveRevision/);
});
