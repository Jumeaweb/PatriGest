import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES,
  ProtectedPersonArchiveTransitionError,
  executeProtectedPersonArchiveTransition,
  mapProtectedPersonArchiveRpcError,
  protectedPersonArchiveTransitionSchema,
} from "./archive-lifecycle.ts";
import { mapDossierCapacityRpcError } from "../subscriptions/dossier-capacity.ts";

const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

const validInput = {
  protectedPersonId: "97000000-0000-4000-8000-000000000001",
  expectedRevision: 3,
  reason: "  Fin de mesure  ",
};

function gateway(result = { data: 4, error: null }) {
  return {
    calls: [],
    async transition(operation, input) {
      this.calls.push({ operation, input });
      return result;
    },
  };
}

async function expectTransitionError(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof ProtectedPersonArchiveTransitionError);
    assert.equal(error.code, code);
    assert.equal(error.message, PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES[code]);
    assert.doesNotMatch(error.message, /P4A|P4D|PGRST|SQL|jeton|secret/i);
    return true;
  });
}

test("normalise et valide les UUID, révisions et motifs", () => {
  assert.deepEqual(protectedPersonArchiveTransitionSchema.parse(validInput), {
    ...validInput,
    reason: "Fin de mesure",
  });

  for (const input of [
    { ...validInput, protectedPersonId: "invalide" },
    { ...validInput, expectedRevision: 0 },
    { ...validInput, expectedRevision: -1 },
    { ...validInput, expectedRevision: 1.5 },
    { ...validInput, reason: "   " },
    { ...validInput, reason: "x".repeat(2001) },
  ]) {
    assert.equal(protectedPersonArchiveTransitionSchema.safeParse(input).success, false);
  }
});

test("accepte un motif de 2 000 caractères et refuse les propriétés inattendues", () => {
  assert.equal(protectedPersonArchiveTransitionSchema.safeParse({
    ...validInput,
    reason: "é".repeat(2000),
  }).success, true);
  assert.equal(protectedPersonArchiveTransitionSchema.safeParse({
    ...validInput,
    author: "identité fournie par le client",
  }).success, false);
});

test("retourne la nouvelle révision pour un archivage réussi", async () => {
  const rpc = gateway();
  assert.deepEqual(
    await executeProtectedPersonArchiveTransition(rpc, "archive", validInput),
    { archiveRevision: 4 },
  );
  assert.deepEqual(rpc.calls, [{ operation: "archive", input: validInput }]);
});

test("retourne la nouvelle révision pour une restauration réussie", async () => {
  const rpc = gateway({ data: 8, error: null });
  assert.deepEqual(
    await executeProtectedPersonArchiveTransition(rpc, "restore", validInput),
    { archiveRevision: 8 },
  );
  assert.equal(rpc.calls[0].operation, "restore");
});

test("traduit P4A01 à P4A05 sans exposer les messages PostgreSQL", () => {
  const expected = [
    ["P4A01", "forbidden"],
    ["P4A02", "not_found"],
    ["P4A03", "invalid_reason"],
    ["P4A04", "incompatible_state"],
    ["P4A05", "stale_revision"],
  ];
  for (const [postgresCode, applicationCode] of expected) {
    const error = mapProtectedPersonArchiveRpcError({
      code: postgresCode,
      message: "détail SQL avec jeton secret",
    });
    assert.equal(error.code, applicationCode);
    assert.equal(error.message, PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES[applicationCode]);
  }
});

test("réutilise le mapping des refus de capacité P4D01 à P4D03", () => {
  const expected = [
    ["P4D01", "quota_reached"],
    ["P4D02", "subscription_missing"],
    ["P4D03", "configuration_unavailable"],
  ];
  for (const [postgresCode, applicationCode] of expected) {
    const error = mapProtectedPersonArchiveRpcError({
      code: postgresCode,
      message: "détail confidentiel",
    }, mapDossierCapacityRpcError);
    assert.equal(error.code, applicationCode);
    assert.equal(error.message, PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES[applicationCode]);
  }
});

test("distingue une RPC indisponible d’une erreur inconnue", () => {
  for (const code of ["PGRST202", "42883"]) {
    assert.equal(mapProtectedPersonArchiveRpcError({ code }).code, "rpc_unavailable");
  }
  assert.equal(mapProtectedPersonArchiveRpcError({
    code: "XX000",
    message: "erreur interne avec secret",
  }).code, "technical");
});

test("propage les codes connus sous forme d’erreurs applicatives sûres", async () => {
  for (const [postgresCode, applicationCode] of [
    ["P4A01", "forbidden"],
    ["P4A02", "not_found"],
    ["P4A03", "invalid_reason"],
    ["P4A04", "incompatible_state"],
    ["P4A05", "stale_revision"],
    ["P4D01", "quota_reached"],
    ["P4D02", "subscription_missing"],
    ["P4D03", "configuration_unavailable"],
    ["PGRST202", "rpc_unavailable"],
    ["XX000", "technical"],
  ]) {
    await expectTransitionError(executeProtectedPersonArchiveTransition(
      gateway({ data: null, error: { code: postgresCode, message: "SQL secret" } }),
      "archive",
      validInput,
      mapDossierCapacityRpcError,
    ), applicationCode);
  }
});

test("une erreur réseau devient une erreur technique sûre", async () => {
  await expectTransitionError(executeProtectedPersonArchiveTransition({
    async transition() {
      throw new Error("URL interne et jeton secret");
    },
  }, "archive", validInput), "technical");
});

test("une réponse RPC mal formée est refusée", async () => {
  for (const data of [null, "4", 0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, {}]) {
    await expectTransitionError(executeProtectedPersonArchiveTransition(
      gateway({ data, error: null }),
      "archive",
      validInput,
    ), "invalid_response");
  }
});

test("le service serveur appelle exclusivement les RPC authentifiées", async () => {
  const service = await source("domains/protected-persons/services/protected-person-archive-service.ts");
  assert.match(service, /import "server-only"/);
  assert.match(service, /getAuthenticatedUser\(\)/);
  assert.match(service, /"archive_protected_person"/);
  assert.match(service, /"restore_protected_person"/);
  assert.doesNotMatch(service, /createAdminClient|service_role|SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(service, /\.from\("protected_persons"\)|\.update\(|\.insert\(|\.delete\(/);
  assert.doesNotMatch(service, /protected_person_archive_changes|get_owned_dossier_capacity|account_subscriptions/);
});

test("les actions valident puis revalident uniquement après une transition réussie", async () => {
  const actions = await source("domains/protected-persons/actions.ts");
  const transition = actions.slice(
    actions.indexOf("async function protectedPersonArchiveTransitionAction"),
    actions.indexOf("export async function createProtectedPersonAction"),
  );
  const revalidation = actions.slice(
    actions.indexOf("function revalidateProtectedPersonArchiveTransition"),
    actions.indexOf("async function protectedPersonArchiveTransitionAction"),
  );

  assert.match(transition, /protectedPersonArchiveTransitionSchema\.safeParse/);
  assert.match(transition, /if \(!parsed\.success\) return validationError/);
  assert.match(transition, /archiveProtectedPerson\(parsed\.data\)/);
  assert.match(transition, /restoreProtectedPerson\(parsed\.data\)/);
  assert.ok(
    transition.indexOf("revalidateProtectedPersonArchiveTransition")
      > transition.indexOf("catch (error)"),
  );
  for (const path of [
    'revalidatePath("/dossiers")',
    'revalidatePath("/tableau-de-bord")',
    "revalidatePath(`/dossiers/${protectedPersonId}`)",
    "revalidatePath(`/dossiers/${protectedPersonId}/tableau-de-bord`)",
    'revalidatePath("/parametres/compte")',
  ]) {
    assert.ok(revalidation.includes(path), `revalidation absente : ${path}`);
  }
  assert.doesNotMatch(transition, /redirect\(/);
});
