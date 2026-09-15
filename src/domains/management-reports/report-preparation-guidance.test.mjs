import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getReportPreparationGuidance } from "./report-preparation-guidance.ts";

const page = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/page.tsx", import.meta.url), "utf8");
const form = readFileSync(new URL("./management-report-create-form.tsx", import.meta.url), "utf8");
const service = readFileSync(new URL("./services.ts", import.meta.url), "utf8");
const period = (id, start_date, end_date) => ({ id, start_date, end_date });
const annual = period("annual", "2026-01-01", "2026-12-31");

test("sans exercice, la guidance n'impose pas un exercice pour préparer manuellement", () => {
  assert.deepEqual(getReportPreparationGuidance([], []), { suggested: null, state: "no_period" });
  assert.match(page, /Aucun exercice de gestion n&apos;est actuellement disponible/);
  assert.match(page, /continuer en renseignant les dates manuellement ci-dessous/);
  assert.match(page, /\{canManage && \(\s*<ManagementReportCreateForm/);
  assert.match(form, /value=\{suggested\?\.id \?\? ""\}/);
  assert.match(service, /if \(input\.managementPeriodId\) \{/);
});

test("le lien correct est réservé aux rôles pouvant gérer les exercices", () => {
  assert.match(page, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(page, /\{canManage && \(\s*<Link href=\{`\/dossiers\/\$\{protectedPersonId\}\/exercices`\}/);
  assert.match(page, /Gérer les exercices/);
});

test("un exercice annuel disponible préserve le préremplissage existant", () => {
  assert.deepEqual(getReportPreparationGuidance([annual], []), { suggested: annual, state: "suggested" });
  assert.match(page, /suggested=\{suggested \?\? null\}/);
});

test("les périodes manuelles restent possibles sans préremplissage", () => {
  const nonAnnual = period("short", "2026-02-01", "2026-11-30");
  assert.deepEqual(getReportPreparationGuidance([nonAnnual], []), { suggested: null, state: "manual" });
  assert.deepEqual(getReportPreparationGuidance([annual], [{ period_start: annual.start_date, period_end: annual.end_date }]), { suggested: null, state: "manual" });
  assert.match(page, /renseigner les dates manuellement ci-dessous/);
  assert.match(form, /name="periodStart" required readOnly=\{Boolean\(suggested\)\}/);
});

test("les rapports existants restent visibles et aucun précontrôle approximatif n'est ajouté", () => {
  assert.match(page, /\{reports\.map\(\(report\) => \(/);
  assert.match(page, /\{!reports\.length && \(/);
  assert.doesNotMatch(page, /getFinancialAccounts|getTransactions|aggregateStableReportOperations/);
  assert.doesNotMatch(page, /preparationState === "no_period" && <ManagementReportCreateForm/);
});
