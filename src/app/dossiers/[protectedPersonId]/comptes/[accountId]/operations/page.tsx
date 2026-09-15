import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { FileText, Info } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { getCategories } from "@/domains/categories/services/category-service";
import { getFinancialAccount } from "@/domains/financial-accounts/services/financial-account-service";
import {
  formatCurrency,
  getCurrentAccountValue,
  isValuationAccount,
} from "@/domains/financial-accounts/utils/financial-account-utils";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { TransactionJournal } from "@/domains/transactions/components/transaction-journal";
import { TransactionQuickActions } from "@/domains/transactions/components/transaction-quick-actions";
import type { TransactionFilters as TransactionFilterValues } from "@/domains/transactions/schemas/transaction-schema";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { calculateRunningBalances } from "@/domains/transactions/utils/transaction-utils";
import { getSafeTransactionReturnTo } from "@/domains/transactions/return-to";

export const metadata: Metadata = { title: "Journal du compte" };
export const dynamic = "force-dynamic";
type Search = Promise<Record<string, string | string[] | undefined>>;
const one = (value: string | string[] | undefined) =>
  typeof value === "string" ? value : undefined;
const filterType = (value: string | undefined) =>
  value === "income" || value === "expense" || value === "transfer"
    ? value
    : undefined;

export default async function AccountOperationsPage({
  params,
  searchParams,
}: {
  params: Promise<{ protectedPersonId: string; accountId: string }>;
  searchParams: Search;
}) {
  const { protectedPersonId, accountId } = await params;
  if (
    ![protectedPersonId, accountId].every(
      (id) => z.uuid().safeParse(id).success,
    )
  )
    notFound();
  const [person, account, categories] = await Promise.all([
    getProtectedPerson(protectedPersonId),
    getFinancialAccount(accountId),
    getCategories(false),
  ]);
  if (
    !person ||
    !account ||
    account.protected_person_id !== protectedPersonId
  )
    notFound();
  const valuationAccount = isValuationAccount(account.account_type);
  const search = await searchParams;
  const filters: TransactionFilterValues = {
    startDate: one(search.start),
    endDate: one(search.end),
    accountId,
    type: filterType(one(search.type)),
    categoryId: one(search.category),
    query: one(search.q),
  };
  const filterValues = { start: filters.startDate, end: filters.endDate, type: filters.type, category: filters.categoryId, q: filters.query };
  const query = new URLSearchParams(Object.entries(filterValues).filter((entry): entry is [string, string] => Boolean(entry[1]))).toString();
  const returnTo = getSafeTransactionReturnTo(protectedPersonId, `/dossiers/${protectedPersonId}/comptes/${accountId}/operations${query ? `?${query}` : ""}`, accountId);
  const [items, allItems] = await Promise.all([
    getTransactions(protectedPersonId, filters),
    getTransactions(protectedPersonId, { accountId }),
  ]);
  const balances = valuationAccount ? undefined : calculateRunningBalances(account.initial_balance, allItems);
  const current = getCurrentAccountValue(
    account,
    account.valuations,
    account.transactions,
  );
  const canManage =
    person.accessRole !== "read_only" && account.status === "active" && !valuationAccount;
  const canTransfer = person.accessRole !== "read_only" && account.status === "active";
  return (
    <PrivateShell
      current="dossiers"
      dossier={{
        id: protectedPersonId,
        name: `${person.first_name} ${person.last_name}`,
        current: "accounts",
      }}
    >
      <AppBreadcrumb
        items={[
          { label: "Dossiers", href: "/dossiers" },
          {
            label: `${person.first_name} ${person.last_name}`,
            href: `/dossiers/${protectedPersonId}/comptes`,
          },
          {
            label: "Comptes et patrimoine",
            href: `/dossiers/${protectedPersonId}/comptes`,
          },
          { label: account.account_name },
        ]}
      />
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-[#2563EB]">
            {person.first_name} {person.last_name}
          </p>
          <div className="mt-0.5 flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
            <h1 className="text-xl font-bold leading-7 sm:text-2xl">
              {account.account_name}
            </h1>
            <p className="text-xs text-[#64748B]">{account.institution_name}</p>
          </div>
          <p className="mt-0.5 text-lg font-extrabold leading-6 tabular-nums text-[#334155]">
            {formatCurrency(current.value)}
          </p>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {items.length > 0 && <TransactionQuickActions personId={protectedPersonId} accountId={accountId} accessRole={person.accessRole} ordinaryAllowed={canManage} transferAllowed={canTransfer} returnTo={returnTo} />}
          <Link
            href={`/dossiers/${protectedPersonId}/comptes/${accountId}/releves`}
            className="button button-secondary min-h-8 gap-1.5 px-2.5 text-xs"
          >
            <FileText size={14} />
            Relevés
          </Link>
          <Link
            href={`/dossiers/${protectedPersonId}/comptes/${accountId}`}
            className="button button-secondary min-h-8 gap-1.5 px-2.5 text-xs"
          >
            <Info size={14} />
            Informations du compte
          </Link>
        </div>
      </div>
      <DossierNavigation
        protectedPersonId={protectedPersonId}
        current="accounts"
      />
      <FinancialNavigation protectedPersonId={protectedPersonId} accountId={accountId} current="operations" />
      <AccountFilters categories={categories} values={filterValues} />
      <TransactionJournal
        personId={protectedPersonId}
        items={items}
        periods={person.managementPeriods}
        accessRole={person.accessRole}
        accountId={accountId}
        ordinaryAllowed={canManage}
        transferAllowed={canTransfer}
        accountRegister
        balances={balances}
        returnTo={returnTo}
      />
    </PrivateShell>
  );
}

function AccountFilters({
  categories,
  values,
}: {
  categories: Awaited<ReturnType<typeof getCategories>>;
  values: { start?: string; end?: string; type?: string; category?: string; q?: string };
}) {
  return (
    <form className="mt-3 rounded-xl border border-[#E2E8F0] bg-white p-2.5">
      <div className="grid gap-1.5 sm:grid-cols-2 lg:grid-cols-5">
        <label><span className="mb-1 block text-[10px] font-semibold text-[#64748B]">Date de début</span><input
          className="auth-input h-8! rounded-lg px-2.5 text-xs"
          name="start"
          type="date"
          defaultValue={values.start}
        /></label>
        <label><span className="mb-1 block text-[10px] font-semibold text-[#64748B]">Date de fin</span><input
          className="auth-input h-8! rounded-lg px-2.5 text-xs"
          name="end"
          type="date"
          defaultValue={values.end}
        /></label>
        <select
          className="auth-input h-8! rounded-lg px-2.5 text-xs"
          name="type"
          aria-label="Type"
          defaultValue={values.type ?? ""}
        >
          <option value="">Tous les types</option>
          <option value="income">Recettes</option>
          <option value="expense">Dépenses</option>
          <option value="transfer">Virements</option>
        </select>
        <select
          className="auth-input h-8! rounded-lg px-2.5 text-xs"
          name="category"
          aria-label="Catégorie"
          defaultValue={values.category ?? ""}
        >
          <option value="">Toutes catégories</option>
          {categories
            .filter((category) => category.active)
            .map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
        </select>
        <input
          className="auth-input h-8! rounded-lg px-2.5 text-xs"
          name="q"
          placeholder="Rechercher…"
          aria-label="Rechercher par libellé"
          defaultValue={values.q}
        />
      </div>
      <div className="mt-1.5 flex justify-end gap-1.5">
        <a
          className="button button-secondary min-h-8! rounded-lg px-2.5! text-xs"
          href="?"
        >
          Effacer
        </a>
        <button
          className="button button-primary min-h-8! rounded-lg px-2.5! text-xs"
          type="submit"
        >
          Filtrer
        </button>
      </div>
    </form>
  );
}
