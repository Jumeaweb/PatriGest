"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { deletePlatformUser, resendApplicationActivationEmail, reviewApplicationRegistration } from "./services/administration-service";
import {
  activateAdministrativeDocumentExceptionalRecovery,
  authorizeAndExecuteAdministrativeDocumentRepair,
  decideAdministrativeDocumentExceptionalRecovery,
  renewAdministrativeDocumentRepair,
  requestAdministrativeDocumentExceptionalRecovery,
  resumeAdministrativeDocumentExceptionalRecovery,
} from "./services/administrative-document-repair-service";
import { AdministrativeDocumentRepairError, repairActionSchema } from "./administrative-document-repair";
import {
  exceptionalRecoveryActivationRequestSchema,
  exceptionalRecoveryDecisionSchema,
  exceptionalRecoveryRequestSchema,
  exceptionalRecoveryResumeSchema,
} from "./administrative-document-exceptional-recovery";
import { physicalVerificationRequestSchema } from "./administrative-document-physical-verification";
import { verifyAdministrativeDocumentPhysicalObject } from "./services/administrative-document-physical-verification-service";
import { sendGlobalReleaseNotifications, sendTestReleaseNotification } from "./services/release-notification-service";
import type { AdministrativeDocumentRepairActionState, DeleteUserState, RegistrationReviewState, ReleaseNotificationActionState } from "./state";

const administrativeDeletionSchema = z.object({
  userId: z.uuid(),
  attemptId: z.uuid("Tentative de suppression invalide."),
  reason: z.string().trim().min(1, "Le motif est obligatoire.").max(2000, "Le motif ne peut pas dépasser 2 000 caractères."),
  confirmation: z.literal("on", { error: "Confirmez la suppression définitive." }),
});

function exceptionalRecoveryActionError(error: unknown, fallback: string): AdministrativeDocumentRepairActionState {
  return {
    status: "error",
    message: error instanceof AdministrativeDocumentRepairError ? error.message : fallback,
  };
}

export async function deletePlatformUserAction(userId: string, _state: DeleteUserState, formData: FormData): Promise<DeleteUserState> {
  void _state;
  const parsed = administrativeDeletionSchema.safeParse({
    userId,
    attemptId: formData.get("attemptId"),
    reason: formData.get("reason"),
    confirmation: formData.get("confirmation"),
  });
  if (!parsed.success) {
    const errors = parsed.error.flatten().fieldErrors;
    return {
      status: "error",
      message: "Vérifiez la confirmation et le motif de suppression.",
      fieldErrors: { reason: errors.reason, confirmation: errors.confirmation },
    };
  }
  try { await deletePlatformUser(userId, { attemptId: parsed.data.attemptId, reason: parsed.data.reason }); }
  catch (error) { return { status: "error", message: error instanceof Error ? error.message : "Impossible de supprimer cet utilisateur." }; }
  return { status: "success", message: "L’utilisateur a été supprimé." };
}

const registrationReviewSchema = z.object({
  userId: z.uuid(),
  decision: z.enum(["active", "rejected"]),
});

export async function reviewApplicationRegistrationAction(_state: RegistrationReviewState, formData: FormData): Promise<RegistrationReviewState> {
  void _state;
  const parsed = registrationReviewSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "Inscription ou décision invalide." };

  try {
    const result = await reviewApplicationRegistration(parsed.data.userId, parsed.data.decision);
    if (parsed.data.decision === "rejected") {
      if (!result.emailSent) return { status: "warning", message: "Inscription refusée, mais l’e-mail n’a pas pu être envoyé. Vous pouvez réessayer.", decision: "rejected" };
      return { status: "success", message: "Inscription refusée et e-mail envoyé.", decision: "rejected" };
    }
    if (!result.emailSent) return { status: "warning", message: "Accès activé, mais l’e-mail n’a pas pu être envoyé.", decision: "active" };
    return { status: "success", message: "Accès activé et e-mail envoyé.", decision: "active" };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "Impossible de traiter cette inscription." };
  }
}

export async function resendApplicationActivationEmailAction(_state: RegistrationReviewState, formData: FormData): Promise<RegistrationReviewState> {
  void _state;
  const parsed = z.object({ userId: z.uuid() }).safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "Compte utilisateur invalide." };
  try {
    await resendApplicationActivationEmail(parsed.data.userId);
    return { status: "success", message: "E-mail d’activation renvoyé." };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "Impossible de renvoyer l’e-mail d’activation." };
  }
}

const releaseTestSchema = z.object({ version: z.string().regex(/^\d+\.\d+\.\d+$/), userId: z.uuid() });
const releaseGlobalSchema = z.object({ version: z.string().regex(/^\d+\.\d+\.\d+$/) });

export async function sendTestReleaseNotificationAction(_state: ReleaseNotificationActionState, formData: FormData): Promise<ReleaseNotificationActionState> {
  void _state;
  const parsed = releaseTestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "Version ou destinataire de test invalide." };
  try {
    const result = await sendTestReleaseNotification(parsed.data.version, parsed.data.userId);
    return { status: "success", message: `E-mail de test envoyé à ${result.email}.` };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "Impossible d’envoyer l’e-mail de test." };
  }
}

export async function sendGlobalReleaseNotificationsAction(_state: ReleaseNotificationActionState, formData: FormData): Promise<ReleaseNotificationActionState> {
  void _state;
  const parsed = releaseGlobalSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "Version PatriGest invalide." };
  try {
    const summary = await sendGlobalReleaseNotifications(parsed.data.version);
    return {
      status: "success",
      message: `${summary.sent} e-mail(s) envoyé(s), ${summary.alreadySent} déjà traité(s), ${summary.failed} échec(s).`,
      summary,
    };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "Impossible d’informer les utilisateurs." };
  }
}

const repairRequestSchema = z.object({
  operationId: z.uuid(),
  attemptId: z.uuid(),
  reason: z.string().trim().min(1).max(2000),
  confirmation: z.literal("on"),
  decisions: z.array(z.object({
    targetId: z.uuid(),
    action: repairActionSchema,
    residualReason: z.string().trim().max(2000).optional(),
  })).min(1),
});

export async function executeAdministrativeDocumentRepairAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  let decisions: unknown;
  try { decisions = JSON.parse(String(formData.get("decisions") ?? "[]")); }
  catch { return { status: "error", message: "Les décisions de réparation sont invalides." }; }
  const parsed = repairRequestSchema.safeParse({
    operationId: formData.get("operationId"), attemptId: formData.get("attemptId"),
    reason: formData.get("reason"), confirmation: formData.get("confirmation"), decisions,
  });
  if (!parsed.success) return { status: "error", message: "Vérifiez le motif, les actions et la confirmation." };
  try {
    const result = await authorizeAndExecuteAdministrativeDocumentRepair(parsed.data);
    revalidatePath("/administration/reparations-documentaires");
    return result.residualAccepted
      ? { status: "warning", message: "L’état résiduel a été explicitement accepté et audité. Il ne constitue pas une restauration." }
      : { status: "success", message: "La réparation a été physiquement vérifiée et scellée." };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "La réparation a échoué." };
  }
}

const renewalSchema = z.object({ operationId: z.uuid(), attemptId: z.uuid(), renewalId: z.uuid() });

export async function renewAdministrativeDocumentRepairAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  const parsed = renewalSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "La demande de prolongation est invalide." };
  try {
    await renewAdministrativeDocumentRepair(parsed.data);
    revalidatePath("/administration/reparations-documentaires");
    return { status: "success", message: "La fenêtre de reprise a été prolongée de dix minutes." };
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "La prolongation a échoué." };
  }
}

export async function requestAdministrativeDocumentExceptionalRecoveryAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  const parsed = exceptionalRecoveryRequestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { status: "error", message: "Vérifiez le motif et la confirmation de la demande." };
  }
  try {
    await requestAdministrativeDocumentExceptionalRecovery(parsed.data);
    revalidatePath("/administration/reparations-documentaires");
    return { status: "success", message: "La demande attend maintenant la validation d’un autre administrateur." };
  } catch (error) {
    return exceptionalRecoveryActionError(error, "La demande exceptionnelle a échoué.");
  }
}

export async function decideAdministrativeDocumentExceptionalRecoveryAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  const parsed = exceptionalRecoveryDecisionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { status: "error", message: "Vérifiez la décision, son motif et la confirmation." };
  }
  try {
    await decideAdministrativeDocumentExceptionalRecovery({
      ...parsed.data,
      approve: parsed.data.decision === "approve",
    });
    revalidatePath("/administration/reparations-documentaires");
    return {
      status: "success",
      message: parsed.data.decision === "approve"
        ? "La récupération exceptionnelle a été approuvée."
        : "La récupération exceptionnelle a été refusée.",
    };
  } catch (error) {
    return exceptionalRecoveryActionError(error, "La décision exceptionnelle a échoué.");
  }
}

export async function activateAdministrativeDocumentExceptionalRecoveryAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  const parsed = exceptionalRecoveryActivationRequestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { status: "error", message: "La demande d’activation est invalide." };
  }
  try {
    await activateAdministrativeDocumentExceptionalRecovery(parsed.data);
    revalidatePath("/administration/reparations-documentaires");
    return { status: "success", message: "La fenêtre exceptionnelle de cinq minutes est active." };
  } catch (error) {
    return exceptionalRecoveryActionError(error, "L’activation exceptionnelle a échoué.");
  }
}

export async function resumeAdministrativeDocumentExceptionalRecoveryAction(
  _state: AdministrativeDocumentRepairActionState,
  formData: FormData,
): Promise<AdministrativeDocumentRepairActionState> {
  void _state;
  const parsed = exceptionalRecoveryResumeSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { status: "error", message: "La reprise exceptionnelle est invalide." };
  }
  try {
    await resumeAdministrativeDocumentExceptionalRecovery(parsed.data);
    revalidatePath("/administration/reparations-documentaires");
    return { status: "success", message: "La réparation a été reprise, vérifiée et scellée." };
  } catch (error) {
    return exceptionalRecoveryActionError(error, "La reprise exceptionnelle a échoué.");
  }
}

export async function verifyAdministrativeDocumentPhysicalObjectAction(
  _state: { status: "idle" | "success" | "error"; message: string },
  formData: FormData,
): Promise<{ status: "idle" | "success" | "error"; message: string }> {
  void _state;
  const parsed = physicalVerificationRequestSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { status: "error", message: "La demande de vérification physique est invalide." };
  try {
    const observation = await verifyAdministrativeDocumentPhysicalObject(parsed.data);
    revalidatePath("/administration/inventaire-documentaire");
    const messages = {
      verified_readable: "Les octets ont été lus et la preuve disponible a été vérifiée.",
      missing_physical_bytes: "Les octets physiques sont absents ou introuvables.",
      version_mismatch: "La version Storage a changé pendant la vérification.",
      hash_mismatch: "L’empreinte physique diverge de la référence durable.",
      verification_inconclusive: "La vérification n’a pas permis d’établir une preuve concluante.",
      stale_inventory_finding: "Le constat a changé depuis l’inventaire et doit être relu.",
    } as const;
    return { status: "success", message: messages[observation.outcome] };
  } catch {
    return { status: "error", message: "La vérification physique a échoué sans exposer de détail technique." };
  }
}
