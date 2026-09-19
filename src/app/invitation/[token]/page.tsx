import Link from "next/link";
import { AuthShell } from "@/components/auth/auth-shell";
import { acceptDossierInvitationAction, continueDossierInvitationAsIntendedUserAction } from "@/domains/access/actions";
import { getInvitationPreview } from "@/domains/access/services";
import { getDossierInvitationSentence, getInvitationRoleLabel } from "@/domains/access/invitation-presentation";
import { getDossierInvitationLoginPath } from "@/lib/auth/invitation-destination";
import { createClient } from "@/lib/supabase/server";
export const dynamic = "force-dynamic";
export default async function InvitationPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const result = await getInvitationPreview(token);
  if (result.status !== "pending") {
    const description = result.status === "expired"
      ? "Cette invitation a expiré. Demandez à la personne qui vous a invité de vous en envoyer une nouvelle."
      : result.status === "revoked"
        ? "Cette invitation a été annulée."
        : result.status === "accepted"
          ? "Cette invitation a déjà été utilisée."
          : result.status === "error"
            ? "Impossible de vérifier l’invitation pour le moment. Réessayez plus tard."
            : "Ce lien d’invitation est invalide.";
    return <AuthShell title="Invitation indisponible" description={description}><Link className="auth-back-link" href="/">Retour à l’accueil</Link></AuthShell>;
  }

  const invitation = result.invitation;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const connectedEmail = typeof claims?.claims?.email === "string" ? claims.claims.email : null;
  return <AuthShell title="Invitation à un dossier" description={getDossierInvitationSentence(invitation)}><p className="rounded-xl bg-blue-50 p-3 text-sm text-[#334155]">Rôle proposé : <strong>{getInvitationRoleLabel(invitation.role)}</strong></p>{connectedEmail ? connectedEmail.toLowerCase() === invitation.email.toLowerCase() ? <form action={acceptDossierInvitationAction.bind(null, token)}><button className="button button-primary mt-4 w-full" type="submit">Accepter l’invitation</button></form> : <div className="mt-4 space-y-3"><p className="text-sm text-red-700">Cette invitation est destinée à {invitation.email}. Connectez-vous avec cette adresse.</p><form action={continueDossierInvitationAsIntendedUserAction.bind(null, token)}><button className="button button-primary w-full" type="submit">Se déconnecter et continuer avec {invitation.email}</button></form></div> : <div className="mt-4 space-y-3"><Link className="button button-primary w-full" href={getDossierInvitationLoginPath(token)}>J’ai déjà un compte</Link><Link className="button button-secondary w-full" href={`/inscription?token=${encodeURIComponent(token)}`}>Créer ou finaliser mon compte</Link></div>}</AuthShell>;
}
