import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("le service conserve la révision présentée et appelle uniquement la RPC de clôture", () => {
  const services = source("./services.ts");
  const start = services.indexOf("export async function settleDebt(");
  const settlement = services.slice(start);

  assert.ok(start >= 0);
  assert.match(settlement, /getAuthenticatedUser\(\)/);
  assert.match(settlement, /rpc\("can_manage_protected_person",\{person_id:personId\}\)/);
  assert.match(settlement, /select\("id,revision,status,settled_at,start_date,current_balance"\)/);
  assert.match(settlement, /debtResult\.data\.revision!==expectedRevision/);
  assert.match(settlement, /DebtSettlementError\("stale_revision"\)/);
  assert.match(settlement, /rpc\("settle_debt",\{p_protected_person_id:personId,p_debt_id:debtId,p_expected_revision:expectedRevision/);
  assert.doesNotMatch(settlement, /p_expected_revision:debtResult\.data\.revision/);
});

test("le service refuse les états incompatibles avant la RPC sans remplacer PostgreSQL", () => {
  const services = source("./services.ts");
  const settlement = services.slice(services.indexOf("export async function settleDebt("));

  assert.match(settlement, /personResult\.data\.status==="archived"/);
  assert.match(settlement, /DebtSettlementError\("archived_dossier"\)/);
  assert.match(settlement, /debtResult\.data\.status!=="active"\|\|debtResult\.data\.settled_at!==null/);
  assert.match(settlement, /DebtSettlementError\("already_settled"\)/);
  assert.match(settlement, /debtResult\.data\.start_date===null/);
  assert.match(settlement, /DebtSettlementError\("missing_start_date"\)/);
  assert.match(settlement, /debtResult\.data\.current_balance===null/);
  assert.match(settlement, /DebtSettlementError\("missing_zero_balance"\)/);
  assert.match(settlement, /debtResult\.data\.current_balance!==0/);
  assert.match(settlement, /DebtSettlementError\("positive_balance"\)/);
});

test("les erreurs PostgreSQL sont classées sans exposer leurs détails", () => {
  const services = source("./services.ts");
  const actions = source("./actions.ts");
  const settlementService = services.slice(services.indexOf("export async function settleDebt("));
  const settlementAction = actions.slice(actions.indexOf("export async function settleDebtAction("), actions.indexOf("export async function setPatrimonyAbsenceConfirmationAction"));

  for (const code of ["42501", "P0002", "40001", "P4R01", "23514"]) assert.match(settlementService, new RegExp(`error\\.code===\"${code}\"`));
  for (const errorCode of ["forbidden", "not_found", "stale_revision", "already_settled", "missing_zero_balance", "later_balance", "missing_start_date", "invalid_date", "closed_period", "archived_dossier", "inconsistent", "technical"]) assert.match(settlementService, new RegExp(`DebtSettlementError\\(\"${errorCode}\"\\)`));
  assert.doesNotMatch(settlementAction, /error\.message/);
  assert.match(settlementAction, /Cette dette a changé depuis l’ouverture de la fenêtre/);
  assert.match(settlementAction, /Cette date appartient à un exercice clôturé/);
  assert.match(settlementAction, /Renseignez d’abord la date de début avec « Modifier la dette »/);
});

test("l’action valide les identifiants, la révision, la date et le motif", () => {
  const actions = source("./actions.ts");
  const settlement = actions.slice(actions.indexOf("export async function settleDebtAction("), actions.indexOf("export async function setPatrimonyAbsenceConfirmationAction"));

  assert.match(settlement, /ids\(personId,debtId\)/);
  assert.match(settlement, /Number\.isSafeInteger\(expectedRevision\)/);
  assert.match(settlement, /debtSettlementSchema\.safeParse\(\{settledAt:get\(f,"settledAt"\),reason:get\(f,"reason"\)\}\)/);
  assert.match(settlement, /settleDebt\(personId,debtId,expectedRevision,parsed\.data\)/);
  assert.match(settlement, /refresh\(personId,undefined,debtId\)/);
  assert.ok(settlement.indexOf("await settleDebt") < settlement.indexOf("refresh(personId,undefined,debtId)"));
});

test("la fenêtre présente la dette, le CRD, la date et le motif obligatoire", () => {
  const manager = source("./components/debt-manager.tsx");

  assert.match(manager, /Solder la dette/);
  assert.match(manager, /subject=\{item\.designation\}/);
  assert.match(manager, /Capital restant dû courant/);
  assert.match(manager, /name="settledAt"/);
  assert.match(manager, /name="reason"/);
  assert.match(manager, /maxLength=\{2000\} required/);
  assert.match(manager, /Cette clôture est une action explicite/);
  assert.match(manager, /Confirmer la clôture/);
  assert.match(manager, /disabled=\{pending\|\|Boolean\(validationMessage\)\}/);
});

test("la fenêtre explique chaque précondition vérifiable localement", () => {
  const manager = source("./components/debt-manager.tsx");

  assert.match(manager, /item\.current_balance===null/);
  assert.match(manager, /Le capital restant dû doit être égal à 0 €/);
  assert.match(manager, /!item\.start_date/);
  assert.match(manager, /Modifier la dette/);
  assert.match(manager, /settledAt<item\.start_date\|\|settledAt>today/);
  assert.match(manager, /balance\.balance_date===settledAt&&balance\.remaining_balance===0/);
  assert.match(manager, /balance\.balance_date>settledAt/);
});

test("le bouton et les mutations incompatibles sont réservés aux dettes actives modifiables", () => {
  const manager = source("./components/debt-manager.tsx");
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");

  assert.match(manager, /if\(item\.status!=="active"\)return null/);
  assert.match(manager, /showSettlement&&<button[^>]*>.*Solder la dette/s);
  assert.match(page, /person\.accessRole !== "read_only" && person\.status === "active"/);
  assert.match(page, /\{canManage && <DebtActions personId=\{protectedPersonId\} item=\{debt\} showSettlement \/>\}/);
  assert.doesNotMatch(manager, /name="status"/);
  assert.equal((manager.match(/name="settledAt"/g) ?? []).length, 1);
});

test("la fiche recharge et affiche l’historique audité après clôture", () => {
  const services = source("./services.ts");
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");
  const actions = source("./actions.ts");

  assert.match(services, /from\("debt_status_changes"\)\.select\("\*"\)\.eq\("debt_id",debtId\)\.eq\("protected_person_id",personId\)/);
  assert.match(services, /Impossible de charger l’historique des statuts de la dette/);
  assert.match(page, /Historique du statut/);
  assert.match(page, /debt\.statusChanges\.map/);
  assert.match(page, /change\.changed_by_name/);
  assert.match(page, /change\.reason/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/dettes\/\$\{debtId\}`\)/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/tableau-de-bord`\)/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/comptes-de-gestion`\)/);
});
