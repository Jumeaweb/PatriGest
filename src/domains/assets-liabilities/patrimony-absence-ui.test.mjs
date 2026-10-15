import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const component = source("./components/patrimony-absence-confirmation.tsx");
const propertyPage = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/page.tsx");
const debtPage = source("../../app/dossiers/[protectedPersonId]/dettes/page.tsx");

test("les deux pages chargent explicitement les confirmations avec leurs données métier", () => {
  assert.match(propertyPage, /Promise\.all\([\s\S]*getProperties\(protectedPersonId\)[\s\S]*getArchivedProperties\(protectedPersonId\)[\s\S]*getPatrimonyAbsenceConfirmations\(protectedPersonId\)/);
  assert.match(debtPage, /Promise\.all\([\s\S]*getDebts\(protectedPersonId\)[\s\S]*getPatrimonyAbsenceConfirmations\(protectedPersonId\)/);
  assert.match(propertyPage, /confirmation=\{absenceConfirmations\.realEstate\}/);
  assert.match(debtPage, /confirmation=\{absenceConfirmations\.activeDebt\}/);
});

test("un bien actif ou une dette active masque le contrôle d’absence", () => {
  assert.match(propertyPage, /hasActiveProperty = items\.some\(\(item\) => item\.status === "active"\)/);
  assert.match(propertyPage, /!hasActiveProperty && <PatrimonyAbsenceConfirmationControl/);
  assert.match(debtPage, /hasActiveDebt = items\.some\(\(item\) => item\.status === "active"\)/);
  assert.match(debtPage, /!hasActiveDebt && <PatrimonyAbsenceConfirmationControl/);
});

test("les biens cédés ou archivés et les dettes soldées restent consultables sans compter comme actifs", () => {
  assert.match(propertyPage, /<PropertyManager personId=\{protectedPersonId\} items=\{items\}/);
  assert.match(propertyPage, /Biens archivés/);
  assert.match(propertyPage, /archivedItems\.length/);
  assert.match(debtPage, /<DebtManager personId=\{protectedPersonId\} items=\{items\}/);
  assert.doesNotMatch(propertyPage, /status !== "disposed"/);
  assert.doesNotMatch(debtPage, /status !== "settled"/);
});

test("le contrôle présente l’absence non confirmée et les confirmations datées", () => {
  assert.match(component, /Je confirme qu’aucun bien immobilier n’est actuellement détenu\./);
  assert.match(component, /Je confirme qu’aucune dette n’est actuellement en cours\./);
  assert.match(component, /Absence de bien immobilier confirmée/);
  assert.match(component, /Absence de dette active confirmée/);
  assert.match(component, /dateFormatter\.format\(new Date\(confirmation\.confirmed_at\)\)/);
  assert.match(component, /Cette absence n’a pas encore été confirmée\./);
});

test("la lecture seule conserve l’état visible mais masque toutes les mutations", () => {
  assert.match(propertyPage, /canManage = person\.accessRole !== "read_only"/);
  assert.match(debtPage, /canManage = person\.accessRole !== "read_only"/);
  assert.match(component, /\{canManage && <button/);
  assert.match(component, /confirmation\.confirmed_at/);
});

test("la confirmation et le retrait réutilisent exclusivement les quatre actions du lot 5D", () => {
  assert.match(component, /confirmRealEstateAbsenceAction/);
  assert.match(component, /withdrawRealEstateAbsenceConfirmationAction/);
  assert.match(component, /confirmActiveDebtAbsenceAction/);
  assert.match(component, /withdrawActiveDebtAbsenceConfirmationAction/);
  assert.doesNotMatch(component, /createClient|\.from\(|\.rpc\(/);
  assert.match(component, /router\.refresh\(\)/);
});

test("le retrait exige une confirmation explicite et les erreurs restent visibles dans le dialogue", () => {
  assert.match(component, /Retirer cette confirmation \?/);
  assert.match(component, /Confirmer le retrait/);
  assert.match(component, /requireExplicitClose=\{pending\}/);
  assert.match(component, /result\.status === "success"/);
  assert.match(component, /<FormMessage state=\{state\} \/><\/AppConfirmDialog>/);
  assert.match(component, /setState\(result\)/);
});

test("la carte et le dialogue conservent une disposition utilisable sur mobile et ordinateur", () => {
  assert.match(component, /flex flex-col gap-3[^"]+sm:flex-row sm:items-center sm:justify-between/);
  assert.match(component, /w-full[^"]+sm:w-auto/);
  assert.match(component, /self-start[^"]+sm:self-center/);
  assert.match(component, /type="button"/);
  assert.match(component, /aria-label="Confirmation patrimoniale"/);
  assert.match(component, /AppConfirmDialog/);
});
