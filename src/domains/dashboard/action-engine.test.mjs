import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getDashboardActions, getDashboardActionCounts } from "./action-engine.ts";

const personId = "11111111-1111-4111-8111-111111111111";
const period = (id, status = "closed", start_date = "2026-01-01", end_date = "2026-12-31") => ({ id, status, start_date, end_date });
const report = (id, management_period_id = null, status = "draft", period_start = "2026-01-01", period_end = "2026-12-31") => ({ id, management_period_id, status, period_start, period_end, report_year: Number(period_end.slice(0, 4)) });
const actions = (periods, reports, role = "owner") => getDashboardActions(personId, role, periods, reports);

test("aucun exercice et aucun rapport ne produisent aucune action", () => {
  assert.deepEqual(actions([], []), []);
  assert.deepEqual(getDashboardActionCounts(actions([], [])), { actionCount: 0, reportActionCount: 0 });
});

test("un exercice ouvert garde son échéance et sa destination directe", () => {
  const result = actions([period("open-1", "open")], []);
  assert.deepEqual(result.map((item) => item.kind), ["period_deadline"]);
  assert.equal(result[0].id, `period-${personId}-open-1`);
  assert.equal(result[0].href, `/dossiers/${personId}/exercices`);
  assert.equal(result[0].dueDate, "2026-12-31");
});

test("un exercice clôturé sans rapport permet sa préparation", () => {
  const result = actions([period("closed-1")], []);
  assert.deepEqual(result.map((item) => item.kind), ["report_to_prepare"]);
  assert.equal(result[0].href, `/dossiers/${personId}/comptes-de-gestion`);
  assert.deepEqual(getDashboardActionCounts(result), { actionCount: 1, reportActionCount: 1 });
});

test("un brouillon lié par FK remplace préparer par reprendre", () => {
  const result = actions([period("closed-1")], [report("draft-1", "closed-1")]);
  assert.deepEqual(result.map((item) => item.kind), ["draft_to_resume"]);
  assert.equal(result[0].href, `/dossiers/${personId}/comptes-de-gestion/draft-1`);
  assert.equal(result[0].id, `draft-${personId}-draft-1`);
  assert.deepEqual(getDashboardActionCounts(result), { actionCount: 1, reportActionCount: 1 });
});

test("un brouillon manuel aux dates exactement égales supprime le doublon préparer/reprendre", () => {
  const result = actions([period("closed-1")], [report("manual-1")]);
  assert.deepEqual(result.map((item) => item.kind), ["draft_to_resume"]);
  assert.equal(result[0].periodId, null);
  assert.equal(result[0].reportId, "manual-1");
});

test("des dates différentes ou seulement chevauchantes ne sont pas rapprochées", () => {
  for (const other of [report("other", null, "draft", "2025-01-01", "2025-12-31"), report("overlap", null, "draft", "2026-02-01", "2026-12-31")]) {
    assert.deepEqual(actions([period("closed-1")], [other]).map((item) => item.kind), ["report_to_prepare", "draft_to_resume"]);
  }
});

test("des périodes distinctes gardent des identités indépendantes", () => {
  const result = actions([period("2025", "closed", "2025-01-01", "2025-12-31"), period("2026")], []);
  assert.equal(result.length, 2);
  assert.notEqual(result[0].id, result[1].id);
  assert.deepEqual(getDashboardActionCounts(result), { actionCount: 2, reportActionCount: 2 });
});

test("un exercice ouvert et son brouillon restent deux intentions distinctes", () => {
  const result = actions([period("open-1", "open")], [report("draft-1", "open-1")]);
  assert.deepEqual(result.map((item) => item.kind), ["period_deadline", "draft_to_resume"]);
  assert.equal(getDashboardActionCounts(result).actionCount, result.length);
});

test("un brouillon manuel sans exercice corrige le faux zéro global", () => {
  const result = actions([], [report("draft-1")]);
  assert.deepEqual(result.map((item) => item.kind), ["draft_to_resume"]);
  assert.deepEqual(getDashboardActionCounts(result), { actionCount: 1, reportActionCount: 1 });
});

test("owner et manager ont les mêmes intentions ; read_only conserve l'information sans action comptée", () => {
  const periods = [period("closed-1"), period("open-1", "open", "2027-01-01", "2027-12-31")];
  const reports = [report("draft-1", "closed-1")];
  for (const role of ["owner", "manager"]) {
    const result = actions(periods, reports, role);
    assert.ok(result.every((item) => item.actionable));
    assert.equal(getDashboardActionCounts(result).actionCount, result.length);
  }
  const readOnly = actions(periods, reports, "read_only");
  assert.equal(readOnly.length, 2);
  assert.ok(readOnly.every((item) => !item.actionable));
  assert.deepEqual(getDashboardActionCounts(readOnly), { actionCount: 0, reportActionCount: 0 });
});

test("ready et autres statuts n'ajoutent aucune intention", () => {
  for (const status of ["ready", "generated", "finalized", "transmitted", "approved", "difficulty"]) {
    assert.deepEqual(actions([], [report("not-draft", null, status)]), []);
    assert.deepEqual(actions([period("closed-1")], [report("not-draft", "closed-1", status)]), []);
  }
});

test("les deux dashboards consomment le moteur partagé et ses compteurs", () => {
  const globalService = readFileSync(new URL("./services/dashboard-service.ts", import.meta.url), "utf8");
  const dossierService = readFileSync(new URL("./services/dossier-dashboard-service.ts", import.meta.url), "utf8");
  const globalPage = readFileSync(new URL("../../app/tableau-de-bord/page.tsx", import.meta.url), "utf8");
  const dossierPage = readFileSync(new URL("../../app/dossiers/[protectedPersonId]/tableau-de-bord/page.tsx", import.meta.url), "utf8");
  assert.match(globalService, /getDashboardActions\(/);
  assert.match(dossierService, /getDashboardActions\(/);
  assert.match(globalService, /getDashboardActionCounts\(tasks\)/);
  assert.match(dossierService, /getDashboardActionCounts\(tasks\)/);
  assert.match(globalService, /period_start,period_end,status/);
  assert.match(globalPage, /Comptes de gestion à traiter/);
  assert.match(globalPage, /dossier\.nextAction\?\.href/);
  assert.match(dossierPage, /actionCount=\{data\.actionCounts\.actionCount\}/);
  assert.match(globalPage, /tasks\.filter\(\(task\) => !task\.actionable\)/);
  assert.match(dossierPage, /tasks\.filter\(\(task\) => !task\.actionable\)/);
});
