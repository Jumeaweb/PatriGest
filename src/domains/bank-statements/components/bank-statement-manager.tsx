"use client";

import { Fragment, useRef, useState } from "react";
import { Download, ExternalLink, FilePenLine, FilePlus2, RefreshCw, Scale, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import type { BankStatement, FinancialAccount } from "@/types/database";
import type { BankReconciliationControl, BankReconciliationListState, OutstandingTransactionPage } from "../reconciliation-service";
import { getReconciliationUnavailableReason, type ReconciliationUnavailableReason } from "../reconciliation-calculations";
import { OutstandingTransactionsDialog } from "./outstanding-transactions-dialog";

const date = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(`${value}T00:00:00Z`));
const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(value));
const euro = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);
type AccountDates = Pick<FinancialAccount, "closing_date" | "initial_balance_date" | "opening_date">;
type ManagerProps = { personId: string; accountId: string; items: BankStatement[]; reconciliations: BankReconciliationListState[]; accountDates: AccountDates; canManage: boolean };
type StatementProps = Omit<ManagerProps, "items" | "reconciliations"> & { item: BankStatement; reconciliation: BankReconciliationListState | null };

export function BankStatementManager({ personId, accountId, items, reconciliations, accountDates, canManage }: ManagerProps) {
  const [adding, setAdding] = useState(false);
  const byStatement = new Map(reconciliations.map((item) => [item.bank_statement_id, item]));
  return <>
    <div className="mt-5 flex items-center justify-between gap-3">
      <h2 className="text-base font-bold">{items.length} relevé{items.length > 1 ? "s" : ""}</h2>
      {canManage && <button className="button button-primary min-h-8 gap-1.5 px-3 text-xs" onClick={() => setAdding(true)}><FilePlus2 size={14} />Ajouter un relevé</button>}
    </div>
    {items.length ? <>
      <div className="mt-3 hidden overflow-hidden rounded-xl border border-[#E2E8F0] bg-white md:block">
        <table className="w-full text-left text-xs">
          <thead className="bg-[#F8FAFC] text-[11px] uppercase tracking-wide text-[#64748B]"><tr><th className="px-3 py-2">Date du relevé</th><th className="px-3 py-2">Période</th><th className="px-3 py-2 text-right">Solde du relevé</th><th className="px-3 py-2">Document</th></tr></thead>
          <tbody className="divide-y divide-[#E2E8F0]">{items.map((item) => <StatementRow key={item.id} personId={personId} accountId={accountId} item={item} reconciliation={byStatement.get(item.id) ?? null} accountDates={accountDates} canManage={canManage} />)}</tbody>
        </table>
      </div>
      <div className="mt-3 space-y-2 md:hidden">{items.map((item) => <StatementCard key={item.id} personId={personId} accountId={accountId} item={item} reconciliation={byStatement.get(item.id) ?? null} accountDates={accountDates} canManage={canManage} />)}</div>
    </> : <p className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun relevé bancaire enregistré.</p>}
    <StatementDialog personId={personId} accountId={accountId} open={adding} close={() => setAdding(false)} />
  </>;
}

function StatementRow(props: StatementProps) {
  const [validated, setValidated] = useState(props.reconciliation?.status === "validated");
  return <Fragment>
    <tr><td className="px-3 py-2.5 font-bold">{date(props.item.statement_end_date)}</td><td className="px-3 py-2.5 text-[#64748B]">{props.item.statement_start_date ? `${date(props.item.statement_start_date)} → ${date(props.item.statement_end_date)}` : "—"}</td><td className="px-3 py-2.5 text-right font-bold tabular-nums">{props.item.statement_balance === null ? "—" : euro(props.item.statement_balance)}</td><td className="px-3 py-2.5"><StatementActions {...props} isValidated={validated} /></td></tr>
    <tr><td className="bg-[#F8FAFC] px-3 py-2.5" colSpan={4}><ReconciliationControl {...props} onValidated={() => setValidated(true)} /></td></tr>
  </Fragment>;
}

function StatementCard(props: StatementProps) {
  const [validated, setValidated] = useState(props.reconciliation?.status === "validated");
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-3">
    <div className="flex justify-between gap-3"><div><p className="text-sm font-bold">{date(props.item.statement_end_date)}</p><p className="text-[11px] text-[#64748B]">{props.item.statement_start_date ? `${date(props.item.statement_start_date)} → ${date(props.item.statement_end_date)}` : "Date de fin du relevé"}</p></div>{props.item.statement_balance !== null && <p className="text-sm font-bold tabular-nums">{euro(props.item.statement_balance)}</p>}</div>
    <div className="mt-2"><StatementActions {...props} isValidated={validated} /></div>
    <div className="mt-3 border-t border-[#E2E8F0] pt-3"><ReconciliationControl {...props} onValidated={() => setValidated(true)} /></div>
  </article>;
}

function initialValidatedControl(item: BankStatement, reconciliation: BankReconciliationListState | null): BankReconciliationControl | null {
  if (!reconciliation || reconciliation.status !== "validated") return null;
  return { reconciliationId: reconciliation.id, status: "validated", reconciliationMode: reconciliation.reconciliation_mode, unavailableReason: null, statementEndDate: item.statement_end_date, statementBalance: item.statement_balance, calculatedBalance: reconciliation.calculated_balance, calculatedBalanceInCents: reconciliation.calculated_balance === null ? null : Math.round(reconciliation.calculated_balance * 100), difference: reconciliation.difference, differenceInCents: reconciliation.difference === null ? null : Math.round(reconciliation.difference * 100), validatedAt: reconciliation.validated_at, outstandingDebits: reconciliation.outstanding_debits, outstandingCredits: reconciliation.outstanding_credits, explainedBankBalance: reconciliation.explained_bank_balance, residualDifference: reconciliation.residual_difference, outstandingCount: null };
}

function unavailableMessage(reason: ReconciliationUnavailableReason) {
  if (reason === "missing_statement_balance") return "Solde du relevé non renseigné. Ajoutez-le pour contrôler ce relevé.";
  if (reason === "before_minimum_date") return "Ce relevé est antérieur à la première date contrôlable du compte.";
  return "Ce relevé est postérieur à la clôture du compte.";
}

function ReconciliationControl({ personId, accountId, item, reconciliation, accountDates, canManage, onValidated }: StatementProps & { onValidated: () => void }) {
  const router = useRouter();
  const [control, setControl] = useState<BankReconciliationControl | null>(() => initialValidatedControl(item, reconciliation));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [pointingOpen, setPointingOpen] = useState(false);
  const [pointingPage, setPointingPage] = useState<OutstandingTransactionPage | null>(null);
  const endpoint = `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}/rapprochement`;
  const pointingEndpoint = `${endpoint}/pointage`;
  const unavailableReason = getReconciliationUnavailableReason(item, accountDates);
  const status = control?.status ?? reconciliation?.status ?? "none";

  async function request(method: "GET" | "POST" | "PATCH") {
    setBusy(true); setMessage("");
    try {
      const response = await fetch(endpoint, { method });
      const result = await response.json() as BankReconciliationControl & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de traiter le contrôle bancaire.");
      setControl(result);
      if (result.status === "validated") { onValidated(); router.refresh(); }
    } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de traiter le contrôle bancaire."); }
    finally { setBusy(false); }
  }

  async function openPointing(activate: boolean) {
    setBusy(true); setMessage("");
    try {
      const response = await fetch(pointingEndpoint, { method: activate ? "POST" : "GET" });
      const result = await response.json() as OutstandingTransactionPage & { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de charger le rapprochement détaillé.");
      setPointingPage(result);
      if (control && activate) setControl({ ...control, reconciliationMode: "complete", ...result.summary });
      setPointingOpen(true);
    } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de charger le rapprochement détaillé."); }
    finally { setBusy(false); }
  }

  if (unavailableReason && status !== "validated") return <div><p className="text-xs font-semibold text-[#64748B]">Contrôle indisponible</p><p className="mt-0.5 text-xs text-[#64748B]">{unavailableMessage(unavailableReason)}</p></div>;
  if (status === "none") return <div className="flex flex-wrap items-center justify-between gap-2"><div><p className="text-xs font-bold">Contrôle non commencé</p><p className="text-[11px] text-[#64748B]">Comparez le relevé au solde calculé par PatriGest.</p></div>{canManage && <button className="button button-secondary min-h-8 gap-1.5 px-2.5 text-xs" disabled={busy} onClick={() => request("POST")}><Scale size={13} />{busy ? "Calcul…" : "Contrôler le solde"}</button>}{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>;
  if (status === "draft" && !control) return <div className="flex flex-wrap items-center justify-between gap-2"><p className="text-xs font-bold">Brouillon</p><button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => request("GET")}>{busy ? "Calcul…" : "Afficher le contrôle"}</button>{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>;
  if (!control || control.calculatedBalance === null || control.difference === null || control.statementBalance === null) return null;
  return <div><div className="grid gap-2 sm:grid-cols-3"><Value label="Solde du relevé" value={control.statementBalance} /><Value label={`Solde PatriGest au ${date(control.statementEndDate)}`} value={control.calculatedBalance} /><Value label={control.reconciliationMode === "complete" ? "Écart simple" : "Écart"} value={control.difference} /></div>{control.reconciliationMode === "complete" && <div className="mt-2 grid gap-2 rounded-lg bg-white p-2 sm:grid-cols-4"><Value label="+ Débits en circulation" value={control.outstandingDebits} /><Value label="− Crédits en circulation" value={control.outstandingCredits} /><Value label="Solde bancaire expliqué" value={control.explainedBankBalance} /><Value label="Écart résiduel" value={control.residualDifference} /></div>}<div className="mt-2 flex flex-wrap items-center justify-between gap-2"><p className="text-[11px] font-semibold text-[#64748B]">{control.status === "validated" && control.validatedAt ? `Validé le ${dateTime(control.validatedAt)} — montants figés` : control.reconciliationMode === "complete" ? "Brouillon détaillé — recalculé à l’affichage" : "Brouillon — recalculé à l’affichage"}</p><div className="flex flex-wrap gap-1.5">{control.reconciliationMode === "complete" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(false)}>Opérations en circulation</button>}{control.status === "draft" && canManage && <>{control.reconciliationMode === "simple" && <button className="button button-secondary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => openPointing(true)}>Rapprochement détaillé</button>}<button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" disabled={busy} onClick={() => request("GET")}><RefreshCw size={13} />Recalculer</button><button className="button button-primary min-h-8 px-2.5 text-xs" disabled={busy} onClick={() => request("PATCH")}>Valider le contrôle</button></>}</div>{message && <p role="alert" className="w-full text-xs text-red-700">{message}</p>}</div>{pointingOpen && <OutstandingTransactionsDialog endpoint={pointingEndpoint} open canManage={canManage && control.status === "draft"} initialPage={pointingPage} onClose={() => setPointingOpen(false)} onChange={(page) => { setPointingPage(page); setControl((current) => current ? { ...current, ...page.summary } : current); }} />}</div>;
}

function Value({ label, value }: { label: string; value: number | null }) { return <div><p className="text-[10px] font-bold uppercase tracking-wide text-[#64748B]">{label}</p><p className="text-sm font-bold tabular-nums">{value === null ? "—" : euro(value)}</p></div>; }

function StatementActions({ personId, accountId, item, canManage, isValidated }: StatementProps & { isValidated: boolean }) {
  const [editing, setEditing] = useState(false), [deleting, setDeleting] = useState(false); const endpoint = `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}`; const hasDocument = item.original_file_name !== null && item.mime_type !== null && item.file_size !== null;
  return <><div className="flex flex-wrap gap-1.5">{hasDocument ? <><a className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" href={endpoint} target="_blank" rel="noreferrer"><ExternalLink size={13} />Voir</a><a className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" href={`${endpoint}?download=1`}><Download size={13} />Télécharger</a></> : <span className="self-center text-xs text-[#64748B]">Aucun PDF</span>}{canManage && !isValidated && <><button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" onClick={() => setEditing(true)}><FilePenLine size={13} />Modifier</button><button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs text-red-700" onClick={() => setDeleting(true)}><Trash2 size={13} />Supprimer</button></>}</div><StatementDialog personId={personId} accountId={accountId} item={item} open={editing} close={() => setEditing(false)} /><DeleteDialog endpoint={endpoint} item={item} open={deleting} close={() => setDeleting(false)} /></>;
}

function StatementDialog({ personId, accountId, item, open, close }: { personId: string; accountId: string; item?: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter(); const [busy, setBusy] = useState(false), [message, setMessage] = useState(""); const input = useRef<HTMLInputElement>(null); const formId = `statement-${item?.id ?? "new"}`; const endpoint = item ? `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}` : `/api/dossiers/${personId}/comptes/${accountId}/releves`;
  async function submit(form: FormData) { setBusy(true); setMessage(""); try { const response = await fetch(endpoint, { method: "POST", body: form }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Impossible d’enregistrer le relevé."); if (input.current) input.current.value = ""; close(); router.refresh(); } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible d’enregistrer le relevé."); } finally { setBusy(false); } }
  return <AppConfirmDialog open={open} onClose={close} title={item ? "Modifier le relevé" : "Ajouter un relevé"} description={item ? "Modifiez les informations ou choisissez un PDF pour ajouter ou remplacer le document." : "Renseignez le relevé et ajoutez éventuellement son PDF."} actions={<button className="button button-primary" type="submit" form={formId} disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer"}</button>}><form id={formId} action={submit} className="grid gap-3 sm:grid-cols-2"><Field name="statementStartDate" label="Date de début (facultative)" type="date" value={item?.statement_start_date} /><Field name="statementEndDate" label="Date de fin" type="date" value={item?.statement_end_date} required /><Field name="statementBalance" label="Solde final (facultatif)" type="number" value={item?.statement_balance} /><Field name="note" label="Note (facultative)" value={item?.note} /><label className="sm:col-span-2"><span className="auth-label">Fichier PDF (facultatif)</span><input ref={input} className="block max-w-full text-xs file:mr-2 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:font-semibold" name="file" type="file" accept="application/pdf" /></label>{message && <p role="alert" className="sm:col-span-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</form></AppConfirmDialog>;
}

function DeleteDialog({ endpoint, item, open, close }: { endpoint: string; item: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter(); const [busy, setBusy] = useState(false), [message, setMessage] = useState(""); async function remove() { setBusy(true); setMessage(""); try { const response = await fetch(endpoint, { method: "DELETE" }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Impossible de supprimer le relevé."); close(); router.refresh(); } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de supprimer le relevé."); } finally { setBusy(false); } }
  return <AppConfirmDialog open={open} onClose={close} title="Supprimer ce relevé ?" description="Le fichier privé et ses métadonnées seront supprimés." subject={date(item.statement_end_date)} actions={<button className="button button-danger" onClick={remove} disabled={busy}>{busy ? "Suppression…" : "Supprimer le relevé"}</button>}>{message && <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</AppConfirmDialog>;
}

function Field({ name, label, type = "text", value, required }: { name: string; label: string; type?: string; value?: string | number | null; required?: boolean }) { return <label><span className="auth-label">{label}</span><input className="auth-input" name={name} type={type} step={type === "number" ? "0.01" : undefined} defaultValue={value ?? ""} required={required} /></label>; }
