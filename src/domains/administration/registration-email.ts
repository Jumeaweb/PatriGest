import "server-only";

import { APP_NAME } from "@/lib/app";
import { getApplicationOrigin } from "@/lib/auth/redirects";
import { sendEmailWithResend } from "@/lib/email/resend-transport";
import { buildApplicationActivationEmail } from "./registration-email-presentation";

export async function sendApplicationActivationEmail({ email, firstName, lastName }: { email: string; firstName: string; lastName: string }) {
  const loginUrl = `${await getApplicationOrigin()}/connexion`;
  const content = buildApplicationActivationEmail({ appName: APP_NAME, firstName, lastName, loginUrl });
  await sendEmailWithResend({ to: email, ...content });
}
