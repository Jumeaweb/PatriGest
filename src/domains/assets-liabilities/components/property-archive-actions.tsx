"use client";

import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { Archive, ArchiveRestore } from "lucide-react";
import { FieldError, FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { changePropertyArchiveStateAction } from "../actions";
import { initialAssetLiabilityState } from "../state";

type Props = {
  personId: string;
  propertyId: string;
  propertyName: string;
  archiveRevision: number;
  archived: boolean;
};

export function PropertyArchiveAction({ personId, propertyId, propertyName, archiveRevision, archived }: Props) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const operation = archived ? "restore" : "archive";
  const [state, action, pending] = useActionState(
    changePropertyArchiveStateAction.bind(null, personId, propertyId, archiveRevision, operation),
    initialAssetLiabilityState,
  );
  const completed = state.status === "success";
  const formId = `property-${operation}-${propertyId}`;

  function close() {
    setOpen(false);
    if (completed) router.refresh();
  }

  return <>
    <button
      type="button"
      className={`button gap-1 px-3 ${archived ? "button-primary" : "button-secondary text-amber-800"}`}
      onClick={() => setOpen(true)}
    >
      {archived ? <ArchiveRestore aria-hidden="true" size={13} /> : <Archive aria-hidden="true" size={13} />}
      {archived ? "Restaurer le bien" : "Archiver le bien"}
    </button>
    <AppConfirmDialog
      open={open}
      onClose={close}
      title={archived ? "Restaurer ce bien ?" : "Archiver ce bien ?"}
      description={completed
        ? state.message
        : archived
          ? "Confirmez la restauration. Le bien réapparaîtra dans les vues patrimoniales courantes sans modification de son statut ni de sa date de cession."
          : "Confirmez l’archivage. Le bien sera retiré des vues patrimoniales courantes, sans suppression de ses données. Ses événements et historiques resteront conservés et une restauration autorisée restera possible."}
      subject={`${propertyName} · Révision ${archiveRevision}`}
      cancelLabel={completed ? "Fermer" : "Annuler"}
      actions={completed ? null : <button type="submit" form={formId} className="button button-primary" disabled={pending}>{pending ? "Enregistrement…" : archived ? "Confirmer la restauration" : "Confirmer l’archivage"}</button>}
    >
      {!completed && <form id={formId} action={action} className="grid gap-3">
        <div>
          <label className="auth-label" htmlFor={`${formId}-reason`}>Motif {archived ? "de la restauration" : "de l’archivage"}</label>
          <textarea
            className="auth-input min-h-24 resize-y py-2"
            id={`${formId}-reason`}
            name="reason"
            required
            maxLength={2000}
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
