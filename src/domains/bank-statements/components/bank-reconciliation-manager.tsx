"use client";

import { useState } from "react";
import { AlertTriangle, RefreshCw, Scale } from "lucide-react";
import { useRouter } from "next/navigation";
import type { BankStatement, FinancialAccount } from "@/types/database";
import {
  getReconciliationUnavailableReason,
  type BankReconciliationAttentionSummary,
  type ReconciliationUnavailableReason,
} from "../reconciliation-calculations";
import type {
  BankReconciliationControl,
  BankReconciliationListState,
  OutstandingTransactionPage,
  TransactionBankingImpact,
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
  attentionSummary: BankReconciliationAttentionSummary;
  reconciliations: BankReconciliationListState[];
  accountDates: AccountDates;
  canManage: boolean;
};
type ControlProps = Omit<ManagerProps, "items" | "totalCount" | "attentionSummary" | "reconciliations"> & {
  item: BankStatement;
  reconciliation: BankReconciliationListState | null;
};
type ControlWithImpacts = BankReconciliationControl & { impacts: TransactionBankingImpact[] };

export function BankReconciliationManager({
  personId,
  accountId,
  items,
  totalCount,
  attentionSummary,
  reconciliations,
  accountDates,
  canManage,
}: ManagerProps) {
  const byStatement = new Map(reconciliations.map((item) => [item.bank_statement_id, item]));
  const pendingLabel = `${attentionSummary.pendingCount} rapprochement${attentionSummary.pendingCount > 1 ? "s" : ""} en attente`;

  return (
    <section className="mt-5">
      <div>
        <h2 className="text-base font-bold">
          {attentionSummary.pendingCount === 0 ? "Aucun rapprochement en attente" : pendingLabel}
        </h2>
        <p className="mt-1 text-sm text-[#64748B]">
          {totalCount} relevé{totalCount > 1 ? "s" : ""} bancaire{totalCount > 1 ? "s" : ""} au total. Comparez les contrôles en attente avec le solde calculé par PatriGest.
        </p>
      </div>
      {attentionSummary.pendingCount > 0 && (
        <ReconciliationAttentionBanner summary={attentionSummary} />
      )}
      {items.length ? (
        <div className="mt-3 space-y-3">
          {items.map((item) => {
            const reconciliation = byStatement.get(item.id) ?? null;
            return <article key={item.id} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
              <div className="flex flex-wrap items-start justify-between gap-2 border-b border-[#E2E8F0] pb-3">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-sm font-bold">Relevé du {date(item.statement_end_date)}</p>
                    <ReconciliationCardStatus
                      reconciliation={reconciliation}
                      draftDifference={attentionSummary.differenceByStatementId[item.id] ?? null}
                    />
                  </div>
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
                  reconciliation={reconciliation}
                  accountDates={accountDates}
                  canManage={canManage}
                />
              </div>
            </article>;
          })}
        </div>
      ) : (
        <p className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">
          Aucun relevé bancaire à contrôler.
        </p>
      )}
    </section>
  );
}

function ReconciliationAttentionBanner({ summary }: { summary: BankReconciliationAttentionSummary }) {
  let explanation = `${summary.pendingCount} rapprochements attendent votre contrôle. Consultez chaque relevé pour vérifier son état et son éventuel écart.`;
  if (summary.pendingCount === 1 && summary.singlePending) {
    const statementDate = date(summary.singlePending.statementEndDate);
    if (summary.singlePending.difference === null) {
      explanation = `Le rapprochement du relevé du ${statementDate} nécessite votre intervention. Son écart n’est pas encore disponible.`;
    } else if (Math.round(summary.singlePending.difference * 100) === 0) {
      explanation = `Le rapprochement du relevé du ${statementDate} reste à contrôler, même si les soldes concordent.`;
    } else {
      explanation = `Un écart de ${euro(Math.abs(summary.singlePending.difference))} subsiste pour le relevé du ${statementDate}.`;
    }
  }
  return <div role="status" className="mt-3 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-amber-950"><AlertTriangle className="mt-0.5 shrink-0" size={18} aria-hidden="true" /><div><p className="text-sm font-bold">{summary.pendingCount} rapprochement{summary.pendingCount > 1 ? "s" : ""} en attente</p><p className="mt-0.5 text-xs leading-relaxed text-amber-900">{explanation}</p></div></div>;
}

function ReconciliationCardStatus({
  reconciliation,
  draftDifference,
}: {
  reconciliation: BankReconciliationListState | null;
  draftDifference: number | null;
}) {
  if (reconciliation?.status === "validated") {
    return <span className="rounded-full bg-emerald-50 px-2 py-1 text-[10px] font-bold uppercase tracking-wide text-emerald-700">Validé</span>;
  }
  if (reconciliation?.status !== "draft") return null;
  const hasDifference = draftDifference !== null;
  const differenceIsNonZero = hasDifference && Math.round(draftDifference * 100) !== 0;
  return <div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-amber-100 px-2 py-1 text-[10px] font-bold uppercase tracking-wide text-amber-900">À contrôler</span><span className={`text-xs font-semibold tabular-nums ${differenceIsNonZero ? "text-amber-800" : "text-[#64748B]"}`}>{hasDifference ? `Écart : ${euro(draftDifference)}` : "Écart indisponible"}</span></div>;
}

function initialValidatedControl(
  item: BankStatement,
  reconciliation: BankReconciliationListState | null,
): ControlWithImpacts | null {
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
    impacts: [],
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
  const [control, setControl] = useState<ControlWithImpacts | null>(
    () => initialValidatedControl(item, reconciliation),
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [pointingOpen, setPointingOpen] = useState(false);
  const [pointingPage, setPointingPage] = useState<OutstandingTransactionPage | null>(null);
  const [impactReasons, setImpactReasons] = useState<Record<string, string>>({});
  const endpoint = `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}/rapprochement`;
  const pointingEndpoint = `${endpoint}/pointage`;
  const unavailableReason = getReconciliationUnavailableReason(item, accountDates);
  const status = control?.status ?? reconciliation?.status ?? "none";

  async function request(method: "GET" | "POST" | "PATCH") {
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch(endpoint, { method });
      const result = await response.json() as ControlWithImpacts & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de traiter le contrôle bancaire.");
      setControl(result);
      if (result.status === "validated") router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible de traiter le contrôle bancaire.");
    } finally {
      setBusy(false);
    }
  }

  async function acknowledgeImpact(impactId: string) {
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch(endpoint, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ impactId, justification: impactReasons[impactId] ?? "" }) });
      const result = await response.json() as ControlWithImpacts & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible d’enregistrer la reconnaissance.");
      setControl(result);
      setImpactReasons((current) => ({ ...current, [impactId]: "" }));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Impossible d’enregistrer la reconnaissance.");
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

  const pendingImpacts = control.impacts.filter((impact) => impact.acknowledgementState === "pending");
  const validationBlockedByImpacts = pendingImpacts.length > 0;
  const validationDifference = control.reconciliationMode === "simple" ? control.difference : control.residualDifference;
  const validationBlockedByDifference = validationDifference !== null && Math.round(validationDifference * 100) !== 0;
  const validationBlocked = validationBlockedByImpacts || validationBlockedByDifference;
  const validationHelpId = `reconciliation-validation-help-${control.reconciliationId}`;
  const differenceHelpId = `${validationHelpId}-difference`;
  const impactsHelpId = `${validationHelpId}-impacts`;
  const validationHelpIds = [validationBlockedByDifference ? differenceHelpId : null, validationBlockedByImpacts ? impactsHelpId : null].filter(Boolean).join(" ") || undefined;
  return <div><div className="grid gap-2 sm:grid-cols-3"><Value label="Solde du relevé" value={control.statementBalance} /><Value label={`Solde PatriGest au ${date(control.statementEndDate)}`} value={control.calculatedBalance} /><DifferenceValue label={control.reconciliationMode === "complete" ? "Écart simple" : "Écart"} value={control.difference} zero={control.differenceInCents === 0} /></div>{control.reconciliationMode === "complete" && <div className="mt-3 grid gap-2 rounded-lg bg-[#F8FAFC] p-3 sm:grid-cols-2 lg:grid-cols-4"><Value label="+ Débits en circulation" value={control.outstandingDebits} /><Value label="− Crédits en circulation" value={control.outstandingCredits} /><Value label="Solde bancaire expliqué" value={control.explainedBankBalance} /><DifferenceValue label="Écart résiduel" value={control.residualDifference} zero={control.residualDifference === 0} residual /></div>}{control.status === "draft" && control.impacts.length > 0 && <section className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3" aria-labelledby={`impacts-${control.reconciliationId}`}><h3 id={`impacts-${control.reconciliationId}`} className="text-sm font-bold text-amber-950">Impacts bancaires à vérifier</h3><p className="mt-1 text-xs text-amber-900">Ces corrections ou annulations sont postérieures à un rapprochement validé. Chaque impact doit être reconnu et justifié avant validation.</p><ul className="mt-3 space-y-2">{control.impacts.map((impact) => <li key={impact.impactId} className="rounded-lg bg-white p-3 text-xs"><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-bold">{impact.transactionLabel}</p><p className="text-[#64748B]">Opération du {date(impact.transactionDate)} · rapprochement historique au {date(impact.historicalStatementEndDate)}</p></div><span className={`rounded-full px-2 py-1 font-semibold ${impact.acknowledgementState === "acknowledged" ? "bg-emerald-50 text-emerald-800" : "bg-amber-100 text-amber-900"}`}>{impact.acknowledgementState === "acknowledged" ? "Reconnu" : "À reconnaître"}</span></div><p className="mt-2">{impact.impactKind === "reverse_previous" ? "Annulation de l’effet bancaire précédent" : "Application de la valeur corrigée"} : <strong>{euro(impact.signedAmount)}</strong></p>{impact.acknowledgementState === "acknowledged" ? <p className="mt-2 rounded-md bg-slate-50 px-2 py-1.5"><span className="font-semibold">Justification :</span> {impact.justification}</p> : canManage ? <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-end"><label className="min-w-0 flex-1"><span className="font-semibold">Justification *</span><textarea className="auth-input mt-1 min-h-16 py-2" value={impactReasons[impact.impactId] ?? ""} onChange={(event) => setImpactReasons((current) => ({ ...current, [impact.impactId]: event.target.value }))} minLength={3} maxLength={1000} /></label><button type="button" className="button button-secondary shrink-0" disabled={busy || (impactReasons[impact.impactId] ?? "").trim().length < 3} onClick={() => acknowledgeImpact(impact.impactId)}>Reconnaître l’impact</button></div> : <p className="mt-2 text-[#64748B]">Un gestionnaire doit reconnaître cet impact avant la validation.</p>}</li>)}</ul></section>}<div className="mt-3 flex flex-wrap items-center justify-between gap-2"><p className="text-[11px] font-semibold text-[#64748B]">{control.status === "validated" && control.validatedAt ? `Validé le ${dateTime(control.validatedAt)} — contrôle ${control.reconciliationMode === "complete" ? "détaillé" : "simple"} — montants figés` : control.reconciliationMode === "complete" ? "Brouillon détaillé — recalculé à l’affichage" : "Brouillon simple — recalculé à l’affichage"}</p><div className="flex flex-wrap gap-1.5">{control.reconciliationMode === "complete" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(false)}>Opérations en circulation</button>}{control.status === "draft" && canManage && <>{control.reconciliationMode === "simple" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(true)}>Rapprochement détaillé</button>}<button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" disabled={busy} onClick={() => request("GET")}><RefreshCw size={13} />Recalculer</button><button className={`button min-h-8 px-2.5 text-xs ${validationBlocked ? "cursor-not-allowed bg-slate-200 text-slate-500 shadow-none" : "button-primary"}`} disabled={busy || validationBlocked} aria-describedby={validationHelpIds} onClick={() => request("PATCH")}>Valider le contrôle</button></>}</div>{validationBlockedByDifference && validationDifference !== null && <p id={differenceHelpId} className="w-full text-xs font-semibold text-amber-800">{control.reconciliationMode === "simple" ? <>Un écart de {euro(Math.abs(validationDifference))} subsiste entre le relevé bancaire et PatriGest. Vérifiez les opérations ou utilisez le rapprochement détaillé pour identifier les opérations en circulation.</> : <>Un écart résiduel de {euro(Math.abs(validationDifference))} subsiste. Identifiez correctement les opérations en circulation avant de valider le rapprochement.</>}</p>}{validationBlockedByImpacts && <p id={impactsHelpId} className="w-full text-xs font-semibold text-amber-800">Reconnaissez et justifiez tous les impacts bancaires avant de valider le rapprochement.</p>}{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>{pointingOpen && <OutstandingTransactionsDialog endpoint={pointingEndpoint} open canManage={canManage && control.status === "draft"} initialPage={pointingPage} onClose={() => setPointingOpen(false)} onChange={(page) => { setPointingPage(page); setControl((current) => current ? { ...current, ...page.summary } : current); }} />}</div>;
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
