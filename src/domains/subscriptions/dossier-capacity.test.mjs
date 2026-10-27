import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  DOSSIER_CAPACITY_ERROR_MESSAGES,
  DossierCapacityServiceError,
  classifyDossierCapacityMutationError,
  loadOwnedDossierCapacity,
  mapDossierCapacityRpcError,
  parseOwnedDossierCapacity,
} from "./dossier-capacity.ts";

const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

function limitedRow(limit, count) {
  return {
    unlimited: false,
    active_dossier_limit: limit,
    active_dossier_count: count,
    remaining_dossier_count: Math.max(limit - count, 0),
    exceeded_by: Math.max(count - limit, 0),
  };
}

function unlimitedRow(count = 0) {
  return {
    unlimited: true,
    active_dossier_limit: null,
    active_dossier_count: count,
    remaining_dossier_count: null,
    exceeded_by: 0,
  };
}

function gateway(result = { data: [limitedRow(5, 1)], error: null }) {
  return {
    async getOwnedCapacity() {
      return result;
    },
  };
}

async function expectServiceError(promise, code, message) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof DossierCapacityServiceError);
    assert.equal(error.code, code);
    if (message) assert.equal(error.message, message);
    return true;
  });
}

test("les capacités plafonnées 2, 5, 10 et personnalisées restent issues de PostgreSQL", () => {
  for (const [limit, count] of [[2, 1], [5, 2], [10, 4], [37, 12]]) {
    const capacity = parseOwnedDossierCapacity([limitedRow(limit, count)]);
    assert.deepEqual(capacity, {
      state: "available",
      unlimited: false,
      activeDossierLimit: limit,
      activeDossierCount: count,
      remainingDossierCount: limit - count,
      exceededBy: 0,
    });
  }
});

test("zéro dossier actif est une capacité disponible et non une absence de compteur", () => {
  assert.deepEqual(parseOwnedDossierCapacity([limitedRow(2, 0)]), {
    state: "available",
    unlimited: false,
    activeDossierLimit: 2,
    activeDossierCount: 0,
    remainingDossierCount: 2,
    exceededBy: 0,
  });
});

test("un plafond atteint est distingué d’une capacité encore disponible", () => {
  assert.deepEqual(parseOwnedDossierCapacity([limitedRow(5, 5)]), {
    state: "reached",
    unlimited: false,
    activeDossierLimit: 5,
    activeDossierCount: 5,
    remainingDossierCount: 0,
    exceededBy: 0,
  });
});

test("un plafond dépassé conserve le dépassement sans place négative", () => {
  assert.deepEqual(parseOwnedDossierCapacity([limitedRow(5, 8)]), {
    state: "exceeded",
    unlimited: false,
    activeDossierLimit: 5,
    activeDossierCount: 8,
    remainingDossierCount: 0,
    exceededBy: 3,
  });
});

test("une capacité explicitement illimitée n’invente ni plafond ni places restantes", () => {
  assert.deepEqual(parseOwnedDossierCapacity([unlimitedRow(18)]), {
    state: "unlimited",
    unlimited: true,
    activeDossierLimit: null,
    activeDossierCount: 18,
    remainingDossierCount: null,
    exceededBy: 0,
  });
});

test("les réponses limitées incohérentes sont refusées", () => {
  assert.throws(() => parseOwnedDossierCapacity([{
    ...limitedRow(5, 2),
    remaining_dossier_count: 4,
  }]));
  assert.throws(() => parseOwnedDossierCapacity([{
    ...limitedRow(5, 8),
    exceeded_by: 2,
  }]));
  assert.throws(() => parseOwnedDossierCapacity([{
    ...limitedRow(5, 2),
    active_dossier_limit: null,
  }]));
});

test("les réponses illimitées incohérentes sont refusées", () => {
  assert.throws(() => parseOwnedDossierCapacity([{
    ...unlimitedRow(),
    active_dossier_limit: 5,
  }]));
  assert.throws(() => parseOwnedDossierCapacity([{
    ...unlimitedRow(),
    remaining_dossier_count: 5,
  }]));
  assert.throws(() => parseOwnedDossierCapacity([{
    ...unlimitedRow(),
    exceeded_by: 1,
  }]));
});

test("les valeurs négatives et décimales sont refusées", () => {
  for (const invalidRow of [
    { ...limitedRow(5, 1), active_dossier_limit: -1 },
    { ...limitedRow(5, 1), active_dossier_count: -1 },
    { ...limitedRow(5, 1), remaining_dossier_count: -1 },
    { ...limitedRow(5, 1), exceeded_by: -1 },
    { ...limitedRow(5, 1), active_dossier_limit: 2.5 },
    { ...limitedRow(5, 1), active_dossier_count: 1.5 },
  ]) {
    assert.throws(() => parseOwnedDossierCapacity([invalidRow]));
  }
});

test("les valeurs manquantes, réponses vides ou dupliquées sont refusées", () => {
  const missingValue = limitedRow(5, 1);
  delete missingValue.exceeded_by;
  assert.throws(() => parseOwnedDossierCapacity([missingValue]));
  assert.throws(() => parseOwnedDossierCapacity([]));
  assert.throws(() => parseOwnedDossierCapacity([
    limitedRow(5, 1),
    limitedRow(5, 1),
  ]));
  assert.throws(() => parseOwnedDossierCapacity(null));
});

test("les données commerciales ou d’identité supplémentaires sont refusées", () => {
  assert.throws(() => parseOwnedDossierCapacity([{
    ...limitedRow(5, 1),
    plan_key: "premium",
  }]));
  assert.throws(() => parseOwnedDossierCapacity([{
    ...limitedRow(5, 1),
    owner_id: "10000000-0000-4000-8000-000000000001",
  }]));
});

test("le chargeur appelle une passerelle sans identifiant utilisateur", async () => {
  let receivedArguments = null;
  const capacity = await loadOwnedDossierCapacity({
    async getOwnedCapacity(...args) {
      receivedArguments = args;
      return { data: [limitedRow(2, 1)], error: null };
    },
  });
  assert.deepEqual(receivedArguments, []);
  assert.equal(capacity.activeDossierLimit, 2);
});

test("les codes PostgreSQL connus sont traduits en erreurs applicatives stables", () => {
  const expected = [
    ["P4D01", "quota_reached"],
    ["P4D02", "subscription_missing"],
    ["P4D03", "configuration_unavailable"],
    ["42501", "access_denied"],
    ["PGRST202", "rpc_unavailable"],
    ["42883", "rpc_unavailable"],
    ["XX000", "technical"],
  ];
  for (const [postgresCode, applicationCode] of expected) {
    const mapped = mapDossierCapacityRpcError({
      code: postgresCode,
      message: "détail SQL interne et secret",
    });
    assert.equal(mapped.code, applicationCode);
    assert.equal(mapped.message, DOSSIER_CAPACITY_ERROR_MESSAGES[applicationCode]);
    assert.doesNotMatch(mapped.message, /SQL|secret|P4D|42501|PGRST|XX000/i);
  }
});

test("les mutations ne préservent que les quatre refus PostgreSQL attendus", () => {
  const expected = [
    ["P4D01", "quota_reached"],
    ["P4D02", "subscription_missing"],
    ["P4D03", "configuration_unavailable"],
    ["42501", "access_denied"],
  ];

  for (const [postgresCode, applicationCode] of expected) {
    const error = classifyDossierCapacityMutationError({
      code: postgresCode,
      message: "détail SQL interne avec jeton secret",
    });
    assert.ok(error instanceof DossierCapacityServiceError);
    assert.equal(error.code, applicationCode);
    assert.equal(error.message, DOSSIER_CAPACITY_ERROR_MESSAGES[applicationCode]);
    assert.doesNotMatch(error.message, /SQL|jeton|secret|P4D|42501/i);
  }
});

test("une erreur inconnue ou réseau n'est pas classée comme un refus de capacité", () => {
  assert.equal(classifyDossierCapacityMutationError({
    code: "XX000",
    message: "message PostgreSQL confidentiel",
  }), null);
  assert.equal(classifyDossierCapacityMutationError({
    message: "échec réseau avec données internes",
  }), null);
  assert.equal(classifyDossierCapacityMutationError(null), null);
});

test("les trois messages fonctionnels français restent explicites", () => {
  assert.equal(
    DOSSIER_CAPACITY_ERROR_MESSAGES.quota_reached,
    "Vous avez atteint le nombre maximal de dossiers actifs autorisé par votre abonnement.",
  );
  assert.equal(
    DOSSIER_CAPACITY_ERROR_MESSAGES.subscription_missing,
    "Aucun abonnement actif ne permet actuellement de créer ou de restaurer un dossier.",
  );
  assert.equal(
    DOSSIER_CAPACITY_ERROR_MESSAGES.configuration_unavailable,
    "La capacité de votre abonnement est temporairement indisponible.",
  );
});

test("une RPC absente échoue explicitement sans accorder de capacité", async () => {
  await expectServiceError(loadOwnedDossierCapacity(gateway({
    data: null,
    error: { code: "PGRST202", message: "Could not find function" },
  })), "rpc_unavailable", DOSSIER_CAPACITY_ERROR_MESSAGES.rpc_unavailable);
});

test("une erreur d’autorisation reste distincte d’une erreur de quota", async () => {
  await expectServiceError(loadOwnedDossierCapacity(gateway({
    data: null,
    error: { code: "42501", message: "Accès propriétaire requis." },
  })), "access_denied", DOSSIER_CAPACITY_ERROR_MESSAGES.access_denied);
});

test("les erreurs de quota, d’abonnement et de configuration restent distinctes", async () => {
  for (const [postgresCode, serviceCode] of [
    ["P4D01", "quota_reached"],
    ["P4D02", "subscription_missing"],
    ["P4D03", "configuration_unavailable"],
  ]) {
    await expectServiceError(loadOwnedDossierCapacity(gateway({
      data: null,
      error: { code: postgresCode, message: "information interne" },
    })), serviceCode, DOSSIER_CAPACITY_ERROR_MESSAGES[serviceCode]);
  }
});

test("une erreur réseau reste technique et ne produit jamais un DTO illimité", async () => {
  await expectServiceError(loadOwnedDossierCapacity({
    async getOwnedCapacity() {
      throw new Error("jeton et adresse internes");
    },
  }), "technical", DOSSIER_CAPACITY_ERROR_MESSAGES.technical);
});

test("une erreur PostgreSQL inconnue ne devient pas un quota atteint", async () => {
  await expectServiceError(loadOwnedDossierCapacity(gateway({
    data: null,
    error: { code: "XX000", message: "secret technique" },
  })), "technical", DOSSIER_CAPACITY_ERROR_MESSAGES.technical);
});

test("une réponse RPC invalide produit une erreur sûre", async () => {
  await expectServiceError(loadOwnedDossierCapacity(gateway({
    data: [],
    error: null,
  })), "invalid_response", DOSSIER_CAPACITY_ERROR_MESSAGES.invalid_response);
});

test("le service serveur appelle seulement la RPC authentifiée sans identifiant ni service role", async () => {
  const services = await source("domains/subscriptions/services.ts");
  const capacityGateway = services.slice(
    services.indexOf("function createDossierCapacityRpcGateway"),
    services.indexOf("export async function getDossierFeatureCapabilities"),
  );
  assert.match(services, /import "server-only"/);
  assert.match(services, /import \{ createClient \} from "@\/lib\/supabase\/server"/);
  assert.match(capacityGateway, /rpc\("get_owned_dossier_capacity"\)/);
  assert.match(capacityGateway, /as unknown as EntitlementRpcInvoker/);
  assert.doesNotMatch(capacityGateway, /ownerId|userId|protectedPersonId|p_owner_id/);
  assert.doesNotMatch(capacityGateway, /createAdminClient|service_role|SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(capacityGateway, /account_subscriptions|subscription_dossier_capacities|plan_key|price/);
});
