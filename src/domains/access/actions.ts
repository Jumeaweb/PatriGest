"use server";

import { createHash, randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { getApplicationOrigin } from "@/lib/auth/redirects";
import { getDossierInvitationPath } from "@/lib/auth/invitation-destination";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { sendDossierInvitationEmail } from "./invitation-email";
import type { AccessActionState } from "./state";

const requestSchema = z.object({ firstName: z.string().trim().min(1).max(80), lastName: z.string().trim().min(1).max(80), email: z.email().trim().toLowerCase(), message: z.string().trim().max(1000).optional() });

async function requirePlatformAdmin() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) throw new Error("Accès refusé.");
  const { data } = await supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle();
  if (!data) throw new Error("Accès refusé.");
  return { supabase, userId };
}

export async function submitAccountRequestAction(_state: AccessActionState, formData: FormData): Promise<AccessActionState> {
  const parsed = requestSchema.safeParse({ firstName: formData.get("firstName"), lastName: formData.get("lastName"), email: formData.get("email"), message: formData.get("message") || undefined });
  if (!parsed.success) return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: parsed.error.flatten().fieldErrors };
  const supabase = await createClient();
  const { error } = await supabase.from("account_requests").insert({ first_name: parsed.data.firstName, last_name: parsed.data.lastName, email: parsed.data.email, message: parsed.data.message || null });
  if (error?.code === "23505") return { status: "error", message: "Une demande est déjà en attente pour cette adresse email." };
  if (error) return { status: "error", message: "Impossible d’envoyer votre demande. Réessayez dans quelques instants." };
  return { status: "success", message: "Votre demande a bien été envoyée. Vous recevrez un email lorsqu’elle aura été traitée." };
}

export async function reviewAccountRequestAction(_state: AccessActionState, formData: FormData): Promise<AccessActionState> {
  try {
    const { supabase, userId } = await requirePlatformAdmin();
    const id = z.string().uuid().parse(formData.get("id"));
    const decision = z.enum(["approved", "rejected"]).parse(formData.get("decision"));
    if (decision === "rejected") {
      const { error } = await supabase.from("account_requests").update({ status: decision, reviewed_at: new Date().toISOString(), reviewed_by: userId }).eq("id", id).eq("status", "pending");
      if (error) throw error;
      revalidatePath("/administration/demandes");
      return { status: "success", message: "La demande a été refusée." };
    }
    const invitation = await createAccountInvitation();
    const { error } = await supabase.from("account_requests").update({ status: decision, reviewed_at: new Date().toISOString(), reviewed_by: userId, invitation_token_hash: invitation.tokenHash, invitation_expires_at: invitation.expiresAt }).eq("id", id).eq("status", "pending");
    if (error) throw error;
    return { status: "success", message: "Demande approuvée", invitationUrl: invitation.url, invitationExpiresAt: invitation.expiresAt };
  } catch { return { status: "error", message: "Impossible de traiter cette demande." }; }
}

export async function regenerateAccountInvitationAction(_state: AccessActionState, formData: FormData): Promise<AccessActionState> {
  try {
    const { supabase } = await requirePlatformAdmin();
    const id = z.string().uuid().parse(formData.get("id"));
    const invitation = await createAccountInvitation();
    const { data, error } = await supabase.from("account_requests").update({ invitation_token_hash: invitation.tokenHash, invitation_expires_at: invitation.expiresAt }).eq("id", id).eq("status", "approved").is("invitation_used_at", null).select("id").maybeSingle();
    if (error || !data) throw error ?? new Error("Demande indisponible.");
    return { status: "success", message: "Lien d’inscription régénéré", invitationUrl: invitation.url, invitationExpiresAt: invitation.expiresAt };
  } catch { return { status: "error", message: "Impossible de régénérer ce lien d’inscription." }; }
}

async function createAccountInvitation() {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  return { tokenHash: createHash("sha256").update(token).digest("hex"), expiresAt, url: `${await getApplicationOrigin()}/inscription?token=${encodeURIComponent(token)}` };
}

export async function validateSignupInvitation(token: string) {
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const admin = createAdminClient();
  const now = new Date().toISOString();
  const [requestResult, dossierResult] = await Promise.all([
    admin.from("account_requests").select("id,email,first_name,last_name").eq("invitation_token_hash", tokenHash).eq("status", "approved").is("invitation_used_at", null).gt("invitation_expires_at", now).maybeSingle(),
    admin.from("protected_person_invitations").select("id,email").eq("token_hash", tokenHash).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now).maybeSingle(),
  ]);
  if (requestResult.data) return { kind: "account" as const, ...requestResult.data };
  if (dossierResult.data) return { kind: "dossier" as const, ...dossierResult.data, first_name: "", last_name: "" };
  return null;
}

export async function markSignupInvitationUsed(token: string) {
  const admin = createAdminClient();
  await admin.from("account_requests").update({ invitation_used_at: new Date().toISOString() }).eq("invitation_token_hash", createHash("sha256").update(token).digest("hex")).is("invitation_used_at", null);
}

async function getDossierActor(protectedPersonId: string) {
  const parsedPersonId = z.uuid().parse(protectedPersonId);
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) throw new Error("Authentification requise.");

  const [{ data: person, error: personError }, { data: access, error: accessError }] = await Promise.all([
    supabase.from("protected_persons").select("owner_id").eq("id", parsedPersonId).maybeSingle(),
    supabase.from("protected_person_access").select("role").eq("protected_person_id", parsedPersonId).eq("user_id", userId).maybeSingle(),
  ]);
  if (personError || accessError || !person) throw new Error("Dossier introuvable.");

  const role = person.owner_id === userId ? "owner" as const : access?.role ?? null;
  return { supabase, userId, protectedPersonId: parsedPersonId, role };
}

export async function inviteCollaboratorAction(protectedPersonId: string, _state: AccessActionState, formData: FormData): Promise<AccessActionState> {
  try {
    const input = z.object({ email: z.email().trim().toLowerCase(), role: z.enum(["manager", "read_only"]) }).parse({ email: formData.get("email"), role: formData.get("role") });
    const actor = await getDossierActor(protectedPersonId);
    if (actor.role !== "owner" && actor.role !== "manager") return { status: "error", message: "Vous ne pouvez pas inviter de collaborateur." };
    if (actor.role === "manager" && input.role !== "read_only") return { status: "error", message: "Un gestionnaire ne peut inviter qu’en lecture seule." };
    const invitation = createDossierInvitationSecret();
    const { error } = await actor.supabase.rpc("issue_protected_person_invitation", {
      p_protected_person_id: actor.protectedPersonId,
      p_email: input.email,
      p_role: input.role,
      p_token_hash: invitation.tokenHash,
      p_expires_at: invitation.expiresAt,
    });
    if (error) return { status: "error", message: "Impossible de créer cette invitation." };
    const invitationUrl = `${await getApplicationOrigin()}${getDossierInvitationPath(invitation.token)}`;
    revalidatePath(`/dossiers/${actor.protectedPersonId}/acces`);
    try {
      await sendDossierInvitationEmail({ email: input.email, role: input.role, invitationUrl, expiresAt: invitation.expiresAt });
      return { status: "success", message: "Invitation envoyée." };
    } catch {
      return { status: "warning", message: "Invitation créée, mais l’e-mail n’a pas pu être envoyé.", invitationUrl, invitationExpiresAt: invitation.expiresAt };
    }
  } catch { return { status: "error", message: "Impossible de créer cette invitation." }; }
}

export async function reissueDossierInvitationAction(protectedPersonId: string, invitationId: string, _state: AccessActionState, _formData: FormData): Promise<AccessActionState> {
  void _state;
  void _formData;
  try {
    const parsedInvitationId = z.uuid().parse(invitationId);
    const actor = await getDossierActor(protectedPersonId);
    if (actor.role !== "owner" && actor.role !== "manager") return { status: "error", message: "Vous ne pouvez pas renvoyer cette invitation." };
    const { data: source, error: sourceError } = await actor.supabase
      .from("protected_person_invitations")
      .select("id,email,role,protected_person_id,invited_by,accepted_at,revoked_at")
      .eq("id", parsedInvitationId)
      .eq("protected_person_id", actor.protectedPersonId)
      .maybeSingle();
    if (sourceError || !source || source.accepted_at || source.revoked_at) {
      return { status: "error", message: "Cette invitation ne peut plus être renvoyée." };
    }
    if (actor.role === "manager" && (source.role !== "read_only" || source.invited_by !== actor.userId)) {
      return { status: "error", message: "Vous ne pouvez pas renvoyer cette invitation." };
    }

    const invitation = createDossierInvitationSecret();
    const { error } = await actor.supabase.rpc("reissue_protected_person_invitation", {
      p_invitation_id: parsedInvitationId,
      p_token_hash: invitation.tokenHash,
      p_expires_at: invitation.expiresAt,
    });
    if (error) return { status: "error", message: "Impossible de renvoyer cette invitation." };

    const invitationUrl = `${await getApplicationOrigin()}${getDossierInvitationPath(invitation.token)}`;
    revalidatePath(`/dossiers/${actor.protectedPersonId}/acces`);
    try {
      await sendDossierInvitationEmail({ email: source.email, role: source.role, invitationUrl, expiresAt: invitation.expiresAt });
      return { status: "success", message: "Nouvelle invitation envoyée." };
    } catch {
      return { status: "warning", message: "Nouvelle invitation créée, mais l’e-mail n’a pas pu être envoyé.", invitationUrl, invitationExpiresAt: invitation.expiresAt };
    }
  } catch {
    return { status: "error", message: "Impossible de renvoyer cette invitation." };
  }
}

export async function revokeDossierInvitationAction(protectedPersonId: string, invitationId: string, _state: AccessActionState, _formData: FormData): Promise<AccessActionState> {
  void _state;
  void _formData;
  try {
    const parsedInvitationId = z.uuid().parse(invitationId);
    const actor = await getDossierActor(protectedPersonId);
    if (actor.role !== "owner" && actor.role !== "manager") return { status: "error", message: "Vous ne pouvez pas annuler cette invitation." };
    const { data: invitation } = await actor.supabase
      .from("protected_person_invitations")
      .select("id,role,invited_by")
      .eq("id", parsedInvitationId)
      .eq("protected_person_id", actor.protectedPersonId)
      .maybeSingle();
    if (!invitation) return { status: "error", message: "Invitation indisponible." };
    if (actor.role === "manager" && (invitation.role !== "read_only" || invitation.invited_by !== actor.userId)) {
      return { status: "error", message: "Vous ne pouvez pas annuler cette invitation." };
    }
    const { error } = await actor.supabase.rpc("revoke_protected_person_invitation", { p_invitation_id: parsedInvitationId });
    if (error) return { status: "error", message: "Impossible d’annuler cette invitation." };
    revalidatePath(`/dossiers/${actor.protectedPersonId}/acces`);
    return { status: "success", message: "Invitation annulée." };
  } catch {
    return { status: "error", message: "Impossible d’annuler cette invitation." };
  }
}

function createDossierInvitationSecret() {
  const token = randomBytes(32).toString("base64url");
  return {
    token,
    tokenHash: createHash("sha256").update(token).digest("hex"),
    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  };
}

export async function acceptDossierInvitationAction(token: string): Promise<void> {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) throw new Error("Authentification requise.");
  const { data: administrator } = await supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle();
  if (administrator) throw new Error("Un Administrateur PatriGest ne peut pas accepter une invitation métier.");
  const { data, error } = await supabase.rpc("accept_protected_person_invitation", { p_token_hash: createHash("sha256").update(token).digest("hex") });
  if (error || !data) throw new Error("Invitation invalide ou expirée.");
  revalidatePath("/dossiers");
  const { redirect } = await import("next/navigation");
  redirect(`/dossiers/${data}/tableau-de-bord`);
}

export async function updateCollaboratorRoleAction(protectedPersonId: string, formData: FormData) {
  const id = z.string().uuid().parse(formData.get("id"));
  const role = z.enum(["manager", "read_only"]).parse(formData.get("role"));
  const supabase = await createClient();
  const { data, error } = await supabase.from("protected_person_access").update({ role }).eq("id", id).eq("protected_person_id", z.uuid().parse(protectedPersonId)).select("id").maybeSingle();
  if (error || !data) throw new Error("Impossible de modifier ce rôle.");
  revalidatePath(`/dossiers/${protectedPersonId}/acces`);
}

export async function removeCollaboratorAction(protectedPersonId: string, accessId: string, _state: AccessActionState, _formData: FormData): Promise<AccessActionState> {
  void _state;
  void _formData;
  try {
    const parsedPersonId = z.uuid().parse(protectedPersonId);
    const parsedAccessId = z.uuid().parse(accessId);
    const supabase = await createClient();
    const { error } = await supabase.rpc("remove_protected_person_access", {
      p_protected_person_id: parsedPersonId,
      p_access_id: parsedAccessId,
    });
    if (error) return { status: "error", message: "Impossible de retirer cet accès." };
    revalidatePath(`/dossiers/${parsedPersonId}/acces`);
    return { status: "success", message: "L’accès au dossier a été retiré." };
  } catch {
    return { status: "error", message: "Impossible de retirer cet accès." };
  }
}
