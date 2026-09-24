"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { deletePlatformUserAction } from "../actions";
import { initialDeleteUserState } from "../state";

export function DeleteUserButton({ userId, name, email }: { userId: string; name: string; email: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(deletePlatformUserAction.bind(null, userId), initialDeleteUserState);
  const succeeded = state.status === "success";
  function closeDialog() {
    setOpen(false);
    if (succeeded) router.refresh();
  }
  return <><button type="button" className="button button-danger" onClick={() => setOpen(true)}>Supprimer l’utilisateur</button><form action={action}><AppConfirmDialog open={open} title="Supprimer cet utilisateur ?" description={succeeded ? "Le compte utilisateur a été supprimé." : "Cette action est irréversible. Le compte Auth, le profil et les accès sont supprimés lorsque les protections backend l’autorisent. Les données métier nécessaires à l’historique peuvent être conservées ou détachées de l’utilisateur."} subject={`${name || "Nom non renseigné"} — ${email}`} onClose={closeDialog} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <DeleteSubmitButton />}><FormMessage state={state} /></AppConfirmDialog></form></>;
}

function DeleteSubmitButton() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-danger" disabled={pending}>{pending ? "Suppression…" : "Supprimer définitivement"}</button>;
}
