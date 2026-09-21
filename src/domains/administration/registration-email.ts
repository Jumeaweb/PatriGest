import "server-only";

import { APP_NAME } from "@/lib/app";
import { getApplicationOrigin } from "@/lib/auth/redirects";
import { sendEmailWithResend } from "@/lib/email/resend-transport";
import { buildApplicationActivationEmail } from "./registration-email-presentation";

export async function sendApplicationActivationEmail({ email, firstName }: { email: string; firstName: string }) {
  const loginUrl = `${await getApplicationOrigin()}/connexion`;
  const content = buildApplicationActivationEmail({ appName: APP_NAME, firstName, loginUrl });
  await sendEmailWithResend({ to: email, ...content });
}
