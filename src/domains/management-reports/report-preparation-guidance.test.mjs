import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { managementReportCreateSchema } from "./schemas.ts";
import { getManagementReportPeriodOptions } from "./report-preparation-guidance.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/page.tsx");
const form = source("./management-report-create-form.tsx");
const service = source("./services.ts");
const migration = source("../../../supabase/migrations/20261114200000_enable_management_report_period_selection.sql");
const period = (id, start_date, end_date, status = "closed") => ({ id, start_date, end_date, status });

test("tous les exercices sont triés du plus récent au plus ancien sans sélection automatique", () => {
  const historical = period("historical", "2023-01-01", "2023-12-31");
  const current = period("current", "2026-01-01", "2026-12-31", "open");
  assert.deepEqual(
    getManagementReportPeriodOptions([historical, current], []).map(({ id, covered }) => ({ id, covered })),
    [{ id: "current", covered: false }, { id: "historical", covered: false }],
  );
  assert.match(form, /useState\(""\)/);
  assert.match(form, /<option value="">Sélectionnez un exercice<\/option>/);
});

test("un exercice historique, incomplet ou non civil reste disponible", () => {
  const options = getManagementReportPeriodOptions([
    period("short", "2023-03-15", "2023-12-31"),
    period("cross-year", "2024-07-01", "2025-06-30"),
  ], []);
  assert.equal(options.every((option) => !option.covered), true);
  assert.match(migration, /drop constraint management_reports_same_calendar_year/);
  assert.match(migration, /drop constraint management_reports_period_ends_on_december_31/);
});

test("tout chevauchement, même partiel, rend l'exercice indisponible", () => {
  const [option] = getManagementReportPeriodOptions(
    [period("2023", "2023-01-01", "2023-12-31")],
    [{ period_start: "2023-06-01", period_end: "2024-05-31" }],
  );
  assert.equal(option.covered, true);
  assert.match(form, /disabled=\{period\.covered\}/);
  assert.match(form, /déjà couvert/);
});

test("le formulaire transmet uniquement l'identifiant et affiche les valeurs dérivées en lecture seule", () => {
  assert.match(form, /name="managementPeriodId"/);
  assert.doesNotMatch(form, /name="periodStart"|name="periodEnd"|name="reportYear"/);
  assert.match(form, /selectedPeriod\?\.start_date/);
  assert.match(form, /selectedPeriod\?\.end_date/);
  assert.match(form, /selectedPeriod\.end_date\.slice\(0, 4\)/);
  assert.equal((form.match(/readOnly/g) ?? []).length, 3);
  assert.match(form, /disabled=\{pending \|\| !selectedPeriod\}/);
});

test("le schéma refuse l'absence de sélection et ignore les champs manipulés", () => {
  assert.equal(managementReportCreateSchema.safeParse({ managementPeriodId: "" }).success, false);
  const parsed = managementReportCreateSchema.parse({
    managementPeriodId: "99400000-0000-4000-8000-000000000001",
    periodStart: "1900-01-01",
    periodEnd: "2200-12-31",
    reportYear: 2200,
  });
  assert.deepEqual(parsed, { managementPeriodId: "99400000-0000-4000-8000-000000000001" });
});

test("le serveur relit l'exercice dans le dossier et déduit dates et année", () => {
  assert.match(service, /\.eq\("id", input\.managementPeriodId\)[\s\S]*?\.eq\("protected_person_id", personId\)/);
  assert.match(service, /const periodStart = period\.start_date/);
  assert.match(service, /const periodEnd = period\.end_date/);
  assert.match(service, /const reportYear = Number\(periodEnd\.slice\(0, 4\)\)/);
  assert.doesNotMatch(service, /input\.periodStart|input\.periodEnd|input\.reportYear/);
});

test("la page supprime la saisie manuelle et conserve les contrôles d'accès", () => {
  assert.match(page, /getManagementReportPeriodOptions/);
  assert.match(page, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(page, /\{canManage && \(\s*<ManagementReportCreateForm/);
  assert.doesNotMatch(page, /renseigner les dates manuellement/);
  assert.match(page, /Tous les exercices sont déjà couverts/);
});

test("la migration protège les dates liées sans toucher aux CRG ni à leurs instantanés", () => {
  assert.match(migration, /management_periods_protect_linked_dates/);
  assert.match(migration, /new\.start_date, new\.end_date[\s\S]*?old\.start_date, old\.end_date/);
  assert.match(migration, /report\.management_period_id = old\.id/);
  assert.doesNotMatch(migration, /update\s+public\.management_reports|delete\s+from\s+public\.management_reports|management_report_documents/i);
});
