import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { getDebtForReportPeriod } from "./debt-period.ts";

const debt = (overrides = {}) => ({
  start_date: "2022-01-01",
  settled_at: null,
  status: "active",
  balances: [],
  ...overrides,
});
const situation = (balance_date, remaining_balance, cancelled_at = null) => ({
  balance_date, remaining_balance, cancelled_at,
});
const for2024 = (record) => getDebtForReportPeriod(record, "2024-01-01", "2024-12-31");

test("une dette active figure dans plusieurs exercices avec le CRD propre à chacun", () => {
  const first = situation("2023-12-20", 200);
  const second = situation("2024-12-20", 100);
  const record = debt({ balances: [second, first] });
  assert.deepEqual(getDebtForReportPeriod(record, "2023-01-01", "2023-12-31"), {
    balance: first, presentation: { status: "Active" },
  });
  assert.deepEqual(for2024(record), {
    balance: second, presentation: { status: "Active" },
  });
});

test("une clôture postérieure à un exercice non civil ne change ni son statut ni son CRD", () => {
  const last = situation("2024-11-30", 210);
  const record = debt({
    status: "settled", settled_at: "2025-07-01",
    balances: [situation("2025-07-01", 0), last],
  });
  assert.deepEqual(getDebtForReportPeriod(record, "2024-07-01", "2025-06-30"), {
    balance: last, presentation: { status: "Active" },
  });
});

for (const settlementDate of ["2024-01-01", "2024-04-30", "2024-12-31"]) {
  test(`une dette soldée le ${settlementDate} figure avec sa clôture et son CRD nul`, () => {
    const zero = situation(settlementDate, 0);
    assert.deepEqual(for2024(debt({
      status: "settled", settled_at: settlementDate, balances: [zero],
    })), { balance: zero, presentation: { status: "Soldée", settlementDate } });
  });
}

test("les dettes closes avant l’exercice ou contractées après sont exclues", () => {
  assert.equal(for2024(debt({ status: "settled", settled_at: "2023-12-31" })), null);
  assert.equal(for2024(debt({ start_date: "2025-01-01" })), null);
  assert.equal(for2024(debt({ start_date: "2024-12-31" })).presentation.status, "Active");
});

test("une date de début absente est signalée sans exclure la dette ni sa situation", () => {
  const last = situation("2024-02-02", 75);
  const result = for2024(debt({ start_date: null, balances: [last] }));
  assert.equal(result.balance, last);
  assert.equal(result.presentation.status, "Active");
  assert.deepEqual(result.presentation.warnings, ["Date de début non renseignée."]);
});

test("une date de clôture absente ou contradictoire rend le statut indéterminé", () => {
  for (const record of [
    debt({ status: "settled" }),
    debt({ status: "settled", start_date: "2024-03-01", settled_at: "2024-01-01" }),
    debt({ settled_at: "2024-01-01" }),
  ]) {
    const { presentation } = for2024(record);
    assert.equal(presentation.status, "Statut historique indéterminé");
    assert.equal(presentation.settlementDate, undefined);
    assert.deepEqual(presentation.warnings, ["Date de clôture absente ou incohérente."]);
  }
});

test("seule la dernière situation valide est retenue après correction ou annulation", () => {
  const valid = situation("2024-08-31", 80);
  const corrected = situation("2024-11-11", 35);
  const future = situation("2025-01-01", 12);
  const tooEarly = situation("2024-01-01", 100);
  const record = debt({ start_date: "2024-02-01", balances: [valid, future, corrected, tooEarly] });
  assert.equal(for2024(record).balance, corrected);
  corrected.cancelled_at = "2025-01-08T00:00:00Z";
  const fallback = for2024(record);
  assert.equal(fallback.balance, valid);
  assert.deepEqual(fallback.presentation.warnings, ["Situation antérieure au début de la dette ignorée."]);
  assert.equal(for2024({ ...record, balances: [future, tooEarly, corrected] }).balance, null);
});

test("une clôture historique incohérente ne fabrique pas un CRD nul", () => {
  const lastKnown = situation("2024-03-01", 150);
  const record = debt({
    status: "settled", settled_at: "2024-06-01",
    balances: [lastKnown, situation("2024-06-02", 0)],
  });
  const result = for2024(record);
  assert.equal(result.balance, lastKnown);
  assert.deepEqual(result.presentation.warnings, [
    "Situation postérieure à la clôture de la dette ignorée.",
    "Aucune situation à 0 € à la date de clôture.",
  ]);
  assert.equal(for2024(debt({ balances: [situation("2024-12-31", 0)] })).balance.remaining_balance, 0);
  assert.equal(for2024(debt()).balance, null);
});

test("la préparation, l’aperçu et le PDF consomment la même restitution historique", () => {
  const read = (file) => readFileSync(new URL(file, import.meta.url), "utf8");
  const service = read("./services.ts");
  const model = read("./preview-model.ts");
  const components = read("./components.tsx");
  const preview = read("./preview.tsx");
  assert.match(service, /getDebtForReportPeriod\(debt, report\.period_start, report\.period_end\)/);
  assert.match(service, /complete: relevantDebts\.every\(\(item\) => Boolean\(item\.balance\)\)/);
  assert.match(components, /presentation\.status[\s\S]*?presentation\.settlementDate[\s\S]*?presentation\.warnings/);
  assert.match(model, /\.\.\.presentation,[\s\S]*?remainingBalance: balance\?\.remaining_balance \?\? null/);
  assert.match(preview, /debt\.status[\s\S]*?debt\.settlementDate[\s\S]*?debt\.warnings/);
  assert.match(read("./pdf.ts"), /debt\.settlementDate[\s\S]*?debt\.status[\s\S]*?debt\.warnings/);
});
