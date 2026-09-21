import type { ReleaseRecipient } from "./release-notification-policy";

export const RELEASE_NOTIFICATION_BATCH_SIZE = 10;

export type ReleaseSendSummary = {
  recipients: number;
  alreadySent: number;
  sent: number;
  failed: number;
};

type Reservation =
  | { status: "reserved"; notificationId: string; idempotencyKey: string }
  | { status: "skipped" };

export async function runReleaseNotificationBatch({ recipients, reserve, send, markSent, markFailed }: {
  recipients: readonly ReleaseRecipient[];
  reserve: (recipient: ReleaseRecipient) => Promise<Reservation>;
  send: (recipient: ReleaseRecipient, idempotencyKey: string) => Promise<{ providerMessageId: string | null }>;
  markSent: (notificationId: string, providerMessageId: string | null) => Promise<void>;
  markFailed: (notificationId: string) => Promise<void>;
}): Promise<ReleaseSendSummary> {
  const summary: ReleaseSendSummary = { recipients: recipients.length, alreadySent: 0, sent: 0, failed: 0 };

  for (let offset = 0; offset < recipients.length; offset += RELEASE_NOTIFICATION_BATCH_SIZE) {
    const batch = recipients.slice(offset, offset + RELEASE_NOTIFICATION_BATCH_SIZE);
    for (const recipient of batch) {
      const reservation = await reserve(recipient);
      if (reservation.status === "skipped") {
        summary.alreadySent += 1;
        continue;
      }
      try {
        const result = await send(recipient, reservation.idempotencyKey);
        await markSent(reservation.notificationId, result.providerMessageId);
        summary.sent += 1;
      } catch {
        await markFailed(reservation.notificationId);
        summary.failed += 1;
      }
    }
  }

  return summary;
}
