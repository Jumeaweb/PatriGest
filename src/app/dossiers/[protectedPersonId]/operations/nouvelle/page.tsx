import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { getCategories } from "@/domains/categories/services/category-service";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { TransactionForm } from "@/domains/transactions/components/transaction-form";

export const metadata: Metadata = { title: "Nouvelle opération" };
export const dynamic = "force-dynamic";

export default async function NewOperationPage({ params, searchParams }: { params: Promise<{ protectedPersonId: string }>; searchParams: Promise<{ account?: string | string[]; mode?: string | string[] }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person || person.accessRole === "read_only") notFound();
  const [accounts, categories] = await Promise.all([getFinancialAccounts(protectedPersonId), getCategories(false)]);
  const search = await searchParams;
  const requestedAccountId = typeof search.account === "string" && accounts.some((account) => account.id === search.account) ? search.account : undefined;
  const requestedMode = search.mode === "transfer" ? "transfer" : undefined;
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "operations" }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Opérations", href: `/dossiers/${protectedPersonId}/operations` }, { label: "Nouvelle opération" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Ajouter une opération</h1>
    <DossierNavigation protectedPersonId={protectedPersonId} current="operations" />
    <FinancialNavigation protectedPersonId={protectedPersonId} accountId={requestedAccountId} current="operations" />
    <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5"><TransactionForm personId={protectedPersonId} accounts={accounts} categories={categories} defaultAccountId={requestedAccountId} defaultMode={requestedMode} /></section>
  </PrivateShell>;
}
