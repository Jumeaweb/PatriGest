"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { FieldError, FormMessage, SubmitButton } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { requestEmailChangeAction, resendEmailChangeAction } from "../actions";
import { initialAccountState } from "../state";

export function EmailForm({ currentEmail, pendingEmail }: { currentEmail: string; pendingEmail: string | null }) {
  if (pendingEmail) return <PendingEmailChange currentEmail={currentEmail} pendingEmail={pendingEmail} />;

  return <NewEmailChangeForm currentEmail={currentEmail} />;
}

function NewEmailChangeForm({ currentEmail }: { currentEmail: string }) {
  const [state, action] = useActionState(requestEmailChangeAction, initialAccountState);
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => { if (state.status === "success") formRef.current?.reset(); }, [state]);

  return <form ref={formRef} action={action} className="mt-4 space-y-4">
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="rounded-xl bg-slate-50 px-3.5 py-3"><p className="text-xs font-semibold text-[#64748B]">Adresse e-mail actuelle</p><p className="mt-1 break-all text-sm font-bold">{currentEmail}</p></div>
    </div>
    <div><label className="auth-label" htmlFor="emailCurrentPassword">Mot de passe actuel</label><input className="auth-input" id="emailCurrentPassword" name="currentPassword" type="password" autoComplete="current-password" required aria-invalid={Boolean(state.fieldErrors?.currentPassword)} /><FieldError messages={state.fieldErrors?.currentPassword} /></div>
    <div className="grid gap-4 sm:grid-cols-2">
      <div><label className="auth-label" htmlFor="newEmail">Nouvelle adresse e-mail</label><input className="auth-input" id="newEmail" name="newEmail" type="email" autoComplete="email" required aria-invalid={Boolean(state.fieldErrors?.newEmail)} /><FieldError messages={state.fieldErrors?.newEmail} /></div>
      <div><label className="auth-label" htmlFor="emailConfirmation">Confirmer la nouvelle adresse e-mail</label><input className="auth-input" id="emailConfirmation" name="emailConfirmation" type="email" autoComplete="email" required aria-invalid={Boolean(state.fieldErrors?.emailConfirmation)} /><FieldError messages={state.fieldErrors?.emailConfirmation} /></div>
    </div>
    <p className="text-xs leading-5 text-[#64748B]">Une confirmation peut être nécessaire avant que la nouvelle adresse devienne votre identifiant de connexion.</p>
    <FormMessage state={state} />
    <div className="w-full [&_.auth-submit]:whitespace-nowrap [&_.auth-submit]:px-5 sm:w-auto sm:[&_.auth-submit]:w-auto"><SubmitButton pendingLabel="Enregistrement…">Modifier mon adresse e-mail</SubmitButton></div>
  </form>;
}

function PendingEmailChange({ currentEmail, pendingEmail }: { currentEmail: string; pendingEmail: string }) {
  const [state, action, pending] = useActionState(resendEmailChangeAction, initialAccountState);
  const [successDialogDismissed, setSuccessDialogDismissed] = useState(false);

  return <>
    <div className="mt-4 grid gap-3 sm:grid-cols-2">
      <div className="rounded-xl bg-slate-50 px-3.5 py-3"><p className="text-xs font-semibold text-[#64748B]">Adresse e-mail actuelle</p><p className="mt-1 break-all text-sm font-bold">{currentEmail}</p></div>
      <div className="rounded-xl bg-amber-50 px-3.5 py-3"><p className="text-xs font-semibold text-[#92400E]">Changement en attente</p><p className="mt-1 break-all text-sm font-bold text-[#78350F]">{pendingEmail}</p><p className="mt-1.5 text-xs leading-5 text-[#92400E]">La confirmation du changement n’est pas encore terminée.</p></div>
    </div>
    <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50/60 px-3.5 py-3 text-sm leading-6 text-[#78350F]">
      Terminez les confirmations reçues aux deux adresses avant de demander un autre changement. Le formulaire de nouvelle adresse est temporairement bloqué pour éviter d’écraser cette demande.
    </div>
    <form action={action} className="mt-4 space-y-3" onSubmit={() => setSuccessDialogDismissed(false)}>
      {state.status === "error" && <FormMessage state={state} />}
      <div className="w-full [&_.auth-submit]:whitespace-nowrap [&_.auth-submit]:px-5 sm:w-auto sm:[&_.auth-submit]:w-auto"><SubmitButton pendingLabel="Renvoi…">Renvoyer les confirmations</SubmitButton></div>
    </form>
    <AppConfirmDialog
      open={state.status === "success" && !successDialogDismissed && !pending}
      title="Confirmations renvoyées"
      description="Les confirmations du changement d’adresse e-mail ont été renvoyées aux adresses concernées. Consultez les deux boîtes de réception pour terminer la modification."
      cancelLabel="Fermer"
      actions={null}
      onClose={() => setSuccessDialogDismissed(true)}
      requireExplicitClose
    />
  </>;
}
