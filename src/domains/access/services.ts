import "server-only";
import { createHash } from "node:crypto";
import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getDossierInvitationStatus } from "./invitation-status";
import { canRecoverDossierInvitations } from "./invitation-recovery-policy";

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

export async function getDossierAccess(protectedPersonId: string) {
  const person = await getProtectedPerson(protectedPersonId);
  if (!person || person.accessRole === "read_only") notFound();
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) notFound();
  const admin = createAdminClient();
  const [ownerResult, accessResult, invitationResult] = await Promise.all([
    admin.auth.admin.getUserById(person.owner_id),
    admin.from("protected_person_access").select("*").eq("protected_person_id", protectedPersonId).order("created_at"),
    supabase.from("protected_person_invitations").select("id,email,role,expires_at,accepted_at,revoked_at,invited_by,created_at").eq("protected_person_id", protectedPersonId).order("created_at", { ascending: false }),
  ]);
  if (accessResult.error || invitationResult.error) throw new Error("Impossible de charger les accès du dossier.");
  const access = accessResult.data;
  const collaborators = await Promise.all((access ?? []).map(async (entry) => { const { data: authUser } = await admin.auth.admin.getUserById(entry.user_id); const { data: profile } = await admin.from("profiles").select("first_name,last_name").eq("id", entry.user_id).maybeSingle(); return { ...entry, email: authUser.user?.email ?? "", name: [profile?.first_name, profile?.last_name].filter(Boolean).join(" ") }; }));
  return {
    person,
    ownerEmail: ownerResult.data.user?.email ?? "",
    collaborators,
    invitations: invitationResult.data.map((invitation) => ({
      ...invitation,
      status: getDossierInvitationStatus(invitation),
      canManage: person.accessRole === "owner" || (invitation.role === "read_only" && invitation.invited_by === userId),
    })),
  };
}
