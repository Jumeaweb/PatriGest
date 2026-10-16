"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { Pencil } from "lucide-react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { updateCollaboratorRoleAction } from "@/domains/access/actions";
import { initialAccessState, isCompletedAccessAction } from "@/domains/access/state";
import type { SharedAccessRole } from "@/types/database";

export function CollaboratorRoleButton({
  protectedPersonId,
  accessId,
  collaboratorName,
  role: persistedRole,
  roleAvailability,
}: {
  protectedPersonId: string;
  accessId: string;
  collaboratorName: string;
  role: SharedAccessRole;
  roleAvailability: Record<SharedAccessRole, boolean>;
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
            onChange={(event) => setRole(event.target.value as SharedAccessRole)}
            aria-describedby="collaborator-role-capacity"
          >
            <option value="manager" disabled={persistedRole !== "manager" && !roleAvailability.manager}>
              Gestionnaire{persistedRole !== "manager" && !roleAvailability.manager ? " (limite atteinte)" : ""}
            </option>
            <option value="read_only" disabled={persistedRole !== "read_only" && !roleAvailability.read_only}>
              Lecture seule{persistedRole !== "read_only" && !roleAvailability.read_only ? " (limite atteinte)" : ""}
            </option>
          </select>
          <p id="collaborator-role-capacity" className="mt-1 text-xs text-[#64748B]">
            Un rôle dont la limite est atteinte ne peut pas recevoir de collaborateur supplémentaire.
          </p>
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
