"use client";

import { useActionState, useEffect, useId, useState } from "react";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { mutateAdministrativeEntitlementAction } from "../administrative-entitlement-actions";
import { initialAdministrativeEntitlementActionState } from "../state";
import {
  createAdministrationOverrideDraft,
  createAdministrationPlanDraft,
  describeAdministrationOverrideDraft,
  describeAdministrationPlanDraft,
  selectAdministrationPlan,
  validateAdministrationOverrideDraft,
  validateAdministrationPlanDraft,
  type AdministrationOverrideDraft,
  type AdministrationPlanDraft,
} from "../administration-user-subscription-editor";
import type { PlatformUserSummary } from "../services/administration-service";

export type EntitlementEditorRequest = {
  user: PlatformUserSummary;
  entityType: "plan" | "override";
  operation: "assign" | "replace" | "revoke";
};

export function AdministrationUserEntitlementEditor({ request, onClose }: { request: EntitlementEditorRequest; onClose: () => void }) {
  const router = useRouter();
  const formId = useId();
  const [state, submit, pending] = useActionState(mutateAdministrativeEntitlementAction, initialAdministrativeEntitlementActionState);
  const [phase, setPhase] = useState<"edit" | "confirm">("edit");
  const [reason, setReason] = useState("");
  const [clientError, setClientError] = useState<string | null>(null);
  const [planDraft, setPlanDraft] = useState<AdministrationPlanDraft>(() => createAdministrationPlanDraft(request.user));
  const [overrideDraft, setOverrideDraft] = useState<AdministrationOverrideDraft>(() => createAdministrationOverrideDraft(request.user));
  const [requestId, setRequestId] = useState<string | null>(null);
  const succeeded = state.status === "success";

  useEffect(() => {
    if (succeeded) router.refresh();
  }, [router, succeeded]);

  const assignment = request.user.entitlements?.administrativeAssignment;
  const entitlementOverride = request.user.entitlements?.administrativeOverride;
  const entityId = request.entityType === "plan" ? assignment?.id : entitlementOverride?.id;
  const expectedRevision = request.operation === "assign"
    ? 0
    : request.entityType === "plan" ? assignment?.revision : entitlementOverride?.revision;
  const userName = `${request.user.firstName} ${request.user.lastName}`.trim() || request.user.email;

  function intentChanged() {
    setRequestId(null);
    setClientError(null);
  }

  function continueToConfirmation() {
    const validation = request.operation === "revoke"
      ? null
      : request.entityType === "plan"
        ? validateAdministrationPlanDraft(planDraft, request.user.activeOwnedDossiers)
        : validateAdministrationOverrideDraft(overrideDraft, request.user.activeOwnedDossiers);
    if (validation) return setClientError(validation);
    if (!reason.trim()) return setClientError("Le motif est obligatoire.");
    if (!entityId && request.operation !== "assign") return setClientError("Les droits affichés ne sont plus modifiables. Actualisez la page.");
    if (expectedRevision === undefined) return setClientError("La révision administrative est indisponible. Actualisez la page.");
    setRequestId((current) => current ?? crypto.randomUUID());
    setClientError(null);
    setPhase("confirm");
  }

  const labels = getOperationLabels(request);
  const before = getBeforeDescription(request);
  const after = getAfterDescription(request, planDraft, overrideDraft);

  return <AppConfirmDialog
    open
    size="wide"
    title={succeeded ? "Modification enregistrée" : labels.title}
    description={succeeded ? "Les droits affichés vont être rechargés depuis Supabase." : phase === "edit" ? labels.description : "Vérifiez les valeurs avant de confirmer cette décision administrative."}
    subject={`${userName} — ${request.user.email}`}
    onClose={onClose}
    cancelLabel={succeeded ? "Fermer" : phase === "confirm" ? "Annuler" : "Fermer"}
    requireExplicitClose={pending}
    actions={succeeded ? null : phase === "edit"
      ? <button type="button" className="button button-primary" onClick={continueToConfirmation}>Continuer</button>
      : <button type="submit" form={formId} className={request.operation === "revoke" ? "button button-danger" : "button button-primary"} disabled={pending}>{pending ? "Enregistrement…" : labels.confirmLabel}</button>}
  >
    {succeeded ? <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800">{state.message}</p> : phase === "edit" ? <div className="grid gap-4">
      {request.operation !== "revoke" && request.entityType === "plan" && <PlanFields draft={planDraft} setDraft={(draft) => { intentChanged(); setPlanDraft(draft); }} />}
      {request.operation !== "revoke" && request.entityType === "override" && <OverrideFields user={request.user} draft={overrideDraft} setDraft={(draft) => { intentChanged(); setOverrideDraft(draft); }} />}
      {request.operation === "revoke" && <Comparison before={before} after={after} />}
      <div><label className="auth-label" htmlFor={`${formId}-reason`}>Motif de la modification</label><textarea id={`${formId}-reason`} className="auth-input min-h-24 resize-y py-2" value={reason} onChange={(event) => { intentChanged(); setReason(event.target.value); }} maxLength={2000} required /></div>
      {clientError && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm font-semibold text-red-800">{clientError}</p>}
    </div> : <form id={formId} action={submit} className="grid gap-4">
      <Comparison before={before} after={after} />
      <div><p className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Motif</p><p className="mt-1 whitespace-pre-wrap text-sm">{reason.trim()}</p></div>
      <input type="hidden" name="entityType" value={request.entityType} /><input type="hidden" name="operation" value={request.operation} />
      <input type="hidden" name="ownerId" value={request.user.id} /><input type="hidden" name="entityId" value={entityId ?? ""} />
      <input type="hidden" name="expectedRevision" value={expectedRevision ?? ""} /><input type="hidden" name="requestId" value={requestId ?? ""} />
      <input type="hidden" name="reason" value={reason.trim()} /><input type="hidden" name="planKey" value={planDraft.planKey} />
      <input type="hidden" name="billingPeriod" value={planDraft.billingPeriod} /><input type="hidden" name="capacityKey" value={planDraft.capacityKey} />
      <input type="hidden" name="featurePlanKey" value={overrideDraft.featurePlanKey ?? ""} /><input type="hidden" name="overrideCapacityKey" value={overrideDraft.capacityKey ?? ""} />
      {state.status === "error" && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm font-semibold text-red-800">{state.message}</p>}
      <button type="button" className="justify-self-start text-sm font-semibold text-[#2563EB] underline-offset-2 hover:underline" onClick={() => { setRequestId(null); setPhase("edit"); }}>Modifier la saisie</button>
    </form>}
  </AppConfirmDialog>;
}

function PlanFields({ draft, setDraft }: { draft: AdministrationPlanDraft; setDraft: (draft: AdministrationPlanDraft) => void }) {
  return <div className="grid gap-3 sm:grid-cols-3">
    <SelectField label="Formule" value={draft.planKey} onChange={(value) => setDraft(selectAdministrationPlan(draft, value as AdministrationPlanDraft["planKey"]))} options={[['essential', 'Essentiel'], ['comfort', 'Confort'], ['premium', 'Premium']]} />
    <SelectField label="Périodicité informative" value={draft.billingPeriod} onChange={(value) => setDraft({ ...draft, billingPeriod: value as AdministrationPlanDraft["billingPeriod"] })} options={[['monthly', 'Mensuel'], ['annual', 'Annuel']]} />
    <SelectField label="Capacité" value={draft.capacityKey} onChange={(value) => setDraft({ ...draft, capacityKey: value as AdministrationPlanDraft["capacityKey"] })} disabled={draft.planKey === "essential"} options={[['included', '2 dossiers'], ['five', '5 dossiers'], ['ten', '10 dossiers']]} />
  </div>;
}

function OverrideFields({ user, draft, setDraft }: { user: PlatformUserSummary; draft: AdministrationOverrideDraft; setDraft: (draft: AdministrationOverrideDraft) => void }) {
  const baseLimit = user.entitlements?.baseActiveDossierLimit;
  return <div className="grid gap-3 sm:grid-cols-2">
    <SelectField label="Formule fonctionnelle" value={draft.featurePlanKey ?? ""} onChange={(value) => setDraft({ ...draft, featurePlanKey: value ? value as "comfort" | "premium" : null })} options={[["", "Conserver la formule de base"], ['comfort', 'Confort'], ['premium', 'Premium']]} />
    <SelectField label="Capacité" value={draft.capacityKey ?? ""} onChange={(value) => setDraft({ ...draft, capacityKey: value ? value as "five" | "ten" : null })} options={[["", baseLimit === null || baseLimit === undefined ? "Conserver la capacité de base" : `Conserver la base (${baseLimit} dossiers)`], ['five', '5 dossiers'], ['ten', '10 dossiers']]} />
  </div>;
}

function SelectField({ label, value, options, onChange, disabled = false }: { label: string; value: string; options: string[][]; onChange: (value: string) => void; disabled?: boolean }) {
  const id = useId();
  return <div><label className="auth-label" htmlFor={id}>{label}</label><select id={id} className="auth-input" value={value} onChange={(event) => onChange(event.target.value)} disabled={disabled}>{options.map(([optionValue, optionLabel]) => <option key={optionValue || "base"} value={optionValue}>{optionLabel}</option>)}</select></div>;
}

function Comparison({ before, after }: { before: { title: string; lines: string[] }; after: { title: string; lines: string[] } }) {
  return <div className="grid gap-3 sm:grid-cols-2"><Summary title={before.title} lines={before.lines} /><Summary title={after.title} lines={after.lines} /></div>;
}
function Summary({ title, lines }: { title: string; lines: string[] }) {
  return <div className="rounded-xl border border-[#E2E8F0] bg-[#F8FAFC] p-3"><p className="text-xs font-bold uppercase tracking-wide text-[#64748B]">{title}</p><ul className="mt-2 space-y-1 text-sm">{lines.map((line) => <li key={line}>{line}</li>)}</ul></div>;
}

function getOperationLabels(request: EntitlementEditorRequest) {
  const noun = request.entityType === "plan" ? "l’attribution administrative" : "la dérogation";
  const verb = request.operation === "assign" ? "Attribuer" : request.operation === "replace" ? "Modifier" : "Révoquer";
  return { title: `${verb} ${noun}`, description: `${verb} les droits de ce compte avec un motif obligatoire et une trace d’audit.`, confirmLabel: `${verb} et enregistrer` };
}
function getBeforeDescription(request: EntitlementEditorRequest) {
  if (request.entityType === "plan") {
    const value = request.user.entitlements?.administrativeAssignment;
    return { title: "Avant", lines: value ? [value.planKey, value.billingPeriod, formatCapacity(value.dossierCapacityKey)] : ["Aucune attribution administrative"] };
  }
  const value = request.user.entitlements?.administrativeOverride;
  return { title: "Avant", lines: value ? [value.featurePlanKey ?? "Formule de base", value.dossierCapacityKey ? formatCapacity(value.dossierCapacityKey) : "Capacité de base"] : ["Aucune dérogation"] };
}
function getAfterDescription(request: EntitlementEditorRequest, plan: AdministrationPlanDraft, entitlementOverride: AdministrationOverrideDraft) {
  if (request.operation === "revoke") return { title: "Après", lines: [request.entityType === "plan" ? "Aucune attribution administrative active" : "Aucune dérogation active"] };
  const value = request.entityType === "plan"
    ? describeAdministrationPlanDraft(plan)
    : describeAdministrationOverrideDraft(entitlementOverride, request.user.entitlements?.baseActiveDossierLimit ?? null);
  return { title: "Après", lines: Object.values(value) };
}
function formatCapacity(value: "included" | "five" | "ten") { return value === "included" ? "2 dossiers actifs" : value === "five" ? "5 dossiers actifs" : "10 dossiers actifs"; }
