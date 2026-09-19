import type { Metadata } from "next";
import { AuthShell } from "@/components/auth/auth-shell";
import { SignupForm } from "@/components/auth/auth-forms";
import { validateSignupInvitation } from "@/domains/access/actions";
import { getDossierInvitationSentence, getInvitationRoleLabel } from "@/domains/access/invitation-presentation";

export const metadata: Metadata = { title: "Créer un compte" };

export default async function SignupPage({ searchParams }: { searchParams: Promise<{ token?: string }> }) {
  const { token } = await searchParams;
  if (!token) {
    return <AuthShell title="Créer votre compte PatriGest" description="PatriGest est actuellement accessible sur validation. Créez votre compte ci-dessous. Après confirmation de votre adresse e-mail, votre inscription sera examinée avant l’activation de votre accès."><SignupForm /></AuthShell>;
  }

  const invitation = await validateSignupInvitation(token);
  if (!invitation) return <AuthShell title="Invitation invalide" description="Ce lien d’inscription n’est plus disponible."><p className="text-sm leading-6 text-[#64748B]">Cette invitation est invalide, expirée ou a déjà été utilisée. Vous pouvez créer un compte sans invitation ou vous connecter si vous êtes déjà inscrit.</p><div className="mt-4 flex flex-wrap gap-3"><a className="button button-primary" href="/inscription">Créer un compte</a><a className="button button-secondary" href="/connexion">Se connecter</a></div></AuthShell>;
  const description = invitation.kind === "dossier"
    ? `${getDossierInvitationSentence(invitation)} Rôle proposé : ${getInvitationRoleLabel(invitation.role)}.`
    : "Votre invitation a été vérifiée. Créez votre compte puis confirmez votre adresse e-mail.";
  return <AuthShell title="Créer votre compte PatriGest" description={description}><SignupForm invitationToken={token} email={invitation.email} firstName={invitation.first_name} lastName={invitation.last_name} /></AuthShell>;
}
