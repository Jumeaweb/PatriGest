"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { CalendarPlus, LockKeyhole, Pencil, RotateCcw } from "lucide-react";
import type { ManagementPeriod } from "@/types/database";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import { FieldError, FormMessage } from "@/components/auth/form-controls";
import { formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
import { addManagementPeriodAction, closeManagementPeriodAction, reopenManagementPeriodAction, updateManagementPeriodAction } from "../actions";
import { initialProtectedPersonState } from "../state";

export function ManagementPeriodManager({ protectedPersonId, periods }: { protectedPersonId: string; periods: ManagementPeriod[] }) {
  const [createOpen, setCreateOpen] = useState(false);
  return <div className="mt-5">
    <div className="flex items-center justify-between gap-3"><h2 className="text-lg font-bold">Tous les exercices</h2><button className="button button-primary gap-1.5" type="button" onClick={() => setCreateOpen(true)}><CalendarPlus size={15} />Créer un exercice</button></div>
    <div className="mt-3 space-y-2">{periods.length ? periods.map((period) => <PeriodRow key={period.id} protectedPersonId={protectedPersonId} period={period} />) : <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun exercice de gestion.</p>}</div>
    {createOpen && <PeriodDialog protectedPersonId={protectedPersonId} open onClose={() => setCreateOpen(false)} />}
  </div>;
}

function PeriodRow({ protectedPersonId, period }: { protectedPersonId: string; period: ManagementPeriod }) {
  const [editOpen, setEditOpen] = useState(false);
  const [closeOpen, setCloseOpen] = useState(false);
  const [reopenOpen, setReopenOpen] = useState(false);
  const [reopenState, reopenAction] = useActionState(reopenManagementPeriodAction.bind(null, protectedPersonId, period.id), initialProtectedPersonState);
  const previousReopenState = useRef(reopenState);
  const open = period.status === "open";
  useEffect(() => { if (reopenOpen && reopenState.status === "success" && previousReopenState.current !== reopenState) setReopenOpen(false); previousReopenState.current = reopenState; }, [reopenOpen, reopenState]);
  const reopenFormId = `reopen-period-${period.id}`;

  return <article className="flex flex-col gap-2.5 rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3 sm:flex-row sm:items-center sm:justify-between">
    <div><div className="flex flex-wrap items-center gap-1.5"><p className="text-sm font-bold">Du {formatFinancialDate(period.start_date)} au {formatFinancialDate(period.end_date)}</p><span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold ${open ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-slate-200 bg-slate-100 text-slate-700"}`}>{open ? "Ouvert · exercice courant" : "Clôturé"}</span></div>{period.closed_at && <p className="mt-0.5 text-[11px] text-[#94A3B8]">Clôturé le {new Intl.DateTimeFormat("fr-FR", { dateStyle: "short" }).format(new Date(period.closed_at))}</p>}</div>
    {open ? <div className="flex gap-1.5"><button className="button button-secondary gap-1.5" type="button" onClick={() => setEditOpen(true)}><Pencil size={14} />Modifier</button><button className="button button-secondary gap-1.5" type="button" onClick={() => setCloseOpen(true)}><LockKeyhole size={14} />Clôturer</button></div> : <button className="button button-secondary gap-1.5" type="button" onClick={() => setReopenOpen(true)}><RotateCcw size={14} />Réouvrir l’exercice</button>}
    {editOpen && <PeriodDialog protectedPersonId={protectedPersonId} period={period} open onClose={() => setEditOpen(false)} />}
    <AppConfirmDialog open={closeOpen} onClose={() => setCloseOpen(false)} title="Clôturer cet exercice ?" description="La clôture empêchera ensuite la modification et la suppression des opérations comprises dans cette période." subject={`Du ${formatFinancialDate(period.start_date)} au ${formatFinancialDate(period.end_date)}`} actions={<form action={closeManagementPeriodAction.bind(null, protectedPersonId, period.id)}><button className="button button-danger" type="submit">Clôturer l’exercice</button></form>} />
    <AppConfirmDialog open={reopenOpen} onClose={() => setReopenOpen(false)} title="Réouvrir cet exercice ?" description="Les opérations comprises dans cette période redeviendront modifiables." subject={`Du ${formatFinancialDate(period.start_date)} au ${formatFinancialDate(period.end_date)}`} actions={<button className="button button-primary" type="submit" form={reopenFormId}>Réouvrir l’exercice</button>}><form id={reopenFormId} action={reopenAction}><FormMessage state={reopenState} /></form></AppConfirmDialog>
  </article>;
}

function PeriodDialog({ protectedPersonId, period, open, onClose }: { protectedPersonId: string; period?: ManagementPeriod; open: boolean; onClose: () => void }) {
  const action = period ? updateManagementPeriodAction.bind(null, protectedPersonId, period.id) : addManagementPeriodAction.bind(null, protectedPersonId);
  const [state, formAction, pending] = useActionState(action, initialProtectedPersonState);
  const formId = `period-${period?.id ?? "new"}`;
  const year = new Date().getFullYear();
  const [startDate, setStartDate] = useState(period?.start_date ?? `${year}-01-01`);
  const [endDate, setEndDate] = useState(period?.end_date ?? `${year}-12-31`);
  const succeeded = state.status === "success";
  return <AppConfirmDialog open={open} onClose={onClose} title={period ? "Modifier l’exercice" : "Créer un exercice"} description={succeeded ? "L’opération est terminée. Vous pouvez fermer cette boîte de dialogue." : "Définissez la période couverte par cet exercice de gestion."} cancelLabel={succeeded ? "Fermer" : "Annuler"} actions={succeeded ? null : <button className="button button-primary" type="submit" form={formId} disabled={pending}>{pending ? "Enregistrement…" : period ? "Enregistrer" : "Créer l’exercice"}</button>}>{succeeded ? <FormMessage state={state} /> : <form id={formId} action={formAction} className="grid gap-3 sm:grid-cols-2"><DateField id={`${formId}-start`} name="startDate" label="Date de début" value={startDate} onChange={setStartDate} errors={state.fieldErrors?.startDate} /><DateField id={`${formId}-end`} name="endDate" label="Date de fin" value={endDate} onChange={setEndDate} errors={state.fieldErrors?.endDate} /><div className="sm:col-span-2"><FormMessage state={state} /></div></form>}</AppConfirmDialog>;
}

function DateField({ id, name, label, value, onChange, errors }: { id: string; name: string; label: string; value: string; onChange: (value: string) => void; errors?: string[] }) { const errorId = `${id}-error`; return <div><label className="auth-label" htmlFor={id}>{label}</label><input className="auth-input" id={id} name={name} type="date" required value={value} onChange={(event) => onChange(event.target.value)} aria-describedby={errors?.length ? errorId : undefined} />{errors?.length ? <span id={errorId}><FieldError messages={errors} /></span> : null}</div>; }
