import "server-only";

import { sendEmailWithResend } from "@/lib/email/resend-transport";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  buildRegistrationReviewNotification,
  REGISTRATION_REVIEW_NOTIFICATION_RECIPIENT,
} from "../registration-review-notification";
import { runRegistrationReviewNotificationDelivery } from "../registration-review-notification-runner";

const SAFE_PROVIDER_ERROR = "Échec de l’envoi e-mail.";
const STALE_RESERVATION_MILLISECONDS = 10 * 60 * 1000;

type AdminClient = ReturnType<typeof createAdminClient>;

async function loadEligibleRegistration(admin: AdminClient, userId: string) {
  const [authResult, authorizationResult, profileResult] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin
      .from("application_user_authorizations")
      .select("status,registration_intent,autonomous_registration_status,created_at")
      .eq("user_id", userId)
      .maybeSingle(),
    admin.from("profiles").select("first_name,last_name").eq("id", userId).maybeSingle(),
  ]);
  const authUser = authResult.data.user;
  const authorization = authorizationResult.data;
  if (authResult.error || authorizationResult.error || profileResult.error) {
    throw new Error("Impossible de vérifier la nouvelle inscription.");
  }
  if (!authUser?.email || !authUser.email_confirmed_at) return null;
  if (authorization?.status !== "pending"
      || authorization.registration_intent !== "autonomous"
      || authorization.autonomous_registration_status !== "pending") return null;

  return {
    email: authUser.email,
    firstName: profileResult.data?.first_name ?? String(authUser.user_metadata?.first_name ?? ""),
    lastName: profileResult.data?.last_name ?? String(authUser.user_metadata?.last_name ?? ""),
    requestedAt: authorization.created_at,
  };
}

async function reserveNotification(admin: AdminClient, userId: string) {
  const now = new Date().toISOString();
  const { error: insertError } = await admin.from("registration_review_notifications").insert({
    user_id: userId,
    status: "sending",
    attempt_count: 1,
    last_attempt_at: now,
  });
  if (!insertError) {
    return { status: "reserved" as const, idempotencyKey: `registration-review:${userId}` };
  }
  if (insertError.code !== "23505") throw new Error("Impossible de réserver l’alerte d’inscription.");

  const { data: existing, error: existingError } = await admin
    .from("registration_review_notifications")
    .select("status,attempt_count,updated_at")
    .eq("user_id", userId)
    .maybeSingle();
  if (existingError || !existing) throw new Error("Impossible de vérifier l’alerte existante.");
  if (existing.status === "sent") return { status: "skipped" as const };
  if (existing.status === "sending"
      && Date.now() - new Date(existing.updated_at).getTime() < STALE_RESERVATION_MILLISECONDS) {
    return { status: "skipped" as const };
  }

  const { data: retried, error: retryError } = await admin
    .from("registration_review_notifications")
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
  if (retryError) throw new Error("Impossible de relancer l’alerte d’inscription.");
  if (!retried) return { status: "skipped" as const };
  return { status: "reserved" as const, idempotencyKey: `registration-review:${userId}` };
}

async function sendPendingRegistrationNotification(userId: string) {
  const admin = createAdminClient();
  const registration = await loadEligibleRegistration(admin, userId);
  if (!registration) return "skipped" as const;
  const message = buildRegistrationReviewNotification(registration);

  return runRegistrationReviewNotificationDelivery({
    reserve: () => reserveNotification(admin, userId),
    send: (idempotencyKey) => sendEmailWithResend({
      to: REGISTRATION_REVIEW_NOTIFICATION_RECIPIENT,
      ...message,
      idempotencyKey,
    }),
    markSent: async (providerMessageId) => {
      const { error } = await admin.from("registration_review_notifications").update({
        status: "sent",
        provider_message_id: providerMessageId,
        sent_at: new Date().toISOString(),
        last_error_safe: null,
      }).eq("user_id", userId).eq("status", "sending").select("user_id").single();
      if (error) throw new Error("Impossible d’enregistrer l’alerte envoyée.");
    },
    markFailed: async () => {
      const { error } = await admin.from("registration_review_notifications").update({
        status: "failed",
        last_error_safe: SAFE_PROVIDER_ERROR,
      }).eq("user_id", userId).eq("status", "sending");
      if (error) throw new Error("Impossible d’enregistrer l’échec de l’alerte.");
    },
  });
}

export async function trySendPendingRegistrationNotification(userId: string) {
  try {
    return await sendPendingRegistrationNotification(userId);
  } catch {
    console.error("[PatriGest] Alerte de nouvelle inscription indisponible");
    return "failed" as const;
  }
}
