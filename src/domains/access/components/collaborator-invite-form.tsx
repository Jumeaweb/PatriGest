"use client";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { Check, Copy } from "lucide-react";
import { inviteCollaboratorAction } from "@/domains/access/actions";
import { initialAccessState } from "@/domains/access/state";
import type { SharedAccessRole } from "@/types/database";

export function CollaboratorInviteForm({ protectedPersonId, isOwner, availableRoles }: { protectedPersonId: string; isOwner: boolean; availableRoles?: SharedAccessRole[] }) {
  const [state, action] = useActionState(inviteCollaboratorAction.bind(null, protectedPersonId), initialAccessState);
  const [copied, setCopied] = useState(false);
  const canInvite = !isOwner || Boolean(availableRoles?.length);
  const defaultRole = availableRoles?.includes("read_only") ? "read_only" : availableRoles?.[0] ?? "read_only";
  const unavailableRoles = isOwner
    ? (["manager", "read_only"] as const).filter((role) => !availableRoles?.includes(role))
    : [];
  async function copyLink() {
    if (!state.invitationUrl) return;
    await navigator.clipboard.writeText(state.invitationUrl);
    setCopied(true);
  }
  return <form action={action} className="mt-4 grid gap-3 sm:grid-cols-[1fr_12rem_auto]"><div><label className="auth-label" htmlFor="invite-email">Adresse email</label><input className="auth-input" id="invite-email" name="email" type="email" required disabled={!canInvite} /></div><div>{isOwner ? <><label className="auth-label" htmlFor="invite-role">Rôle</label><select className="auth-input" id="invite-role" name="role" defaultValue={defaultRole} disabled={!canInvite} aria-describedby={unavailableRoles.length ? "invite-quota-explanation" : undefined}><option value="read_only" disabled={!availableRoles?.includes("read_only")}>Lecture seule</option><option value="manager" disabled={!availableRoles?.includes("manager")}>Gestionnaire</option></select></> : <><p className="auth-label">Rôle</p><input type="hidden" name="role" value="read_only" /><p className="auth-input flex items-center bg-slate-50 text-[#475569]">Lecture seule</p></>}</div><div className="self-end w-full sm:w-auto"><InviteSubmitButton disabled={!canInvite} describedBy={!canInvite ? "invite-quota-explanation" : undefined} /></div>{unavailableRoles.length > 0 && <p id="invite-quota-explanation" className="sm:col-span-3 text-xs font-semibold text-amber-800">{canInvite ? `Aucune nouvelle invitation possible pour ${unavailableRoles.map(roleLabel).join(" ou ")} : la limite est atteinte.` : "Aucune nouvelle invitation n’est possible : les deux limites de partage sont atteintes."}</p>}{state.message && <p role={state.status === "error" ? "alert" : "status"} aria-live="polite" className={`sm:col-span-3 rounded-lg px-3 py-2 text-sm ${state.status === "error" ? "bg-red-50 text-red-700" : state.status === "warning" ? "bg-amber-50 text-amber-800" : "bg-green-50 text-green-700"}`}>{state.message}</p>}{state.invitationUrl && <div className="sm:col-span-3"><label className="auth-label" htmlFor="invitation-url">Lien à transmettre</label><div className="flex flex-col gap-2 sm:flex-row"><input id="invitation-url" className="auth-input" readOnly value={state.invitationUrl} /><button className="button button-secondary shrink-0 gap-1.5" type="button" onClick={copyLink}>{copied ? <Check aria-hidden="true" size={14} /> : <Copy aria-hidden="true" size={14} />}{copied ? "Lien copié" : "Copier le lien"}</button></div></div>}</form>;
}

function InviteSubmitButton({ disabled, describedBy }: { disabled: boolean; describedBy?: string }) {
  const { pending } = useFormStatus();
  return <button className="auth-submit w-full whitespace-nowrap sm:w-auto" type="submit" disabled={disabled || pending} aria-describedby={describedBy}>{pending ? "Envoi…" : "Inviter"}</button>;
}

function roleLabel(role: SharedAccessRole) {
  return role === "manager" ? "les gestionnaires" : "la lecture seule";
}
