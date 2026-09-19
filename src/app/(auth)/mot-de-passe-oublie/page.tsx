import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { ForgotPasswordForm } from "@/components/auth/auth-forms";

export const metadata: Metadata = { title: "Mot de passe oublié" };

export default async function ForgotPasswordPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  return <AuthShell title="Mot de passe oublié" description="Recevez un lien sécurisé pour choisir un nouveau mot de passe."><ForgotPasswordForm nextPath={next} /></AuthShell>;
}
