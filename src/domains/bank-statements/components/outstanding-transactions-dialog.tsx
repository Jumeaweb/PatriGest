"use client";

import { useState } from "react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import type { OutstandingTransactionPage } from "../reconciliation-service";

const date = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(`${value}T00:00:00Z`));
const euro = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);
const debit = (type: string) => type === "expense" || type === "transfer_out";

export function OutstandingTransactionsDialog({
  endpoint,
  open,
  canManage,
  initialPage,
  onClose,
  onChange,
}: {
  endpoint: string;
  open: boolean;
  canManage: boolean;
  initialPage: OutstandingTransactionPage | null;
  onClose: () => void;
  onChange: (page: OutstandingTransactionPage) => void;
}) {
  const [page, setPage] = useState<OutstandingTransactionPage | null>(initialPage);
  const [cursor, setCursor] = useState<string | null>(null);
  const [history, setHistory] = useState<Array<string | null>>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function load(nextCursor: string | null, nextHistory: Array<string | null>) {
    setLoading(true); setMessage("");
    try {
      const response = await fetch(`${endpoint}${nextCursor ? `?cursor=${encodeURIComponent(nextCursor)}` : ""}`);
      const result = await response.json() as OutstandingTransactionPage & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de charger les opérations.");
      setPage(result); setCursor(nextCursor); setHistory(nextHistory); onChange(result);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible de charger les opérations.");
    } finally { setLoading(false); }
  }

  async function toggle(transactionId: string, outstanding: boolean) {
    setBusyId(transactionId); setMessage("");
    try {
      const response = await fetch(endpoint, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ transactionId, outstanding }),
      });
      const result = await response.json() as OutstandingTransactionPage & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de modifier l’opération.");
      setPage(result); setCursor(null); setHistory([]); onChange(result);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible de modifier l’opération.");
    } finally { setBusyId(null); }
  }

  const summary = page?.summary;
  return <AppConfirmDialog
    open={open}
    onClose={onClose}
    size="wide"
    title="Opérations en circulation"
    description="Sélectionnez les opérations enregistrées dans PatriGest qui ne figurent pas encore sur ce relevé bancaire."
    actions={<button type="button" className="button button-primary" onClick={onClose}>Terminer</button>}
  >
    {summary && <div className="grid gap-2 rounded-xl bg-slate-50 p-3 text-xs sm:grid-cols-2 lg:grid-cols-5">
      <Summary label="Solde PatriGest" value={summary.calculatedBalance} />
      <Summary label="+ Débits en circulation" value={summary.outstandingDebits} />
      <Summary label="− Crédits en circulation" value={summary.outstandingCredits} />
      <Summary label="Solde bancaire expliqué" value={summary.explainedBankBalance} />
      <Summary label="Écart résiduel" value={summary.residualDifference} />
    </div>}
    <p className="mt-3 text-xs font-semibold text-[#64748B]">{summary?.outstandingCount ?? 0} opération{summary?.outstandingCount === 1 ? "" : "s"} en circulation</p>
    {page?.items.length ? <>
      <div className="mt-2 hidden overflow-hidden rounded-xl border border-[#E2E8F0] md:block">
        <table className="w-full text-left text-xs"><thead className="bg-slate-50 text-[10px] uppercase tracking-wide text-[#64748B]"><tr><th className="px-3 py-2">Date</th><th className="px-3 py-2">Libellé</th><th className="px-3 py-2">Sens</th><th className="px-3 py-2 text-right">Montant</th><th className="px-3 py-2 text-center">En circulation</th></tr></thead><tbody className="divide-y divide-[#E2E8F0]">{page.items.map((item) => <tr key={item.transactionId}><td className="whitespace-nowrap px-3 py-2">{date(item.transactionDate)}</td><td className="px-3 py-2 font-semibold">{item.label}{item.carriedFromPrevious && <span className="ml-2 rounded-full bg-amber-50 px-2 py-0.5 text-[10px] text-amber-800">Reportée</span>}</td><td className="px-3 py-2">{debit(item.transactionType) ? "Débit" : "Crédit"}</td><td className="whitespace-nowrap px-3 py-2 text-right font-bold">{euro(item.amount)}</td><td className="px-3 py-2 text-center"><Toggle checked={item.isOutstanding} disabled={!canManage || busyId === item.transactionId} onChange={(checked) => toggle(item.transactionId, checked)} /></td></tr>)}</tbody></table>
      </div>
      <div className="mt-2 space-y-2 md:hidden">{page.items.map((item) => <article key={item.transactionId} className="rounded-xl border border-[#E2E8F0] p-3"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="text-[11px] text-[#64748B]">{date(item.transactionDate)} · {debit(item.transactionType) ? "Débit" : "Crédit"}</p><p className="break-words text-sm font-bold">{item.label}</p>{item.carriedFromPrevious && <p className="mt-1 text-[10px] font-semibold text-amber-800">Reportée du rapprochement précédent</p>}</div><p className="shrink-0 text-sm font-bold">{euro(item.amount)}</p></div><label className="mt-2 flex items-center justify-between gap-3 text-xs font-semibold"><span>En circulation</span><Toggle checked={item.isOutstanding} disabled={!canManage || busyId === item.transactionId} onChange={(checked) => toggle(item.transactionId, checked)} /></label></article>)}</div>
    </> : !loading && <p className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] p-5 text-center text-sm text-[#64748B]">Aucune opération candidate.</p>}
    <div className="mt-3 flex items-center justify-center gap-2"><button type="button" className="button button-secondary min-h-8 px-2.5 text-xs" disabled={loading || history.length === 0} onClick={() => { const previous = history.at(-1) ?? null; void load(previous, history.slice(0, -1)); }}>Précédent</button><button type="button" className="button button-secondary min-h-8 px-2.5 text-xs" disabled={loading || !page?.nextCursor} onClick={() => { if (page?.nextCursor) void load(page.nextCursor, [...history, cursor]); }}>Suivant</button></div>
    {message && <p role="alert" className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}
  </AppConfirmDialog>;
}

function Summary({ label, value }: { label: string; value: number | null }) {
  return <div><p className="font-semibold text-[#64748B]">{label}</p><p className="mt-0.5 font-bold tabular-nums text-[#334155]">{value === null ? "—" : euro(value)}</p></div>;
}

function Toggle({ checked, disabled, onChange }: { checked: boolean; disabled: boolean; onChange: (checked: boolean) => void }) {
  return <input aria-label="Opération en circulation" type="checkbox" className="size-4 accent-blue-600" checked={checked} disabled={disabled} onChange={(event) => onChange(event.target.checked)} />;
}
