"use client";

import { useActionState, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { FieldError, FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { deletePlatformUserAction } from "../actions";
import { initialDeleteUserState } from "../state";

export function DeleteUserButton({ userId, name, email }: { userId: string; name: string; email: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(deletePlatformUserAction.bind(null, userId), initialDeleteUserState);
  const attemptId = useRef<string | null>(null);
  const succeeded = state.status === "success";
  function closeDialog() {
    setOpen(false);
    attemptId.current = null;
    if (succeeded) router.refresh();
  }
  function submit(formData: FormData) {
    attemptId.current ??= crypto.randomUUID();
    formData.set("attemptId", attemptId.current);
    action(formData);
  }
  const formId = `delete-platform-user-${userId}`;
  return <><button type="button" className="button button-danger" onClick={() => setOpen(true)}>Supprimer l’utilisateur</button><form action={submit}><AppConfirmDialog open={open} title="Supprimer cet utilisateur ?" description={succeeded ? "Le compte utilisateur a été supprimé." : "Cette action est irréversible. Le compte Auth est supprimé uniquement après vérification des protections métier et documentaires."} subject={`${name || "Nom non renseigné"} — ${email}`} onClose={closeDialog} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <DeleteSubmitButton />}><div className="grid gap-3"><div><label className="auth-label" htmlFor={`${formId}-reason`}>Motif de la suppression</label><textarea className="auth-input min-h-24 resize-y py-2" id={`${formId}-reason`} name="reason" required maxLength={2000} aria-invalid={Boolean(state.fieldErrors?.reason?.length)} /><FieldError messages={state.fieldErrors?.reason} /></div><label className="flex items-start gap-3 rounded-xl border border-red-200 bg-red-50/60 px-3 py-2 text-sm leading-5 text-[#7F1D1D]"><input className="mt-1 size-4 shrink-0 accent-red-700" type="checkbox" name="confirmation" required aria-invalid={Boolean(state.fieldErrors?.confirmation?.length)} /><span>Je confirme la suppression définitive de ce compte utilisateur.</span></label><FieldError messages={state.fieldErrors?.confirmation} /><FormMessage state={state} /></div></AppConfirmDialog></form></>;
}

function DeleteSubmitButton() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-danger" disabled={pending}>{pending ? "Suppression…" : "Supprimer définitivement"}</button>;
}
