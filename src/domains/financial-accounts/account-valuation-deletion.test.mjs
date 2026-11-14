import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { deleteAccountValuationRow } from "./services/account-valuation-delete.ts";
import { getCurrentValuationValue } from "./utils/account-valuation-utils.ts";

function deletionClient(result) {
  const calls = [];
  const query = {
    delete() {
      calls.push(["delete"]);
      return this;
    },
    eq(column, value) {
      calls.push(["eq", column, value]);
      return this;
    },
    select(columns) {
      calls.push(["select", columns]);
      return this;
    },
    async single() {
      calls.push(["single"]);
      return result;
    },
  };
  return {
    calls,
    client: {
      from(table) {
        calls.push(["from", table]);
        return query;
      },
    },
  };
}

test("supprime une valorisation existante avec les deux filtres et un retour id", async () => {
  const { client, calls } = deletionClient({
    data: { id: "valuation-id" },
    error: null,
  });

  await deleteAccountValuationRow(client, "account-id", "valuation-id");

  assert.deepEqual(calls, [
    ["from", "account_valuations"],
    ["delete"],
    ["eq", "id", "valuation-id"],
    ["eq", "financial_account_id", "account-id"],
    ["select", "id"],
    ["single"],
  ]);
});

test("rejette explicitement une suppression à zéro ligne", async () => {
  const { client } = deletionClient({
    data: null,
    error: { code: "PGRST116" },
  });

  await assert.rejects(
    deleteAccountValuationRow(client, "account-id", "missing-id"),
    /Impossible de supprimer la valorisation/,
  );
});

test("explique la protection d'une valorisation déjà rapprochée", async () => {
  const { client } = deletionClient({
    data: null,
    error: { code: "55000", message: "Cette valorisation est utilisée par un rapprochement validé" },
  });

  await assert.rejects(
    deleteAccountValuationRow(client, "account-id", "protected-id"),
    /rapprochement validé et ne peut plus être supprimée/,
  );
});

test("la valorisation précédente devient naturellement la valeur courante", () => {
  const valuations = [
    { id: "old", valuation_date: "2025-12-31", value: 120 },
    { id: "latest", valuation_date: "2026-12-31", value: 150 },
  ];
  const remaining = valuations.filter((valuation) => valuation.id !== "latest");

  assert.deepEqual(getCurrentValuationValue(90, remaining), {
    value: 120,
    valuation: remaining[0],
  });
});

test("le solde initial s'applique lorsqu'il ne reste aucune valorisation", () => {
  assert.deepEqual(getCurrentValuationValue(90, []), {
    value: 90,
    valuation: null,
  });
});

test("le service impose la gestion du compte et délègue le DELETE strict", () => {
  const source = readFileSync(
    new URL("./services/financial-account-service.ts", import.meta.url),
    "utf8",
  );
  const start = source.indexOf("export async function deleteAccountValuation(");
  const deletionSource = source.slice(start);

  assert.ok(start >= 0);
  assert.match(deletionSource, /requireManagedAccount\(accountId\)/);
  assert.match(
    deletionSource,
    /deleteAccountValuationRow\(supabase, accountId, valuationId\)/,
  );
});

test("les snapshots figés copient les valeurs sans référencer la valorisation", () => {
  const previewSource = readFileSync(
    new URL("../management-reports/preview-model.ts", import.meta.url),
    "utf8",
  );
  const snapshotSource = readFileSync(
    new URL("../management-reports/snapshot.ts", import.meta.url),
    "utf8",
  );

  assert.match(previewSource, /startValue: situation\?\.startBalance \?\? null/);
  assert.match(previewSource, /endValue: situation\?\.endBalance \?\? null/);
  assert.doesNotMatch(snapshotSource, /valuationId|valuation_id/);
});
