"use client";

import Link from "next/link";
import { useActionState } from "react";
import { FieldError, FormMessage, SubmitButton } from "@/components/auth/form-controls";
import { createFinancialAccountAction, updateFinancialAccountAction } from "../actions";
import { initialFinancialAccountState } from "../state";
import { financialAccountLabels } from "../utils/financial-account-utils";
import type { FinancialAccount } from "@/types/database";

export function FinancialAccountForm({ protectedPersonId, account }: { protectedPersonId: string; account?: FinancialAccount }) {
  const action = account ? updateFinancialAccountAction.bind(null, protectedPersonId, account.id) : createFinancialAccountAction.bind(null, protectedPersonId);
  const [state, formAction] = useActionState(action, initialFinancialAccountState);
  const cancelHref = account ? `/dossiers/${protectedPersonId}/comptes/${account.id}` : `/dossiers/${protectedPersonId}/comptes`;
  return <form action={formAction} className="grid gap-3 sm:grid-cols-2">
    <div><label className="auth-label" htmlFor="accountType">Type de compte *</label><select className="auth-input" id="accountType" name="accountType" required defaultValue={account?.account_type ?? "checking"}>{Object.entries(financialAccountLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><FieldError messages={state.fieldErrors?.accountType} /></div>
    <Field id="accountName" label="Intitulé" required defaultValue={account?.account_name} help="Exemple : Crédit Agricole - 2302" errors={state.fieldErrors?.accountName} />
    <Field id="institutionName" label="Établissement" required defaultValue={account?.institution_name} errors={state.fieldErrors?.institutionName} />
    <Field id="accountReference" label="Référence facultative" defaultValue={account?.account_reference} errors={state.fieldErrors?.accountReference} />
    <Field id="initialBalance" label="Solde initial" type="number" step="0.01" required defaultValue={account?.initial_balance ?? "0.00"} help="Indiquez la valeur réelle du compte à la date du solde initial. Ce montant sert de point de départ au suivi dans PatriGest ; 0,00 est proposé par défaut, mais n’est pas une valeur calculée." errors={state.fieldErrors?.initialBalance} /><Field id="initialBalanceDate" label="Date du solde initial" type="date" required defaultValue={account?.initial_balance_date ?? new Date().toISOString().slice(0, 10)} help="Choisissez la date à laquelle correspond le solde initial : ensemble, ils décrivent le point de départ du compte." errors={state.fieldErrors?.initialBalanceDate} />
    <Field id="openingDate" label="Date d’ouverture facultative" type="date" defaultValue={account?.opening_date} errors={state.fieldErrors?.openingDate} />
    <div className="sm:col-span-2"><label className="auth-label" htmlFor="notes">Notes facultatives</label><textarea className="auth-input min-h-20 py-2" id="notes" name="notes" defaultValue={account?.notes ?? ""} aria-invalid={Boolean(state.fieldErrors?.notes?.length)} /><FieldError messages={state.fieldErrors?.notes} /></div>
    <div className="sm:col-span-2"><FormMessage state={state} /></div>
    <div className="flex flex-col-reverse gap-2 sm:col-span-2 sm:flex-row sm:justify-end"><Link href={cancelHref} className="button button-secondary">Annuler</Link><div className="sm:min-w-40"><SubmitButton pendingLabel="Enregistrement…">{account ? "Enregistrer" : "Ajouter le compte"}</SubmitButton></div></div>
  </form>;
}

function Field({ id, label, type = "text", required = false, defaultValue, help, step, errors }: { id: string; label: string; type?: string; required?: boolean; defaultValue?: string | number | null; help?: string; step?: string; errors?: string[] }) {
  return <div><label className="auth-label" htmlFor={id}>{label}{required ? " *" : ""}</label><input className="auth-input" id={id} name={id} type={type} required={required} defaultValue={defaultValue ?? ""} step={step} aria-invalid={Boolean(errors?.length)} />{help && <p className="mt-1.5 text-xs text-[#94A3B8]">{help}</p>}<FieldError messages={errors} /></div>;
}
