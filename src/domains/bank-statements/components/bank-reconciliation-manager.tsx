"use client";

import { useState } from "react";
import { RefreshCw, Scale } from "lucide-react";
import { useRouter } from "next/navigation";
import type { BankStatement, FinancialAccount } from "@/types/database";
import {
  getReconciliationUnavailableReason,
  type ReconciliationUnavailableReason,
} from "../reconciliation-calculations";
import type {
  BankReconciliationControl,
  BankReconciliationListState,
  OutstandingTransactionPage,
} from "../reconciliation-service";
import { OutstandingTransactionsDialog } from "./outstanding-transactions-dialog";

const date = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(`${value}T00:00:00Z`));
const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(value));
const euro = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);

type AccountDates = Pick<FinancialAccount, "closing_date" | "initial_balance_date" | "opening_date">;
type ManagerProps = {
  personId: string;
  accountId: string;
  items: BankStatement[];
  totalCount: number;
  reconciliations: BankReconciliationListState[];
  accountDates: AccountDates;
  canManage: boolean;
};
type ControlProps = Omit<ManagerProps, "items" | "totalCount" | "reconciliations"> & {
  item: BankStatement;
  reconciliation: BankReconciliationListState | null;
};

export function BankReconciliationManager({
  personId,
  accountId,
  items,
  totalCount,
  reconciliations,
  accountDates,
  canManage,
}: ManagerProps) {
  const byStatement = new Map(reconciliations.map((item) => [item.bank_statement_id, item]));

  return (
    <section className="mt-5">
      <div>
        <h2 className="text-base font-bold">
          {totalCount} relevé{totalCount > 1 ? "s" : ""} à contrôler
        </h2>
        <p className="mt-1 text-sm text-[#64748B]">
          Comparez chaque solde bancaire avec le solde calculé par PatriGest.
        </p>
      </div>
      {items.length ? (
        <div className="mt-3 space-y-3">
          {items.map((item) => (
            <article key={item.id} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
              <div className="flex flex-wrap items-start justify-between gap-2 border-b border-[#E2E8F0] pb-3">
                <div>
                  <p className="text-sm font-bold">Relevé du {date(item.statement_end_date)}</p>
                  <p className="text-xs text-[#64748B]">
                    {item.statement_start_date
                      ? `Période du ${date(item.statement_start_date)} au ${date(item.statement_end_date)}`
                      : "Date de début non renseignée"}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-[10px] font-bold uppercase tracking-wide text-[#64748B]">Solde du relevé</p>
                  <p className="text-sm font-bold tabular-nums">
                    {item.statement_balance === null ? "—" : euro(item.statement_balance)}
                  </p>
                </div>
              </div>
              <div className="pt-3">
                <ReconciliationControl
                  personId={personId}
                  accountId={accountId}
                  item={item}
                  reconciliation={byStatement.get(item.id) ?? null}
                  accountDates={accountDates}
                  canManage={canManage}
                />
              </div>
            </article>
          ))}
        </div>
      ) : (
        <p className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">
          Aucun relevé bancaire à contrôler.
        </p>
      )}
    </section>
  );
}

function initialValidatedControl(
  item: BankStatement,
  reconciliation: BankReconciliationListState | null,
): BankReconciliationControl | null {
  if (!reconciliation || reconciliation.status !== "validated") return null;
  return {
    reconciliationId: reconciliation.id,
    status: "validated",
    reconciliationMode: reconciliation.reconciliation_mode,
    unavailableReason: null,
    statementEndDate: item.statement_end_date,
    statementBalance: item.statement_balance,
    calculatedBalance: reconciliation.calculated_balance,
    calculatedBalanceInCents: reconciliation.calculated_balance === null
      ? null
      : Math.round(reconciliation.calculated_balance * 100),
    difference: reconciliation.difference,
    differenceInCents: reconciliation.difference === null
      ? null
      : Math.round(reconciliation.difference * 100),
    validatedAt: reconciliation.validated_at,
    outstandingDebits: reconciliation.outstanding_debits,
    outstandingCredits: reconciliation.outstanding_credits,
    explainedBankBalance: reconciliation.explained_bank_balance,
    residualDifference: reconciliation.residual_difference,
    outstandingCount: null,
  };
}

function unavailableMessage(reason: ReconciliationUnavailableReason) {
  if (reason === "missing_statement_balance") {
    return "Solde du relevé non renseigné. Ajoutez-le depuis l’onglet Relevés pour contrôler ce relevé.";
  }
  if (reason === "before_minimum_date") {
    return "Ce relevé est antérieur à la première date contrôlable du compte.";
  }
  return "Ce relevé est postérieur à la clôture du compte.";
}

export function ReconciliationControl({
  personId,
  accountId,
  item,
  reconciliation,
  accountDates,
  canManage,
}: ControlProps) {
  const router = useRouter();
  const [control, setControl] = useState<BankReconciliationControl | null>(
    () => initialValidatedControl(item, reconciliation),
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [pointingOpen, setPointingOpen] = useState(false);
  const [pointingPage, setPointingPage] = useState<OutstandingTransactionPage | null>(null);
  const endpoint = `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}/rapprochement`;
  const pointingEndpoint = `${endpoint}/pointage`;
  const unavailableReason = getReconciliationUnavailableReason(item, accountDates);
  const status = control?.status ?? reconciliation?.status ?? "none";

  async function request(method: "GET" | "POST" | "PATCH") {
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch(endpoint, { method });
      const result = await response.json() as BankReconciliationControl & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de traiter le contrôle bancaire.");
      setControl(result);
      if (result.status === "validated") router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible de traiter le contrôle bancaire.");
    } finally {
      setBusy(false);
    }
  }

  async function openPointing(activate: boolean) {
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch(pointingEndpoint, { method: activate ? "POST" : "GET" });
      const result = await response.json() as OutstandingTransactionPage & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de charger le rapprochement détaillé.");
      setPointingPage(result);
      if (control && activate) {
        setControl({ ...control, reconciliationMode: "complete", ...result.summary });
      }
      setPointingOpen(true);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible de charger le rapprochement détaillé.");
    } finally {
      setBusy(false);
    }
  }

  if (unavailableReason && status !== "validated") {
    return <div><p className="text-xs font-semibold text-[#64748B]">Contrôle indisponible</p><p className="mt-0.5 text-xs text-[#64748B]">{unavailableMessage(unavailableReason)}</p></div>;
  }
  if (status === "none") {
    return <div className="flex flex-wrap items-center justify-between gap-2"><div><p className="text-xs font-bold">Contrôle non commencé</p><p className="text-[11px] text-[#64748B]">Comparez le relevé au solde calculé par PatriGest.</p></div>{canManage && <button className="button button-secondary min-h-8 gap-1.5 px-2.5 text-xs" disabled={busy} onClick={() => request("POST")}><Scale size={13} />{busy ? "Calcul…" : "Contrôler le solde"}</button>}{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>;
  }
  if (status === "draft" && !control) {
    return <div className="flex flex-wrap items-center justify-between gap-2"><p className="text-xs font-bold">Brouillon — contrôle {reconciliation?.reconciliation_mode === "complete" ? "détaillé" : "simple"}</p><button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => request("GET")}>{busy ? "Calcul…" : "Afficher le contrôle"}</button>{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>;
  }
  if (!control || control.calculatedBalance === null || control.difference === null || control.statementBalance === null) {
    return null;
  }

  return <div><div className="grid gap-2 sm:grid-cols-3"><Value label="Solde du relevé" value={control.statementBalance} /><Value label={`Solde PatriGest au ${date(control.statementEndDate)}`} value={control.calculatedBalance} /><DifferenceValue label={control.reconciliationMode === "complete" ? "Écart simple" : "Écart"} value={control.difference} zero={control.differenceInCents === 0} /></div>{control.reconciliationMode === "complete" && <div className="mt-3 grid gap-2 rounded-lg bg-[#F8FAFC] p-3 sm:grid-cols-2 lg:grid-cols-4"><Value label="+ Débits en circulation" value={control.outstandingDebits} /><Value label="− Crédits en circulation" value={control.outstandingCredits} /><Value label="Solde bancaire expliqué" value={control.explainedBankBalance} /><DifferenceValue label="Écart résiduel" value={control.residualDifference} zero={control.residualDifference === 0} residual /></div>}<div className="mt-3 flex flex-wrap items-center justify-between gap-2"><p className="text-[11px] font-semibold text-[#64748B]">{control.status === "validated" && control.validatedAt ? `Validé le ${dateTime(control.validatedAt)} — contrôle ${control.reconciliationMode === "complete" ? "détaillé" : "simple"} — montants figés` : control.reconciliationMode === "complete" ? "Brouillon détaillé — recalculé à l’affichage" : "Brouillon simple — recalculé à l’affichage"}</p><div className="flex flex-wrap gap-1.5">{control.reconciliationMode === "complete" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(false)}>Opérations en circulation</button>}{control.status === "draft" && canManage && <>{control.reconciliationMode === "simple" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(true)}>Rapprochement détaillé</button>}<button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" disabled={busy} onClick={() => request("GET")}><RefreshCw size={13} />Recalculer</button><button className="button button-primary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => request("PATCH")}>Valider le contrôle</button></>}</div>{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>{pointingOpen && <OutstandingTransactionsDialog endpoint={pointingEndpoint} open canManage={canManage && control.status === "draft"} initialPage={pointingPage} onClose={() => setPointingOpen(false)} onChange={(page) => { setPointingPage(page); setControl((current) => current ? { ...current, ...page.summary } : current); }} />}</div>;
}

function Value({ label, value }: { label: string; value: number | null }) {
  return <div><p className="text-[10px] font-bold uppercase tracking-wide text-[#64748B]">{label}</p><p className="text-sm font-bold tabular-nums">{value === null ? "—" : euro(value)}</p></div>;
}

function DifferenceValue({
  label,
  value,
  zero,
  residual = false,
}: {
  label: string;
  value: number | null;
  zero: boolean;
  residual?: boolean;
}) {
  const status = zero
    ? residual ? "Rapprochement équilibré" : "Les soldes concordent"
    : residual ? "Un écart résiduel subsiste" : "Un écart subsiste";
  return <div><p className="text-[10px] font-bold uppercase tracking-wide text-[#64748B]">{label}</p><p className="text-sm font-bold tabular-nums">{value === null ? "—" : euro(value)}</p>{value !== null && <p className={`text-[11px] font-semibold ${zero ? "text-emerald-700" : "text-amber-700"}`}>{status}</p>}</div>;
}
