import "server-only";

import { sendEmailWithResend } from "@/lib/email/resend-transport";
import { createAdminClient } from "@/lib/supabase/admin";
import { buildRegistrationRejectionNotification } from "../registration-rejection-notification";
import { runRegistrationReviewNotificationDelivery } from "../registration-review-notification-runner";

const SAFE_PROVIDER_ERROR = "Échec de l’envoi e-mail.";
const STALE_RESERVATION_MILLISECONDS = 10 * 60 * 1000;

type AdminClient = ReturnType<typeof createAdminClient>;

async function loadRejectedRegistration(admin: AdminClient, userId: string) {
  const [authResult, authorizationResult] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin
      .from("application_user_authorizations")
      .select("registration_intent,autonomous_registration_status")
      .eq("user_id", userId)
      .maybeSingle(),
  ]);
  if (authResult.error || authorizationResult.error) {
    throw new Error("Impossible de vérifier l’inscription refusée.");
  }
  if (!authResult.data.user?.email || !authResult.data.user.email_confirmed_at) return null;
  if (authorizationResult.data?.registration_intent !== "autonomous"
      || authorizationResult.data.autonomous_registration_status !== "rejected") return null;
  return { email: authResult.data.user.email };
}

async function loadReservation(admin: AdminClient, userId: string) {
  const { data, error } = await admin
    .from("registration_rejection_notifications")
    .select("status,attempt_count,updated_at")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error("Impossible de vérifier la notification de refus.");
  return data;
}

async function reserveNotification(admin: AdminClient, userId: string, allowCreate: boolean) {
  const now = new Date().toISOString();
  if (allowCreate) {
    const { error } = await admin.from("registration_rejection_notifications").insert({
      user_id: userId,
      status: "sending",
      attempt_count: 1,
      last_attempt_at: now,
    });
    if (!error) return { status: "reserved" as const, idempotencyKey: `registration-rejection:${userId}` };
    if (error.code !== "23505") throw new Error("Impossible de réserver la notification de refus.");
  }

  const existing = await loadReservation(admin, userId);
  if (!existing) return { status: "skipped" as const };
  if (existing.status === "sent") return { status: "skipped" as const };
  if (existing.status === "sending"
      && Date.now() - new Date(existing.updated_at).getTime() < STALE_RESERVATION_MILLISECONDS) {
    return { status: "skipped" as const };
  }

  const { data: retried, error: retryError } = await admin
    .from("registration_rejection_notifications")
    .update({
      status: "sending",
      attempt_count: existing.attempt_count + 1,
      provider_message_id: null,
      last_error_safe: null,
      last_attempt_at: now,
      sent_at: null,
    })
    .eq("user_id", userId)
    .eq("status", existing.status)
    .eq("updated_at", existing.updated_at)
    .select("user_id")
    .maybeSingle();
  if (retryError) throw new Error("Impossible de relancer la notification de refus.");
  if (!retried) return { status: "skipped" as const };
  return { status: "reserved" as const, idempotencyKey: `registration-rejection:${userId}` };
}

async function sendRegistrationRejectionNotification(userId: string, allowCreate: boolean) {
  const admin = createAdminClient();
  const registration = await loadRejectedRegistration(admin, userId);
  if (!registration) return "skipped" as const;
  const message = buildRegistrationRejectionNotification();

  return runRegistrationReviewNotificationDelivery({
    reserve: () => reserveNotification(admin, userId, allowCreate),
    send: (idempotencyKey) => sendEmailWithResend({
      to: registration.email,
      ...message,
      idempotencyKey,
    }),
    markSent: async (providerMessageId) => {
      const { error } = await admin.from("registration_rejection_notifications").update({
        status: "sent",
        provider_message_id: providerMessageId,
        sent_at: new Date().toISOString(),
        last_error_safe: null,
      }).eq("user_id", userId).eq("status", "sending").select("user_id").single();
      if (error) throw new Error("Impossible d’enregistrer la notification de refus.");
    },
    markFailed: async () => {
      const { error } = await admin.from("registration_rejection_notifications").update({
        status: "failed",
        last_error_safe: SAFE_PROVIDER_ERROR,
      }).eq("user_id", userId).eq("status", "sending");
      if (error) throw new Error("Impossible d’enregistrer l’échec de la notification de refus.");
    },
  });
}

export async function trySendRegistrationRejectionNotification(userId: string, options: { allowCreate: boolean }) {
  try {
    return await sendRegistrationRejectionNotification(userId, options.allowCreate);
  } catch {
    console.error("[PatriGest] Notification de refus indisponible");
    return "failed" as const;
  }
}
