import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  finalizeManagementReportProjectSnapshot,
  MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
} from "./snapshot.ts";
import { generateManagementReportPdf } from "./pdf.ts";

const projectSnapshot = {
  complete: true,
  report: {
    id: "10000000-0000-4000-8000-000000000001",
    protected_person_id: "10000000-0000-4000-8000-000000000002",
    management_period_id: null,
    report_year: 2026,
    period_start: "2026-01-01",
    period_end: "2026-12-31",
    status: "generated",
    residence_changed: false,
    representative_address_changed: false,
    real_estate_confirmed: true,
    financial_investments_confirmed: true,
    observations: "Projet relu",
    signature_place: "Paris",
    generated_at: null,
    finalized_at: null,
    transmitted_at: null,
    approved_at: null,
    difficulty_reported_at: null,
    created_by: "10000000-0000-4000-8000-000000000003",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
  },
  person: {
    id: "10000000-0000-4000-8000-000000000002",
    owner_id: "10000000-0000-4000-8000-000000000003",
    first_name: "Jean",
    last_name: "TEST",
    birth_name: null,
    birth_date: null,
    birth_place: null,
    address_line1: "1 rue du Projet",
    address_line2: null,
    postal_code: "75001",
    city: "Paris",
    country: "France",
    phone: null,
    email: null,
    residence_address_line1: null,
    residence_address_line2: null,
    residence_postal_code: null,
    residence_city: null,
    residence_country: null,
    notes: null,
    status: "active",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
    archived_at: null,
  },
  measure: null,
  measureCorrespondence: null,
  resources: {
    sections: [{
      label: "Ressources",
      lines: [{ code: "RES-1", label: "Revenus", amount: 100, amountCents: 10000 }],
      total: 100,
    }],
    total: 100,
    totalCents: 10000,
    count: 1,
  },
  expenses: { sections: [], total: 0, totalCents: 0, count: 0 },
  result: 100,
  balance: { start: 400, end: 500 },
  accounts: [],
  placements: [{
    id: "10000000-0000-4000-8000-000000000004",
    institution: "Banque",
    name: "Placement",
    type: "Assurance-vie",
    startValue: 400,
    endValue: 500,
    startValueDate: "2026-01-01",
    endValueDate: "2026-12-31",
    reliable: true,
  }],
  statements: [],
  properties: [],
  propertyEvents: [],
  debts: [],
  confirmations: {
    residenceChanged: false,
    representativeAddressChanged: false,
    realEstateConfirmed: true,
    financialInvestmentsConfirmed: true,
  },
  observations: "Projet relu",
  signaturePlace: "Paris",
  checks: {
    resources: true,
    expenses: true,
    result: true,
    reference: true,
    classified: true,
    consistent: true,
    unclassifiedOperations: 0,
    unexpectedCodes: [],
  },
};

test("le snapshot définitif ne diffère du projet que par son statut", () => {
  const result = finalizeManagementReportProjectSnapshot(
    projectSnapshot,
    MANAGEMENT_REPORT_SNAPSHOT_SCHEMA_VERSION,
  );
  assert.equal(result.success, true);
  if (!result.success) return;

  assert.deepEqual(result.snapshot, {
    ...projectSnapshot,
    report: { ...projectSnapshot.report, status: "finalized" },
  });
  assert.equal(result.preview.report.status, "finalized");
});

test("ignore une transaction modifiée après la génération du projet", () => {
  const currentData = structuredClone(projectSnapshot);
  currentData.resources.sections[0].lines[0].amount = 999;
  currentData.resources.total = 999;

  const result = finalizeManagementReportProjectSnapshot(projectSnapshot, 1);
  assert.equal(result.success, true);
  if (!result.success) return;
  assert.equal(result.preview.resources.sections[0].lines[0].amount, 100);
  assert.notEqual(result.preview.resources.total, currentData.resources.total);
});

test("ignore une valorisation modifiée après la génération du projet", () => {
  const currentData = structuredClone(projectSnapshot);
  currentData.placements[0].endValue = 9999;

  const result = finalizeManagementReportProjectSnapshot(projectSnapshot, 1);
  assert.equal(result.success, true);
  if (!result.success) return;
  assert.equal(result.preview.placements[0].endValue, 500);
  assert.notEqual(result.preview.placements[0].endValue, currentData.placements[0].endValue);
});

test("ignore une modification des données personnelles postérieure au projet", () => {
  const currentData = structuredClone(projectSnapshot);
  currentData.person.address_line1 = "99 rue modifiée";

  const result = finalizeManagementReportProjectSnapshot(projectSnapshot, 1);
  assert.equal(result.success, true);
  if (!result.success) return;
  assert.equal(result.preview.person.address_line1, "1 rue du Projet");
  assert.notEqual(result.preview.person.address_line1, currentData.person.address_line1);
});

test("refuse un snapshot absent, incompatible, invalide ou hors statut projet", () => {
  assert.deepEqual(finalizeManagementReportProjectSnapshot(null, 1), {
    success: false,
    reason: "missing",
  });
  assert.deepEqual(finalizeManagementReportProjectSnapshot(projectSnapshot, 2), {
    success: false,
    reason: "unsupported_version",
  });
  assert.equal(finalizeManagementReportProjectSnapshot({}, 1).reason, "invalid");
  assert.equal(finalizeManagementReportProjectSnapshot({
    ...projectSnapshot,
    report: { ...projectSnapshot.report, status: "finalized" },
  }, 1).reason, "invalid_status");
});

test("le générateur limite les différences projet/final à la présentation", () => {
  const pdf = readFileSync(new URL("./pdf.ts", import.meta.url), "utf8");
  const route = readFileSync(
    new URL("../../app/api/dossiers/[protectedPersonId]/comptes-de-gestion/[reportId]/document/route.ts", import.meta.url),
    "utf8",
  );
  const patchBody = route.slice(route.indexOf("export async function PATCH"), route.indexOf("export async function DELETE"));

  assert.match(pdf, /if \(mode === "draft"\)[\s\S]*doc\.text\("PROJET"/);
  assert.match(pdf, /if \(mode === "draft"\)[\s\S]*DOCUMENT DE TRAVAIL — NON FINALISÉ/);
  assert.doesNotMatch(pdf, /preview\.report\.status/);
  assert.match(patchBody, /finalizeManagementReportProjectSnapshot\(draft\.preview_snapshot, draft\.snapshot_schema_version\)/);
  assert.doesNotMatch(patchBody, /livePreview\(/);
  assert.match(patchBody, /context\.report\.refresh_required_at/);
  assert.match(route, /rpc\("resume_management_report_preparation"/);
  assert.match(route, /accessRole === "read_only"/);
});

test("le PDF durable est reproductible pour une même photographie", async () => {
  const first = await generateManagementReportPdf(projectSnapshot, {
    mode: "draft",
    deterministicCreationDate: projectSnapshot.report.updated_at,
  });
  const retry = await generateManagementReportPdf(structuredClone(projectSnapshot), {
    mode: "draft",
    deterministicCreationDate: projectSnapshot.report.updated_at,
  });
  const finalSnapshot = finalizeManagementReportProjectSnapshot(projectSnapshot, 1);
  assert.equal(finalSnapshot.success, true);
  if (!finalSnapshot.success) return;
  const final = await generateManagementReportPdf(finalSnapshot.preview, {
    mode: "final",
    deterministicCreationDate: finalSnapshot.preview.report.updated_at,
  });

  assert.deepEqual(first, retry);
  assert.notDeepEqual(first, final);
});
