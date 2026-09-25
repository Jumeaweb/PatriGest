import type { SharedAccessRole } from "@/types/database";
import { buildBrandedEmailHtml } from "../../lib/email/branded-email.mjs";

export function getInvitationRoleLabel(role: SharedAccessRole) {
  return role === "manager" ? "Gestionnaire" : "Lecture seule";
}

export function getDossierInvitationSentence({
  inviterName,
  dossierName,
}: {
  inviterName: string | null;
  dossierName: string;
}) {
  return `${inviterName || "Un utilisateur PatriGest"} vous invite à accéder au dossier PatriGest de ${dossierName}.`;
}

export function buildDossierInvitationEmail({
  appName,
  inviterName,
  dossierName,
  role,
  invitationUrl,
  expirationLabel,
}: {
  appName: string;
  inviterName: string | null;
  dossierName: string;
  role: SharedAccessRole;
  invitationUrl: string;
  expirationLabel: string;
}) {
  const roleLabel = getInvitationRoleLabel(role);
  const invitationSentence = getDossierInvitationSentence({ inviterName, dossierName });
  return {
    subject: "Invitation à accéder à un dossier PatriGest",
    text: [
      `${invitationSentence.slice(0, -1)} avec le rôle « ${roleLabel} ».`,
      `Cette invitation est valable jusqu’au ${expirationLabel}.`,
      `Accepter l’invitation : ${invitationUrl}`,
    ].join("\n\n"),
    html: buildBrandedEmailHtml({
      appName,
      actionUrl: invitationUrl,
      actionLabel: "Accepter l’invitation",
      eyebrow: "Partage d’un dossier",
      title: "Invitation à accéder à un dossier",
      paragraphs: [
        `${invitationSentence.slice(0, -1)} avec le rôle « ${roleLabel} ».`,
        `Cette invitation est valable jusqu’au ${expirationLabel}.`,
      ],
      footerText: "Si vous n’attendiez pas cette invitation, vous pouvez ignorer ce message.",
    }),
  };
}
