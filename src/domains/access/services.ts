import "server-only";
import { createHash } from "node:crypto";
import type { User } from "@supabase/supabase-js";
import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getDossierInvitationStatus } from "./invitation-status";
import { canRecoverDossierInvitations } from "./invitation-recovery-policy";
import {
  getInvitationHistoryPageMetadata,
  INVITATION_HISTORY_PAGE_SIZE,
} from "./access-pagination";

const PROFILE_BATCH_SIZE = 100;
const DATABASE_PAGE_SIZE = 500;

function chunks<T>(items: readonly T[], size: number) {
  const result: T[][] = [];
  for (let offset = 0; offset < items.length; offset += size) result.push(items.slice(offset, offset + size));
  return result;
}

async function getAuthUsersById(admin: ReturnType<typeof createAdminClient>, userIds: string[]) {
  const targetIds = new Set(userIds);
  const users = new Map<string, User>();
  const perPage = 1000;
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error("Impossible de charger les accès du dossier.");
    for (const user of data.users) {
      if (targetIds.has(user.id)) users.set(user.id, user);
    }
    if (users.size === targetIds.size || data.users.length < perPage) return users;
  }
}

async function getProfilesById(admin: ReturnType<typeof createAdminClient>, userIds: string[]) {
  const results = await Promise.all(chunks(userIds, PROFILE_BATCH_SIZE).map((batch) =>
    admin.from("profiles").select("id,first_name,last_name").in("id", batch),
  ));
  if (results.some((result) => result.error)) throw new Error("Impossible de charger les accès du dossier.");
  return new Map(results.flatMap((result) => result.data ?? []).map((profile) => [profile.id, profile]));
}

async function getAllPendingInvitations(
  supabase: Awaited<ReturnType<typeof createClient>>,
  protectedPersonId: string,
  now: string,
) {
  const invitations = [];
  for (let page = 0; ; page += 1) {
    const from = page * DATABASE_PAGE_SIZE;
    const { data, error } = await supabase.from("protected_person_invitations")
      .select("id,email,role,expires_at,accepted_at,revoked_at,invited_by,created_at")
      .eq("protected_person_id", protectedPersonId)
      .is("accepted_at", null)
      .is("revoked_at", null)
      .gt("expires_at", now)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(from, from + DATABASE_PAGE_SIZE - 1);
    if (error) throw new Error("Impossible de charger les accès du dossier.");
    invitations.push(...data);
    if (data.length < DATABASE_PAGE_SIZE) return invitations;
  }
}

export type RecoverableDossierInvitation = {
  id: string;
  protectedPersonId: string;
  dossierName: string;
  role: "manager" | "read_only";
  inviterName: string | null;
  expiresAt: string;
};

export async function getDossierInvitationDisplayContext(protectedPersonId: string, invitedBy: string | null) {
  const admin = createAdminClient();
  const [personResult, inviterResult] = await Promise.all([
    admin.from("protected_persons").select("first_name,last_name").eq("id", protectedPersonId).maybeSingle(),
    invitedBy
      ? admin.from("profiles").select("first_name,last_name").eq("id", invitedBy).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);
  if (personResult.error || inviterResult.error || !personResult.data) {
    throw new Error("Impossible de charger le contexte de l’invitation.");
  }
  return {
    dossierName: `${personResult.data.first_name} ${personResult.data.last_name}`.trim(),
    inviterName: invitedBy
      ? [inviterResult.data?.first_name, inviterResult.data?.last_name].filter(Boolean).join(" ") || "Un utilisateur PatriGest"
      : "Utilisateur supprimé",
  };
}

async function getVerifiedInvitationIdentity(userId: string) {
  const admin = createAdminClient();
  const [{ data: userData, error: userError }, { data: authorization, error: authorizationError }, { data: administrator, error: administratorError }] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle(),
    admin.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);
  const user = userData.user;
  const status = authorization?.status;
  if (userError || authorizationError || administratorError) throw new Error("Impossible de vérifier les invitations en attente.");
  if (!user?.email || !canRecoverDossierInvitations({
    emailConfirmed: Boolean(user.email_confirmed_at),
    authorizationStatus: status ?? null,
    platformAdministrator: Boolean(administrator),
  })) return null;
  return { email: user.email.trim().toLowerCase(), status };
}

export async function getRecoverableDossierInvitations(userId: string): Promise<RecoverableDossierInvitation[]> {
  const identity = await getVerifiedInvitationIdentity(userId);
  if (!identity) return [];

  const admin = createAdminClient();
  const { data: invitations, error } = await admin
    .from("protected_person_invitations")
    .select("id,protected_person_id,role,invited_by,expires_at")
    .eq("email", identity.email)
    .is("accepted_at", null)
    .is("revoked_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: true });
  if (error) throw new Error("Impossible de vérifier les invitations en attente.");
  if (!invitations.length) return [];

  const protectedPersonIds = [...new Set(invitations.map((invitation) => invitation.protected_person_id))];
  const inviterIds = [...new Set(invitations.flatMap((invitation) => invitation.invited_by ? [invitation.invited_by] : []))];
  const [{ data: people, error: peopleError }, profilesResult] = await Promise.all([
    admin.from("protected_persons").select("id,first_name,last_name").in("id", protectedPersonIds),
    inviterIds.length
      ? admin.from("profiles").select("id,first_name,last_name").in("id", inviterIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (peopleError || profilesResult.error) throw new Error("Impossible de charger les invitations en attente.");

  const peopleById = new Map((people ?? []).map((person) => [person.id, `${person.first_name} ${person.last_name}`.trim()]));
  const profilesById = new Map((profilesResult.data ?? []).map((profile) => [profile.id, `${profile.first_name} ${profile.last_name}`.trim()]));
  return invitations.flatMap((invitation) => {
    const dossierName = peopleById.get(invitation.protected_person_id);
    if (!dossierName) return [];
    return [{
      id: invitation.id,
      protectedPersonId: invitation.protected_person_id,
      dossierName,
      role: invitation.role,
      inviterName: invitation.invited_by ? profilesById.get(invitation.invited_by) || null : null,
      expiresAt: invitation.expires_at,
    }];
  });
}

export async function hasRecoverableDossierInvitations(userId: string) {
  return (await getRecoverableDossierInvitations(userId)).length > 0;
}

export async function getInvitationPreview(token: string) {
  const admin = createAdminClient();
  const { data, error } = await admin
    .from("protected_person_invitations")
    .select("id,email,role,protected_person_id,invited_by,expires_at,accepted_at,revoked_at")
    .eq("token_hash", createHash("sha256").update(token).digest("hex"))
    .maybeSingle();
  if (error) {
    console.error("[PatriGest] Échec de vérification d’une invitation", { code: error.code, message: error.message });
    return { status: "error" as const };
  }
  if (!data) return { status: "invalid" as const };
  const status = getDossierInvitationStatus(data);
  if (status !== "pending") return { status };

  let displayContext;
  try {
    displayContext = await getDossierInvitationDisplayContext(data.protected_person_id, data.invited_by);
  } catch {
    console.error("[PatriGest] Échec du chargement du contexte d’une invitation valide");
    return { status: "error" as const };
  }
  return {
    status: "pending" as const,
    invitation: {
      ...data,
      ...displayContext,
    },
  };
}

export async function getDossierAccess(protectedPersonId: string, requestedHistoryPage = 1) {
  const person = await getProtectedPerson(protectedPersonId);
  if (!person || person.accessRole === "read_only") notFound();
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) notFound();
  const admin = createAdminClient();
  const now = new Date().toISOString();
  const [accessResult, pendingInvitations, historyCountResult] = await Promise.all([
    admin.from("protected_person_access").select("*").eq("protected_person_id", protectedPersonId).order("created_at"),
    getAllPendingInvitations(supabase, protectedPersonId, now),
    supabase.from("protected_person_invitations")
      .select("id", { count: "exact", head: true })
      .eq("protected_person_id", protectedPersonId)
      .or(`accepted_at.not.is.null,revoked_at.not.is.null,expires_at.lte.${now}`),
  ]);
  if (accessResult.error || historyCountResult.error) throw new Error("Impossible de charger les accès du dossier.");

  const history = getInvitationHistoryPageMetadata(historyCountResult.count ?? 0, requestedHistoryPage);
  const from = (history.page - 1) * INVITATION_HISTORY_PAGE_SIZE;
  const access = accessResult.data ?? [];
  const identityIds = [...new Set([person.owner_id, ...access.map((entry) => entry.user_id)])];
  const [historyInvitationResult, authUsersById, profilesById] = await Promise.all([
    supabase.from("protected_person_invitations")
      .select("id,email,role,expires_at,accepted_at,revoked_at,invited_by,created_at")
      .eq("protected_person_id", protectedPersonId)
      .or(`accepted_at.not.is.null,revoked_at.not.is.null,expires_at.lte.${now}`)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(from, from + INVITATION_HISTORY_PAGE_SIZE - 1),
    getAuthUsersById(admin, identityIds),
    getProfilesById(admin, identityIds),
  ]);
  if (historyInvitationResult.error) throw new Error("Impossible de charger les accès du dossier.");

  const identity = (id: string) => {
    const profile = profilesById.get(id);
    return {
      email: authUsersById.get(id)?.email ?? "",
      name: [profile?.first_name, profile?.last_name].filter(Boolean).join(" "),
    };
  };
  const collaborators = access.map((entry) => ({ ...entry, ...identity(entry.user_id) }));
  const invitation = (entry: (typeof pendingInvitations)[number]) => ({
    ...entry,
    status: getDossierInvitationStatus(entry),
    canManage: person.accessRole === "owner" || (entry.role === "read_only" && entry.invited_by === userId),
  });
  return {
    person,
    owner: identity(person.owner_id),
    collaborators,
    pendingInvitations: pendingInvitations.map(invitation),
    invitationHistory: historyInvitationResult.data.map(invitation),
    history,
  };
}
