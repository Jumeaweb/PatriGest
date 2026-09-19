import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthShell } from "@/components/auth/auth-shell";
import { acceptRecoveredDossierInvitationAction } from "@/domains/access/actions";
import { getRecoverableDossierInvitations } from "@/domains/access/services";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Invitations en attente" };
export const dynamic = "force-dynamic";

export default async function PendingInvitationsPage() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) redirect("/connexion?next=%2Finvitations");

  const invitations = await getRecoverableDossierInvitations(userId);
  if (!invitations.length) {
    const { data: authorization } = await supabase.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle();
    redirect(authorization?.status === "active" ? "/tableau-de-bord" : "/acces-en-attente");
  }

  return <AuthShell
    title={invitations.length === 1 ? "Votre invitation" : "Vos invitations"}
    description={invitations.length === 1
      ? "Acceptez cette invitation pour activer votre accès au dossier."
      : "Plusieurs dossiers vous sont proposés. Choisissez explicitement l’invitation à accepter."}
  >
    <div className="space-y-3">
      {invitations.map((invitation) => <article className="rounded-xl border border-[#E2E8F0] p-4" key={invitation.id}>
        <h2 className="font-bold text-[#0F172A]">{invitation.dossierName}</h2>
        <p className="mt-1 text-sm text-[#64748B]">Rôle proposé : {invitation.role === "manager" ? "Gestionnaire" : "Lecture seule"}</p>
        {invitation.inviterName && <p className="mt-1 text-sm text-[#64748B]">Invitation envoyée par {invitation.inviterName}</p>}
        <form action={acceptRecoveredDossierInvitationAction.bind(null, invitation.id)}>
          <button className="button button-primary mt-3 w-full" type="submit">Accepter cette invitation</button>
        </form>
      </article>)}
    </div>
  </AuthShell>;
}
