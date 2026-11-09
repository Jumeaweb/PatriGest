import { buildBrandedEmailHtml } from "../../lib/email/branded-email.mjs";

export const REGISTRATION_REJECTION_NOTIFICATION_SUBJECT = "PatriGest — Réponse à votre demande d'inscription";
export const REGISTRATION_REJECTION_SUPPORT_EMAIL = "support@jumeaweb.fr";

export function buildRegistrationRejectionNotification() {
  const greeting = "Bonjour,";
  const refusal = "Nous vous informons que votre demande d'inscription à PatriGest n'a pas été acceptée.";
  const access = "Votre compte ne sera donc pas activé et aucun essai gratuit ne sera démarré.";
  const support = `Pour toute question concernant cette décision, vous pouvez contacter notre équipe à ${REGISTRATION_REJECTION_SUPPORT_EMAIL}.`;
  const signature = "L'équipe PatriGest\nÉdité par Jumeaweb";

  return {
    subject: REGISTRATION_REJECTION_NOTIFICATION_SUBJECT,
    text: [greeting, refusal, access, support, "Cordialement,", signature].join("\n\n"),
    html: buildBrandedEmailHtml({
      appName: "PatriGest",
      logoBaseUrl: "https://patrigest.fr/",
      actionUrl: `mailto:${REGISTRATION_REJECTION_SUPPORT_EMAIL}`,
      actionLabel: "Contacter le support",
      greeting,
      eyebrow: "Demande d'inscription",
      title: "Réponse à votre demande d'inscription",
      paragraphs: [refusal, access, support, "Cordialement,\nL'équipe PatriGest\nÉdité par Jumeaweb"],
    }),
  };
}
