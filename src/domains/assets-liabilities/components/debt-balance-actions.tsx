"use client";

import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { Ban, Pencil } from "lucide-react";
import { FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import type { DebtBalance } from "@/types/database";
import { cancelDebtBalanceAction, correctDebtBalanceAction } from "../actions";
import { initialAssetLiabilityState } from "../state";

type ClosedPeriod = { id: string; start_date: string; end_date: string };

export function DebtBalanceActions({ personId, debtId, balance, closedPeriods }: {
  personId: string;
  debtId: string;
  balance: DebtBalance;
  closedPeriods: ClosedPeriod[];
}) {
  const [correctionOpen, setCorrectionOpen] = useState(false);
  const [cancellationOpen, setCancellationOpen] = useState(false);
  const belongsToClosedPeriod = isClosed(balance.balance_date, closedPeriods);

  if (balance.cancelled_at !== null) return null;
  if (belongsToClosedPeriod) return <p className="text-xs font-medium text-amber-800">Exercice clôturé — correction et annulation indisponibles.</p>;

  return <>
    <div className="flex flex-wrap gap-2">
      <button type="button" className="button button-secondary gap-1.5 px-3" onClick={() => setCorrectionOpen(true)}><Pencil size={13} />Corriger</button>
      <button type="button" className="button button-secondary gap-1.5 px-3 text-red-700" onClick={() => setCancellationOpen(true)}><Ban size={13} />Annuler la situation</button>
    </div>
    <CorrectionDialog personId={personId} debtId={debtId} balance={balance} closedPeriods={closedPeriods} open={correctionOpen} close={() => setCorrectionOpen(false)} />
    <CancellationDialog personId={personId} debtId={debtId} balance={balance} open={cancellationOpen} close={() => setCancellationOpen(false)} />
  </>;
}

function CorrectionDialog({ personId, debtId, balance, closedPeriods, open, close }: {
  personId: string; debtId: string; balance: DebtBalance; closedPeriods: ClosedPeriod[]; open: boolean; close: () => void;
}) {
  const [balanceDate, setBalanceDate] = useState(balance.balance_date);
  const [state, action, pending] = useActionState(correctDebtBalanceAction.bind(null, personId, debtId, balance.id, balance.revision), initialAssetLiabilityState);
  useCloseAfterSuccess(open, state.status, close);
  const formId = `correct-debt-balance-${balance.id}`;
  const closed = useMemo(() => isClosed(balanceDate, closedPeriods), [balanceDate, closedPeriods]);

  return <AppConfirmDialog open={open} onClose={close} title="Corriger la situation" description="La correction conserve les anciennes valeurs dans le journal." subject={formatDate(balance.balance_date)} actions={<button form={formId} className="button button-primary" disabled={pending || closed}>{pending ? "Correction…" : "Enregistrer la correction"}</button>}>
    <form id={formId} action={action} className="grid gap-3">
      <label><span className="auth-label">Date de situation</span><input className="auth-input" name="balanceDate" type="date" required value={balanceDate} onChange={(event) => setBalanceDate(event.target.value)} /></label>
      <label><span className="auth-label">Capital restant dû</span><input className="auth-input" name="remainingBalance" type="number" min="0" step="0.01" required defaultValue={balance.remaining_balance} /></label>
      <label><span className="auth-label">Durée restante (mois)</span><input className="auth-input" name="remainingDurationMonths" type="number" min="0" step="1" defaultValue={balance.remaining_duration_months ?? ""} /></label>
      <label><span className="auth-label">Motif de la correction</span><textarea className="auth-input min-h-24 resize-y py-2" name="reason" maxLength={2000} required /></label>
      {closed && <p role="alert" className="rounded-xl bg-amber-50 px-3 py-2 text-sm font-medium text-amber-900">La date choisie appartient à un exercice clôturé.</p>}
      <FormMessage state={state} />
    </form>
  </AppConfirmDialog>;
}

function CancellationDialog({ personId, debtId, balance, open, close }: {
  personId: string; debtId: string; balance: DebtBalance; open: boolean; close: () => void;
}) {
  const [state, action, pending] = useActionState(cancelDebtBalanceAction.bind(null, personId, debtId, balance.id, balance.revision), initialAssetLiabilityState);
  useCloseAfterSuccess(open, state.status, close);
  const formId = `cancel-debt-balance-${balance.id}`;
  return <AppConfirmDialog open={open} onClose={close} title="Annuler la situation" description="La situation restera visible dans l’historique, mais sera exclue de tous les calculs." subject={`${formatDate(balance.balance_date)} · ${formatCurrency(balance.remaining_balance)}`} actions={<button form={formId} className="button button-primary bg-red-700 hover:bg-red-800" disabled={pending}>{pending ? "Annulation…" : "Confirmer l’annulation"}</button>}>
    <form id={formId} action={action} className="grid gap-3">
      <label><span className="auth-label">Motif de l’annulation</span><textarea className="auth-input min-h-24 resize-y py-2" name="reason" maxLength={2000} required /></label>
      <FormMessage state={state} />
    </form>
  </AppConfirmDialog>;
}

function isClosed(date: string, periods: ClosedPeriod[]) { return periods.some((period) => date >= period.start_date && date <= period.end_date); }
function formatDate(value: string) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)); }
function formatCurrency(value: number) { return new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value); }
function useCloseAfterSuccess(open: boolean, status: string, close: () => void) {
  const previous = useRef(status);
  useEffect(() => { if (open && status === "success" && previous.current !== status) close(); previous.current = status; }, [open, status, close]);
}
