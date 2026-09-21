import "server-only";

import { Resend } from "resend";
import { APP_NAME } from "@/lib/app";

export type OutgoingEmail = {
  to: string;
  subject: string;
  text: string;
  html: string;
  idempotencyKey?: string;
};

export async function sendEmailWithResend(message: OutgoingEmail) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) throw new Error("RESEND_API_KEY absente.");

  const resend = new Resend(apiKey);
  const { data, error } = await resend.emails.send({
    from: `${APP_NAME} <noreply@patrigest.fr>`,
    to: message.to,
    subject: message.subject,
    text: message.text,
    html: message.html,
  }, message.idempotencyKey ? { idempotencyKey: message.idempotencyKey } : undefined);

  if (error) throw new Error("Échec de l’envoi Resend.");
  return { providerMessageId: data?.id ?? null };
}
