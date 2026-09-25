"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useActionState } from "react";
import {
  forgotPasswordAction,
  loginAction,
  signupAction,
  updatePasswordAction,
} from "@/app/(auth)/actions";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { getDossierInvitationLoginPath, getDossierInvitationPath } from "@/lib/auth/invitation-destination";
import { initialAuthState, type AuthActionState } from "@/lib/auth/state";
import { FieldError, FormMessage, SubmitButton } from "./form-controls";

function Field({
  id,
  label,
  type = "text",
  autoComplete,
  errors,
  defaultValue,
  readOnly,
}: {
  id: string;
  label: string;
  type?: "text" | "email" | "password";
  autoComplete: string;
  errors?: string[];
  defaultValue?: string;
  readOnly?: boolean;
}) {
  const errorId = `${id}-error`;
  return (
    <div>
      <label className="auth-label" htmlFor={id}>{label}</label>
      <input className="auth-input" id={id} name={id} type={type} autoComplete={autoComplete} required defaultValue={defaultValue} readOnly={readOnly} aria-invalid={Boolean(errors?.length)} aria-describedby={errors?.length ? errorId : undefined} />
      <div id={errorId}><FieldError messages={errors} /></div>
    </div>
  );
}

export function LoginForm({ initialState = initialAuthState, nextPath }: { initialState?: AuthActionState; nextPath?: string }) {
  const [state, action] = useActionState(loginAction, initialState);
  const recoveryHref = nextPath ? `/mot-de-passe-oublie?next=${encodeURIComponent(nextPath)}` : "/mot-de-passe-oublie";
  return (
    <form action={action} className="space-y-4">
      {nextPath && <input type="hidden" name="next" value={nextPath} />}
      <Field id="email" label="Adresse email" type="email" autoComplete="email" errors={state.fieldErrors?.email} />
      <Field id="password" label="Mot de passe" type="password" autoComplete="current-password" errors={state.fieldErrors?.password} />
      <div className="flex justify-end"><Link className="auth-link text-sm" href={recoveryHref}>Mot de passe oublié ?</Link></div>
      <FormMessage state={state} />
      <SubmitButton pendingLabel="Connexion…">Se connecter</SubmitButton>
      <p className="text-center text-sm text-[#64748B]">Pas encore de compte ? <Link className="auth-link" href="/inscription">Créer un compte</Link></p>
      <Link className="auth-back-link" href="/">Retour à l’accueil</Link>
    </form>
  );
}

export function SignupForm({ invitationToken, email, firstName, lastName }: { invitationToken?: string; email?: string; firstName?: string; lastName?: string }) {
  const [state, action] = useActionState(signupAction, initialAuthState);
  const loginHref = invitationToken ? getDossierInvitationLoginPath(invitationToken) : "/connexion";
  const recoveryHref = invitationToken ? `/mot-de-passe-oublie?next=${encodeURIComponent(getDossierInvitationPath(invitationToken))}` : "/mot-de-passe-oublie";
  if (state.status === "success") {
    return <div className="rounded-xl bg-green-50 px-4 py-4 text-green-900" role="status" aria-live="polite">
      <h2 className="font-bold">Consultez votre messagerie</h2>
      <p className="mt-2 text-sm leading-6">Si l’adresse <strong className="break-all font-semibold">{state.email}</strong> peut être créée ou récupérée, un e-mail lui a été envoyé pour poursuivre.</p>
      <p className="mt-2 text-sm leading-6">Si vous disposez déjà d’un compte PatriGest, <Link className="auth-link" href={loginHref}>connectez-vous</Link> ou utilisez la <Link className="auth-link" href={recoveryHref}>procédure de mot de passe oublié</Link>.</p>
    </div>;
  }
  return (
    <form action={action} className="space-y-4">
      {invitationToken && <input type="hidden" name="invitationToken" value={invitationToken} />}
      <Field id="email" label="Adresse email" type="email" autoComplete="email" errors={state.fieldErrors?.email} defaultValue={email} readOnly={Boolean(invitationToken)} />
      <div className="grid gap-4 sm:grid-cols-2">
        <Field id="firstName" label="Prénom" autoComplete="given-name" errors={state.fieldErrors?.firstName} defaultValue={firstName} />
        <Field id="lastName" label="Nom" autoComplete="family-name" errors={state.fieldErrors?.lastName} defaultValue={lastName} />
      </div>
      <Field id="password" label="Mot de passe" type="password" autoComplete="new-password" errors={state.fieldErrors?.password} />
      <Field id="passwordConfirmation" label="Confirmation du mot de passe" type="password" autoComplete="new-password" errors={state.fieldErrors?.passwordConfirmation} />
      <p className="text-xs leading-5 text-[#64748B]">Utilisez au moins 8 caractères. Un mot de passe long et unique protège mieux vos données.</p>
      <FormMessage state={state} />
      <SubmitButton pendingLabel="Création…">{invitationToken ? "Créer ou finaliser mon compte" : "Créer mon compte"}</SubmitButton>
      <p className="text-center text-sm text-[#64748B]">Déjà inscrit ? <Link className="auth-link" href={loginHref}>Se connecter</Link></p>
      <Link className="auth-back-link" href="/">Retour à l’accueil</Link>
    </form>
  );
}

export function ForgotPasswordForm({ nextPath }: { nextPath?: string }) {
  const [state, action] = useActionState(forgotPasswordAction, initialAuthState);
  return (
    <form action={action} className="space-y-4">
      {nextPath && <input type="hidden" name="next" value={nextPath} />}
      <Field id="email" label="Adresse email" type="email" autoComplete="email" errors={state.fieldErrors?.email} />
      <FormMessage state={state} />
      <SubmitButton pendingLabel="Envoi…">Envoyer le lien</SubmitButton>
      <Link className="auth-back-link" href={nextPath ? `/connexion?next=${encodeURIComponent(nextPath)}` : "/connexion"}>Retour à la connexion</Link>
    </form>
  );
}

export function UpdatePasswordForm({ nextPath }: { nextPath?: string }) {
  const [state, action] = useActionState(updatePasswordAction, initialAuthState);
  const router = useRouter();
  const succeeded = state.status === "success" && Boolean(state.redirectTo);
  const closeSuccessDialog = () => {
    if (state.redirectTo) router.replace(state.redirectTo);
  };

  return (
    <>
      <form action={action} className="space-y-4">
        {nextPath && <input type="hidden" name="next" value={nextPath} />}
        <Field id="password" label="Nouveau mot de passe" type="password" autoComplete="new-password" errors={state.fieldErrors?.password} />
        <Field id="passwordConfirmation" label="Confirmation du mot de passe" type="password" autoComplete="new-password" errors={state.fieldErrors?.passwordConfirmation} />
        {!succeeded && <FormMessage state={state} />}
        <SubmitButton pendingLabel="Modification…">Modifier le mot de passe</SubmitButton>
        <Link className="auth-back-link" href="/connexion">Retour à la connexion</Link>
      </form>
      <AppConfirmDialog
        open={succeeded}
        title="Mot de passe modifié"
        description="Votre mot de passe a été modifié."
        cancelLabel="Fermer"
        actions={null}
        onClose={closeSuccessDialog}
        requireExplicitClose
      />
    </>
  );
}
