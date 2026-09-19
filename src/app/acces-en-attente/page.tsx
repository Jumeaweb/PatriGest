import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { logoutAction } from "@/app/(auth)/actions";
import { hasRecoverableDossierInvitations } from "@/domains/access/services";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Accès en attente" };
export const dynamic = "force-dynamic";

export default async function AccessWaitingPage() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) redirect("/connexion");

  const [{ data: authorization }, { data: administrator }] = await Promise.all([
    supabase.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle(),
    supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);
  if (administrator || authorization?.status === "active") redirect("/tableau-de-bord");
  let hasInvitationRecovery = false;
  if (authorization?.status === "pending") {
    try {
      hasInvitationRecovery = await hasRecoverableDossierInvitations(userId);
    } catch {
      // L’écran d’attente reste le repli sûr si la reprise est indisponible.
    }
  }
  if (hasInvitationRecovery) redirect("/invitations");

  const rejected = authorization?.status === "rejected";

  return <main className="flex min-h-screen items-center justify-center bg-[#F8FAFC] px-5 py-10">
    <section className="w-full max-w-lg rounded-2xl border border-[#E2E8F0] bg-white p-6 text-center shadow-[0_12px_36px_rgba(15,23,42,0.08)] sm:p-8">
      <p className="text-sm font-semibold text-[#2563EB]">PatriGest</p>
      <h1 className="mt-2 text-2xl font-bold tracking-tight">{rejected ? "Accès non activé" : "Votre inscription est en cours de validation"}</h1>
      <p className="mt-3 text-sm leading-6 text-[#64748B]">
        {rejected
          ? "Votre compte ne dispose pas d’un accès actif à PatriGest."
          : "Votre adresse e-mail a bien été confirmée. Votre inscription doit maintenant être validée avant que vous puissiez accéder à PatriGest."}
      </p>
      {!rejected && <p className="mt-2 text-sm leading-6 text-[#64748B]">Vous recevrez un e-mail dès que votre accès sera activé.</p>}
      <div className="mt-6 flex flex-col justify-center gap-2 sm:flex-row">
        {!rejected && <a href="/tableau-de-bord" className="button button-primary">Vérifier mon accès</a>}
        <form action={logoutAction}><button type="submit" className="button button-secondary">Se déconnecter</button></form>
      </div>
    </section>
  </main>;
}
