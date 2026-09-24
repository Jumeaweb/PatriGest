"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { sendGlobalReleaseNotificationsAction, sendTestReleaseNotificationAction } from "../actions";
import type { ReleaseRecipient } from "../release-notification-policy";
import { initialReleaseNotificationActionState, type ReleaseNotificationActionState } from "../state";

type Props = {
  release: { version: string; title: string; summary: string };
  recipients: ReleaseRecipient[];
  notificationState: { sent: number; failed: number; inProgress: number };
};

export function ReleaseNotificationPanel({ release, recipients, notificationState }: Props) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"test" | "global" | null>(null);
  const [testUserId, setTestUserId] = useState(recipients[0]?.userId ?? "");
  function closeDialog(refresh: boolean) {
    setDialog(null);
    if (refresh) router.refresh();
  }

  return <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_6px_18px_rgba(15,23,42,0.035)]">
    <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
      <div><h2 className="text-base font-bold">Information de version</h2><p className="mt-1 text-sm font-semibold text-[#334155]">PatriGest v{release.version} — {release.title}</p><p className="mt-1 max-w-3xl text-xs leading-5 text-[#64748B]">{release.summary}</p></div>
      <span className="shrink-0 rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-[#2563EB]">{recipients.length} destinataire{recipients.length === 1 ? "" : "s"}</span>
    </div>
    <div className="mt-3 flex flex-wrap gap-3 text-xs text-[#64748B]"><span>{notificationState.sent} envoyé(s)</span><span>{notificationState.failed} échec(s)</span><span>{notificationState.inProgress} en cours</span></div>
    <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
      <label className="min-w-0 flex-1"><span className="auth-label">Destinataire du test</span><select className="auth-input" value={testUserId} onChange={(event) => setTestUserId(event.target.value)} disabled={recipients.length === 0}>{recipients.map((recipient) => <option key={recipient.userId} value={recipient.userId}>{recipient.email}</option>)}</select></label>
      <button className="button button-secondary" type="button" disabled={!testUserId} onClick={() => setDialog("test")}>Envoyer un e-mail de test</button>
      <button className="button button-primary" type="button" disabled={recipients.length === 0} onClick={() => setDialog("global")}>Informer les utilisateurs</button>
    </div>
    {dialog === "test" && <TestReleaseDialog release={release} recipient={recipients.find((recipient) => recipient.userId === testUserId)} onClose={closeDialog} />}
    {dialog === "global" && <GlobalReleaseDialog release={release} recipientsCount={recipients.length} onClose={closeDialog} />}
  </section>;
}

function TestReleaseDialog({ release, recipient, onClose }: { release: Props["release"]; recipient: ReleaseRecipient | undefined; onClose: (refresh: boolean) => void }) {
  const [state, action] = useActionState(sendTestReleaseNotificationAction, initialReleaseNotificationActionState);
  const succeeded = state.status === "success";
  return <form action={action}>
    <input type="hidden" name="version" value={release.version} />
    <input type="hidden" name="userId" value={recipient?.userId ?? ""} />
    <AppConfirmDialog open title="Envoyer l’e-mail de test ?" description={succeeded ? "L’e-mail de test a été envoyé." : "Cet envoi individuel ne marquera pas la notification globale comme envoyée."} subject={recipient?.email} onClose={() => onClose(succeeded)} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <SubmitButton label="Envoyer le test" pendingLabel="Envoi…" />}>
      <ActionMessage state={state} />
    </AppConfirmDialog>
  </form>;
}

function GlobalReleaseDialog({ release, recipientsCount, onClose }: { release: Props["release"]; recipientsCount: number; onClose: (refresh: boolean) => void }) {
  const [state, action] = useActionState(sendGlobalReleaseNotificationsAction, initialReleaseNotificationActionState);
  const succeeded = state.status === "success";
  return <form action={action}>
    <input type="hidden" name="version" value={release.version} />
    <AppConfirmDialog open title="Informer tous les utilisateurs ?" description={succeeded ? "L’envoi global est terminé." : "L’envoi est individuel et réservé aux utilisateurs actuellement actifs et confirmés."} onClose={() => onClose(succeeded)} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <SubmitButton label="Confirmer l’envoi" pendingLabel="Envoi…" />}>
      {!succeeded && <dl className="grid grid-cols-2 gap-2 rounded-lg bg-[#F8FAFC] p-3 text-sm"><div><dt className="text-xs text-[#64748B]">Version</dt><dd className="font-bold">v{release.version}</dd></div><div><dt className="text-xs text-[#64748B]">Destinataires</dt><dd className="font-bold">{recipientsCount}</dd></div></dl>}
      <ActionMessage state={state} />
    </AppConfirmDialog>
  </form>;
}

function ActionMessage({ state }: { state: ReleaseNotificationActionState }) {
  if (!state.message) return null;
  return <p className={`rounded-lg px-3 py-2 text-sm font-semibold ${state.status === "error" ? "bg-red-50 text-red-700" : "bg-green-50 text-green-700"}`} role={state.status === "error" ? "alert" : "status"} aria-live="polite">{state.message}</p>;
}

function SubmitButton({ label, pendingLabel }: { label: string; pendingLabel: string }) {
  const { pending } = useFormStatus();
  return <button className="button button-primary" type="submit" disabled={pending}>{pending ? pendingLabel : label}</button>;
}
