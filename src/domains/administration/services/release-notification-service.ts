import "server-only";

import type { User } from "@supabase/supabase-js";
import { APP_NAME } from "@/lib/app";
import { getApplicationOrigin } from "@/lib/auth/redirects";
import { sendEmailWithResend } from "@/lib/email/resend-transport";
import { APP_RELEASES } from "@/lib/releases";
import { createAdminClient } from "@/lib/supabase/admin";
import { buildReleaseEmail } from "../release-email";
import { collectAllPages, selectEligibleReleaseRecipients, type ReleaseRecipient } from "../release-notification-policy";
import { runReleaseNotificationBatch } from "../release-notification-runner";
import { requirePlatformAdministrator } from "./administration-service";

const DATABASE_PAGE_SIZE = 500;
const USER_QUERY_BATCH_SIZE = 200;
const SAFE_PROVIDER_ERROR = "Échec de l’envoi e-mail.";

type AdminClient = ReturnType<typeof createAdminClient>;

function getRelease(version: string) {
  const release = APP_RELEASES.find((candidate) => candidate.version === version);
  if (!release) throw new Error("Version PatriGest inconnue.");
  return release;
}

function chunks<T>(items: readonly T[], size: number) {
  const result: T[][] = [];
  for (let offset = 0; offset < items.length; offset += size) result.push(items.slice(offset, offset + size));
  return result;
}

async function getAllAuthUsers(admin: AdminClient) {
  return collectAllPages<User>(async (page, perPage) => {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error("Impossible de charger les utilisateurs destinataires.");
    return data.users;
  });
}

async function loadEligibleRecipients(admin: AdminClient) {
  const users = await getAllAuthUsers(admin);
  const activeUserIds = new Set<string>();
  const administratorIds = new Set<string>();
  const profiles = new Map<string, { firstName: string; lastName: string }>();

  for (const batch of chunks(users.map((user) => user.id), USER_QUERY_BATCH_SIZE)) {
    const [authorizationResult, administratorResult, profileResult] = await Promise.all([
      admin.from("application_user_authorizations").select("user_id,status").in("user_id", batch).eq("status", "active"),
      admin.from("platform_administrators").select("user_id").in("user_id", batch),
      admin.from("profiles").select("id,first_name,last_name").in("id", batch),
    ]);
    if (authorizationResult.error || administratorResult.error || profileResult.error) {
      throw new Error("Impossible de déterminer les destinataires de la release.");
    }
    for (const authorization of authorizationResult.data) activeUserIds.add(authorization.user_id);
    for (const administrator of administratorResult.data) administratorIds.add(administrator.user_id);
    for (const profile of profileResult.data) profiles.set(profile.id, {
      firstName: profile.first_name ?? "",
      lastName: profile.last_name ?? "",
    });
  }

  return selectEligibleReleaseRecipients({
    users: users.map((user) => ({ id: user.id, email: user.email, emailConfirmedAt: user.email_confirmed_at })),
    activeUserIds,
    administratorIds,
    profiles,
  });
}

async function loadGlobalNotifications(admin: AdminClient, version: string) {
  return collectAllPages(async (page, perPage) => {
    const from = (page - 1) * perPage;
    const { data, error } = await admin
      .from("release_notifications")
      .select("status")
      .eq("version", version)
      .eq("delivery_kind", "global")
      .range(from, from + perPage - 1);
    if (error) throw new Error("Impossible de charger l’état des notifications.");
    return data;
  }, DATABASE_PAGE_SIZE);
}

export async function getReleaseNotificationDashboard(version: string) {
  await requirePlatformAdministrator();
  const admin = createAdminClient();
  const release = getRelease(version);
  const [recipients, notifications] = await Promise.all([
    loadEligibleRecipients(admin),
    loadGlobalNotifications(admin, version),
  ]);
  return {
    release: { version: release.version, title: release.title, summary: release.summary },
    recipients,
    notificationState: {
      sent: notifications.filter((notification) => notification.status === "sent").length,
      failed: notifications.filter((notification) => notification.status === "failed").length,
      inProgress: notifications.filter((notification) => notification.status === "pending" || notification.status === "sending").length,
    },
  };
}

async function getReleaseMessage(version: string, recipient: ReleaseRecipient) {
  const release = getRelease(version);
  const changelogUrl = `${await getApplicationOrigin()}/historique-versions`;
  return buildReleaseEmail({ appName: APP_NAME, release, changelogUrl, recipient });
}

export async function sendTestReleaseNotification(version: string, targetUserId: string) {
  const { userId: requestedBy } = await requirePlatformAdministrator();
  const admin = createAdminClient();
  const recipients = await loadEligibleRecipients(admin);
  const recipient = recipients.find((candidate) => candidate.userId === targetUserId);
  if (!recipient) throw new Error("Destinataire de test non autorisé.");
  const message = await getReleaseMessage(version, recipient);
  const { data: notification, error: insertError } = await admin
    .from("release_notifications")
    .insert({
      version,
      user_id: recipient.userId,
      email_snapshot: recipient.email,
      delivery_kind: "test",
      status: "sending",
      attempt_count: 1,
      requested_by: requestedBy,
    })
    .select("id")
    .single();
  if (insertError) throw new Error("Impossible de préparer l’e-mail de test.");

  try {
    const result = await sendEmailWithResend({
      to: recipient.email,
      ...message,
      idempotencyKey: `release-test:${version}:${notification.id}`,
    });
    const { error } = await admin.from("release_notifications").update({
      status: "sent",
      provider_message_id: result.providerMessageId,
      sent_at: new Date().toISOString(),
      last_error_safe: null,
    }).eq("id", notification.id).eq("status", "sending").select("id").single();
    if (error) throw new Error("Impossible d’enregistrer l’envoi de test.");
    return { email: recipient.email };
  } catch {
    await admin.from("release_notifications").update({
      status: "failed",
      last_error_safe: SAFE_PROVIDER_ERROR,
    }).eq("id", notification.id).eq("status", "sending");
    throw new Error("L’e-mail de test n’a pas pu être envoyé.");
  }
}

async function reserveGlobalNotification(admin: AdminClient, version: string, recipient: ReleaseRecipient, requestedBy: string) {
  const { data, error } = await admin.from("release_notifications").insert({
    version,
    user_id: recipient.userId,
    email_snapshot: recipient.email,
    delivery_kind: "global",
    status: "sending",
    attempt_count: 1,
    requested_by: requestedBy,
  }).select("id").single();

  if (!error) return { status: "reserved" as const, notificationId: data.id, idempotencyKey: `release:${version}:${recipient.userId}` };
  if (error.code !== "23505") throw new Error("Impossible de réserver la notification de release.");

  const { data: existing, error: existingError } = await admin
    .from("release_notifications")
    .select("id,status,attempt_count")
    .eq("version", version)
    .eq("user_id", recipient.userId)
    .eq("delivery_kind", "global")
    .maybeSingle();
  if (existingError || !existing) throw new Error("Impossible de vérifier la notification existante.");
  if (existing.status !== "failed") return { status: "skipped" as const };

  const { data: retried, error: retryError } = await admin
    .from("release_notifications")
    .update({
      status: "sending",
      email_snapshot: recipient.email,
      attempt_count: existing.attempt_count + 1,
      last_error_safe: null,
      requested_by: requestedBy,
    })
    .eq("id", existing.id)
    .eq("status", "failed")
    .select("id")
    .maybeSingle();
  if (retryError) throw new Error("Impossible de relancer la notification en échec.");
  if (!retried) return { status: "skipped" as const };
  return { status: "reserved" as const, notificationId: retried.id, idempotencyKey: `release:${version}:${recipient.userId}` };
}

export async function sendGlobalReleaseNotifications(version: string) {
  const { userId: requestedBy } = await requirePlatformAdministrator();
  const admin = createAdminClient();
  const recipients = await loadEligibleRecipients(admin);

  return runReleaseNotificationBatch({
    recipients,
    reserve: (recipient) => reserveGlobalNotification(admin, version, recipient, requestedBy),
    send: async (recipient, idempotencyKey) => {
      const message = await getReleaseMessage(version, recipient);
      return sendEmailWithResend({ to: recipient.email, ...message, idempotencyKey });
    },
    markSent: async (notificationId, providerMessageId) => {
      const { error } = await admin.from("release_notifications").update({
        status: "sent",
        provider_message_id: providerMessageId,
        sent_at: new Date().toISOString(),
        last_error_safe: null,
      }).eq("id", notificationId).eq("status", "sending").select("id").single();
      if (error) throw new Error("Impossible d’enregistrer une notification envoyée.");
    },
    markFailed: async (notificationId) => {
      const { error } = await admin.from("release_notifications").update({
        status: "failed",
        last_error_safe: SAFE_PROVIDER_ERROR,
      }).eq("id", notificationId).eq("status", "sending").select("id").single();
      if (error) throw new Error("Impossible d’enregistrer un échec d’envoi.");
    },
  });
}
