"use client";

import { useActionState, useEffect, useRef, useState, type MutableRefObject, type ReactNode } from "react";
import { useFormStatus } from "react-dom";
import {
  activateAdministrativeDocumentExceptionalRecoveryAction,
  decideAdministrativeDocumentExceptionalRecoveryAction,
  requestAdministrativeDocumentExceptionalRecoveryAction,
  resumeAdministrativeDocumentExceptionalRecoveryAction,
} from "../actions";
import {
  exceptionalRecoveryStateLabels,
  type AdministrativeDocumentExceptionalRecovery,
  type AdministrativeExceptionalRepairAuthorization,
} from "../administrative-document-exceptional-recovery";
import { initialAdministrativeDocumentRepairActionState } from "../state";

function stableId(reference: MutableRefObject<string | null>) {
  reference.current ??= crypto.randomUUID();
  return reference.current;
}

function ActionMessage({ state }: { state: typeof initialAdministrativeDocumentRepairActionState }) {
  if (state.status === "idle") return null;
  const classes = state.status === "success"
    ? "bg-green-50 text-green-800"
    : state.status === "warning"
      ? "bg-amber-50 text-amber-900"
      : "bg-red-50 text-red-800";
  return <p role="status" className={`mt-3 rounded-lg px-3 py-2 text-sm ${classes}`}>{state.message}</p>;
}

function SubmitButton({ children, danger = false }: { children: ReactNode; danger?: boolean }) {
  const { pending } = useFormStatus();
  return <button
    type="submit"
    className={danger ? "button button-danger" : "button button-secondary"}
    disabled={pending}
  >{pending ? "Traitement…" : children}</button>;
}

function DecisionButtons() {
  const { pending } = useFormStatus();
  return <div className="mt-3 flex flex-wrap gap-2">
    <button type="submit" name="decision" value="approve" className="button button-secondary" disabled={pending}>{pending ? "Décision…" : "Approuver"}</button>
    <button type="submit" name="decision" value="reject" className="button button-danger" disabled={pending}>{pending ? "Décision…" : "Refuser"}</button>
  </div>;
}

function RemainingTime({ expiresAt }: { expiresAt: string }) {
  const [seconds, setSeconds] = useState(() => Math.max(0, Math.ceil((Date.parse(expiresAt) - Date.now()) / 1000)));
  useEffect(() => {
    const update = () => setSeconds(Math.max(0, Math.ceil((Date.parse(expiresAt) - Date.now()) / 1000)));
    update();
    const timer = window.setInterval(update, 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return <span aria-live="polite">{seconds > 0 ? `${minutes} min ${String(remainder).padStart(2, "0")} s restantes (indicatif)` : "Fenêtre expirée — actualisez la page"}</span>;
}

export function AdministrativeDocumentExceptionalRecoveryPanel({
  operationId,
  authorization,
  recovery,
  requestEligible,
  storageGuardEnabled,
}: {
  operationId: string;
  authorization: AdministrativeExceptionalRepairAuthorization | null;
  recovery: AdministrativeDocumentExceptionalRecovery | null;
  requestEligible: boolean;
  storageGuardEnabled: boolean;
}) {
  const [requestState, requestAction] = useActionState(
    requestAdministrativeDocumentExceptionalRecoveryAction,
    initialAdministrativeDocumentRepairActionState,
  );
  const [decisionState, decisionAction] = useActionState(
    decideAdministrativeDocumentExceptionalRecoveryAction,
    initialAdministrativeDocumentRepairActionState,
  );
  const [activationState, activationAction] = useActionState(
    activateAdministrativeDocumentExceptionalRecoveryAction,
    initialAdministrativeDocumentRepairActionState,
  );
  const [resumeState, resumeAction] = useActionState(
    resumeAdministrativeDocumentExceptionalRecoveryAction,
    initialAdministrativeDocumentRepairActionState,
  );
  const requestId = useRef<string | null>(null);
  const decisionId = useRef<string | null>(null);
  const activationId = useRef<string | null>(null);

  function request(formData: FormData) {
    formData.set("requestId", stableId(requestId));
    requestAction(formData);
  }
  function decide(formData: FormData) {
    formData.set("decisionId", stableId(decisionId));
    decisionAction(formData);
  }
  function activate(formData: FormData) {
    formData.set("activationId", stableId(activationId));
    activationAction(formData);
  }

  if (!recovery && !requestEligible) return null;

  return <section className="mt-5 space-y-4 rounded-xl border border-amber-200 bg-amber-50/40 p-4">
    <div>
      <p className="text-xs font-bold uppercase tracking-widest text-amber-800">Récupération exceptionnelle</p>
      <h2 className="mt-1 text-base font-bold">Dernier recours après six prolongations</h2>
      <p className="mt-1 text-sm leading-6 text-[#64748B]">Deux validations administratives distinctes sont requises. Deux fenêtres de cinq minutes au maximum peuvent ensuite reprendre le plan initial, sans le recréer.</p>
    </div>
    {!storageGuardEnabled && <p role="alert" className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm font-semibold text-amber-900">La garde Storage n’est pas activée : toute mutation destructive reste bloquée par le moteur.</p>}

    {!recovery && authorization && requestEligible && <form action={request} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={operationId} />
      <input type="hidden" name="authorizationId" value={authorization.authorizationId} />
      <input type="hidden" name="attemptId" value={authorization.attemptId} />
      <input type="hidden" name="expectedPlanHash" value={authorization.planHash} />
      <input type="hidden" name="expectedAuthorizationRevision" value={authorization.revision} />
      <label className="auth-label" htmlFor="exceptional-request-reason">Motif exceptionnel obligatoire</label>
      <textarea id="exceptional-request-reason" name="reason" className="auth-input min-h-24 py-2" required maxLength={2000} />
      <label className="mt-3 flex items-start gap-3 text-sm leading-5"><input className="mt-1 size-4" type="checkbox" name="confirmation" required /><span>Je confirme demander une validation indépendante pour reprendre strictement le plan existant.</span></label>
      <div className="mt-3"><SubmitButton>Demander la récupération</SubmitButton></div>
      <ActionMessage state={requestState} />
    </form>}

    {recovery && <div className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <dl className="grid gap-3 text-sm sm:grid-cols-2">
        <div><dt className="text-xs text-[#64748B]">État</dt><dd className="font-semibold">{exceptionalRecoveryStateLabels[recovery.state]}</dd></div>
        <div><dt className="text-xs text-[#64748B]">Activations</dt><dd className="font-semibold">{recovery.activationCount} / {recovery.maxActivations}</dd></div>
        <div><dt className="text-xs text-[#64748B]">Demandeur</dt><dd className="font-semibold">{recovery.requesterIsCaller ? "Vous" : "Autre administrateur"}</dd></div>
        <div><dt className="text-xs text-[#64748B]">Demandée le</dt><dd className="font-semibold">{new Date(recovery.requestedAt).toLocaleString("fr-FR")}</dd></div>
      </dl>
      <p className="mt-3 text-sm"><span className="font-semibold">Motif :</span> {recovery.reason}</p>
      {recovery.decisionReason && <p className="mt-2 text-sm"><span className="font-semibold">Motif de décision :</span> {recovery.decisionReason}</p>}
      {recovery.state === "active" && recovery.expiresAt && <p className="mt-3 rounded-lg bg-blue-50 p-3 text-sm font-semibold text-blue-900"><RemainingTime expiresAt={recovery.expiresAt} />. L’horloge PostgreSQL reste seule autorité.</p>}
      {recovery.state === "expired" && recovery.activationCount >= recovery.maxActivations && <p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm font-semibold text-red-800">Les deux activations sont épuisées. Cette récupération est définitivement bloquée.</p>}
    </div>}

    {recovery?.canApprove && <form action={decide} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={recovery.operationId} />
      <input type="hidden" name="recoveryId" value={recovery.recoveryId} />
      <input type="hidden" name="expectedRevision" value={recovery.revision} />
      <label className="auth-label" htmlFor="exceptional-decision-reason">Motif de la décision</label>
      <textarea id="exceptional-decision-reason" name="reason" className="auth-input min-h-24 py-2" required maxLength={2000} />
      <label className="mt-3 flex items-start gap-3 text-sm leading-5"><input className="mt-1 size-4" type="checkbox" name="confirmation" required /><span>Je confirme avoir examiné cette demande indépendante.</span></label>
      <DecisionButtons />
      <ActionMessage state={decisionState} />
    </form>}

    {recovery?.requesterIsCaller && ["approved", "expired"].includes(recovery.state) && recovery.activationCount < recovery.maxActivations && <form action={activate} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={recovery.operationId} />
      <input type="hidden" name="recoveryId" value={recovery.recoveryId} />
      <input type="hidden" name="expectedRevision" value={recovery.revision} />
      <label className="flex items-start gap-3 text-sm leading-5"><input className="mt-1 size-4" type="checkbox" name="confirmation" required /><span>Je confirme activer une fenêtre non renouvelable de cinq minutes.</span></label>
      <div className="mt-3"><SubmitButton>Activer la fenêtre {recovery.activationCount + 1} / {recovery.maxActivations}</SubmitButton></div>
      <ActionMessage state={activationState} />
    </form>}

    {recovery?.requesterIsCaller && recovery.state === "active" && authorization && <form action={resumeAction} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={recovery.operationId} />
      <input type="hidden" name="attemptId" value={authorization.attemptId} />
      <label className="flex items-start gap-3 text-sm leading-5"><input className="mt-1 size-4" type="checkbox" name="confirmation" required /><span>Je confirme reprendre le moteur existant sans modifier le plan ni les cibles.</span></label>
      <div className="mt-3"><SubmitButton danger>Reprendre la réparation</SubmitButton></div>
      <ActionMessage state={resumeState} />
    </form>}

    {recovery && recovery.history.length > 0 && <details className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <summary className="cursor-pointer text-sm font-bold">Historique audité ({recovery.history.length})</summary>
      <ol className="mt-3 grid gap-2 text-xs text-[#64748B]">{recovery.history.map((event) => <li key={event.sequenceNumber}>#{event.sequenceNumber} — {event.eventType} — {new Date(event.occurredAt).toLocaleString("fr-FR")}{event.safeCode ? ` — ${event.safeCode}` : ""}</li>)}</ol>
    </details>}
  </section>;
}
