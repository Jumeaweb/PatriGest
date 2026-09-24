"use server";

import { z } from "zod";
import { deletePlatformUser, resendApplicationActivationEmail, reviewApplicationRegistration } from "./services/administration-service";
import { sendGlobalReleaseNotifications, sendTestReleaseNotification } from "./services/release-notification-service";
import type { DeleteUserState, RegistrationReviewState, ReleaseNotificationActionState } from "./state";

export async function deletePlatformUserAction(userId: string, _state: DeleteUserState, _formData: FormData): Promise<DeleteUserState> {
  void _state;
  void _formData;
  if (!z.uuid().safeParse(userId).success) return { status: "error", message: "Utilisateur invalide." };
  try { await deletePlatformUser(userId); }
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
    if (parsed.data.decision === "rejected") return { status: "success", message: "Inscription refusée.", decision: "rejected" };
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
