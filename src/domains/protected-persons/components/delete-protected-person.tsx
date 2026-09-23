"use client";

import { useActionState, useState } from "react";
import { FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { deleteProtectedPersonAction } from "../actions";
import { initialProtectedPersonState } from "../state";

export function DeleteProtectedPerson({ protectedPersonId, personName }: { protectedPersonId: string; personName: string }) {
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(deleteProtectedPersonAction.bind(null, protectedPersonId), initialProtectedPersonState);
  return <><button type="button" className="button button-danger" onClick={() => setOpen(true)}>Supprimer le dossier</button><form action={action}><AppConfirmDialog open={open} title="Supprimer ce dossier ?" description="Cette action est définitive. Le dossier doit être vide avant de pouvoir être supprimé." subject={personName} onClose={() => setOpen(false)} actions={<button type="submit" className="button button-danger">Supprimer le dossier</button>}><FormMessage state={state} /></AppConfirmDialog></form></>;
}
