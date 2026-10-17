"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import {
  acceptDossierInvitationAction,
  acceptRecoveredDossierInvitationAction,
  declineDossierInvitationAction,
} from "@/domains/access/actions";
import { initialAccessState } from "@/domains/access/state";

type InvitationReference =
  | { token: string }
  | { invitationId: string };

export function InvitationDecisionActions({
  reference,
  acceptLabel,
}: {
  reference: InvitationReference;
  acceptLabel: string;
}) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [declineState, declineAction] = useActionState(
    declineDossierInvitationAction.bind(null, reference),
    initialAccessState,
  );

  if (declineState.status === "success") {
    return <div className="mt-3 rounded-xl bg-green-50 p-3 text-sm text-green-800" role="status" aria-live="polite">
      <p className="font-semibold">{declineState.message}</p>
      <Link className="button button-secondary mt-3 w-full" href="/tableau-de-bord">Continuer vers mon espace</Link>
    </div>;
  }

  const acceptAction = "token" in reference
    ? acceptDossierInvitationAction.bind(null, reference.token)
    : acceptRecoveredDossierInvitationAction.bind(null, reference.invitationId);

  return <div className="mt-3 grid gap-2 sm:grid-cols-2">
    <form action={acceptAction}>
      <button className="button button-primary w-full" type="submit">{acceptLabel}</button>
    </form>
    <button className="button button-secondary w-full text-red-700" type="button" onClick={() => setDialogOpen(true)}>
      Refuser l’invitation
    </button>
    <form action={declineAction}>
      <AppConfirmDialog
        open={dialogOpen}
        onClose={() => setDialogOpen(false)}
        title="Refuser cette invitation ?"
        description="Vous n’obtiendrez aucun accès à ce dossier. Le propriétaire conservera la trace du refus."
        actions={<DeclineButton />}
      >
        {declineState.status === "error" && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700" role="alert" aria-live="assertive">{declineState.message}</p>}
      </AppConfirmDialog>
    </form>
  </div>;
}

function DeclineButton() {
  const { pending } = useFormStatus();
  return <button className="button min-h-10 bg-red-700 px-4 text-sm font-bold text-white hover:bg-red-800 disabled:cursor-not-allowed disabled:opacity-60" type="submit" disabled={pending}>
    {pending ? "Refus…" : "Confirmer le refus"}
  </button>;
}
