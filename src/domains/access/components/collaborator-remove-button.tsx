"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { UserMinus } from "lucide-react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { removeCollaboratorAction } from "@/domains/access/actions";
import { initialAccessState, isCompletedAccessAction } from "@/domains/access/state";

export function CollaboratorRemoveButton({
  protectedPersonId,
  accessId,
  collaboratorName,
}: {
  protectedPersonId: string;
  accessId: string;
  collaboratorName: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(
    removeCollaboratorAction.bind(null, protectedPersonId, accessId),
    initialAccessState,
  );
  const succeeded = isCompletedAccessAction(state);
  function closeDialog() {
    setOpen(false);
    if (succeeded) router.refresh();
  }

  return <div>
    <button type="button" className="button button-secondary gap-1.5 text-red-700" onClick={() => setOpen(true)}>
      <UserMinus aria-hidden="true" size={15} />Retirer
    </button>
    <form action={action}>
      <AppConfirmDialog
        open={open}
        onClose={closeDialog}
        title="Retirer l’accès au dossier ?"
        description={succeeded ? "L’accès a été retiré." : `${collaboratorName} ne pourra plus accéder à ce dossier.`}
        cancelLabel={succeeded ? "Fermer" : "Annuler"}
        actions={succeeded ? null : <RemoveButton />}
      >
        {state.message && <p role={state.status === "error" ? "alert" : "status"} aria-live="polite" className={`rounded-lg px-3 py-2 text-sm ${state.status === "error" ? "bg-red-50 text-red-700" : "bg-green-50 text-green-700"}`}>{state.message}</p>}
      </AppConfirmDialog>
    </form>
  </div>;
}

function RemoveButton() {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} className="button button-danger">{pending ? "Retrait…" : "Retirer l’accès"}</button>;
}
