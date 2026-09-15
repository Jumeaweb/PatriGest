import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { FinancialAccountForm } from "@/domains/financial-accounts/components/financial-account-form";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Ajouter un compte" };
export const dynamic = "force-dynamic";

export default async function NewFinancialAccountPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person || person.accessRole === "read_only") notFound();
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "accounts", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Comptes et patrimoine", href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Nouveau compte" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Ajouter un compte</h1>
    <DossierNavigation protectedPersonId={protectedPersonId} current="accounts" />
    <FinancialNavigation protectedPersonId={protectedPersonId} current="accounts" />
    <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-sm sm:p-5"><FinancialAccountForm protectedPersonId={protectedPersonId} /></section>
  </PrivateShell>;
}
