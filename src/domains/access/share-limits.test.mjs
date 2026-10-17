import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  getSafeShareErrorMessage,
  parseProtectedPersonShareCapacity,
} from "./share-limits.ts";
import { getDossierInvitationStatus } from "./invitation-status.ts";

const root = new URL("../../", import.meta.url);
const source = async (path) => readFile(new URL(path, root), "utf8");

const capacityRows = () => [
  {
    share_role: "manager",
    role_limit: 7,
    active_access_count: 3,
    pending_invitation_count: 2,
    used_count: 5,
    remaining_count: 2,
    exceeded_by: 0,
  },
  {
    share_role: "read_only",
    role_limit: 4,
    active_access_count: 5,
    pending_invitation_count: 1,
    used_count: 6,
    remaining_count: 0,
    exceeded_by: 2,
  },
];

test("les compteurs PostgreSQL sont validés et exposés sans plafond TypeScript", () => {
  const capacity = parseProtectedPersonShareCapacity(capacityRows());
  assert.deepEqual(capacity.manager, {
    role: "manager",
    limit: 7,
    activeAccessCount: 3,
    pendingInvitationCount: 2,
    usedCount: 5,
    remainingCount: 2,
    exceededBy: 0,
  });
  assert.equal(capacity.read_only.limit, 4);
  assert.equal(capacity.read_only.exceededBy, 2);
});

test("les réponses de compteurs incomplètes ou incohérentes sont refusées", () => {
  assert.throws(() => parseProtectedPersonShareCapacity(capacityRows().slice(0, 1)));
  assert.throws(() => parseProtectedPersonShareCapacity([capacityRows()[0], capacityRows()[0]]));
  assert.throws(() => parseProtectedPersonShareCapacity([
    { ...capacityRows()[0], used_count: 4 },
    capacityRows()[1],
  ]));
  assert.throws(() => parseProtectedPersonShareCapacity([
    capacityRows()[0],
    { ...capacityRows()[1], remaining_count: -1 },
  ]));
});

test("le mapping d’erreur n’expose que les erreurs de partage attendues", () => {
  assert.equal(
    getSafeShareErrorMessage({ code: "23514", message: "La limite de gestionnaires partagés est atteinte." }, "Échec."),
    "La limite de gestionnaires partagés est atteinte.",
  );
  assert.equal(
    getSafeShareErrorMessage({ code: "23514", message: "La limite de collaborateurs en lecture seule est atteinte." }, "Échec."),
    "La limite de collaborateurs en lecture seule est atteinte.",
  );
  assert.equal(
    getSafeShareErrorMessage({ code: "42501", message: "détail SQL interne" }, "Échec."),
    "Vous ne disposez pas des droits nécessaires pour cette opération.",
  );
  assert.equal(getSafeShareErrorMessage({ code: "XX000", message: "secret technique" }, "Échec."), "Échec.");
});

test("le service lit exclusivement la RPC propriétaire et valide sa réponse", async () => {
  const services = await source("domains/access/services.ts");
  const body = services.slice(services.indexOf("export async function getProtectedPersonShareCapacity"));
  assert.match(body, /z\.uuid\(\)\.safeParse\(protectedPersonId\)/);
  assert.match(body, /rpc\("get_protected_person_share_capacity"/);
  assert.match(body, /parseProtectedPersonShareCapacity/);
  assert.doesNotMatch(body, /createAdminClient/);
});

test("le changement de rôle utilise la RPC transactionnelle et reste réservé au propriétaire", async () => {
  const actions = await source("domains/access/actions.ts");
  const body = actions.slice(
    actions.indexOf("export async function updateCollaboratorRoleAction"),
    actions.indexOf("export async function removeCollaboratorAction"),
  );
  assert.match(body, /actor\.role !== "owner"/);
  assert.match(body, /rpc\("change_protected_person_access_role"/);
  assert.doesNotMatch(body, /\.from\("protected_person_access"\)[\s\S]*\.update/);
  assert.match(body, /getSafeShareErrorMessage/);
});

test("les invitations propagent les refus de quota sans calcul applicatif", async () => {
  const [actions, limits] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/share-limits.ts"),
  ]);
  assert.match(actions, /issue_protected_person_invitation/);
  assert.match(actions, /reissue_protected_person_invitation/);
  assert.match(actions, /revoke_protected_person_invitation/);
  assert.match(actions, /invitationCreationErrorMessage\(error\)/);
  assert.doesNotMatch(limits, /(?:manager|read_only)(?:Limit|_limit)?\s*[=:]\s*5\b/);
});

test("le refus d’invitation est préparé sans interface et utilise le hash du jeton", async () => {
  const actions = await source("domains/access/actions.ts");
  const body = actions.slice(
    actions.indexOf("export async function declineDossierInvitationAction"),
    actions.indexOf("export async function acceptRecoveredDossierInvitationAction"),
  );
  assert.match(body, /getClaims\(\)/);
  assert.match(body, /rpc\("decline_protected_person_invitation"/);
  assert.match(body, /createHash\("sha256"\)/);
  assert.doesNotMatch(body, /p_token_hash:\s*parsedToken/);
});

test("une invitation refusée est exclue des parcours actifs et conservée dans l’historique", async () => {
  const [services, actions] = await Promise.all([
    source("domains/access/services.ts"),
    source("domains/access/actions.ts"),
  ]);
  assert.match(services, /\.is\("declined_at", null\)/);
  assert.match(services, /declined_at\.not\.is\.null/);
  assert.match(actions, /\.is\("declined_at", null\)/);
  assert.equal(getDossierInvitationStatus({
    accepted_at: null,
    revoked_at: null,
    declined_at: "2026-10-16T08:00:00.000Z",
    expires_at: "2026-10-23T08:00:00.000Z",
  }, new Date("2026-10-16T09:00:00.000Z")), "declined");
});

test("les types déclarent les trois nouvelles RPC et les colonnes de refus", async () => {
  const database = await source("types/database.ts");
  assert.match(database, /get_protected_person_share_capacity/);
  assert.match(database, /change_protected_person_access_role/);
  assert.match(database, /decline_protected_person_invitation/);
  assert.match(database, /declined_at: string \| null/);
  assert.match(database, /declined_by: string \| null/);
});

test("la page ne charge et n’affiche les compteurs que pour le propriétaire", async () => {
  const page = await source("app/dossiers/[protectedPersonId]/acces/page.tsx");
  assert.match(page, /const owner = data\.person\.accessRole === "owner"/);
  assert.match(page, /const shareCapacity = owner \? await getProtectedPersonShareCapacity\(protectedPersonId\) : null/);
  assert.match(page, /view === "invite" \? <>[\s\S]*\{shareCapacity && <ShareCapacitySummary capacity=\{shareCapacity\} \/>\}/);
  assert.doesNotMatch(page, /<AccessTabs[^>]*\/>\s*\{shareCapacity && <ShareCapacitySummary/);
  assert.doesNotMatch(page, /<CollaboratorInviteForm[^>]+shareCapacity=/);
  assert.doesNotMatch(page, /<InvitationActions[^>]+shareCapacity=/);
});

test("la synthèse présente les deux quotas dynamiques, les invitations et les dépassements", async () => {
  const summary = await source("domains/access/components/share-capacity-summary.tsx");
  assert.match(summary, /Capacité de partage/);
  assert.match(summary, /Gestionnaires partagés/);
  assert.match(summary, /Collaborateurs en lecture seule/);
  assert.match(summary, /\{counter\.usedCount\} \/ \{counter\.limit\}/);
  assert.match(summary, /counter\.pendingInvitationCount/);
  assert.match(summary, /counter\.remainingCount/);
  assert.match(summary, /counter\.exceededBy/);
  assert.match(summary, /Limite dépassée de/);
  assert.match(summary, /sm:grid-cols-2/);
  assert.match(summary, /flex items-baseline justify-between/);
  assert.match(summary, /<h3[^>]*>\{label\}<\/h3>[\s\S]*\{counter\.usedCount\} \/ \{counter\.limit\}/);
  assert.match(summary, /className="mt-4 rounded-xl[^\"]*p-3"/);
  assert.doesNotMatch(summary, />\s*5\s*<|\/\s*5\b/);
});

test("le formulaire bloque seulement les nouveaux rôles saturés connus du propriétaire", async () => {
  const form = await source("domains/access/components/collaborator-invite-form.tsx");
  assert.match(form, /const canInvite = !isOwner \|\| Boolean\(availableRoles\?\.length\)/);
  assert.match(form, /disabled=\{!availableRoles\?\.includes\("read_only"\)\}/);
  assert.match(form, /disabled=\{!availableRoles\?\.includes\("manager"\)\}/);
  assert.match(form, /<InviteSubmitButton disabled=\{!canInvite\}/);
  assert.match(form, /<input type="hidden" name="role" value="read_only"/);
  assert.match(form, /aria-describedby/);
  assert.doesNotMatch(form, /(?:manager|read_only)(?:Limit|_limit)?\s*[=:]\s*5\b/);
});

test("les réductions restent possibles quand un quota est atteint ou dépassé", async () => {
  const [invitationActions, roleButton, removeButton] = await Promise.all([
    source("domains/access/components/invitation-actions.tsx"),
    source("domains/access/components/collaborator-role-button.tsx"),
    source("domains/access/components/collaborator-remove-button.tsx"),
  ]);
  assert.match(invitationActions, /status === "expired" && canCreateForRole === false/);
  assert.match(invitationActions, /const canRevoke = canManage && status === "pending"/);
  assert.doesNotMatch(invitationActions, /status === "pending" && canCreateForRole === false/);
  assert.match(roleButton, /persistedRole !== "manager" && !roleAvailability\.manager/);
  assert.match(roleButton, /persistedRole !== "read_only" && !roleAvailability\.read_only/);
  assert.doesNotMatch(roleButton, /shareCapacity|remainingCount/);
  assert.doesNotMatch(removeButton, /canCreateForRole|shareCapacity|remainingCount/);
});

test("les compteurs sont rafraîchis après chaque mutation de partage", async () => {
  const [actions, roleButton, removeButton, invitationActions] = await Promise.all([
    source("domains/access/actions.ts"),
    source("domains/access/components/collaborator-role-button.tsx"),
    source("domains/access/components/collaborator-remove-button.tsx"),
    source("domains/access/components/invitation-actions.tsx"),
  ]);
  const inviteBody = actions.slice(
    actions.indexOf("export async function inviteCollaboratorAction"),
    actions.indexOf("export async function reissueDossierInvitationAction"),
  );
  assert.match(inviteBody, /revalidatePath\(`\/dossiers\/\$\{actor\.protectedPersonId\}\/acces`\)/);
  assert.match(roleButton, /if \(succeeded\) router\.refresh\(\)/);
  assert.match(removeButton, /if \(succeeded\) router\.refresh\(\)/);
  assert.match(invitationActions, /if \(refresh\) router\.refresh\(\)/);
});
