"use client";

import { useActionState, useState } from "react";
import { FieldError, FormMessage, SubmitButton } from "@/components/auth/form-controls";
import { updateProfileAction } from "../actions";
import { initialAccountState } from "../state";

export function ProfileForm({ firstName: initialFirstName, lastName: initialLastName }: { firstName: string; lastName: string }) {
  const [state, action] = useActionState(updateProfileAction, initialAccountState);
  const [firstName, setFirstName] = useState(initialFirstName);
  const [lastName, setLastName] = useState(initialLastName);

  return <form action={action} className="mt-4 space-y-4">
    <div className="grid gap-4 sm:grid-cols-2">
      <div><label className="auth-label" htmlFor="firstName">Prénom</label><input className="auth-input" id="firstName" name="firstName" autoComplete="given-name" required maxLength={80} value={firstName} onChange={(event) => setFirstName(event.target.value)} aria-invalid={Boolean(state.fieldErrors?.firstName)} /><FieldError messages={state.fieldErrors?.firstName} /></div>
      <div><label className="auth-label" htmlFor="lastName">Nom</label><input className="auth-input" id="lastName" name="lastName" autoComplete="family-name" required maxLength={80} value={lastName} onChange={(event) => setLastName(event.target.value)} aria-invalid={Boolean(state.fieldErrors?.lastName)} /><FieldError messages={state.fieldErrors?.lastName} /></div>
    </div>
    <FormMessage state={state} />
    <div className="w-full [&_.auth-submit]:whitespace-nowrap [&_.auth-submit]:px-5 sm:w-auto sm:[&_.auth-submit]:w-auto"><SubmitButton pendingLabel="Enregistrement…">Enregistrer le profil</SubmitButton></div>
  </form>;
}
