import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE,
  getAccountDossierCapacityPresentation,
  shouldLoadOwnedDossierCapacity,
} from "./account-dossier-capacity.ts";

test("réserve le compteur au propriétaire autonome", () => {
  assert.equal(shouldLoadOwnedDossierCapacity({ accountMode: "autonomous", isPlatformAdmin: false }), true);
  assert.equal(shouldLoadOwnedDossierCapacity({ accountMode: "collaborator", isPlatformAdmin: false }), false);
  assert.equal(shouldLoadOwnedDossierCapacity({ accountMode: null, isPlatformAdmin: true }), false);
  assert.equal(shouldLoadOwnedDossierCapacity({ accountMode: "autonomous", isPlatformAdmin: true }), false);
  assert.equal(shouldLoadOwnedDossierCapacity({ accountMode: null, isPlatformAdmin: false }), false);
});

test("présente une capacité illimitée sans plafond ni places fictives", () => {
  assert.deepEqual(getAccountDossierCapacityPresentation({
    state: "unlimited",
    unlimited: true,
    activeDossierLimit: null,
    activeDossierCount: 0,
    remainingDossierCount: null,
    exceededBy: 0,
  }), {
    activeDossiersLabel: "Dossiers actifs : 0",
    capacityLabel: "Capacité : Illimitée",
    remainingPlacesLabel: null,
    notice: null,
    exceededLabel: null,
  });
});

test("présente une capacité limitée et ses places disponibles", () => {
  const presentation = getAccountDossierCapacityPresentation({
    state: "available",
    unlimited: false,
    activeDossierLimit: 5,
    activeDossierCount: 3,
    remainingDossierCount: 2,
    exceededBy: 0,
  });
  assert.equal(presentation.activeDossiersLabel, "Dossiers actifs : 3");
  assert.equal(presentation.capacityLabel, "Capacité : 5 dossiers");
  assert.equal(presentation.remainingPlacesLabel, "Places restantes : 2");
  assert.equal(presentation.notice, null);
  assert.equal(presentation.exceededLabel, null);
});

test("signale discrètement un plafond atteint", () => {
  const presentation = getAccountDossierCapacityPresentation({
    state: "reached",
    unlimited: false,
    activeDossierLimit: 5,
    activeDossierCount: 5,
    remainingDossierCount: 0,
    exceededBy: 0,
  });
  assert.equal(presentation.activeDossiersLabel, "Dossiers actifs : 5");
  assert.equal(presentation.capacityLabel, "Capacité : 5 dossiers");
  assert.equal(presentation.remainingPlacesLabel, "Places restantes : 0");
  assert.equal(presentation.notice, "Le plafond de dossiers actifs est atteint.");
});

test("présente le dépassement comme un état de capacité", () => {
  const presentation = getAccountDossierCapacityPresentation({
    state: "exceeded",
    unlimited: false,
    activeDossierLimit: 5,
    activeDossierCount: 8,
    remainingDossierCount: 0,
    exceededBy: 3,
  });
  assert.equal(presentation.activeDossiersLabel, "Dossiers actifs : 8");
  assert.equal(presentation.capacityLabel, "Capacité : 5 dossiers");
  assert.equal(presentation.remainingPlacesLabel, "Places restantes : 0");
  assert.equal(presentation.exceededLabel, "Dépassement : 3 dossiers");
});

test("isole l’erreur de capacité sans inventer de valeur de secours", () => {
  const component = readFileSync(new URL("./components/account-dossier-capacity.tsx", import.meta.url), "utf8");
  assert.equal(
    ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE,
    "La capacité de vos dossiers est momentanément indisponible. Veuillez réessayer ultérieurement.",
  );
  assert.match(component, /result\.status === "error"/);
  assert.match(component, /ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE/);
  assert.doesNotMatch(component, /activeDossierLimit\s*\?\?\s*2|unlimited:\s*true/);
});

test("n’appelle la RPC que dans l’onglet Abonnement pour un mode éligible", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  assert.match(page, /current === "subscription" \? getPrivateAccessContext\(\) : Promise\.resolve\(null\)/);
  assert.match(page, /if \(accessContext && shouldLoadOwnedDossierCapacity\(accessContext\)\)/);
  assert.match(page, /await getOwnedDossierCapacity\(\)/);
  assert.doesNotMatch(page, /from\("account_subscriptions"\)|service_role|ownerId/);
});

test("conserve les cinq onglets et masque tout compteur personnel aux modes non éligibles", () => {
  const navigation = readFileSync(new URL("./account-navigation.ts", import.meta.url), "utf8");
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  for (const label of ["Profil", "Abonnement", "Factures", "Résiliation", "Mes données"]) {
    assert.match(navigation, new RegExp(`label: "${label}"`));
  }
  assert.match(page, /let dossierCapacity: AccountDossierCapacityResult \| null = null/);
  assert.match(page, /<AccountSubscriptionView dossierCapacity=\{dossierCapacity\}/);
});
