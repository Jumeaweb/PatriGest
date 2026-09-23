import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CheckCircle2, CircleDashed, FileSearch } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getBankReconciliationListStates } from "@/domains/bank-statements/reconciliation-service";
import { getBankStatements } from "@/domains/bank-statements/services";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { getFinancialAccountEntryHref } from "@/domains/financial-accounts/financial-account-entry";
import { getFinancialAccount } from "@/domains/financial-accounts/services/financial-account-service";
import { isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Rapprochements" };
export const dynamic = "force-dynamic";

export default async function AccountReconciliationsPage({
  params,
}: {
  params: Promise<{ protectedPersonId: string; accountId: string }>;
}) {
  const { protectedPersonId, accountId } = await params;
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

  const statements = await getBankStatements(accountId);
  const reconciliations = await getBankReconciliationListStates(
    statements.map((statement) => statement.id),
  );
  const validated = reconciliations.filter((item) => item.status === "validated").length;
  const drafts = reconciliations.filter((item) => item.status === "draft").length;
  const notStarted = Math.max(0, statements.length - validated - drafts);
  const statementsHref = `/dossiers/${protectedPersonId}/comptes/${accountId}/releves`;
  const accountHref = getFinancialAccountEntryHref(
    protectedPersonId,
    accountId,
    isValuationAccount(account.account_type),
  );

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
          { label: account.account_name, href: accountHref },
          { label: "Rapprochements" },
        ]}
      />
      <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">
        {person.first_name} {person.last_name}
      </p>
      <h1 className="mt-1 text-2xl font-bold">Rapprochements</h1>
      <p className="mt-1 text-sm font-semibold">{account.account_name}</p>
      <p className="text-xs text-[#64748B]">
        {account.institution_name}
        {account.account_reference ? ` · ${account.account_reference}` : ""}
      </p>
      <DossierNavigation protectedPersonId={protectedPersonId} current="accounts" />
      <FinancialNavigation
        protectedPersonId={protectedPersonId}
        accountId={accountId}
        current="reconciliations"
      />

      <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="text-base font-bold">Synthèse des contrôles bancaires</h2>
        <p className="mt-1 text-sm text-[#64748B]">
          Les contrôles restent réalisés depuis chaque relevé bancaire. Cette synthèse rend leur avancement accessible sans dupliquer la gestion des documents.
        </p>
        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <Summary icon={CircleDashed} label="Non commencés" value={notStarted} />
          <Summary icon={FileSearch} label="Brouillons" value={drafts} />
          <Summary icon={CheckCircle2} label="Validés" value={validated} />
        </div>
        <Link className="button button-primary mt-4" href={statementsHref}>
          Accéder aux contrôles dans Relevés
        </Link>
      </section>
    </PrivateShell>
  );
}

function Summary({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof CircleDashed;
  label: string;
  value: number;
}) {
  return (
    <div className="rounded-lg border border-[#E2E8F0] bg-[#F8FAFC] p-3">
      <div className="flex items-center gap-2 text-brand-foreground">
        <Icon aria-hidden="true" size={16} />
        <p className="text-xs font-semibold">{label}</p>
      </div>
      <p className="mt-1 text-xl font-bold">{value}</p>
    </div>
  );
}
