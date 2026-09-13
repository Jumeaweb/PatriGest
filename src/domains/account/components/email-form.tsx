"use client";

import { useActionState, useEffect, useRef } from "react";
import { FieldError, FormMessage, SubmitButton } from "@/components/auth/form-controls";
import { requestEmailChangeAction } from "../actions";
import { initialAccountState } from "../state";

export function EmailForm({ currentEmail, pendingEmail }: { currentEmail: string; pendingEmail: string | null }) {
  const [state, action] = useActionState(requestEmailChangeAction, initialAccountState);
  const formRef = useRef<HTMLFormElement>(null);
  useEffect(() => { if (state.status === "success") formRef.current?.reset(); }, [state]);

  return <form ref={formRef} action={action} className="mt-4 space-y-4">
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="rounded-xl bg-slate-50 px-3.5 py-3"><p className="text-xs font-semibold text-[#64748B]">Adresse e-mail actuelle</p><p className="mt-1 break-all text-sm font-bold">{currentEmail}</p></div>
      {pendingEmail && <div className="rounded-xl bg-amber-50 px-3.5 py-3"><p className="text-xs font-semibold text-[#92400E]">Changement en attente</p><p className="mt-1 break-all text-sm font-bold text-[#78350F]">{pendingEmail}</p><p className="mt-1.5 text-xs leading-5 text-[#92400E]">La confirmation du changement n’est pas encore terminée.</p></div>}
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
