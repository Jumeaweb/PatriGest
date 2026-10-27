"use client";

import { useActionState, useRef } from "react";
import { useFormStatus } from "react-dom";
import { verifyAdministrativeDocumentPhysicalObjectAction } from "../actions";
import {
  physicalVerificationOutcomeLabels,
  physicalVerificationProofLabels,
  type PhysicalVerificationObservation,
} from "../administrative-document-physical-verification";

const initialState = { status: "idle" as const, message: "" };

export function AdministrativeDocumentPhysicalVerification({
  inventoryKey,
  observations,
}: {
  inventoryKey: string;
  observations: PhysicalVerificationObservation[];
}) {
  const [state, action] = useActionState(verifyAdministrativeDocumentPhysicalObjectAction, initialState);
  const requestId = useRef<string | null>(null);
  function submit(formData: FormData) {
    requestId.current ??= crypto.randomUUID();
    formData.set("requestId", requestId.current);
    action(formData);
  }
  return <section className="mt-4 rounded-xl border border-blue-200 bg-blue-50 p-3" aria-labelledby="physical-verification-title">
    <h4 id="physical-verification-title" className="text-sm font-bold text-blue-950">Réconciliation physique en lecture seule</h4>
    <p className="mt-1 text-xs leading-5 text-blue-900">Un seul objet autorisé sera lu côté serveur. Aucun chemin, octet ou lien signé n’est transmis au navigateur.</p>
    <form action={submit} className="mt-3">
      <input type="hidden" name="inventoryKey" value={inventoryKey} />
      <label className="flex items-start gap-2 text-xs text-blue-950"><input className="mt-0.5 size-4" type="checkbox" name="confirmation" required /><span>Je demande explicitement la vérification physique de ce constat.</span></label>
      <div className="mt-3"><VerificationButton /></div>
    </form>
    {state.status !== "idle" && <p role="status" className={`mt-3 rounded-lg p-2 text-xs font-semibold ${state.status === "success" ? "bg-green-100 text-green-900" : "bg-red-100 text-red-900"}`}>{state.message}</p>}
    <div className="mt-4">
      <h5 className="text-xs font-bold uppercase tracking-wide text-blue-950">Historique des observations</h5>
      <p className="mt-1 text-xs text-blue-900">Chaque observation décrit uniquement l’état constaté à sa date et ne prouve pas l’état physique actuel.</p>
      {observations.length === 0 ? <p className="mt-2 text-xs text-blue-900">Aucune vérification physique enregistrée.</p> : <ol className="mt-2 space-y-2">{observations.map((observation) => <li key={observation.id} className="rounded-lg bg-white p-2 text-xs">
        <p className="font-semibold">{physicalVerificationOutcomeLabels[observation.outcome]}</p>
        <p className="mt-1 text-[#64748B]">{new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(observation.observedAt))} — {physicalVerificationProofLabels[observation.proofLevel]}</p>
        {observation.limitationCode && <p className="mt-1 text-amber-800">Limite : {observation.limitationCode}</p>}
      </li>)}</ol>}
    </div>
  </section>;
}

function VerificationButton() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-secondary" disabled={pending}>{pending ? "Vérification…" : "Vérifier physiquement"}</button>;
}
