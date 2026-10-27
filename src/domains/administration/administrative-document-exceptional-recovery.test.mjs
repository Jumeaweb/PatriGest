import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  exceptionalRecoveryListSchema,
  exceptionalRecoverySchema,
  getExceptionalRecoveryErrorMessage,
  isExceptionalRecoveryRequestEligible,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "./administrative-document-exceptional-recovery.ts";

const ids = {
  recovery: "11111111-1111-4111-8111-111111111111",
  authorization: "22222222-2222-4222-8222-222222222222",
  operation: "33333333-3333-4333-8333-333333333333",
  attempt: "44444444-4444-4444-8444-444444444444",
  admin: "55555555-5555-4555-8555-555555555555",
  target: "66666666-6666-4666-8666-666666666666",
};

function authorization(overrides = {}) {
  return {
    authorizationId: ids.authorization,
    operationId: ids.operation,
    administratorSubjectId: ids.admin,
    attemptId: ids.attempt,
    reason: "Réparation commencée",
    repairPlan: [{
      targetId: ids.target,
      action: "confirm_already_conform",
      expectedTargetRevision: 0,
      expectedApplicationState: "pending",
      expectedObjectExists: false,
      expectedObjectId: null,
      expectedObjectVersion: null,
      backupId: null,
      expectedBackupRevision: null,
      expectedBackupState: null,
      residualReason: null,
    }],
    planHash: "a".repeat(64),
    state: "active",
    revision: 6,
    expiresAt: "2026-10-26T10:00:00.000Z",
    renewalCount: 6,
    ...overrides,
  };
}

function recovery(overrides = {}) {
  return {
    recoveryId: ids.recovery,
    authorizationId: ids.authorization,
    operationId: ids.operation,
    state: "requested",
    reason: "Reprendre la vérification",
    decisionReason: null,
    requestedAt: "2026-10-26T10:00:00.000Z",
    decidedAt: null,
    expiresAt: null,
    activationCount: 0,
    maxActivations: 2,
    revision: 0,
    requesterIsCaller: false,
    approverIsCaller: false,
    canApprove: true,
    activations: [],
    history: [{
      sequenceNumber: 1,
      eventType: "requested",
      outcome: "success",
      safeCode: null,
      occurredAt: "2026-10-26T10:00:00.000Z",
      actorIsCaller: false,
    }],
    ...overrides,
  };
}

test("propose une demande uniquement après six renouvellements et expiration", () => {
  assert.equal(isExceptionalRecoveryRequestEligible(authorization(), Date.parse("2026-10-26T10:00:01Z")), true);
  assert.equal(isExceptionalRecoveryRequestEligible(authorization({ renewalCount: 5 }), Date.parse("2026-10-26T10:00:01Z")), false);
  assert.equal(isExceptionalRecoveryRequestEligible(authorization({ expiresAt: "2026-10-26T10:01:00Z" }), Date.parse("2026-10-26T10:00:01Z")), false);
  assert.equal(isExceptionalRecoveryRequestEligible(authorization({ state: "cancelled" }), Date.parse("2026-10-26T10:00:01Z")), false);
});

test("valide les états, les deux activations et l’historique sûr", () => {
  const parsed = exceptionalRecoverySchema.parse(recovery({
    state: "active",
    decisionReason: "Validation indépendante",
    decidedAt: "2026-10-26T10:01:00Z",
    expiresAt: "2026-10-26T10:06:00Z",
    activationCount: 1,
    revision: 2,
    activations: [{ ordinal: 1, activatedAt: "2026-10-26T10:01:00Z", expiresAt: "2026-10-26T10:06:00Z", activatedByCaller: true }],
    objectPath: "secret/path.pdf",
  }));
  assert.equal(parsed.state, "active");
  assert.equal(parsed.activations.length, 1);
  assert.equal("objectPath" in parsed, false);
});

test("refuse une troisième activation dans la réponse SQL", () => {
  assert.throws(() => exceptionalRecoverySchema.parse(recovery({ activationCount: 3 })));
  assert.throws(() => exceptionalRecoverySchema.parse(recovery({ requestedAt: "date-invalide" })));
});

test("impose un curseur complet lorsque la file possède une page suivante", () => {
  assert.throws(() => exceptionalRecoveryListSchema.parse({
    items: [], hasMore: true, limit: 20, nextRequestedAt: null, nextId: null,
  }));
});

test("traduit les erreurs SQL sans exposer leur détail", () => {
  assert.match(getExceptionalRecoveryErrorMessage({ code: "P4X05", message: "raw SQL" }), /concurrente|clé/);
  assert.doesNotMatch(getExceptionalRecoveryErrorMessage({ code: "P4X05", message: "raw SQL" }), /raw SQL/);
  assert.match(getExceptionalRecoveryErrorMessage({ code: "P4X07" }), /deux activations/);
});

test("les actions conservent des clés stables et revalident seulement après succès", () => {
  const component = readFileSync(new URL("./components/administrative-document-exceptional-recovery-panel.tsx", import.meta.url), "utf8");
  const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(component, /requestId\.current \?\?= crypto\.randomUUID\(\)|stableId\(requestId\)/);
  assert.match(component, /stableId\(decisionId\)/);
  assert.match(component, /stableId\(activationId\)/);
  const requestAction = actions.slice(actions.indexOf("export async function requestAdministrativeDocumentExceptionalRecoveryAction"));
  assert.ok(requestAction.indexOf("await requestAdministrativeDocumentExceptionalRecovery") < requestAction.indexOf("revalidatePath"));
});

test("les actions exceptionnelles masquent les exceptions internes inattendues", () => {
  const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  const exceptionalActions = actions.slice(
    actions.indexOf("export async function requestAdministrativeDocumentExceptionalRecoveryAction"),
  );
  assert.match(actions, /error instanceof AdministrativeDocumentRepairError \? error\.message : fallback/);
  assert.doesNotMatch(exceptionalActions, /error instanceof Error \? error\.message/);
});

test("les décisions métier utilisent les RPC de session et non un second moteur", () => {
  const service = readFileSync(new URL("./services/administrative-document-repair-service.ts", import.meta.url), "utf8");
  const requestSection = service.slice(
    service.indexOf("export async function requestAdministrativeDocumentExceptionalRecovery"),
    service.indexOf("export async function resumeAdministrativeDocumentExceptionalRecovery"),
  );
  assert.match(requestSection, /requirePlatformAdministrator\(\)/);
  assert.match(requestSection, /request_administrative_document_exceptional_recovery/);
  assert.match(requestSection, /decide_administrative_document_exceptional_recovery/);
  assert.match(requestSection, /activate_administrative_document_exceptional_recovery/);
  assert.doesNotMatch(requestSection, /createAdminClient\(\)/);
  assert.match(requestSection, /p_expected_revision: input\.expectedRevision/g);
  assert.doesNotMatch(requestSection, /recovery\.revision !== input\.expectedRevision/);
});

test("la reprise réutilise le plan et le moteur existants", () => {
  const service = readFileSync(new URL("./services/administrative-document-repair-service.ts", import.meta.url), "utf8");
  const resumeSection = service.slice(service.indexOf("export async function resumeAdministrativeDocumentExceptionalRecovery"));
  assert.match(resumeSection, /authorization\.repairPlan/);
  assert.match(resumeSection, /new AdministrativeDocumentRepairEngine/);
  assert.match(resumeSection, /seal_administrative_document_repair/);
  assert.doesNotMatch(resumeSection, /issue_administrative_document_repair_authorization/);
});

test("l’interface exige des confirmations et signale la garde Storage absente", () => {
  const component = readFileSync(new URL("./components/administrative-document-exceptional-recovery-panel.tsx", import.meta.url), "utf8");
  assert.match(component, /name="confirmation" required/);
  assert.match(component, /L’horloge PostgreSQL reste seule autorité/);
  assert.match(component, /toute mutation destructive reste bloquée/);
  assert.match(component, /disabled=\{pending\}/);
  assert.doesNotMatch(component, /objectPath|backupId|token/);
});

test("le harnais utilise des ressources uniques, des délais bornés et nettoie seulement ce qu’il crée", () => {
  const harness = readFileSync(
    new URL("../../../scripts/test-administrative-document-exceptional-recovery-concurrency.mjs", import.meta.url),
    "utf8",
  );
  assert.match(harness, /randomUUID\(\)/);
  assert.match(harness, /statement_timeout='15s'/);
  assert.match(harness, /lock_timeout='5s'/);
  assert.match(harness, /dockerEndpoint\.startsWith\("npipe:\/\/\/\/\.\/pipe\/"\)/);
  assert.match(harness, /com\.supabase\.cli\.workdir/);
  assert.match(harness, /process\.cwd\(\)/);
  assert.match(harness, /databaseCreated = true/);
  assert.match(harness, /if \(databaseCreated\)/);
  assert.doesNotMatch(harness, /dropdb[^\n]+--if-exists[^\n]+\);\n\s+docker\(\[\n\s+"exec", container, "pg_dump"/);
  assert.match(harness, /select pg_sleep\(2\);[\s\S]+start_administrative_document_repair_item/);
});
