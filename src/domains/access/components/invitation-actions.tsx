"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Ban, Check, Copy, RefreshCw } from "lucide-react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import {
  reissueDossierInvitationAction,
  revokeDossierInvitationAction,
} from "@/domains/access/actions";
import { initialAccessState, isCompletedAccessAction, type AccessActionState } from "@/domains/access/state";
import type { DossierInvitationStatus } from "@/domains/access/invitation-status";

export function InvitationActions({
  protectedPersonId,
  invitationId,
  email,
  status,
  canManage,
}: {
  protectedPersonId: string;
  invitationId: string;
  email: string;
  status: DossierInvitationStatus;
  canManage: boolean;
}) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"reissue" | "revoke" | null>(null);
  const [reissueState, reissueAction] = useActionState(
    reissueDossierInvitationAction.bind(null, protectedPersonId, invitationId),
    initialAccessState,
  );
  const [revokeState, revokeAction] = useActionState(
    revokeDossierInvitationAction.bind(null, protectedPersonId, invitationId),
    initialAccessState,
  );
  const canReissue = canManage && (status === "pending" || status === "expired");
  const canRevoke = canManage && status === "pending";
  const reissueFinished = isCompletedAccessAction(reissueState, true);
  const revokeFinished = isCompletedAccessAction(revokeState);
  function closeDialog() {
    const refresh = dialog === "reissue" ? reissueFinished : dialog === "revoke" ? revokeFinished : false;
    setDialog(null);
    if (refresh) router.refresh();
  }

  return <div className="flex flex-wrap items-center justify-end gap-2">
    {canReissue && <button type="button" className="button button-secondary min-h-8 gap-1.5 px-3 text-xs" onClick={() => setDialog("reissue")}><RefreshCw aria-hidden="true" size={14} />Renvoyer</button>}
    {canRevoke && <button type="button" className="button button-secondary min-h-8 gap-1.5 px-3 text-xs text-red-700" onClick={() => setDialog("revoke")}><Ban aria-hidden="true" size={14} />Annuler</button>}
    <form action={reissueAction}>
      <AppConfirmDialog open={dialog === "reissue"} onClose={closeDialog} title="Renvoyer cette invitation ?" description={reissueFinished ? "L’opération est terminée." : "L’ancien lien sera immédiatement invalidé et un nouveau lien valable 7 jours sera envoyé."} subject={email} cancelLabel={reissueFinished ? "Fermer" : "Annuler"} actions={reissueFinished ? null : <PendingButton label="Renvoyer" pendingLabel="Envoi…" />}>
        <InvitationActionMessage state={reissueState} />
      </AppConfirmDialog>
    </form>
    <form action={revokeAction}>
      <AppConfirmDialog open={dialog === "revoke"} onClose={closeDialog} title="Annuler cette invitation ?" description={revokeFinished ? "L’invitation a été annulée." : "Le lien ne pourra plus être utilisé. L’historique de l’invitation sera conservé."} subject={email} cancelLabel={revokeFinished ? "Fermer" : "Annuler"} actions={revokeFinished ? null : <PendingButton label="Annuler l’invitation" pendingLabel="Annulation…" destructive />}>
        <InvitationActionMessage state={revokeState} />
      </AppConfirmDialog>
    </form>
  </div>;
}

function PendingButton({ label, pendingLabel, destructive = false }: { label: string; pendingLabel: string; destructive?: boolean }) {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} className={`button ${destructive ? "button-danger" : "button-primary"}`}>{pending ? pendingLabel : label}</button>;
}

function InvitationActionMessage({ state }: { state: AccessActionState }) {
  const [copied, setCopied] = useState(false);
  if (!state.message) return null;
  return <div aria-live="polite"><p role={state.status === "error" ? "alert" : "status"} className={`rounded-lg px-3 py-2 text-sm ${state.status === "error" ? "bg-red-50 text-red-700" : state.status === "warning" ? "bg-amber-50 text-amber-800" : "bg-green-50 text-green-700"}`}>{state.message}</p>{state.invitationUrl && <button type="button" className="button button-secondary mt-2 gap-1.5" onClick={async () => { await navigator.clipboard.writeText(state.invitationUrl!); setCopied(true); }}>{copied ? <Check aria-hidden="true" size={14} /> : <Copy aria-hidden="true" size={14} />}{copied ? "Lien copié" : "Copier le lien"}</button>}</div>;
}
