import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  DOSSIER_FEATURE_ACCESS_MODES,
  DOSSIER_FEATURE_DENIAL_REASONS,
  DOSSIER_FEATURE_KEYS,
  DossierFeatureServiceError,
  loadDossierFeatureCapabilities,
  parseDossierFeatureCapabilities,
  verifyDossierFeatureAccess,
} from "./entitlements.ts";

const dossierId = "10000000-0000-4000-8000-000000000001";
const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

function capabilityRows() {
  return DOSSIER_FEATURE_KEYS.map((featureKey) => ({
    feature_key: featureKey,
    implementation_status: featureKey === "bank_operation_automation"
      ? "upcoming"
      : "available",
    can_read: featureKey !== "bank_operation_automation",
    can_write: featureKey === "core_management",
    read_denial_reason: featureKey === "bank_operation_automation"
      ? "feature_upcoming"
      : null,
    write_denial_reason: featureKey === "core_management"
      ? null
      : featureKey === "bank_operation_automation"
        ? "feature_upcoming"
        : "role_forbidden",
  }));
}

function gateway(overrides = {}) {
  return {
    async getCapabilities() {
      return { data: capabilityRows(), error: null };
    },
    async checkAccess() {
      return { data: [{ allowed: true, denial_reason: null }], error: null };
    },
    ...overrides,
  };
}

async function expectServiceError(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof DossierFeatureServiceError);
    assert.equal(error.code, code);
    return true;
  });
}

test("les contrats exposent exactement les cinq fonctionnalités et les deux modes", () => {
  assert.deepEqual(DOSSIER_FEATURE_KEYS, [
    "core_management",
    "existing_accounting_documents",
    "data_export",
    "bank_operation_automation",
    "central_document_management",
  ]);
  assert.deepEqual(DOSSIER_FEATURE_ACCESS_MODES, ["read", "write"]);
  assert.deepEqual(DOSSIER_FEATURE_DENIAL_REASONS, [
    "feature_upcoming",
    "subscription_missing",
    "plan_unavailable",
    "not_in_plan",
    "role_forbidden",
    "operation_not_supported",
    "trial_export_unavailable",
  ]);
});

test("les cinq lignes SQL sont normalisées dans l’ordre stable et sans donnée commerciale", () => {
  const capabilities = parseDossierFeatureCapabilities(capabilityRows().toReversed());
  assert.deepEqual(capabilities.map((entry) => entry.featureKey), DOSSIER_FEATURE_KEYS);
  assert.deepEqual(capabilities[0], {
    featureKey: "core_management",
    implementationStatus: "available",
    read: { allowed: true, denialReason: null },
    write: { allowed: true, denialReason: null },
  });
  assert.equal("planKey" in capabilities[0], false);
  assert.equal("ownerId" in capabilities[0], false);
  assert.equal("price" in capabilities[0], false);
  assert.equal("subscriptionStatus" in capabilities[0], false);
});

test("les réponses absentes, incomplètes, dupliquées ou incohérentes sont refusées", () => {
  assert.throws(() => parseDossierFeatureCapabilities(null));
  assert.throws(() => parseDossierFeatureCapabilities(capabilityRows().slice(0, 4)));
  assert.throws(() => parseDossierFeatureCapabilities([
    ...capabilityRows().slice(0, 4),
    capabilityRows()[0],
  ]));
  assert.throws(() => parseDossierFeatureCapabilities(capabilityRows().map((row, index) => (
    index === 0 ? { ...row, can_read: true, read_denial_reason: "not_in_plan" } : row
  ))));
  assert.throws(() => parseDossierFeatureCapabilities(capabilityRows().map((row, index) => (
    index === 0 ? { ...row, can_write: false, write_denial_reason: null } : row
  ))));
});

test("une réponse contenant un motif inconnu ou une donnée commerciale est refusée", () => {
  assert.throws(() => parseDossierFeatureCapabilities(capabilityRows().map((row, index) => (
    index === 0 ? { ...row, can_write: false, write_denial_reason: "sql_secret" } : row
  ))));
  assert.throws(() => parseDossierFeatureCapabilities(capabilityRows().map((row) => ({
    ...row,
    plan_key: "premium",
  }))));
});

test("la lecture des capacités utilise uniquement la passerelle injectée", async () => {
  let receivedId = null;
  const result = await loadDossierFeatureCapabilities(gateway({
    async getCapabilities(protectedPersonId) {
      receivedId = protectedPersonId;
      return { data: capabilityRows(), error: null };
    },
  }), dossierId);
  assert.equal(receivedId, dossierId);
  assert.equal(result.length, 5);
});

test("la vérification ciblée distingue autorisation et refus fonctionnel", async () => {
  const allowed = await verifyDossierFeatureAccess(gateway(), {
    protectedPersonId: dossierId,
    featureKey: "data_export",
    accessMode: "read",
  });
  assert.deepEqual(allowed, {
    allowed: true,
    featureKey: "data_export",
    accessMode: "read",
  });

  for (const reason of DOSSIER_FEATURE_DENIAL_REASONS) {
    const denied = await verifyDossierFeatureAccess(gateway({
      async checkAccess() {
        return { data: [{ allowed: false, denial_reason: reason }], error: null };
      },
    }), {
      protectedPersonId: dossierId,
      featureKey: "core_management",
      accessMode: "write",
    });
    assert.deepEqual(denied, {
      allowed: false,
      featureKey: "core_management",
      accessMode: "write",
      reason,
    });
  }
});

test("les UUID, fonctionnalités et modes invalides sont refusés avant tout appel RPC", async () => {
  let calls = 0;
  const countingGateway = gateway({
    async getCapabilities() {
      calls += 1;
      return { data: capabilityRows(), error: null };
    },
    async checkAccess() {
      calls += 1;
      return { data: [{ allowed: true, denial_reason: null }], error: null };
    },
  });
  await expectServiceError(loadDossierFeatureCapabilities(countingGateway, "invalide"), "invalid_input");
  await expectServiceError(verifyDossierFeatureAccess(countingGateway, {
    protectedPersonId: dossierId,
    featureKey: "premium_everything",
    accessMode: "read",
  }), "invalid_input");
  await expectServiceError(verifyDossierFeatureAccess(countingGateway, {
    protectedPersonId: dossierId,
    featureKey: "core_management",
    accessMode: "execute",
  }), "invalid_input");
  assert.equal(calls, 0);
});

test("les erreurs SQL d’autorisation restent distinctes des refus fonctionnels", async () => {
  await expectServiceError(loadDossierFeatureCapabilities(gateway({
    async getCapabilities() {
      return { data: null, error: { code: "42501", message: "détail interne" } };
    },
  }), dossierId), "access_denied");
});

test("les erreurs SQL et réseau ne produisent jamais une autorisation", async () => {
  await expectServiceError(verifyDossierFeatureAccess(gateway({
    async checkAccess() {
      return { data: null, error: { code: "PGRST202", message: "fonction absente" } };
    },
  }), {
    protectedPersonId: dossierId,
    featureKey: "core_management",
    accessMode: "read",
  }), "technical");
  await expectServiceError(verifyDossierFeatureAccess(gateway({
    async checkAccess() {
      throw new Error("connexion interrompue");
    },
  }), {
    protectedPersonId: dossierId,
    featureKey: "core_management",
    accessMode: "read",
  }), "technical");
});

test("les réponses RPC absentes ou mal formées produisent une erreur explicite", async () => {
  await expectServiceError(loadDossierFeatureCapabilities(gateway({
    async getCapabilities() {
      return { data: null, error: null };
    },
  }), dossierId), "invalid_response");
  await expectServiceError(verifyDossierFeatureAccess(gateway({
    async checkAccess() {
      return { data: [], error: null };
    },
  }), {
    protectedPersonId: dossierId,
    featureKey: "core_management",
    accessMode: "read",
  }), "invalid_response");
});

test("le service serveur utilise le client utilisateur et seulement les deux RPC typées localement", async () => {
  const services = await source("domains/subscriptions/services.ts");
  assert.match(services, /import \{ createClient \} from "@\/lib\/supabase\/server"/);
  assert.match(services, /import "server-only"/);
  assert.match(services, /get_protected_person_feature_capabilities/);
  assert.match(services, /check_protected_person_feature_access/);
  assert.match(services, /as unknown as EntitlementRpcInvoker/);
  assert.doesNotMatch(services, /createAdminClient|service_role|SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(services, /account_subscriptions|subscription_plan_features|plan_key|price/);
});
