import type { Metadata } from "next";
import { ShieldCheck } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { PasswordForm } from "@/domains/account/components/password-form";
import { ProfileForm } from "@/domains/account/components/profile-form";
import { getAccountData } from "@/domains/account/services";

export const metadata: Metadata = { title: "Mon compte" };
export const dynamic = "force-dynamic";

export default async function AccountPage() {
  const account = await getAccountData();
  return <PrivateShell current="account">
    <div className="mx-auto max-w-3xl">
      <AppBreadcrumb items={[{ label: "Tableau de bord", href: "/tableau-de-bord" }, { label: "Mon compte" }]} />
      <header><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">Espace personnel</p><h1 className="mt-1 font-bold tracking-tight">Mon compte</h1><p className="mt-1 text-sm text-[#64748B]">Gérez vos informations personnelles et la sécurité de votre compte.</p></header>
      <div className="mt-5 space-y-4">
        <AccountCard title="Profil" description="Vos informations personnelles utilisées dans PatriGest."><ProfileForm firstName={account.firstName} lastName={account.lastName} email={account.email} /></AccountCard>
        <AccountCard title="Sécurité" description="Choisissez un nouveau mot de passe pour votre compte."><PasswordForm /></AccountCard>
        <AccountCard title="Compte" description="Informations relatives à votre accès PatriGest.">
          <dl className="mt-4 grid gap-3 sm:grid-cols-2"><div className="rounded-xl bg-slate-50 px-3.5 py-3"><dt className="text-xs font-semibold text-[#64748B]">Statut</dt><dd className="mt-1 text-sm font-bold text-[#166534]">Compte actif</dd></div>{account.isPlatformAdmin && <div className="rounded-xl bg-blue-50 px-3.5 py-3"><dt className="text-xs font-semibold text-[#64748B]">Rôle</dt><dd className="mt-1 flex items-center gap-2 text-sm font-bold text-[#1D4ED8]"><ShieldCheck aria-hidden="true" size={16} />Administrateur PatriGest</dd></div>}</dl>
        </AccountCard>
      </div>
    </div>
  </PrivateShell>;
}

function AccountCard({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return <section className="rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-[0_8px_24px_rgba(15,23,42,0.04)] sm:p-5"><h2 className="text-lg font-bold">{title}</h2><p className="mt-1 text-xs text-[#64748B]">{description}</p>{children}</section>;
}
