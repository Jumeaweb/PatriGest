import type { LucideIcon } from "lucide-react";
import { Mail, ShieldCheck, Trash2, UserRound } from "lucide-react";
import type { Metadata } from "next";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getAccountView } from "@/domains/account/account-navigation";
import { AccountDeletionForm } from "@/domains/account/components/account-deletion-form";
import { AccountNavigation } from "@/domains/account/components/account-navigation";
import { EmailForm } from "@/domains/account/components/email-form";
import { PasswordForm } from "@/domains/account/components/password-form";
import { ProfileForm } from "@/domains/account/components/profile-form";
import { getAccountData } from "@/domains/account/services";

export const metadata: Metadata = { title: "Mon compte" };
export const dynamic = "force-dynamic";

export default async function AccountPage({
  searchParams,
}: {
  searchParams: Promise<{ vue?: string | string[] }>;
}) {
  const [account, query] = await Promise.all([getAccountData(), searchParams]);
  const current = getAccountView(query.vue);

  return (
    <PrivateShell current="account">
      <div className="mx-auto max-w-3xl">
        <AppBreadcrumb items={[{ label: "Tableau de bord", href: "/tableau-de-bord" }, { label: "Mon compte" }]} />
        <header>
          <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">Espace personnel</p>
          <h1 className="mt-1 font-bold tracking-tight">Mon compte</h1>
          <p className="mt-1 text-sm text-[#64748B]">Gérez vos informations personnelles et la sécurité de votre compte.</p>
        </header>

        <AccountNavigation current={current} />

        <div className="mt-5">
          {current === "profile" && (
            <AccountCard icon={UserRound} title="Profil" description="Vos informations personnelles utilisées dans PatriGest.">
              <ProfileForm firstName={account.firstName} lastName={account.lastName} />
              <dl className="mt-5 grid gap-3 border-t border-[#E2E8F0] pt-4 sm:grid-cols-2">
                <div className="rounded-xl bg-slate-50 px-3.5 py-3">
                  <dt className="text-xs font-semibold text-[#64748B]">Statut</dt>
                  <dd className="mt-1 text-sm font-bold text-[#166534]">Compte actif</dd>
                </div>
                {account.isPlatformAdmin && (
                  <div className="rounded-xl bg-blue-50 px-3.5 py-3">
                    <dt className="text-xs font-semibold text-[#64748B]">Rôle</dt>
                    <dd className="mt-1 flex items-center gap-2 text-sm font-bold text-[#1D4ED8]"><ShieldCheck aria-hidden="true" size={16} />Administrateur PatriGest</dd>
                  </div>
                )}
              </dl>
            </AccountCard>
          )}

          {current === "email" && (
            <AccountCard icon={Mail} title="Adresse e-mail" description="Modifiez l’adresse utilisée pour vous connecter à PatriGest.">
              <EmailForm currentEmail={account.email} pendingEmail={account.pendingEmail} />
            </AccountCard>
          )}

          {current === "security" && (
            <AccountCard icon={ShieldCheck} title="Sécurité" description="Choisissez un nouveau mot de passe pour votre compte.">
              <PasswordForm />
            </AccountCard>
          )}

          {current === "deletion" && (
            <section className="rounded-2xl border border-red-200 bg-white p-4 shadow-[0_8px_24px_rgba(127,29,29,0.05)] sm:p-5">
              <div className="flex items-start gap-3">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-red-50 text-[#B91C1C]"><Trash2 aria-hidden="true" size={19} /></span>
                <div>
                  <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#B91C1C]">Zone dangereuse</p>
                  <h2 className="mt-1 text-lg font-bold">Supprimer mon compte</h2>
                </div>
              </div>
              <div className="mt-3 space-y-2 text-sm leading-6 text-[#64748B]">
                <p>Cette opération est irréversible. Votre compte de connexion, votre profil et vos accès aux dossiers partagés seront supprimés.</p>
                <p>Les références vous concernant sont détachées ou anonymisées lorsque cela est nécessaire. Les dossiers, opérations, rapports, snapshots, PDF et justificatifs utiles à l’historique métier sont conservés.</p>
                <p>La suppression est impossible tant que vous possédez un dossier. Vous devez d’abord le transférer ou le supprimer. Un administrateur PatriGest ne peut pas supprimer son propre compte.</p>
              </div>
              <AccountDeletionForm eligibility={account.deletionEligibility} />
            </section>
          )}
        </div>
      </div>
    </PrivateShell>
  );
}

function AccountCard({ icon: Icon, title, description, children }: { icon: LucideIcon; title: string; description: string; children: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-[0_8px_24px_rgba(15,23,42,0.04)] sm:p-5">
      <div className="flex items-start gap-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-navigation/35 text-brand-foreground"><Icon aria-hidden="true" size={19} /></span>
        <div><h2 className="text-lg font-bold">{title}</h2><p className="mt-1 text-xs text-[#64748B]">{description}</p></div>
      </div>
      {children}
    </section>
  );
}
