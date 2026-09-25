import type { AppRelease } from "@/lib/releases";
import { buildBrandedEmailHtml } from "../../lib/email/branded-email.mjs";

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
  const html = buildBrandedEmailHtml({
    appName,
    actionUrl: changelogUrl,
    actionLabel: "Voir toutes les nouveautés",
    greeting,
    eyebrow: introduction,
    title: release.title,
    paragraphs: [release.summary],
    items: release.changes,
  });

  return { subject, text, html };
}
