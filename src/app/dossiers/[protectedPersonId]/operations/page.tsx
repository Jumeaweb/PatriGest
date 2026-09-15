import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { getCategories } from "@/domains/categories/services/category-service";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { formatCurrency, getCurrentPatrimonyValue } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { TransactionFilters } from "@/domains/transactions/components/transaction-filters";
import { TransactionJournal } from "@/domains/transactions/components/transaction-journal";
import { TransactionQuickActions } from "@/domains/transactions/components/transaction-quick-actions";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { getSafeTransactionReturnTo } from "@/domains/transactions/return-to";
import type { TransactionFilters as TransactionFilterValues } from "@/domains/transactions/schemas/transaction-schema";

export const metadata: Metadata = { title: "Opérations" };
export const dynamic = "force-dynamic";
type Search = Promise<Record<string, string | string[] | undefined>>;
const one = (value: string | string[] | undefined) => typeof value === "string" ? value : undefined;
const filterType = (value: string | undefined) => value === "income" || value === "expense" || value === "transfer" ? value : undefined;

export default async function OperationsPage({ params, searchParams }: { params: Promise<{ protectedPersonId: string }>; searchParams: Search }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const search = await searchParams;
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [accounts, categories] = await Promise.all([getFinancialAccounts(protectedPersonId), getCategories(false)]);
  const currentPatrimony = getCurrentPatrimonyValue(accounts);
  const startDate = one(search.start);
  const endDate = one(search.end);
  const canAddOperation = person.accessRole !== "read_only";
  const filterValues: { start?: string; end?: string; account?: string; type?: TransactionFilterValues["type"]; category?: string; q?: string } = { start: startDate, end: endDate, account: one(search.account), type: filterType(one(search.type)), category: one(search.category), q: one(search.q) };
  const items = await getTransactions(protectedPersonId, { startDate, endDate, accountId: filterValues.account, type: filterValues.type, categoryId: filterValues.category, query: filterValues.q });
  const query = new URLSearchParams(Object.entries(filterValues).filter((entry): entry is [string, string] => Boolean(entry[1]))).toString();
  const returnTo = getSafeTransactionReturnTo(protectedPersonId, `/dossiers/${protectedPersonId}/operations${query ? `?${query}` : ""}`);
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "operations" }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Opérations" }]} />
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p><div className="mt-1 flex flex-wrap items-end gap-x-4 gap-y-1"><h1 className="text-2xl font-bold sm:text-[28px] sm:leading-8">Opérations</h1><div className="border-l border-blue-100 pl-3"><p className="text-[10px] font-semibold leading-4 text-[#64748B]">Patrimoine actuel</p><p className="text-base font-bold leading-5">{formatCurrency(currentPatrimony)}</p></div></div></div>{items.length > 0 && <TransactionQuickActions personId={protectedPersonId} accessRole={person.accessRole} ordinaryAllowed={canAddOperation} transferAllowed={canAddOperation} returnTo={returnTo} />}</div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="operations" />
    <FinancialNavigation protectedPersonId={protectedPersonId} current="operations" />
    <TransactionFilters personId={protectedPersonId} accounts={accounts} categories={categories} values={filterValues} />
    <TransactionJournal personId={protectedPersonId} items={items} periods={person.managementPeriods} accessRole={person.accessRole} ordinaryAllowed={canAddOperation} transferAllowed={canAddOperation} returnTo={returnTo} />
  </PrivateShell>;
}
