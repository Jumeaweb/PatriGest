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
import { SuccessiveTransactionEntry } from "@/domains/transactions/components/successive-transaction-entry";
import { getSafeTransactionReturnTo } from "@/domains/transactions/return-to";
import { isSuccessiveAccountEligible } from "@/domains/transactions/successive-entry";

export const metadata: Metadata = { title: "Saisie successive" };
export const dynamic = "force-dynamic";

export default async function SuccessiveEntryPage({ params, searchParams }: {
  params: Promise<{ protectedPersonId: string }>;
  searchParams: Promise<{ account?: string | string[]; returnTo?: string | string[] }>;
}) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person || person.accessRole === "read_only") notFound();
  const [accounts, categories] = await Promise.all([getFinancialAccounts(protectedPersonId), getCategories(false)]);
  const search = await searchParams;
  if (search.account !== undefined && (typeof search.account !== "string" || !accounts.some((account) => account.id === search.account && isSuccessiveAccountEligible(account)))) notFound();
  const requestedAccount = typeof search.account === "string" && accounts.find((account) => account.id === search.account && isSuccessiveAccountEligible(account));
  const accountId = requestedAccount ? requestedAccount.id : undefined;
  const returnHref = getSafeTransactionReturnTo(protectedPersonId, typeof search.returnTo === "string" ? search.returnTo : undefined, accountId);
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "operations", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Opérations", href: returnHref }, { label: "Saisie successive" }]} />
    <h1 className="mt-1 text-2xl font-bold">Saisie successive</h1>
    <p className="mt-1 text-sm text-[#64748B]">Enregistrez une recette ou une dépense, puis passez à la suivante sans quitter cette page.</p>
    <DossierNavigation protectedPersonId={protectedPersonId} current="operations" />
    <FinancialNavigation protectedPersonId={protectedPersonId} accountId={accountId} current="operations" />
    <SuccessiveTransactionEntry personId={protectedPersonId} accounts={accounts} categories={categories} defaultAccountId={accountId} returnHref={returnHref} />
  </PrivateShell>;
}
