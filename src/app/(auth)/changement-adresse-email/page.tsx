import type { Metadata } from "next";
import Link from "next/link";
import { AuthShell } from "@/components/auth/auth-shell";
import { getSafeEmailChangeNextPath } from "@/lib/auth/email-change-confirmation";

export const metadata: Metadata = { title: "Confirmation du changement d’adresse e-mail" };

export default async function EmailChangeConfirmationPage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string | string[]; next?: string | string[] }>;
}) {
  const params = await searchParams;
  const state = typeof params.state === "string" ? params.state : "error";
  const nextPath = getSafeEmailChangeNextPath(typeof params.next === "string" ? params.next : null);

  if (state === "first-confirmed") {
    return (
      <AuthShell title="Première confirmation enregistrée" description="Le changement d’adresse e-mail n’est pas encore terminé.">
        <p className="text-sm leading-6 text-[#475569]">Confirmez maintenant le lien envoyé à l’autre adresse e-mail. Vous pouvez fermer cette page.</p>
        <Link className="button button-secondary mt-5 w-full" href={nextPath}>Retour à PatriGest</Link>
      </AuthShell>
    );
  }

  if (state === "completed") {
    return (
      <AuthShell title="Adresse e-mail modifiée" description="Les deux confirmations ont été validées.">
        <p className="text-sm leading-6 text-[#475569]">Votre nouvelle adresse e-mail est maintenant associée à votre compte PatriGest.</p>
        <Link className="button button-primary mt-5 w-full" href={nextPath}>Retour à PatriGest</Link>
      </AuthShell>
    );
  }

  return (
    <AuthShell title="Confirmation impossible" description="Ce lien de confirmation est invalide ou a expiré.">
      <p className="text-sm leading-6 text-[#475569]">Reconnectez-vous à PatriGest pour vérifier le changement en attente ou renvoyer les confirmations.</p>
      <Link className="button button-primary mt-5 w-full" href="/connexion">Se connecter</Link>
    </AuthShell>
  );
}
