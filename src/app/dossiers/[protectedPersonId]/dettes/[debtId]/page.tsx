import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { CalendarDays, Clock3, History, Landmark, NotebookText, Percent, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DebtActions } from "@/domains/assets-liabilities/components/debt-manager";
import { DebtBalanceActions } from "@/domains/assets-liabilities/components/debt-balance-actions";
import { getDebt } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import type { DebtBalanceChange } from "@/types/database";

export const metadata: Metadata = { title: "Dette et emprunt" };
export const dynamic = "force-dynamic";

const debtTypeLabels = {
  bank_loan: "Prêt bancaire",
  tax_debt: "Dette fiscale",
  institution_debt: "Dette envers un établissement",
  personal_debt: "Dette personnelle",
  other: "Autre",
} as const;

const formatDate = (value: string) => new Intl.DateTimeFormat("fr-FR", {
  dateStyle: "long",
  timeZone: "UTC",
}).format(new Date(`${value}T00:00:00Z`));
const formatDateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", {
  dateStyle: "long",
  timeStyle: "short",
}).format(new Date(value));
const formatCurrency = (value: number) => new Intl.NumberFormat("fr-FR", {
  style: "currency",
  currency: "EUR",
}).format(value);
const formatRate = (value: number) => `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 4 }).format(value)} %`;

export default async function DebtPage({ params }: { params: Promise<{ protectedPersonId: string; debtId: string }> }) {
  const { protectedPersonId, debtId } = await params;
  if (![protectedPersonId, debtId].every((id) => z.uuid().safeParse(id).success)) notFound();

  const [person, debt] = await Promise.all([
    getProtectedPerson(protectedPersonId),
    getDebt(protectedPersonId, debtId),
  ]);
  if (!person || !debt) notFound();

  const canManage = person.accessRole !== "read_only" && person.status === "active";
  const dossierArchived = person.status === "archived";
  const currentBalanceId = debt.balances.find((balance) => balance.cancelled_at === null)?.id ?? null;

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "debts", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[
      { label: "Dossiers", href: "/dossiers" },
      { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}` },
      { label: "Dettes et emprunts", href: `/dossiers/${protectedPersonId}/dettes` },
      { label: debt.designation },
    ]} />
    {dossierArchived && <div role="status" className="mb-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950">
      <p className="font-bold">Dossier archivé — consultation uniquement</p>
      <p className="mt-1">Les informations et l’historique de cette dette restent consultables. Restaurez le dossier avant toute modification.</p>
    </div>}
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
        <h1 className="mt-1 text-2xl font-bold">{debt.designation}</h1>
        <p className="mt-1 text-sm text-[#64748B]">{debt.creditor} · {debtTypeLabels[debt.debt_type]}</p>
      </div>
      {canManage && <DebtActions personId={protectedPersonId} item={debt} showSettlement />}
    </div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="debts" />

    <section className="mt-5 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <Info icon={Landmark} title="Statut">
        <p className="text-sm font-bold">{debt.status === "active" ? "Active" : "Soldée"}</p>
        {debt.settled_at && <p className="mt-1 text-xs text-[#64748B]">Clôturée le {formatDate(debt.settled_at)}</p>}
      </Info>
      <Info icon={WalletCards} title="Capital restant dû">
        {debt.current_balance === null
          ? <p className="text-sm font-semibold text-amber-700">Situation restante à renseigner</p>
          : <p className="text-xl font-bold">{formatCurrency(debt.current_balance)}</p>}
        {debt.current_balance_date && <p className="mt-1 text-xs text-[#64748B]">Situation au {formatDate(debt.current_balance_date)}</p>}
      </Info>
      {(debt.initial_amount !== null || debt.start_date) && <Info icon={CalendarDays} title="Origine de la dette">
        {debt.initial_amount !== null && <Data label="Montant initial" value={formatCurrency(debt.initial_amount)} />}
        {debt.start_date && <Data label="Date de début" value={formatDate(debt.start_date)} />}
      </Info>}
      {(debt.initial_duration_months !== null || debt.remaining_duration_months !== null) && <Info icon={Clock3} title="Durée">
        {debt.initial_duration_months !== null && <Data label="Durée initiale" value={`${debt.initial_duration_months} mois`} />}
        {debt.remaining_duration_months !== null && <Data label="Durée restante" value={`${debt.remaining_duration_months} mois`} />}
      </Info>}
      {(debt.monthly_payment !== null || debt.interest_rate !== null) && <Info icon={Percent} title="Conditions">
        {debt.monthly_payment !== null && <Data label="Mensualité" value={formatCurrency(debt.monthly_payment)} />}
        {debt.interest_rate !== null && <Data label="Taux" value={formatRate(debt.interest_rate)} />}
      </Info>}
      {debt.notes && <Info icon={NotebookText} title="Notes"><p className="whitespace-pre-wrap text-sm text-[#475569]">{debt.notes}</p></Info>}
    </section>

    <section className="mt-6" aria-labelledby="debt-history-title">
      <div className="flex items-center gap-2"><History className="text-[#2563EB]" size={18} /><h2 id="debt-history-title" className="text-lg font-bold">Historique du capital restant dû</h2></div>
      <p className="mt-1 text-xs text-[#64748B]">Situations enregistrées de la plus récente à la plus ancienne.</p>
      <div className="mt-3 space-y-2">
        {debt.balances.length ? debt.balances.map((balance) => {
          const changes = debt.balanceChanges.filter((change) => change.debt_balance_id === balance.id);
          const cancellation = changes.find((change) => change.change_type === "cancellation");
          return <article key={balance.id} className={`rounded-xl border px-3.5 py-3 ${balance.cancelled_at ? "border-slate-200 bg-slate-50 text-slate-600" : "border-[#E2E8F0] bg-white"}`}>
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div><div className="flex flex-wrap items-center gap-2"><p className="text-sm font-bold">{formatDate(balance.balance_date)}</p><span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${balance.cancelled_at ? "bg-red-50 text-red-700" : "bg-emerald-50 text-emerald-700"}`}>{balance.cancelled_at ? "Annulée" : "Active"}</span></div>{balance.remaining_duration_months !== null && <p className="mt-1 text-xs text-[#64748B]">Durée restante : {balance.remaining_duration_months} mois</p>}</div>
            <div className="text-right"><p className={`text-sm font-bold ${balance.cancelled_at ? "line-through" : ""}`}>{formatCurrency(balance.remaining_balance)}</p>{balance.id === currentBalanceId && <span className="mt-1 inline-block rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-bold text-blue-700">Situation courante</span>}</div>
          </div>
          {balance.cancelled_at && <div className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-900"><p className="font-semibold">Annulée le {formatDateTime(balance.cancelled_at)}{cancellation ? ` par ${cancellation.changed_by_name}` : ""}</p><p className="mt-1 whitespace-pre-wrap">Motif : {balance.cancellation_reason ?? cancellation?.reason ?? "Non renseigné"}</p></div>}
          {changes.length > 0 && <div className="mt-3 border-t border-slate-200 pt-3"><p className="text-xs font-bold uppercase tracking-wide text-slate-500">Journal des modifications</p><div className="mt-2 space-y-2">{changes.map((change) => <BalanceChange key={change.id} change={change} />)}</div></div>}
          {canManage && debt.status === "active" && balance.cancelled_at === null && <div className="mt-3 border-t border-slate-200 pt-3"><DebtBalanceActions personId={protectedPersonId} debtId={debt.id} balance={balance} closedPeriods={debt.closedPeriods} /></div>}
        </article>}) : <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucune situation de dette enregistrée.</p>}
      </div>
    </section>
    {debt.staleManagementReports.length > 0 && <section className="mt-6 rounded-xl border border-amber-300 bg-amber-50 p-4" aria-labelledby="stale-reports-title">
      <h2 id="stale-reports-title" className="font-bold text-amber-950">Projets de comptes de gestion à actualiser</h2>
      <p className="mt-1 text-sm text-amber-900">Des données du dossier ont changé depuis leur génération. Les documents définitifs déjà finalisés ne sont pas modifiés.</p>
      <ul className="mt-2 list-disc space-y-1 pl-5 text-sm">{debt.staleManagementReports.map((report) => <li key={report.id}><Link className="font-semibold text-blue-700 underline" href={`/dossiers/${protectedPersonId}/comptes-de-gestion/${report.id}`}>Compte de gestion {report.report_year}</Link></li>)}</ul>
    </section>}
    {debt.statusChanges.length > 0 && <section className="mt-6" aria-labelledby="debt-status-history-title">
      <div className="flex items-center gap-2"><History className="text-[#2563EB]" size={18} /><h2 id="debt-status-history-title" className="text-lg font-bold">Historique du statut</h2></div>
      <p className="mt-1 text-xs text-[#64748B]">Transitions explicites et auditées de la dette.</p>
      <div className="mt-3 space-y-2">
        {debt.statusChanges.map((change) => <article key={change.id} className="rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3">
          <div className="flex flex-wrap items-start justify-between gap-2"><div><p className="text-sm font-bold">Dette soldée{change.new_settled_at ? ` le ${formatDate(change.new_settled_at)}` : ""}</p><p className="mt-1 text-xs text-[#64748B]">Par {change.changed_by_name}</p></div><p className="text-xs text-[#64748B]">{formatDateTime(change.changed_at)}</p></div>
          <p className="mt-2 whitespace-pre-wrap text-sm text-[#475569]">Motif : {change.reason}</p>
        </article>)}
      </div>
    </section>}
  </PrivateShell>;
}

function Info({ icon: Icon, title, children }: { icon: typeof Landmark; title: string; children: React.ReactNode }) {
  return <article className="self-start rounded-xl border border-[#E2E8F0] bg-white p-3.5"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon aria-hidden="true" size={14} /></span><h2 className="text-sm font-bold">{title}</h2></div><div className="mt-2.5">{children}</div></article>;
}

function Data({ label, value }: { label: string; value: string }) {
  return <div className="mb-2 last:mb-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-[#94A3B8]">{label}</p><p className="mt-0.5 text-sm text-[#334155]">{value}</p></div>;
}

function BalanceChange({ change }: { change: DebtBalanceChange }) {
  const oldValues = asSnapshot(change.old_values);
  const newValues = asSnapshot(change.new_values);
  return <div className="rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-700">
    <div className="flex flex-wrap justify-between gap-2"><p className="font-bold">{change.change_type === "correction" ? "Correction" : "Annulation"} par {change.changed_by_name}</p><time>{formatDateTime(change.changed_at)}</time></div>
    {change.change_type === "correction" && <p className="mt-1">{snapshotLabel(oldValues)} → {snapshotLabel(newValues)}</p>}
    <p className="mt-1 whitespace-pre-wrap">Motif : {change.reason}</p>
  </div>;
}

function asSnapshot(value: unknown): Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function snapshotLabel(value: Record<string, unknown>) {
  const dateValue = typeof value.balance_date === "string" ? formatDate(value.balance_date) : "date inconnue";
  const balanceValue = typeof value.remaining_balance === "number" ? formatCurrency(value.remaining_balance) : "CRD inconnu";
  const duration = typeof value.remaining_duration_months === "number" ? `, ${value.remaining_duration_months} mois` : "";
  return `${dateValue}, ${balanceValue}${duration}`;
}
