import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./services.ts");
const reportPage = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/page.tsx");
const previewPage = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/apercu/page.tsx");
const printButton = source("./print-preview-button.tsx");

test("le brouillon expose un aperçu vivant sans changer son statut", () => {
  assert.match(
    service,
    /if \(report\.status === "draft"\)[\s\S]*?getManagementReportSnapshot\(personId, reportId\)[\s\S]*?buildManagementReportPreview\(liveSnapshot\)/,
  );
  assert.match(reportPage, /\["draft", "ready"\]\.includes\(report\.status\)/);
  assert.match(reportPage, /report\.status === "draft" \? "Aperçu provisoire" : "Voir l’aperçu"/);
  assert.match(previewPage, /Aperçu provisoire · données recalculées depuis la préparation/);
});

test("l’aperçu provisoire peut être imprimé sans action métier", () => {
  assert.match(previewPage, /<PrintPreviewButton \/>/);
  assert.match(printButton, /type="button"/);
  assert.match(printButton, /onClick=\{\(\) => window\.print\(\)\}/);
  assert.doesNotMatch(printButton, /action=|formAction|fetch\(|rpc\(/);
});
