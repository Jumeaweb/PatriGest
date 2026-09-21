import "server-only";

import { APP_NAME } from "@/lib/app";
import { sendEmailWithResend } from "@/lib/email/resend-transport";
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
  await sendEmailWithResend({
    to: email,
    subject: content.subject,
    text: content.text,
    html: content.html,
  });
}
