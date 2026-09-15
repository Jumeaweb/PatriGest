import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { LockKeyhole } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getCategories } from "@/domains/categories/services/category-service";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { TransactionForm } from "@/domains/transactions/components/transaction-form";
import { TransactionDeleteButton } from "@/domains/transactions/components/transaction-delete-button";
import { TransactionProof } from "@/domains/transactions/components/transaction-proof";
import { getTransaction, getTransactionDocument } from "@/domains/transactions/services/transaction-service";
import { isDateInClosedPeriod } from "@/domains/transactions/utils/transaction-utils";
import { getSafeTransactionReturnTo } from "@/domains/transactions/return-to";

export const metadata: Metadata = { title: "Modifier l’opération" };
export const dynamic = "force-dynamic";

export default async function EditOperationPage({ params, searchParams }: { params: Promise<{ protectedPersonId: string; transactionId: string }>; searchParams: Promise<{ returnTo?: string | string[] }> }) {
  const { protectedPersonId, transactionId } = await params;
  if (![protectedPersonId, transactionId].every((id) => z.uuid().safeParse(id).success)) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [accounts, categories, transaction] = await Promise.all([getFinancialAccounts(protectedPersonId), getCategories(), getTransaction(transactionId)]);
  if (!transaction || transaction.transfer_id || transaction.account.protected_person_id !== protectedPersonId) notFound();
  const readOnly = person.accessRole === "read_only";
  const closedPeriod = isDateInClosedPeriod(transaction.transaction_date, person.managementPeriods);
  const locked = readOnly || closedPeriod;
  const proof = transaction.transaction_type === "expense" ? await getTransactionDocument(transactionId) : null;
  const requestedReturnTo = (await searchParams).returnTo;
  const returnTo = getSafeTransactionReturnTo(protectedPersonId, typeof requestedReturnTo === "string" ? requestedReturnTo : undefined, transaction.financial_account_id);
  const correctiveIssue = new URL(returnTo, "https://patrigest.internal").searchParams.get("classificationIssue");
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "operations" }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Opérations", href: returnTo }, { label: "Modifier" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <div className="flex flex-wrap items-end justify-between gap-3"><h1 className="mt-1 text-2xl font-bold sm:text-[28px]">{locked ? "Consulter l’opération" : "Modifier l’opération"}</h1>{!locked && <TransactionDeleteButton personId={protectedPersonId} transactionId={transactionId} label={transaction.label} returnHref={returnTo} />}</div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="operations" />
    {locked ? <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-5"><div className="flex items-center gap-3"><span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-[#64748B]"><LockKeyhole size={17} /></span><div><h2 className="text-base font-bold">{closedPeriod ? "Exercice clôturé" : "Consultation en lecture seule"}</h2><p className="text-xs text-[#64748B]">{closedPeriod ? "Cette opération appartient à un exercice clôturé et ne peut plus être modifiée." : "Vous pouvez consulter cette opération, mais vous ne pouvez pas la modifier."}</p></div></div><dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2"><div><dt className="text-xs font-semibold text-[#64748B]">Libellé</dt><dd className="font-bold">{transaction.label}</dd></div><div><dt className="text-xs font-semibold text-[#64748B]">Montant</dt><dd className="font-bold">{transaction.amount.toLocaleString("fr-FR", { style: "currency", currency: "EUR" })}</dd></div><div><dt className="text-xs font-semibold text-[#64748B]">Date</dt><dd>{transaction.transaction_date}</dd></div><div><dt className="text-xs font-semibold text-[#64748B]">Compte</dt><dd>{transaction.account.account_name}</dd></div></dl><Link href={returnTo} className="button button-secondary mt-4">Retour</Link></section> : <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5">{correctiveIssue === "unclassified" && <p className="mb-4 rounded-lg bg-blue-50 px-3 py-2 text-xs text-blue-900">Choisissez une rubrique officielle pour classer cette opération dans le compte de gestion. Si une ancienne catégorie est déjà sélectionnée, choisissez une autre rubrique pour mettre à jour le classement stable.</p>}<TransactionForm personId={protectedPersonId} accounts={accounts} categories={categories} transaction={transaction} returnTo={returnTo} /></section>}
    {transaction.transaction_type === "expense" && transaction.proof_reference && <TransactionProof personId={protectedPersonId} transactionId={transactionId} reference={transaction.proof_reference} proof={proof} canManage={!locked} returnTo={returnTo} />}
  </PrivateShell>;
}
