"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { resendApplicationActivationEmailAction, reviewApplicationRegistrationAction } from "../actions";
import { initialRegistrationReviewState } from "../state";

export function RegistrationReviewActions({ userId, email }: { userId: string; email: string }) {
  const router = useRouter();
  const [decision, setDecision] = useState<"active" | "rejected" | null>(null);
  const [state, action] = useActionState(reviewApplicationRegistrationAction, initialRegistrationReviewState);
  const completed = state.status === "success" || state.status === "warning";
  function closeDialog() {
    setDecision(null);
    if (completed) router.refresh();
  }

  return <div>
    <span className="mb-2 inline-block rounded-full bg-amber-50 px-2 py-1 text-xs font-semibold text-amber-800">En attente</span>
    {!completed && <div className="flex flex-wrap gap-2">
      <button className="button button-primary" type="button" onClick={() => setDecision("active")}>Autoriser l’accès</button>
      <button className="button button-secondary" type="button" onClick={() => setDecision("rejected")}>Refuser</button>
    </div>}
    <form action={action}>
      <input type="hidden" name="userId" value={userId} />
      <input type="hidden" name="decision" value={decision ?? ""} />
      <AppConfirmDialog
        open={decision !== null}
        title={decision === "active" ? "Autoriser l’accès à PatriGest ?" : "Refuser cette inscription ?"}
        description={completed ? "La décision a été enregistrée." : decision === "active" ? "Le compte pourra accéder à PatriGest et un e-mail d’activation sera envoyé." : "Le compte sera conservé, mais ne pourra accéder à aucune donnée métier."}
        subject={email}
        onClose={closeDialog}
        cancelLabel={completed ? "Fermer" : "Annuler"}
        actions={completed ? null : <ReviewSubmit label={decision === "active" ? "Autoriser l’accès" : "Refuser"} />}
      >
        {state.message && <p className={`text-sm font-semibold ${state.status === "error" ? "text-red-700" : state.status === "warning" ? "text-amber-700" : "text-green-700"}`} role={state.status === "error" ? "alert" : "status"} aria-live="polite">{state.message}</p>}
      </AppConfirmDialog>
    </form>
  </div>;
}

export function ResendActivationEmailButton({ userId, email }: { userId: string; email: string }) {
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(resendApplicationActivationEmailAction, initialRegistrationReviewState);
  const succeeded = state.status === "success";
  return <>
    <button type="button" className="button button-secondary" onClick={() => setOpen(true)}>Renvoyer l’e-mail d’activation</button>
    <form action={action}>
      <input type="hidden" name="userId" value={userId} />
      <AppConfirmDialog open={open} onClose={() => setOpen(false)} title="Renvoyer l’e-mail d’activation ?" description={succeeded ? "L’e-mail d’activation a été renvoyé." : "Un nouvel e-mail d’activation va être envoyé à cette adresse."} subject={email} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <ResendSubmit />}>
        {state.message && <p className={`text-sm font-semibold ${state.status === "error" ? "text-red-700" : "text-green-700"}`} role={state.status === "error" ? "alert" : "status"} aria-live="polite">{state.message}</p>}
      </AppConfirmDialog>
    </form>
  </>;
}

function ReviewSubmit({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return <button className="button button-primary" type="submit" disabled={pending}>{pending ? "Traitement…" : label}</button>;
}

function ResendSubmit() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-primary" disabled={pending}>{pending ? "Envoi…" : "Renvoyer l’e-mail"}</button>;
}
