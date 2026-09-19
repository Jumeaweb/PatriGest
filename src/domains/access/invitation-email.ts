import "server-only";

import { Resend } from "resend";
import { APP_NAME } from "@/lib/app";
import type { SharedAccessRole } from "@/types/database";
import { buildDossierInvitationEmail } from "./invitation-presentation";

export async function sendDossierInvitationEmail({
  email,
  role,
  inviterName,
  dossierName,
  invitationUrl,
  expiresAt,
}: {
  email: string;
  role: SharedAccessRole;
  inviterName: string | null;
  dossierName: string;
  invitationUrl: string;
  expiresAt: string;
}) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) throw new Error("RESEND_API_KEY absente.");

  const expirationLabel = new Intl.DateTimeFormat("fr-FR", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Paris",
  }).format(new Date(expiresAt));
  const content = buildDossierInvitationEmail({
    appName: APP_NAME,
    inviterName,
    dossierName,
    role,
    invitationUrl,
    expirationLabel,
  });
  const resend = new Resend(apiKey);
  const { error } = await resend.emails.send({
    from: `${APP_NAME} <noreply@patrigest.fr>`,
    to: email,
    subject: content.subject,
    text: content.text,
    html: content.html,
  });

  if (error) throw new Error("Échec de l’envoi Resend.");
}
