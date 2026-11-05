import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ArrowRight, Ban, CircleCheck, LockKeyhole } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { formatCurrency, formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { TransactionDeleteButton } from "@/domains/transactions/components/transaction-delete-button";
import { TransferChangeHistory } from "@/domains/transactions/components/transfer-change-history";
import { listTransferChanges } from "@/domains/transactions/services/transaction-change-service";
import { getTransactions } from "@/domains/transactions/services/transaction-service";
import { resolveUnifiedTransferDetail } from "@/domains/transactions/transfer-detail";
import { getSafeTransactionReturnTo, withTransactionReturnTo } from "@/domains/transactions/return-to";
import { isDateInClosedPeriod } from "@/domains/transactions/utils/transaction-utils";

export const metadata: Metadata = { title: "Consulter le virement" };
export const dynamic = "force-dynamic";

const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));

export default async function OperationDetailPage({ params, searchParams }: { params: Promise<{ protectedPersonId: string; transactionId: string }>; searchParams: Promise<{ returnTo?: string | string[] }> }) {
  const { protectedPersonId, transactionId } = await params;
  if (![protectedPersonId, transactionId].every((id) => z.uuid().safeParse(id).success)) notFound();
  const [person, transactions, accounts] = await Promise.all([
    getProtectedPerson(protectedPersonId),
    getTransactions(protectedPersonId),
    getFinancialAccounts(protectedPersonId),
  ]);
  if (!person) notFound();
  const selectedMovement = transactions.find((transaction) => transaction.id === transactionId);
  if (!selectedMovement) notFound();
  const requestedReturnTo = (await searchParams).returnTo;
  const returnHref = getSafeTransactionReturnTo(protectedPersonId, typeof requestedReturnTo === "string" ? requestedReturnTo : undefined, selectedMovement.financial_account_id);
  if (!selectedMovement.transfer_id) redirect(withTransactionReturnTo(`/dossiers/${protectedPersonId}/operations/${transactionId}/modifier`, returnHref));
  const detail = resolveUnifiedTransferDetail(transactions, transactionId);
  if (!detail) notFound();

  const { transfer, sourceMovement, destinationMovement } = detail;
  const changes = await listTransferChanges(protectedPersonId, transfer.id);
  const cancellation = changes.find((change) => change.change_kind === "cancellation");
  const accountNames = new Map(accounts.map((account) => [account.id, account.account_name]));
  const closed = isDateInClosedPeriod(transfer.transfer_date, person.managementPeriods);
  const archived = Boolean(person.archived_at);
  const cancelled = Boolean(transfer.cancelled_at);
  const canManage = person.accessRole !== "read_only" && !archived && !closed && !cancelled;
  const lockMessage = cancelled ? "Virement annulé — les deux mouvements sont conservés dans l’historique et n’affectent plus les soldes." : archived ? "Dossier archivé — consultation uniquement." : closed ? "Exercice clôturé — consultation uniquement." : person.accessRole === "read_only" ? "Accès en lecture seule — aucune modification autorisée." : null;
  const label = transfer.label?.trim() || sourceMovement.label;

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "operations" }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Opérations", href: returnHref }, { label: "Virement" }]} />
    <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p><h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Détail du virement</h1></div>{canManage && <TransactionDeleteButton personId={protectedPersonId} transactionId={transactionId} transactionRevision={transfer.revision} transferId={transfer.id} label={label} returnHref={returnHref} />}</div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="operations" />
    <section className="mt-5 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5">
      {lockMessage && <p className="mb-4 flex items-start gap-2 rounded-lg bg-slate-100 px-3 py-2 text-xs font-semibold text-[#64748B]"><LockKeyhole className="mt-0.5 shrink-0" size={15} />{lockMessage}</p>}
      <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-semibold text-[#64748B]">{formatFinancialDate(transfer.transfer_date)}</p><h2 className="mt-1 text-lg font-bold">{label}</h2>{transfer.comment && <p className="mt-1 whitespace-pre-wrap text-sm text-[#475569]">{transfer.comment}</p>}</div><div className="text-right"><p className="text-xl font-extrabold">{formatCurrency(transfer.amount)}</p><span className={`mt-1 inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-bold ${cancelled ? "bg-slate-200 text-[#475569]" : "bg-emerald-50 text-emerald-800"}`}>{cancelled ? <Ban size={13} /> : <CircleCheck size={13} />}{cancelled ? "Annulé" : "Actif"}</span></div></div>
      <div className="mt-5 grid items-stretch gap-2 sm:grid-cols-[1fr_auto_1fr] sm:items-center">
        <MovementCard label="Compte de départ" account={sourceMovement.account.account_name} amount={sourceMovement.amount} direction="out" cancelled={cancelled} />
        <ArrowRight className="mx-auto rotate-90 text-[#94A3B8] sm:rotate-0" aria-hidden size={20} />
        <MovementCard label="Compte d’arrivée" account={destinationMovement.account.account_name} amount={destinationMovement.amount} direction="in" cancelled={cancelled} />
      </div>
      {cancelled && <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm"><p className="font-bold">Annulé le {transfer.cancelled_at ? dateTime(transfer.cancelled_at) : "date indisponible"}</p><p className="mt-1 whitespace-pre-wrap"><span className="font-semibold">Motif :</span> {cancellation?.reason ?? "Motif indisponible"}</p>{cancellation && <p className="mt-1 text-xs text-[#64748B]">Par {cancellation.changed_by_name}</p>}</div>}
      <Link href={returnHref} className="button button-secondary mt-5">Retour</Link>
    </section>
    <TransferChangeHistory transfer={transfer} items={changes} accountNames={accountNames} />
  </PrivateShell>;
}

function MovementCard({ label, account, amount, direction, cancelled }: { label: string; account: string; amount: number; direction: "in" | "out"; cancelled: boolean }) {
  return <article className={`rounded-xl border p-3.5 ${cancelled ? "border-slate-200 bg-slate-50" : "border-[#E2E8F0] bg-white"}`}><p className="text-xs font-semibold text-[#64748B]">{label}</p><p className="mt-1 font-bold">{account}</p><p className={`mt-2 text-lg font-extrabold ${cancelled ? "text-[#64748B] line-through" : direction === "out" ? "text-red-700" : "text-emerald-700"}`}>{direction === "out" ? "−" : "+"}{formatCurrency(amount)}</p>{cancelled && <p className="mt-1 text-[11px] font-semibold text-[#64748B]">Mouvement historique — sans effet sur le solde actuel</p>}</article>;
}
