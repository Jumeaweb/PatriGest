import "server-only";
import { createHash } from "node:crypto";
import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { authUserExistsByEmail } from "./auth-user-lookup";
import { getDossierInvitationStatus } from "./invitation-status";

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

  const inviterResult = data.invited_by
    ? await admin.from("profiles").select("first_name,last_name").eq("id", data.invited_by).maybeSingle()
    : { data: null, error: null };
  let accountExists: boolean;
  try {
    accountExists = await authUserExistsByEmail(admin.auth.admin, data.email);
  } catch {
    console.error("[PatriGest] Échec du chargement d’une invitation valide", {
      ownerCode: inviterResult.error?.code,
      userCode: "lookup_failed",
    });
    return { status: "error" as const };
  }
  if (inviterResult.error) {
    console.error("[PatriGest] Échec du chargement d’une invitation valide", {
      ownerCode: inviterResult.error.code,
    });
    return { status: "error" as const };
  }
  return {
    status: "pending" as const,
    invitation: {
      ...data,
      ownerName: data.invited_by
        ? [inviterResult.data?.first_name, inviterResult.data?.last_name].filter(Boolean).join(" ") || "Un utilisateur PatriGest"
        : "Utilisateur supprimé",
      accountExists,
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
