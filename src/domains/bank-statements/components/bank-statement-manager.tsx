"use client";

import { useEffect, useRef, useState } from "react";
import { Download, ExternalLink, FileClock, FilePenLine, FilePlus2, FileX2, History, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import type { BankStatement } from "@/types/database";
import type { BankReconciliationListState } from "../reconciliation-service";

const date = (value: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(`${value}T00:00:00Z`));
const euro = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);
type ManagerProps = { personId: string; accountId: string; items: BankStatement[]; totalCount: number; reconciliations: BankReconciliationListState[]; canManage: boolean; durableOperationsEnabled: boolean };
type StatementProps = { personId: string; accountId: string; item: BankStatement; reconciliation: BankReconciliationListState | null; canManage: boolean; durableOperationsEnabled: boolean };

export function BankStatementManager({ personId, accountId, items, totalCount, reconciliations, canManage, durableOperationsEnabled }: ManagerProps) {
  const [adding, setAdding] = useState(false);
  const byStatement = new Map(reconciliations.map((item) => [item.bank_statement_id, item]));
  return <>
    <div className="mt-5 flex items-center justify-between gap-3">
      <h2 className="text-base font-bold">{totalCount} relevé{totalCount > 1 ? "s" : ""}</h2>
      {canManage && <button className="button button-primary min-h-8 gap-1.5 px-3 text-xs" onClick={() => setAdding(true)}><FilePlus2 size={14} />Ajouter un relevé</button>}
    </div>
    {items.length ? <>
      <div className="mt-3 hidden overflow-hidden rounded-xl border border-[#E2E8F0] bg-white md:block">
        <table className="w-full text-left text-xs">
          <thead className="bg-[#F8FAFC] text-[11px] uppercase tracking-wide text-[#64748B]"><tr><th className="px-3 py-2">Date du relevé</th><th className="px-3 py-2">Période</th><th className="px-3 py-2 text-right">Solde du relevé</th><th className="px-3 py-2">Contrôle</th><th className="px-3 py-2">Document</th></tr></thead>
          <tbody className="divide-y divide-[#E2E8F0]">{items.map((item) => <StatementRow key={item.id} personId={personId} accountId={accountId} item={item} reconciliation={byStatement.get(item.id) ?? null} canManage={canManage} durableOperationsEnabled={durableOperationsEnabled} />)}</tbody>
        </table>
      </div>
      <div className="mt-3 space-y-2 md:hidden">{items.map((item) => <StatementCard key={item.id} personId={personId} accountId={accountId} item={item} reconciliation={byStatement.get(item.id) ?? null} canManage={canManage} durableOperationsEnabled={durableOperationsEnabled} />)}</div>
    </> : <p className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun relevé bancaire enregistré.</p>}
    <StatementDialog personId={personId} accountId={accountId} open={adding} close={() => setAdding(false)} />
  </>;
}

function StatementRow(props: StatementProps) {
  const isValidated = props.reconciliation?.status === "validated";
  return <tr><td className="px-3 py-2.5 font-bold">{date(props.item.statement_end_date)}</td><td className="px-3 py-2.5 text-[#64748B]">{props.item.statement_start_date ? `${date(props.item.statement_start_date)} → ${date(props.item.statement_end_date)}` : "—"}</td><td className="px-3 py-2.5 text-right font-bold tabular-nums">{props.item.statement_balance === null ? "—" : euro(props.item.statement_balance)}</td><td className="px-3 py-2.5"><ReconciliationStatus reconciliation={props.reconciliation} /></td><td className="px-3 py-2.5"><StatementActions {...props} isValidated={isValidated} /></td></tr>;
}

function StatementCard(props: StatementProps) {
  const isValidated = props.reconciliation?.status === "validated";
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-3">
    <div className="flex justify-between gap-3"><div><p className="text-sm font-bold">{date(props.item.statement_end_date)}</p><p className="text-[11px] text-[#64748B]">{props.item.statement_start_date ? `${date(props.item.statement_start_date)} → ${date(props.item.statement_end_date)}` : "Date de fin du relevé"}</p></div>{props.item.statement_balance !== null && <p className="text-sm font-bold tabular-nums">{euro(props.item.statement_balance)}</p>}</div>
    <div className="mt-2"><ReconciliationStatus reconciliation={props.reconciliation} /></div>
    <div className="mt-2"><StatementActions {...props} isValidated={isValidated} /></div>
  </article>;
}

function ReconciliationStatus({ reconciliation }: { reconciliation: BankReconciliationListState | null }) {
  const label = reconciliation?.status === "validated"
    ? "Contrôle validé"
    : reconciliation?.status === "draft"
      ? "Contrôle en brouillon"
      : "Contrôle non commencé";
  return <span className="text-xs font-semibold text-[#64748B]">{label}</span>;
}

function StatementActions({ personId, accountId, item, canManage, durableOperationsEnabled, isValidated }: StatementProps & { isValidated: boolean }) {
  const [editing, setEditing] = useState(false), [correcting, setCorrecting] = useState(false), [history, setHistory] = useState(false), [deleting, setDeleting] = useState(false), [deletingDocument, setDeletingDocument] = useState(false); const endpoint = `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}`; const hasDocument = item.original_file_name !== null && item.mime_type !== null && item.file_size !== null;
  return <><div className="flex flex-wrap gap-1.5">{hasDocument ? <><a className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" href={endpoint} target="_blank" rel="noreferrer"><ExternalLink size={13} />Voir</a><a className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" href={`${endpoint}?download=1`}><Download size={13} />Télécharger</a><button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" onClick={() => setHistory(true)}><History size={13} />Historique</button></> : <span className="self-center text-xs text-[#64748B]">Aucun PDF</span>}{canManage && isValidated && hasDocument && <button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" onClick={() => setCorrecting(true)}><FileClock size={13} />Corriger le document</button>}{canManage && !isValidated && <><button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs" onClick={() => setEditing(true)}><FilePenLine size={13} />Modifier</button>{hasDocument && durableOperationsEnabled && <button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs text-red-700" onClick={() => setDeletingDocument(true)}><FileX2 size={13} />Supprimer le PDF</button>}{(!hasDocument || !durableOperationsEnabled) && <button className="button button-secondary min-h-8 gap-1 px-2.5 text-xs text-red-700" onClick={() => setDeleting(true)}><Trash2 size={13} />Supprimer</button>}</>}</div><StatementDialog personId={personId} accountId={accountId} item={item} open={editing} close={() => setEditing(false)} />{correcting && <DocumentCorrectionDialog endpoint={endpoint} item={item} open close={() => setCorrecting(false)} />}{history && <DocumentHistoryDialog endpoint={endpoint} open close={() => setHistory(false)} />}<DocumentDeleteDialog endpoint={endpoint} item={item} open={deletingDocument} close={() => setDeletingDocument(false)} /><DeleteDialog endpoint={endpoint} item={item} open={deleting} close={() => setDeleting(false)} /></>;
}

type DocumentVersion = { versionId: string; versionNumber: number; originalFileName: string; fileSize: number; sha256: string | null; integrityStatus: "pending_hash" | "verified"; correctionReason: string | null; createdAt: string; isActive: boolean; activeRevision: number };

function DocumentCorrectionDialog({ endpoint, item, open, close }: { endpoint: string; item: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false), [loading, setLoading] = useState(true), [message, setMessage] = useState(""), [success, setSuccess] = useState(false), [revision, setRevision] = useState<number | null>(null), [confirmed, setConfirmed] = useState(false);
  const requestId = useRef(crypto.randomUUID());
  const fileInput = useRef<HTMLInputElement>(null);
  const formId = `statement-correction-${item.id}`;
  useEffect(() => {
    if (!open) return;
    fetch(`${endpoint}/versions`, { cache: "no-store" }).then(async (response) => {
      const result = await response.json() as { versions?: DocumentVersion[]; message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de préparer la correction.");
      const active = result.versions?.find((version) => version.isActive);
      if (!active) throw new Error("Aucune version active n’est disponible.");
      setRevision(active.activeRevision);
    }).catch((error) => setMessage(error instanceof Error ? error.message : "Impossible de préparer la correction.")).finally(() => setLoading(false));
  }, [endpoint, open]);
  function intentChanged() { requestId.current = crypto.randomUUID(); setConfirmed(false); setSuccess(false); }
  async function submit(form: FormData) {
    if (revision === null || !confirmed) return;
    setBusy(true); setMessage("");
    form.set("clientRequestId", requestId.current); form.set("expectedActiveRevision", String(revision));
    try {
      const response = await fetch(`${endpoint}/versions`, { method: "POST", body: form });
      const result = await response.json() as { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de corriger le document.");
      if (fileInput.current) fileInput.current.value = "";
      requestId.current = crypto.randomUUID(); setSuccess(true); setMessage(result.message || "Le document a été corrigé."); router.refresh();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de corriger le document."); }
    finally { setBusy(false); }
  }
  return <AppConfirmDialog open={open} onClose={busy ? () => undefined : close} title="Corriger le document du relevé" description="Le rapprochement, ses soldes et ses opérations resteront inchangés. Le PDF actuel sera conservé dans l’historique." subject={date(item.statement_end_date)} requireExplicitClose={busy} actions={success ? <button className="button button-primary" type="button" onClick={close}>Fermer</button> : <button className="button button-primary" type="submit" form={formId} disabled={busy || loading || revision === null || !confirmed}>{busy ? "Correction…" : "Confirmer la correction"}</button>}><form id={formId} action={submit} className="space-y-3"><label><span className="auth-label">Nouveau PDF</span><input ref={fileInput} name="file" type="file" accept="application/pdf" required onChange={intentChanged} disabled={success} className="block max-w-full text-xs file:mr-2 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:font-semibold" /></label><label><span className="auth-label">Motif de la correction</span><textarea name="reason" required minLength={3} maxLength={1000} onChange={intentChanged} disabled={success} className="auth-input min-h-24" /></label><label className="flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-xs text-amber-900"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={success} className="mt-0.5" /><span>Je confirme que seul le PDF doit être corrigé et que l’ancienne version doit rester consultable.</span></label>{loading && <p role="status" className="text-xs text-[#64748B]">Préparation de la correction…</p>}{message && <p role={success ? "status" : "alert"} className={`rounded-lg px-3 py-2 text-xs ${success ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-700"}`}>{message}</p>}</form></AppConfirmDialog>;
}

function DocumentHistoryDialog({ endpoint, open, close }: { endpoint: string; open: boolean; close: () => void }) {
  const [versions, setVersions] = useState<DocumentVersion[]>([]), [loading, setLoading] = useState(true), [message, setMessage] = useState("");
  useEffect(() => {
    if (!open) return;
    fetch(`${endpoint}/versions`, { cache: "no-store" }).then(async (response) => {
      const result = await response.json() as { versions?: DocumentVersion[]; message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de charger l’historique.");
      setVersions(result.versions ?? []);
    }).catch((error) => setMessage(error instanceof Error ? error.message : "Impossible de charger l’historique.")).finally(() => setLoading(false));
  }, [endpoint, open]);
  return <AppConfirmDialog open={open} onClose={close} title="Historique du document" description="Chaque version est conservée et protégée par les droits du dossier." size="wide" actions={<span />}>
    {loading ? <p role="status" className="text-sm text-[#64748B]">Chargement…</p> : message ? <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p> : <ol className="space-y-2">{versions.map((version) => { const versionEndpoint = `${endpoint}/versions/${version.versionId}`; return <li key={version.versionId} className="rounded-lg border border-[#E2E8F0] p-3 text-xs"><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-bold">Version {version.versionNumber}{version.isActive ? " · Active" : ""}</p><p className="text-[#64748B]">{version.originalFileName} · {(version.fileSize / 1024).toLocaleString("fr-FR", { maximumFractionDigits: 1 })} Ko</p><p className="text-[#64748B]">Enregistrée le {new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(version.createdAt))}</p></div><span className="flex gap-1.5"><a className="button button-secondary min-h-8 px-2.5 text-xs" href={versionEndpoint} target="_blank" rel="noreferrer">Voir</a><a className="button button-secondary min-h-8 px-2.5 text-xs" href={`${versionEndpoint}?download=1`}>Télécharger</a></span></div>{version.correctionReason && <p className="mt-2 rounded bg-slate-50 px-2 py-1.5"><strong>Motif :</strong> {version.correctionReason}</p>}<p className="mt-2 text-[11px] text-[#64748B]">Intégrité : {version.integrityStatus === "verified" ? "empreinte vérifiée" : "empreinte calculée à la première consultation"}</p></li>; })}</ol>}
  </AppConfirmDialog>;
}

function StatementDialog({ personId, accountId, item, open, close }: { personId: string; accountId: string; item?: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter(); const [busy, setBusy] = useState(false), [message, setMessage] = useState(""); const input = useRef<HTMLInputElement>(null); const clientRequestId = useRef<string | null>(null); const formId = `statement-${item?.id ?? "new"}`; const endpoint = item ? `/api/dossiers/${personId}/comptes/${accountId}/releves/${item.id}` : `/api/dossiers/${personId}/comptes/${accountId}/releves`;
  async function submit(form: FormData) { setBusy(true); setMessage(""); if (!item) { clientRequestId.current ??= crypto.randomUUID(); form.set("clientRequestId", clientRequestId.current); } try { const response = await fetch(endpoint, { method: "POST", body: form }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Impossible d’enregistrer le relevé."); if (input.current) input.current.value = ""; clientRequestId.current = null; close(); router.refresh(); } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible d’enregistrer le relevé."); } finally { setBusy(false); } }
  return <AppConfirmDialog open={open} onClose={close} title={item ? "Modifier le relevé" : "Ajouter un relevé"} description={item ? "Modifiez les informations ou choisissez un PDF pour ajouter ou remplacer le document." : "Renseignez le relevé et ajoutez éventuellement son PDF."} actions={<button className="button button-primary" type="submit" form={formId} disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer"}</button>}><form id={formId} action={submit} className="grid gap-3 sm:grid-cols-2"><Field name="statementStartDate" label="Date de début (facultative)" type="date" value={item?.statement_start_date} /><Field name="statementEndDate" label="Date de fin" type="date" value={item?.statement_end_date} required /><Field name="statementBalance" label="Solde final (facultatif)" type="number" value={item?.statement_balance} /><Field name="note" label="Note (facultative)" value={item?.note} /><label className="sm:col-span-2"><span className="auth-label">Fichier PDF (facultatif)</span><input ref={input} className="block max-w-full text-xs file:mr-2 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:font-semibold" name="file" type="file" accept="application/pdf" /></label>{message && <p role="alert" className="sm:col-span-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</form></AppConfirmDialog>;
}

function DocumentDeleteDialog({ endpoint, item, open, close }: { endpoint: string; item: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter(); const [busy, setBusy] = useState(false), [message, setMessage] = useState(""); async function remove() { setBusy(true); setMessage(""); try { const response = await fetch(`${endpoint}?document=1`, { method: "DELETE" }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Impossible de supprimer le PDF du relevé."); close(); router.refresh(); } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de supprimer le PDF du relevé."); } finally { setBusy(false); } }
  return <AppConfirmDialog open={open} onClose={close} title="Supprimer le PDF de ce relevé ?" description="Le relevé bancaire et ses informations seront conservés. Seul le document PDF sera supprimé de manière sécurisée." subject={date(item.statement_end_date)} actions={<button className="button button-danger" onClick={remove} disabled={busy}>{busy ? "Suppression…" : "Supprimer le PDF"}</button>}>{message && <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</AppConfirmDialog>;
}

function DeleteDialog({ endpoint, item, open, close }: { endpoint: string; item: BankStatement; open: boolean; close: () => void }) {
  const router = useRouter(); const [busy, setBusy] = useState(false), [message, setMessage] = useState(""); async function remove() { setBusy(true); setMessage(""); try { const response = await fetch(endpoint, { method: "DELETE" }); const result = await response.json() as { message?: string }; if (!response.ok) throw new Error(result.message || "Impossible de supprimer le relevé."); close(); router.refresh(); } catch (error) { setMessage(error instanceof Error ? error.message : "Impossible de supprimer le relevé."); } finally { setBusy(false); } }
  return <AppConfirmDialog open={open} onClose={close} title="Supprimer ce relevé ?" description="Le fichier privé et ses métadonnées seront supprimés." subject={date(item.statement_end_date)} actions={<button className="button button-danger" onClick={remove} disabled={busy}>{busy ? "Suppression…" : "Supprimer le relevé"}</button>}>{message && <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</AppConfirmDialog>;
}

function Field({ name, label, type = "text", value, required }: { name: string; label: string; type?: string; value?: string | number | null; required?: boolean }) { return <label><span className="auth-label">{label}</span><input className="auth-input" name={name} type={type} step={type === "number" ? "0.01" : undefined} defaultValue={value ?? ""} required={required} /></label>; }
