import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("les cartes immobilières affichent un bouton Historique sans détourner les actions", () => {
  const manager = source("./components/property-manager.tsx");

  assert.match(manager, /import Link from "next\/link"/);
  assert.match(manager, /href=`\/dossiers\/\$\{personId\}\/patrimoine-immobilier\/\$\{item\.id\}`/);
  assert.match(manager, /<article onClick=\{open\}/);
  assert.doesNotMatch(manager, /<article role="link"/);
  assert.match(manager, /<Link className="button button-secondary gap-1 px-3" href=\{href\}><History size=\{13\}\/>Historique<\/Link>/);
  assert.doesNotMatch(manager, /Voir la fiche/);
  assert.match(manager, /onClick=\{e=>e\.stopPropagation\(\)\}/);
  assert.match(manager, /onClick=\{\(\)=>setEdit\(true\)\}/);
  assert.match(manager, /onClick=\{\(\)=>setEvent\(true\)\}/);
});

test("les cartes de dettes affichent un bouton Historique et réutilisent leurs actions", () => {
  const manager = source("./components/debt-manager.tsx");

  assert.match(manager, /import Link from "next\/link"/);
  assert.match(manager, /href=`\/dossiers\/\$\{personId\}\/dettes\/\$\{item\.id\}`/);
  assert.match(manager, /<article onClick=\{open\}/);
  assert.doesNotMatch(manager, /<article role="link"/);
  assert.match(manager, /<Link className="button button-secondary gap-1 px-3" href=\{href\}><History size=\{13\}\/>Historique<\/Link>/);
  assert.doesNotMatch(manager, /Voir la fiche/);
  assert.match(manager, /<DebtActions personId=\{personId\} item=\{item\} compact\/>/);
  assert.match(manager, /export function DebtActions/);
  assert.match(manager, /className="contents" onClick=\{event=>event\.stopPropagation\(\)\}/);
  assert.match(manager, /className=\{compact\?"contents":"relative z-10 mt-3 flex flex-wrap gap-1.5"\}/);
  assert.match(manager, /onClick=\{\(\)=>setEdit\(true\)\}/);
  assert.match(manager, /onClick=\{\(\)=>setBalance\(true\)\}/);
});

test("le service d'une dette cloisonne le dossier et ordonne tout l'historique", () => {
  const services = source("./services.ts");
  const start = services.indexOf("export async function getDebt(");
  const service = services.slice(start);

  assert.ok(start >= 0);
  assert.match(service, /from\("debts"\)\.select\("\*"\)\.eq\("id",debtId\)\.eq\("protected_person_id",personId\)\.maybeSingle\(\)/);
  assert.match(service, /from\("debt_balances"\)\.select\("\*"\)\.eq\("debt_id",debtId\)/);
  assert.match(service, /order\("balance_date",\{ascending:false\}\)/);
  assert.match(service, /order\("created_at",\{ascending:false\}\)/);
  assert.match(service, /order\("id",\{ascending:false\}\)/);
  assert.match(service, /Impossible de charger l’historique de la dette/);
});

test("la fiche dette valide ses identifiants, ses droits et ses états de lecture seule", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");

  assert.match(page, /params: Promise<\{ protectedPersonId: string; debtId: string \}>/);
  assert.match(page, /\[protectedPersonId, debtId\]\.every/);
  assert.match(page, /getProtectedPerson\(protectedPersonId\)/);
  assert.match(page, /getDebt\(protectedPersonId, debtId\)/);
  assert.match(page, /if \(!person \|\| !debt\) notFound\(\)/);
  assert.match(page, /person\.accessRole !== "read_only" && person\.status === "active"/);
  assert.match(page, /Dossier archivé — consultation uniquement/);
  assert.match(page, /\{canManage && <DebtActions/);
});

test("la fiche dette présente les données métier et l'historique complet", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/dettes/[debtId]/page.tsx");

  for (const label of [
    "Statut",
    "Capital restant dû",
    "Montant initial",
    "Date de début",
    "Durée initiale",
    "Durée restante",
    "Mensualité",
    "Taux",
    "Notes",
    "Historique du capital restant dû",
    "Situation courante",
    "Aucune situation de dette enregistrée.",
  ]) assert.match(page, new RegExp(label));

  assert.match(page, /debt\.balances\.map\(\(balance\)/);
  assert.match(page, /currentBalanceId = debt\.balances\.find/);
  assert.match(page, /formatCurrency\(balance\.remaining_balance\)/);
  assert.match(page, /balance\.remaining_duration_months !== null/);
  assert.doesNotMatch(page, /supprimer/i);
});

test("les écritures réactualisent aussi la fiche dette et les dossiers archivés restent consultables", () => {
  const actions = source("./actions.ts");
  const debtList = source("../../app/dossiers/[protectedPersonId]/dettes/page.tsx");
  const propertyList = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/page.tsx");
  const propertyDetail = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/[propertyId]/page.tsx");

  assert.match(actions, /debtId\?:string/);
  assert.match(actions, /revalidatePath\(`\/dossiers\/\$\{id\}\/dettes\/\$\{debtId\}`\)/);
  assert.match(debtList, /person\.accessRole !== "read_only" && person\.status === "active"/);
  assert.match(propertyList, /person\.accessRole !== "read_only" && person\.status === "active"/);
  assert.match(propertyDetail, /propertyIsArchived \|\| person\.status === "archived"/);
  assert.match(propertyDetail, /const canManage = person\.accessRole !== "read_only" && person\.status === "active"/);
  assert.equal((propertyDetail.match(/!isArchived && person\.accessRole !== "read_only"/g) ?? []).length, 3);
});
