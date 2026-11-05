import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { parseBankStatementPage, type BankStatementQuery } from "@/domains/bank-statements/bank-statement-pagination";
import { BankReconciliationManager } from "@/domains/bank-statements/components/bank-reconciliation-manager";
import { BankStatementPagination } from "@/domains/bank-statements/components/bank-statement-pagination";
import {
  buildBankReconciliationAttentionSummary,
  calculateReconciliationDifference,
  getReconciliationUnavailableReason,
} from "@/domains/bank-statements/reconciliation-calculations";
import { getBankReconciliationOverviewRows } from "@/domains/bank-statements/reconciliation-service";
import { getBankStatementPage } from "@/domains/bank-statements/services";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { getFinancialAccountEntryHref } from "@/domains/financial-accounts/financial-account-entry";
import { getFinancialAccount } from "@/domains/financial-accounts/services/financial-account-service";
import { calculateAccountBalanceAtDate } from "@/domains/financial-accounts/services/account-balance-at-date";
import { isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Rapprochements" };
export const dynamic = "force-dynamic";

export default async function AccountReconciliationsPage({
  params,
  searchParams,
}: {
  params: Promise<{ protectedPersonId: string; accountId: string }>;
  searchParams: Promise<BankStatementQuery>;
}) {
  const [{ protectedPersonId, accountId }, query] = await Promise.all([params, searchParams]);
  if (![protectedPersonId, accountId].every((id) => z.uuid().safeParse(id).success)) {
    notFound();
  }

  const [person, account] = await Promise.all([
    getProtectedPerson(protectedPersonId),
    getFinancialAccount(accountId),
  ]);
  if (!person || !account || account.protected_person_id !== protectedPersonId) {
    notFound();
  }

  const [statementPage, overviewRows] = await Promise.all([
    getBankStatementPage(accountId, parseBankStatementPage(query.page)),
    getBankReconciliationOverviewRows(accountId),
  ]);
  const currentStatementIds = new Set(statementPage.items.map((statement) => statement.id));
  const reconciliations = overviewRows.reconciliations.filter(
    (reconciliation) => currentStatementIds.has(reconciliation.bank_statement_id),
  );
  const attentionSummary = buildBankReconciliationAttentionSummary(
    overviewRows.statements,
    overviewRows.reconciliations,
    (statement) => {
      if (getReconciliationUnavailableReason(statement, account) || statement.statement_balance === null) {
        return null;
      }
      const calculated = calculateAccountBalanceAtDate(
        account.initial_balance,
        account.transactions,
        statement.statement_end_date,
      );
      return calculateReconciliationDifference(
        statement.statement_balance,
        calculated.balanceInCents,
      ).difference;
    },
  );
  const accountHref = getFinancialAccountEntryHref(
    protectedPersonId,
    accountId,
    isValuationAccount(account.account_type),
  );
  const pathname = `/dossiers/${protectedPersonId}/comptes/${accountId}/rapprochements`;

  return (
    <PrivateShell
      current="dossiers"
      dossier={{
        id: protectedPersonId,
        name: `${person.first_name} ${person.last_name}`,
        current: "accounts",
        accessRole: person.accessRole,
      }}
    >
      <AppBreadcrumb items={[
        { label: "Dossiers", href: "/dossiers" },
        { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` },
        { label: "Comptes et patrimoine", href: `/dossiers/${protectedPersonId}/comptes` },
        { label: account.account_name, href: accountHref },
        { label: "Rapprochements" },
      ]} />
      <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">
        {person.first_name} {person.last_name}
      </p>
      <h1 className="mt-1 text-2xl font-bold">Rapprochements</h1>
      <p className="mt-1 text-sm font-semibold">{account.account_name}</p>
      <p className="text-xs text-[#64748B]">
        {account.institution_name}{account.account_reference ? ` · ${account.account_reference}` : ""}
      </p>
      <DossierNavigation protectedPersonId={protectedPersonId} current="accounts" />
      <FinancialNavigation protectedPersonId={protectedPersonId} accountId={accountId} current="reconciliations" />
      {person.archived_at && <p className="mt-4 rounded-lg bg-slate-100 px-3 py-2 text-xs font-semibold text-[#64748B]">Dossier archivé — consultation des rapprochements uniquement.</p>}
      <BankStatementPagination
        pathname={pathname}
        values={query}
        page={statementPage.page}
        totalPages={statementPage.totalPages}
      />
      <BankReconciliationManager
        personId={protectedPersonId}
        accountId={accountId}
        items={statementPage.items}
        totalCount={statementPage.totalCount}
        attentionSummary={attentionSummary}
        reconciliations={reconciliations}
        accountDates={{
          initial_balance_date: account.initial_balance_date,
          opening_date: account.opening_date,
          closing_date: account.closing_date,
        }}
        canManage={person.accessRole !== "read_only" && !person.archived_at}
      />
      <BankStatementPagination
        pathname={pathname}
        values={query}
        page={statementPage.page}
        totalPages={statementPage.totalPages}
      />
    </PrivateShell>
  );
}
