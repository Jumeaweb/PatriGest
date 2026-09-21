import type { AppRelease } from "@/lib/releases";

function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character] ?? character);
}

export function buildReleaseEmail({ appName, release, changelogUrl, recipient }: {
  appName: string;
  release: AppRelease;
  changelogUrl: string;
  recipient: { firstName?: string | null; lastName?: string | null };
}) {
  const firstName = recipient.firstName?.trim() ?? "";
  const lastName = recipient.lastName?.trim() ?? "";
  const fullName = [firstName, lastName].filter(Boolean).join(" ");
  const greeting = fullName ? `Bonjour ${fullName},` : "Bonjour,";
  const introduction = `Voici les nouveautés de la version ${appName} v${release.version}.`;
  const subject = `${appName} v${release.version} — Découvrez les nouveautés`;
  const text = [
    greeting,
    introduction,
    release.title,
    release.summary,
    ...release.changes.map((change) => `• ${change}`),
    `Découvrir toutes les nouveautés : ${changelogUrl}`,
  ].join("\n\n");
  const changes = release.changes
    .map((change) => `<li style="margin:0 0 8px">${escapeHtml(change)}</li>`)
    .join("");
  const html = `
    <div style="font-family:Arial,sans-serif;color:#0f172a;line-height:1.6">
      <p>${escapeHtml(greeting)}</p>
      <p style="font-weight:700;color:#2563eb">${escapeHtml(introduction)}</p>
      <h1 style="font-size:22px;line-height:1.3">${escapeHtml(release.title)}</h1>
      <p>${escapeHtml(release.summary)}</p>
      <ul style="padding-left:20px">${changes}</ul>
      <p style="margin:24px 0">
        <a href="${escapeHtml(changelogUrl)}" style="display:inline-block;border-radius:10px;background:#2563eb;color:#fff;padding:11px 18px;text-decoration:none;font-weight:700">Voir toutes les nouveautés</a>
      </p>
      <p style="font-size:12px;color:#64748b">La gestion claire du patrimoine protégé.</p>
    </div>
  `;

  return { subject, text, html };
}
