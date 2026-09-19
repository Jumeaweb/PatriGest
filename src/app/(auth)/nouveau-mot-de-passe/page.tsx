import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { UpdatePasswordForm } from "@/components/auth/auth-forms";

export const metadata: Metadata = { title: "Nouveau mot de passe" };

export default async function UpdatePasswordPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  return <AuthShell title="Nouveau mot de passe" description="Choisissez un mot de passe robuste et unique."><UpdatePasswordForm nextPath={next} /></AuthShell>;
}
