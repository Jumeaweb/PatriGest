import { buildBrandedEmailHtml } from "../../lib/email/branded-email.mjs";

export function buildApplicationActivationEmail({ appName, firstName, lastName, loginUrl }: {
  appName: string;
  firstName: string;
  lastName: string;
  loginUrl: string;
}) {
  const fullName = [firstName.trim(), lastName.trim()].filter(Boolean).join(" ");
  const greeting = fullName ? `Bonjour ${fullName},` : "Bonjour,";
  return {
    subject: "Votre accès à PatriGest est activé",
    text: [
      greeting,
      `Votre inscription à ${appName} a été validée.`,
      "Vous pouvez maintenant vous connecter et commencer à utiliser l’application.",
      `Se connecter à PatriGest : ${loginUrl}`,
      "La gestion claire du patrimoine protégé.",
    ].join("\n\n"),
    html: buildBrandedEmailHtml({
      appName,
      actionUrl: loginUrl,
      actionLabel: "Se connecter à PatriGest",
      greeting,
      eyebrow: "Accès à PatriGest",
      title: "Votre accès est activé",
      paragraphs: [
        `Votre inscription à ${appName} a été validée.`,
        "Vous pouvez maintenant vous connecter et commencer à utiliser l’application.",
      ],
    }),
  };
}
