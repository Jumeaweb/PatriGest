import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { logoutAction } from "@/app/(auth)/actions";
import { AuthShell } from "@/components/auth/auth-shell";
import { InvitationDecisionActions } from "@/domains/access/components/invitation-decision-actions";
import { getRecoverableDossierInvitations } from "@/domains/access/services";
import { getInvitationRoleLabel } from "@/domains/access/invitation-presentation";
import { selectRecoverableInvitations } from "@/lib/auth/invitation-recovery";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Invitations en attente" };
export const dynamic = "force-dynamic";

export default async function PendingInvitationsPage({ searchParams }: { searchParams: Promise<{ invitation?: string }> }) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) redirect("/connexion?next=%2Finvitations");

  const invitations = await getRecoverableDossierInvitations(userId).catch(() => null);
  if (!invitations) {
    return <AuthShell title="Vérification des invitations indisponible" description="Réessayez dans quelques instants ou ouvrez le lien reçu par e-mail.">
      <Link className="button button-primary" href="/invitations" prefetch={false}>Réessayer</Link>
    </AuthShell>;
  }
  if (!invitations.length) {
    const { data: authorization } = await supabase.from("application_user_authorizations").select("status,registration_intent").eq("user_id", userId).maybeSingle();
    return <AuthShell
      title="Aucune invitation active"
      description="Vérifiez l’adresse utilisée pour vous connecter. Si l’invitation a expiré ou a été annulée, demandez un nouveau lien au propriétaire du dossier."
    >
      {authorization?.status === "active" && <Link className="button button-primary" href="/tableau-de-bord">Retour au tableau de bord</Link>}
      {authorization?.status === "pending" && authorization.registration_intent === "autonomous" && <Link className="button button-primary" href="/acces-en-attente">Voir l’état de mon inscription</Link>}
      <form action={logoutAction}><button className="button button-secondary" type="submit">Se déconnecter pour changer de compte</button></form>
    </AuthShell>;
  }
  const { invitation: preferredInvitationId } = await searchParams;
  const displayedInvitations = selectRecoverableInvitations(invitations, preferredInvitationId);

  return <AuthShell
    title={displayedInvitations.length === 1 ? "Votre invitation" : "Vos invitations"}
    description={displayedInvitations.length === 1
      ? "Acceptez cette invitation pour activer votre accès au dossier."
      : "Plusieurs dossiers vous sont proposés. Choisissez explicitement l’invitation à accepter."}
  >
    <div className="space-y-3">
      {displayedInvitations.map((invitation) => <article className="rounded-xl border border-[#E2E8F0] p-4" key={invitation.id}>
        <h2 className="font-bold text-[#0F172A]">{invitation.inviterName || "Un utilisateur PatriGest"}</h2>
        <p className="mt-1 text-sm text-[#64748B]">vous invite au dossier de <strong className="text-[#334155]">{invitation.dossierName}</strong></p>
        <p className="mt-1 text-sm text-[#64748B]">Rôle proposé : {getInvitationRoleLabel(invitation.role)}</p>
        <InvitationDecisionActions reference={{ invitationId: invitation.id }} acceptLabel="Accepter cette invitation" />
      </article>)}
    </div>
  </AuthShell>;
}
