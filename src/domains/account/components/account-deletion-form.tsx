"use client";

import { useActionState } from "react";
import { FieldError, FormMessage, SubmitButton } from "@/components/auth/form-controls";
import { deleteOwnAccountAction } from "../actions";
import { initialAccountState } from "../state";

type Eligibility = "eligible" | "blocked_owned_dossiers" | "blocked_platform_admin";

export function AccountDeletionForm({ eligibility }: { eligibility: Eligibility }) {
  const [state, action] = useActionState(deleteOwnAccountAction, initialAccountState);

  if (eligibility === "blocked_owned_dossiers") {
    return <p className="mt-4 rounded-xl bg-amber-50 px-4 py-3 text-sm leading-6 text-[#92400E]">Vous devez d’abord transférer ou supprimer chaque dossier dont vous êtes propriétaire. Vos accès comme gestionnaire ou lecteur ne bloquent pas la suppression.</p>;
  }
  if (eligibility === "blocked_platform_admin") {
    return <p className="mt-4 rounded-xl bg-amber-50 px-4 py-3 text-sm leading-6 text-[#92400E]">Un administrateur PatriGest ne peut pas supprimer son propre compte.</p>;
  }

  return <form action={action} className="mt-4 space-y-4">
    <div><label className="auth-label" htmlFor="deleteCurrentPassword">Mot de passe actuel</label><input className="auth-input" id="deleteCurrentPassword" name="currentPassword" type="password" autoComplete="current-password" required maxLength={72} aria-invalid={Boolean(state.fieldErrors?.currentPassword)} /><FieldError messages={state.fieldErrors?.currentPassword} /></div>
    <label className="flex items-start gap-3 rounded-xl border border-red-200 bg-red-50/60 px-4 py-3 text-sm leading-6 text-[#7F1D1D]"><input className="mt-1 size-4 shrink-0 accent-red-700" type="checkbox" name="confirmation" required aria-invalid={Boolean(state.fieldErrors?.confirmation)} /><span>Je confirme vouloir supprimer définitivement mon compte PatriGest. Cette opération est irréversible.</span></label>
    <FieldError messages={state.fieldErrors?.confirmation} />
    <FormMessage state={state} />
    <div className="w-full [&_.auth-submit]:bg-[#B91C1C] [&_.auth-submit]:text-white [&_.auth-submit]:hover:bg-[#991B1B] sm:w-auto sm:[&_.auth-submit]:w-auto"><SubmitButton pendingLabel="Suppression…">Supprimer mon compte</SubmitButton></div>
  </form>;
}
