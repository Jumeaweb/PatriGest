import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/page.tsx");
const statusHelper = source("./management-report-status.ts");

const expectedStatuses = [
  ["draft", "En préparation"],
  ["ready", "Prêt"],
  ["generated", "Projet généré"],
  ["finalized", "Finalisé"],
  ["transmitted", "Transmis"],
  ["approved", "Approuvé"],
  ["difficulty", "Difficulté signalée"],
];

test("tous les statuts métier réels ont un libellé français explicite", () => {
  for (const [status, label] of expectedStatuses) {
    assert.match(statusHelper, new RegExp(`${status}: \\{[\\s\\S]*?label: "${label}"`));
  }
});

test("les statuts associent le texte à une présentation sémantique sans modifier le workflow", () => {
  assert.match(statusHelper, /Record<[\s\S]*?ManagementReportStatus/);
  assert.match(statusHelper, /approved:[\s\S]*?emerald/);
  assert.match(statusHelper, /difficulty:[\s\S]*?red/);
  assert.match(page, /getManagementReportStatusPresentation\(report\.status\)/);
  assert.match(page, /\{status\.label\}/);
  assert.match(page, /\$\{status\.className\}/);
});

test("la préparation et les droits existants restent inchangés", () => {
  assert.match(page, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(page, /\{canManage && \(\s*<ManagementReportCreateForm/);
  assert.match(page, /getReportPreparationGuidance/);
});
