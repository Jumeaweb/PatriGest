"use client";

import { useActionState, useState } from "react";
import { Ban, Trash2 } from "lucide-react";
import { FieldError, FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { deleteTransactionAction, deleteTransferAction } from "../actions";
import { initialTransactionState } from "../state";

export function TransactionDeleteButton({ personId, transactionId, transactionRevision, transferId, label, transactionDate, amount, returnHref }: { personId: string; transactionId: string; transactionRevision: number; transferId?: string; label: string; transactionDate?: string; amount?: number; returnHref: string }) {
  const [open, setOpen] = useState(false);
  const [clientRequestId] = useState(() => crypto.randomUUID());
  const action = transferId ? deleteTransferAction.bind(null, personId, transferId, returnHref) : deleteTransactionAction.bind(null, personId, transactionId, returnHref);
  const [state, formAction, pending] = useActionState(action, initialTransactionState);
  const description = transferId
    ? "Le virement et ses deux mouvements resteront visibles dans l’historique, mais seront exclus des calculs courants."
    : "L’opération restera visible dans le journal et son historique, mais elle sera exclue des calculs courants.";
  return <><button type="button" className="button button-danger gap-1.5" onClick={() => setOpen(true)}>{transferId ? <Trash2 size={15} /> : <Ban size={15} />}{transferId ? "Annuler le virement" : "Annuler l’opération"}</button><AppConfirmDialog open={open} onClose={() => setOpen(false)} title={transferId ? "Annuler ce virement ?" : "Annuler cette opération ?"} description={description} subject={label} actions={<button className="button button-danger" type="submit" form={`delete-${transactionId}`} disabled={pending}>{pending ? "Traitement…" : "Confirmer l’annulation"}</button>}><form id={`delete-${transactionId}`} action={formAction} className="space-y-3">{!transferId && <dl className="grid grid-cols-2 gap-2 rounded-lg bg-slate-50 p-3 text-xs"><div><dt className="font-semibold text-[#64748B]">Date</dt><dd>{transactionDate ?? "—"}</dd></div><div><dt className="font-semibold text-[#64748B]">Montant historique</dt><dd>{amount === undefined ? "—" : amount.toLocaleString("fr-FR", { style: "currency", currency: "EUR" })}</dd></div></dl>}<input type="hidden" name="clientRequestId" value={clientRequestId} /><input type="hidden" name="expectedRevision" value={transactionRevision} /><div><label className="auth-label" htmlFor={`reason-${transactionId}`}>Motif de l’annulation *</label><textarea className="auth-input min-h-20 py-2" id={`reason-${transactionId}`} name="reason" required minLength={3} maxLength={1000} aria-invalid={Boolean(state.fieldErrors?.reason?.length)} /><FieldError messages={state.fieldErrors?.reason} /></div><FormMessage state={state} /></form></AppConfirmDialog></>;
}
