import type { SharedAccessRole } from "@/types/database";

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

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
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
    html: `
      <div style="font-family:Arial,sans-serif;color:#0f172a;line-height:1.6">
        <h1 style="font-size:22px">${escapeHtml(appName)}</h1>
        <p>${escapeHtml(invitationSentence.slice(0, -1))} avec le rôle « <strong>${escapeHtml(roleLabel)}</strong> ».</p>
        <p>Cette invitation est valable jusqu’au ${escapeHtml(expirationLabel)}.</p>
        <p style="margin:24px 0">
          <a href="${escapeHtml(invitationUrl)}" style="display:inline-block;border-radius:10px;background:#2563eb;color:#fff;padding:11px 18px;text-decoration:none;font-weight:700">Accepter l’invitation</a>
        </p>
        <p style="font-size:12px;color:#64748b">Si vous n’attendiez pas cette invitation, vous pouvez ignorer ce message.</p>
      </div>
    `,
  };
}
