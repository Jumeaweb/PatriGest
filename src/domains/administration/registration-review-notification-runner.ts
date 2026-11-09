export type RegistrationNotificationReservation =
  | { status: "reserved"; idempotencyKey: string }
  | { status: "skipped" };

export async function runRegistrationReviewNotificationDelivery({ reserve, send, markSent, markFailed }: {
  reserve: () => Promise<RegistrationNotificationReservation>;
  send: (idempotencyKey: string) => Promise<{ providerMessageId: string | null }>;
  markSent: (providerMessageId: string | null) => Promise<void>;
  markFailed: () => Promise<void>;
}) {
  const reservation = await reserve();
  if (reservation.status === "skipped") return "skipped" as const;

  try {
    const result = await send(reservation.idempotencyKey);
    await markSent(result.providerMessageId);
    return "sent" as const;
  } catch {
    try {
      await markFailed();
    } catch {
      // L'erreur reste volontairement contenue : le parcours Auth est prioritaire.
    }
    return "failed" as const;
  }
}
