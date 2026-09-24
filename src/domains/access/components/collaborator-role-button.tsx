"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Pencil } from "lucide-react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { updateCollaboratorRoleAction } from "@/domains/access/actions";
import { initialAccessState, isCompletedAccessAction } from "@/domains/access/state";

export function CollaboratorRoleButton({
  protectedPersonId,
  accessId,
  collaboratorName,
  role: persistedRole,
}: {
  protectedPersonId: string;
  accessId: string;
  collaboratorName: string;
  role: "manager" | "read_only";
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [role, setRole] = useState(persistedRole);
  const [state, action] = useActionState(
    updateCollaboratorRoleAction.bind(null, protectedPersonId, accessId),
    initialAccessState,
  );
  const succeeded = isCompletedAccessAction(state);
  function closeDialog() {
    setOpen(false);
    if (succeeded) router.refresh();
  }

  return <>
    <button type="button" className="button button-secondary min-h-8 gap-1.5 px-3 text-xs" onClick={() => { setRole(persistedRole); setOpen(true); }}>
      <Pencil aria-hidden="true" size={14} />Modifier
    </button>
    <form action={action}>
      <AppConfirmDialog
        open={open}
        onClose={closeDialog}
        title="Modifier le rôle"
        description={succeeded ? "La modification est terminée." : "Choisissez le niveau d’accès de ce collaborateur."}
        subject={collaboratorName}
        cancelLabel={succeeded ? "Fermer" : "Annuler"}
        actions={succeeded ? null : <SaveRoleButton />}
      >
        {succeeded ? <ActionMessage status="success" message={state.message} /> : <div>
          <label className="auth-label" htmlFor={`collaborator-role-${accessId}`}>Rôle</label>
          <select
            className="auth-input"
            id={`collaborator-role-${accessId}`}
            name="role"
            value={role}
            onChange={(event) => setRole(event.target.value as "manager" | "read_only")}
          >
            <option value="manager">Gestionnaire</option>
            <option value="read_only">Lecture seule</option>
          </select>
          {state.status === "error" && <ActionMessage status="error" message={state.message} />}
        </div>}
      </AppConfirmDialog>
    </form>
  </>;
}

function SaveRoleButton() {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} className="button button-primary">{pending ? "Enregistrement…" : "Enregistrer"}</button>;
}

function ActionMessage({ status, message }: { status: "success" | "error"; message?: string }) {
  if (!message) return null;
  return <p role={status === "error" ? "alert" : "status"} aria-live="polite" className={`mt-3 rounded-lg px-3 py-2 text-sm ${status === "error" ? "bg-red-50 text-red-700" : "bg-green-50 text-green-700"}`}>{message}</p>;
}
