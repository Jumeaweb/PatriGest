import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  financialAccountSchema,
  financialAccountTypes,
} from "./schemas/financial-account-schema.ts";
import { getCurrentValuationValue } from "./utils/account-valuation-utils.ts";
import { resolveTransferOfficialCodeForFutureReport } from "../categories/category-reference.ts";

const accountUtilsSource = readFileSync(
  new URL("./utils/financial-account-utils.ts", import.meta.url),
  "utf8",
);
const transactionFormSource = readFileSync(
  new URL("../transactions/components/transaction-form.tsx", import.meta.url),
  "utf8",
);
const transactionServiceSource = readFileSync(
  new URL("../transactions/services/transaction-service.ts", import.meta.url),
  "utf8",
);
const reportCalculationsSource = readFileSync(
  new URL("../management-reports/calculations.ts", import.meta.url),
  "utf8",
);
const reportServicesSource = readFileSync(
  new URL("../management-reports/services.ts", import.meta.url),
  "utf8",
);
const previewModelSource = readFileSync(
  new URL("../management-reports/preview-model.ts", import.meta.url),
  "utf8",
);
const snapshotSource = readFileSync(
  new URL("../management-reports/snapshot.ts", import.meta.url),
  "utf8",
);

const validAccountInput = {
  accountType: "securities_account",
  accountName: "Compte-titres",
  institutionName: "Courtier",
  accountReference: "CTO-01",
  initialBalance: "1000.00",
  initialBalanceDate: "2026-01-01",
  openingDate: "2026-01-01",
  notes: "Valorisation globale titres et liquidités",
};

test("expose le libellé Compte-titres", () => {
  assert.match(
    accountUtilsSource,
    /securities_account:\s*"Compte-titres"/,
  );
});

test("accepte securities_account dans le schéma canonique", () => {
  const parsed = financialAccountSchema.safeParse(validAccountInput);
  assert.equal(parsed.success, true);
  assert.equal(parsed.data?.accountType, "securities_account");
});

test("préserve tous les types de comptes existants", () => {
  assert.deepEqual(financialAccountTypes, [
    "checking",
    "livret_a",
    "ldds",
    "csl",
    "lep",
    "pel",
    "term_account",
    "life_insurance",
    "other_investment",
    "securities_account",
  ]);
});

test("classe securities_account comme compte à valorisation", () => {
  assert.match(
    accountUtilsSource,
    /type === "securities_account"/,
  );
});

test("utilise la dernière valorisation globale du compte-titres", () => {
  const valuations = [
    { id: "older", valuation_date: "2026-03-31", value: 1100 },
    { id: "latest", valuation_date: "2026-06-30", value: 1250 },
  ];
  assert.deepEqual(getCurrentValuationValue(1000, valuations), {
    value: 1250,
    valuation: valuations[1],
  });
});

test("revient au solde initial sans valorisation", () => {
  assert.deepEqual(getCurrentValuationValue(1000, []), {
    value: 1000,
    valuation: null,
  });
});

test("reste compatible avec le fallback VAL-01 après suppression", () => {
  const valuations = [
    { id: "previous", valuation_date: "2026-03-31", value: 1100 },
    { id: "deleted", valuation_date: "2026-06-30", value: 1250 },
  ];
  const remaining = valuations.filter((item) => item.id !== "deleted");
  assert.equal(getCurrentValuationValue(1000, remaining).value, 1100);
  assert.equal(getCurrentValuationValue(1000, []).value, 1000);
});

test("inclut le compte-titres valorisé dans le patrimoine sans modèle de positions", () => {
  assert.match(
    accountUtilsSource,
    /activeAccounts\.reduce\(\(total, account\) => total \+ getCurrentAccountValue/,
  );
  assert.doesNotMatch(
    accountUtilsSource,
    /position|security|isin|quantity|market_price/i,
  );
});

test("conserve l'ajustement net des virements postérieurs à la valorisation", () => {
  assert.match(
    accountUtilsSource,
    /if \(placementLeg\.transaction_date <= baselineDate\) continue;/,
  );
  assert.match(
    accountUtilsSource,
    /placementLeg\.transaction_type === "transfer_in" \? placementLeg\.amount : -placementLeg\.amount/,
  );
  assert.match(accountUtilsSource, /return displayedValue \+ placementTransferAdjustment;/);
});

test("autorise le compte-titres comme source et destination d'un virement structuré", () => {
  assert.match(
    transactionFormSource,
    /name="sourceAccountId"[^\n]+accounts=\{activeAccounts\}/,
  );
  assert.match(
    transactionFormSource,
    /name="destinationAccountId"[^\n]+accounts=\{activeAccounts\}/,
  );
});

test("classe uniquement le transfert entrant vers compte-titres en DEP-8-01", () => {
  assert.equal(resolveTransferOfficialCodeForFutureReport({
    transactionType: "transfer_in",
    accountType: "securities_account",
  }), "DEP-8-01");
  assert.equal(resolveTransferOfficialCodeForFutureReport({
    transactionType: "transfer_out",
    accountType: "securities_account",
  }), null);
});

test("exclut le compte-titres des recettes et dépenses ordinaires", () => {
  assert.match(
    transactionFormSource,
    /transactionalAccounts = activeAccounts\.filter\(\(account\) => !isValuationAccount\(account\.account_type\)\)/,
  );
  assert.match(
    transactionServiceSource,
    /if \(isValuationAccount\(account\.account_type\)\) throw new Error\("Les recettes et dépenses nécessitent un compte transactionnel\."\)/,
  );
});

test("calcule les valeurs d'ouverture et de clôture comme les autres placements", () => {
  assert.match(reportCalculationsSource, /if \(isValuationAccount\(account\.account_type\)\)/);
  assert.match(reportCalculationsSource, /value\.valuation_date <= date/);
  assert.match(reportCalculationsSource, /const startBalance = selection\.presentAtPeriodStart \? before\(start\) : null/);
  assert.match(reportCalculationsSource, /const endBalance = before\(endDate\)/);
  assert.match(reportCalculationsSource, /income: 0/);
  assert.match(reportCalculationsSource, /expense: 0/);
});

test("inclut le compte-titres dans les placements du compte de gestion", () => {
  assert.match(
    reportServicesSource,
    /account\.account_type === "securities_account"/,
  );
});

test("fige le libellé et les valeurs sans changer le format du snapshot", () => {
  assert.match(previewModelSource, /type: financialAccountLabels\[account\.account_type\]/);
  assert.match(previewModelSource, /startValue: situation\?\.startBalance \?\? null/);
  assert.match(previewModelSource, /endValue: situation\?\.endBalance \?\? null/);
  assert.match(snapshotSource, /type: z\.string\(\)/);
  assert.doesNotMatch(snapshotSource, /securities_account|security|position/i);
});

test("préserve la lecture des rapports figés depuis preview_snapshot", () => {
  assert.match(reportServicesSource, /document\?\.preview_snapshot/);
  assert.match(reportServicesSource, /parseManagementReportSnapshot\(document\.preview_snapshot\)/);
});
