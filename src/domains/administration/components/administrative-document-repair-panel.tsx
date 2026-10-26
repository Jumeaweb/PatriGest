"use client";

import { useActionState, useMemo, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { executeAdministrativeDocumentRepairAction, renewAdministrativeDocumentRepairAction } from "../actions";
import type { AdministrativeDocumentRepairAction } from "../administrative-document-repair";
import type { AdministrativeRepairTargetView } from "../services/administrative-document-repair-service";
import { initialAdministrativeDocumentRepairActionState } from "../state";

const presentations: Record<AdministrativeDocumentRepairAction, { label: string; warning: string }> = {
  resume_compensation: { label: "Reprendre la compensation", warning: "Reprend uniquement la compensation déjà prévue." },
  restore_original: { label: "Restaurer depuis la sauvegarde", warning: "Peut remplacer la cible après vérification physique de la sauvegarde." },
  complete_backup_cleanup: { label: "Nettoyer la sauvegarde", warning: "Supprime la sauvegarde autorisée après vérification de l’original." },
  confirm_already_conform: { label: "Confirmer l’état conforme", warning: "Aucune mutation physique n’est effectuée." },
  accept_residual_state: { label: "Accepter l’état résiduel", warning: "Ne restaure pas le document et conserve les dernières données récupérables." },
};

export function AdministrativeDocumentRepairPanel({
  operationId,
  attemptId,
  targets,
  blocked,
  canRenew,
}: {
  operationId: string;
  attemptId: string;
  targets: AdministrativeRepairTargetView[];
  blocked: boolean;
  canRenew: boolean;
}) {
  const [state, action] = useActionState(executeAdministrativeDocumentRepairAction, initialAdministrativeDocumentRepairActionState);
  const [renewalState, renewalAction] = useActionState(renewAdministrativeDocumentRepairAction, initialAdministrativeDocumentRepairActionState);
  const renewalId = useRef<string | null>(null);
  const [decisions, setDecisions] = useState<Record<string, { action: AdministrativeDocumentRepairAction | ""; residualReason: string }>>(
    () => Object.fromEntries(targets.map((target) => [target.targetId, { action: "", residualReason: "" }])),
  );
  const serialized = useMemo(() => JSON.stringify(targets.map((target) => ({
    targetId: target.targetId,
    action: decisions[target.targetId]?.action,
    residualReason: decisions[target.targetId]?.residualReason,
  }))), [decisions, targets]);

  function renew(formData: FormData) {
    renewalId.current ??= crypto.randomUUID();
    formData.set("renewalId", renewalId.current);
    renewalAction(formData);
  }

  return <div className="mt-5 space-y-4">
    {blocked && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-semibold text-red-800">Une opération ou neutralisation concurrente bloque cette réparation.</p>}
    <form action={action} className="space-y-4 rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={operationId} />
      <input type="hidden" name="attemptId" value={attemptId} />
      <input type="hidden" name="decisions" value={serialized} />
      <div>
        <h2 className="text-base font-bold">Décision administrative</h2>
        <p className="mt-1 text-xs leading-5 text-[#64748B]">Chaque cible doit recevoir une action explicite. Le moteur n’en choisit aucune automatiquement.</p>
      </div>
      <div className="grid gap-3">
        {targets.map((target) => {
          const decision = decisions[target.targetId];
          return <fieldset key={target.targetId} className="rounded-xl border border-[#E2E8F0] p-3">
            <legend className="px-1 text-sm font-bold">Cible {target.ordinal} — {target.bucketLabel}</legend>
            <dl className="mb-3 grid gap-2 text-xs sm:grid-cols-3">
              <div><dt className="text-[#64748B]">Catalogue</dt><dd className="font-semibold">{target.catalogObjectPresent ? "Objet présent" : "Objet absent"}</dd></div>
              <div><dt className="text-[#64748B]">Sauvegarde</dt><dd className="font-semibold">{target.backupState ?? "Aucune"}</dd></div>
              <div><dt className="text-[#64748B]">Verrou</dt><dd className="font-semibold">{target.lockPresent ? "Présent" : "Absent"}</dd></div>
            </dl>
            <label className="auth-label" htmlFor={`repair-action-${target.targetId}`}>Action autorisée</label>
            <select
              className="auth-input"
              id={`repair-action-${target.targetId}`}
              value={decision?.action}
              required
              onChange={(event) => setDecisions((current) => ({ ...current, [target.targetId]: { ...current[target.targetId], action: event.target.value as AdministrativeDocumentRepairAction } }))}
            >
              <option value="" disabled>Choisir une action</option>
              {target.actions.map((value) => <option key={value} value={value}>{presentations[value].label}</option>)}
            </select>
            {decision?.action && <p className={`mt-2 text-xs leading-5 ${decision.action === "accept_residual_state" || decision.action === "complete_backup_cleanup" ? "font-semibold text-amber-800" : "text-[#64748B]"}`}>{presentations[decision.action].warning}</p>}
            {decision?.action === "accept_residual_state" && <div className="mt-3"><label className="auth-label" htmlFor={`residual-reason-${target.targetId}`}>Justification de l’état résiduel</label><textarea id={`residual-reason-${target.targetId}`} className="auth-input min-h-20 py-2" required maxLength={2000} value={decision.residualReason} onChange={(event) => setDecisions((current) => ({ ...current, [target.targetId]: { ...current[target.targetId], residualReason: event.target.value } }))} /></div>}
          </fieldset>;
        })}
      </div>
      <div><label className="auth-label" htmlFor="repair-reason">Motif global obligatoire</label><textarea id="repair-reason" className="auth-input min-h-24 py-2" name="reason" required maxLength={2000} /></div>
      <label className="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm leading-5 text-amber-900"><input className="mt-1 size-4" type="checkbox" name="confirmation" required /><span>Je confirme cette décision et les mutations documentaires explicitement sélectionnées.</span></label>
      <ActionMessage state={state} />
      <RepairSubmitButton disabled={blocked || state.status === "success" || state.status === "warning"} />
    </form>
    {canRenew && <form action={renew} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
      <input type="hidden" name="operationId" value={operationId} />
      <input type="hidden" name="attemptId" value={attemptId} />
      <h2 className="text-sm font-bold">Prolongation explicite</h2>
      <p className="mt-1 text-xs leading-5 text-[#64748B]">Prolonge de dix minutes la même tentative et le même plan. Le plafond SQL reste fixé à six renouvellements.</p>
      <div className="mt-3"><RenewSubmitButton /><ActionMessage state={renewalState} /></div>
    </form>}
  </div>;
}

function ActionMessage({ state }: { state: typeof initialAdministrativeDocumentRepairActionState }) {
  if (state.status === "idle") return null;
  const classes = state.status === "success" ? "bg-green-50 text-green-800" : state.status === "warning" ? "bg-amber-50 text-amber-900" : "bg-red-50 text-red-800";
  return <p role="status" className={`rounded-lg px-3 py-2 text-sm ${classes}`}>{state.message}</p>;
}

function RepairSubmitButton({ disabled }: { disabled: boolean }) {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-danger" disabled={disabled || pending}>{pending ? "Réparation en cours…" : "Autoriser et exécuter la réparation"}</button>;
}

function RenewSubmitButton() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-secondary" disabled={pending}>{pending ? "Prolongation…" : "Prolonger la reprise"}</button>;
}
