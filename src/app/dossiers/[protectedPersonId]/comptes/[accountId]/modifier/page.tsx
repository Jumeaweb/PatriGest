import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { FinancialAccountForm } from "@/domains/financial-accounts/components/financial-account-form";
import { getFinancialAccount } from "@/domains/financial-accounts/services/financial-account-service";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Modifier un compte" };
export const dynamic = "force-dynamic";

export default async function EditFinancialAccountPage({ params }: { params: Promise<{ protectedPersonId: string; accountId: string }> }) {
  const { protectedPersonId, accountId } = await params;
  if (![protectedPersonId, accountId].every((id) => z.uuid().safeParse(id).success)) notFound();
  const [person, account] = await Promise.all([getProtectedPerson(protectedPersonId), getFinancialAccount(accountId)]);
  if (!person || person.accessRole === "read_only" || !account || account.protected_person_id !== protectedPersonId) notFound();
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "accounts" }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Comptes et patrimoine", href: `/dossiers/${protectedPersonId}/comptes` }, { label: account.account_name, href: `/dossiers/${protectedPersonId}/comptes/${accountId}` }, { label: "Modifier" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Modifier le compte</h1>
    <DossierNavigation protectedPersonId={protectedPersonId} current="accounts" />
    <FinancialNavigation protectedPersonId={protectedPersonId} accountId={accountId} current="details" />
    <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-sm sm:p-5"><FinancialAccountForm protectedPersonId={protectedPersonId} account={account} /></section>
  </PrivateShell>;
}
