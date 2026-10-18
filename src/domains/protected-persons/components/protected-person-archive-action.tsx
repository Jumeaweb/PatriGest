"use client";

import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { Archive, ArchiveRestore } from "lucide-react";
import { FieldError, FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import {
  archiveProtectedPersonAction,
  restoreProtectedPersonAction,
} from "../actions";
import type { ProtectedPersonActionState } from "../state";

const initialState: ProtectedPersonActionState = { status: "idle", message: "" };

type Props = {
  protectedPersonId: string;
  personName: string;
  archiveRevision: number;
  archived: boolean;
};

export function ProtectedPersonArchiveAction({
  protectedPersonId,
  personName,
  archiveRevision,
  archived,
}: Props) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const operation = archived ? "restore" : "archive";
  const serverAction = archived ? restoreProtectedPersonAction : archiveProtectedPersonAction;
  const [state, action, pending] = useActionState(
    serverAction.bind(null, protectedPersonId, archiveRevision),
    initialState,
  );
  const completed = state.status === "success";
  const formId = `protected-person-${operation}-${protectedPersonId}`;

  function close() {
    if (pending) return;
    setOpen(false);
    if (completed) router.refresh();
  }

  return <>
    <button
      type="button"
      className={`button gap-2 ${archived ? "button-primary" : "button-secondary text-amber-800"}`}
      onClick={() => setOpen(true)}
    >
      {archived ? <ArchiveRestore aria-hidden="true" size={16} /> : <Archive aria-hidden="true" size={16} />}
      {archived ? "Restaurer le dossier" : "Archiver le dossier"}
    </button>
    <AppConfirmDialog
      open={open}
      onClose={close}
      requireExplicitClose={pending}
      title={archived ? "Restaurer ce dossier ?" : "Archiver ce dossier ?"}
      description={completed
        ? state.message
        : archived
          ? "Ce dossier redeviendra actif et comptera dans votre capacité de dossiers. La restauration sera refusée si votre plafond est atteint."
          : "Ce dossier sera conservé avec ses données et documents. Il ne comptera plus dans votre capacité de dossiers actifs."}
      subject={`${personName} · Révision ${archiveRevision}`}
      cancelLabel={completed ? "Fermer" : "Annuler"}
      actions={completed ? null : <button
        type="submit"
        form={formId}
        className="button button-primary"
        disabled={pending}
      >{pending ? "Enregistrement…" : archived ? "Confirmer la restauration" : "Confirmer l’archivage"}</button>}
    >
      {!completed && <form id={formId} action={action} className="grid gap-3">
        <div>
          <label className="auth-label" htmlFor={`${formId}-reason`}>
            Motif {archived ? "de la restauration" : "de l’archivage"}
          </label>
          <textarea
            className="auth-input min-h-24 resize-y py-2"
            id={`${formId}-reason`}
            name="reason"
            required
            maxLength={2000}
            disabled={pending}
            aria-invalid={Boolean(state.fieldErrors?.reason?.length)}
            aria-describedby={state.fieldErrors?.reason?.length ? `${formId}-reason-error` : undefined}
          />
          <div id={`${formId}-reason-error`}><FieldError messages={state.fieldErrors?.reason} /></div>
        </div>
        <FormMessage state={state} />
      </form>}
    </AppConfirmDialog>
  </>;
}
