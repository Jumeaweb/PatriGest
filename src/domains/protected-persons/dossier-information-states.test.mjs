import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  getDossierAddressStates,
  getDossierAssetActionLabel,
  getDossierDebtState,
  getDossierPropertyState,
} from "./dossier-information-states.ts";

const blankAddress = {
  address_line1: null, address_line2: null, postal_code: null, city: null, country: "France",
  residence_address_line1: null, residence_address_line2: null, residence_postal_code: null, residence_city: null, residence_country: "France",
};

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("domicile et résidence restent non renseignés même si seul le pays est prérempli", () => {
  assert.deepEqual(getDossierAddressStates(blankAddress), {
    domicile: "Non renseigné", residence: "Non renseigné",
  });
});

test("une résidence connue sans domicile ne devient jamais identique au domicile", () => {
  assert.deepEqual(getDossierAddressStates({ ...blankAddress, residence_address_line1: "8 rue des Fleurs", residence_city: "Tours" }), {
    domicile: "Non renseigné", residence: "8 rue des Fleurs, Tours, France",
  });
});

test("l'ancienne indication identique au domicile reste réservée au domicile renseigné", () => {
  assert.deepEqual(getDossierAddressStates({ ...blankAddress, address_line1: "3 rue du Parc", postal_code: "37000", city: "Tours" }), {
    domicile: "3 rue du Parc, 37000 Tours, France", residence: "Identique au domicile",
  });
});

test("une résidence distincte renseignée apparaît avec le domicile", () => {
  const states = getDossierAddressStates({ ...blankAddress, address_line1: "3 rue du Parc", residence_address_line1: "8 rue des Fleurs" });
  assert.equal(states.domicile, "3 rue du Parc, France");
  assert.equal(states.residence, "8 rue des Fleurs, France");
});

test("immobilier vide : non renseigné et aucune valeur prétendue manquante", () => {
  assert.deepEqual(getDossierPropertyState([]), { label: "Non renseigné", knownValue: null, missingValues: 0 });
});

test("un bien connu à zéro et un bien sans valeur restent distingués", () => {
  assert.deepEqual(getDossierPropertyState([{ estimated_value: 0 }, { estimated_value: null }]), {
    label: "2 biens renseignés", knownValue: 0, missingValues: 1,
  });
  assert.deepEqual(getDossierPropertyState([{ estimated_value: null }]), {
    label: "1 bien renseigné", knownValue: null, missingValues: 1,
  });
});

test("dettes vides : non renseigné, et non aucune dette active", () => {
  assert.deepEqual(getDossierDebtState([]), { label: "Non renseigné", knownBalance: null, missingBalances: 0 });
});

test("toutes les dettes soldées : aucune dette active est établi", () => {
  assert.deepEqual(getDossierDebtState([{ status: "settled", current_balance: 50 }]), {
    label: "Aucune dette active", knownBalance: null, missingBalances: 0,
  });
});

test("dettes actives : solde zéro connu distinct des soldes non renseignés", () => {
  assert.deepEqual(getDossierDebtState([
    { status: "active", current_balance: 0 },
    { status: "active", current_balance: null },
    { status: "settled", current_balance: 500 },
  ]), { label: "2 dettes actives", knownBalance: 0, missingBalances: 1 });
});

test("owner/manager voient l'action de renseignement, read_only ne peut que consulter", () => {
  for (const area of ["properties", "debts"]) {
    assert.match(getDossierAssetActionLabel(area, 0, true), /^Renseigner/);
    assert.match(getDossierAssetActionLabel(area, 2, true), /^Gérer/);
    assert.match(getDossierAssetActionLabel(area, 0, false), /^Consulter/);
  }
});

test("la page réutilise les labels d'identité du helper existant sans nouvelle requête", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/page.tsx");
  assert.match(page, /personCompleteness\.missingFields\.map\(\(field\) => field\.label\)/);
  assert.match(page, /getProtectedPersonRegulatoryCompleteness\(person\)/);
  assert.match(page, /getDossierAddressStates\(person\)/);
  assert.match(page, /accounts\.length \? formatCurrency\(currentPatrimony\) : "Non renseigné"/);
});

test("la fiche conserve routes, permissions et accès aux exercices", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/page.tsx");
  assert.match(page, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(page, /getDossierAssetActionLabel\("properties", properties\.length, canManage\)/);
  assert.match(page, /getDossierAssetActionLabel\("debts", debts\.length, canManage\)/);
  assert.match(page, /href=\{`\/dossiers\/\$\{protectedPersonId\}\/patrimoine-immobilier`\}/);
  assert.match(page, /href=\{`\/dossiers\/\$\{protectedPersonId\}\/dettes`\}/);
  assert.match(page, /href=\{`\/dossiers\/\$\{protectedPersonId\}\/exercices`\}/);
  assert.match(page, /person\.protectionMeasures\.length \? "Aucune mesure active" : "Non renseigné"/);
  assert.match(page, /person\.managementPeriods\.length \? "Aucun exercice ouvert" : "Non renseigné"/);
});
