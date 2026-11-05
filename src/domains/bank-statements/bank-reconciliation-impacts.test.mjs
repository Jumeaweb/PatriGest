import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("le service lit et reconnaît les impacts uniquement via les RPC dédiées", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /rpc\("list_transaction_banking_impacts_for_reconciliation"/);
  assert.match(service, /rpc\("acknowledge_transaction_banking_impact"/);
  assert.doesNotMatch(service, /from\("transaction_banking_impact_acknowledgements"\)\.(?:insert|update|delete)/);
});

test("l’API valide UUID, droit de gestion et justification", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/rapprochement/route.ts");
  assert.match(route, /export async function PUT/);
  assert.match(route, /z\.uuid\(\)\.safeParse\(body\.impactId\)/);
  assert.match(route, /accessRole === "read_only" \|\| context\.person\.archived_at/);
  assert.match(route, /acknowledgeTransactionBankingImpact/);
});

test("l’interface n’acquitte rien automatiquement et explique tous les blocages de validation", () => {
  const component = source("./components/bank-reconciliation-manager.tsx");
  assert.match(component, /Impacts bancaires à vérifier/);
  assert.match(component, /Reconnaître l’impact/);
  assert.match(component, /justification:/);
  assert.match(component, /validationBlockedByImpacts = pendingImpacts\.length > 0/);
  assert.match(component, /validationBlockedByDifference = validationDifference !== null && Math\.round\(validationDifference \* 100\) !== 0/);
  assert.match(component, /validationBlocked = validationBlockedByImpacts \|\| validationBlockedByDifference/);
  assert.match(component, /disabled=\{busy \|\| validationBlocked\}/);
  assert.match(component, /cursor-not-allowed bg-slate-200 text-slate-500 shadow-none/);
  assert.match(component, /aria-describedby=\{validationHelpIds\}/);
  assert.match(component, /Un écart de \{euro\(Math\.abs\(validationDifference\)\)\} subsiste entre le relevé bancaire et PatriGest/);
  assert.match(component, /Un écart résiduel de \{euro\(Math\.abs\(validationDifference\)\)\} subsiste/);
  assert.match(component, /Reconnaissez et justifiez tous les impacts bancaires avant de valider le rapprochement\./);
  assert.doesNotMatch(component, /useEffect[\s\S]{0,300}acknowledgeImpact/);
});

test("le service traduit les deux refus d’écart sans exposer PostgreSQL", () => {
  const service = source("./reconciliation-service.ts");
  assert.match(service, /includes\("écart simple"\)/);
  assert.match(service, /L’écart entre le relevé bancaire et PatriGest doit être nul avant la validation\./);
  assert.match(service, /includes\("écart résiduel"\)/);
  assert.match(service, /L’écart résiduel doit être nul avant la validation\./);
});
