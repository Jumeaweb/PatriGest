import { buildBrandedEmailHtml } from "../../lib/email/branded-email.mjs";

export const REGISTRATION_REVIEW_NOTIFICATION_RECIPIENT = "support@jumeaweb.fr";
export const REGISTRATION_REVIEW_NOTIFICATION_SUBJECT = "PatriGest — Nouvelle inscription à valider";
export const REGISTRATION_REVIEW_URL = "https://patrigest.fr/administration/inscriptions";

export function buildRegistrationReviewNotification({
  firstName,
  lastName,
  email,
  requestedAt,
}: {
  firstName: string;
  lastName: string;
  email: string;
  requestedAt: string;
}) {
  const fullName = [firstName.trim(), lastName.trim()].filter(Boolean).join(" ") || "Nom non renseigné";
  const requestedAtLabel = new Intl.DateTimeFormat("fr-FR", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/Paris",
  }).format(new Date(requestedAt));
  const paragraphs = [
    `Nom : ${fullName}`,
    `Adresse e-mail : ${email}`,
    `Date de la demande : ${requestedAtLabel}`,
  ];

  return {
    subject: REGISTRATION_REVIEW_NOTIFICATION_SUBJECT,
    text: [
      "Une nouvelle inscription autonome confirmée attend la validation administrative Jumeaweb.",
      ...paragraphs,
      `Examiner l’inscription : ${REGISTRATION_REVIEW_URL}`,
    ].join("\n\n"),
    html: buildBrandedEmailHtml({
      appName: "PatriGest",
      actionUrl: REGISTRATION_REVIEW_URL,
      actionLabel: "Examiner l’inscription",
      eyebrow: "Administration",
      title: "Nouvelle inscription à valider",
      paragraphs: [
        "Une nouvelle inscription autonome confirmée attend votre validation.",
        ...paragraphs,
      ],
    }),
  };
}
