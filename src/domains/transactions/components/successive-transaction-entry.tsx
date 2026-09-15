"use client";

import Link from "next/link";
import { useActionState, useEffect, useRef, useState } from "react";
import type { Category, FinancialAccount } from "@/types/database";
import { FieldError } from "@/components/auth/form-controls";
import { formatCurrency, formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
import { getEffectiveOfficialCategory, getPrecisionAfterCategoryChange } from "./transaction-classification-form";
import { createSuccessiveTransactionAction } from "../successive-actions";
import { initialSuccessiveActionState, isSuccessiveAccountEligible, nextSuccessiveDraft, type CreatedSuccessiveTransaction, type SuccessiveDraft } from "../successive-entry";

type Props = { personId: string; accounts: FinancialAccount[]; categories: Category[]; defaultAccountId?: string; returnHref: string };

export function SuccessiveTransactionEntry({ personId, accounts, categories, defaultAccountId, returnHref }: Props) {
  const eligibleAccounts = accounts.filter(isSuccessiveAccountEligible);
  const [draft, setDraft] = useState<SuccessiveDraft>({ transactionType: "expense", financialAccountId: defaultAccountId ?? "", transactionDate: new Date().toISOString().slice(0, 10), label: "", amount: "", categoryId: "", classificationPrecision: "" });
  const [history, setHistory] = useState<CreatedSuccessiveTransaction[]>([]);
  const [created, setCreated] = useState<CreatedSuccessiveTransaction | null>(null);
  const [lineNumber, setLineNumber] = useState(1);
  const accountNames = new Map(eligibleAccounts.map((account) => [account.id, account.account_name]));

  function recorded(transaction: CreatedSuccessiveTransaction, savedDraft: SuccessiveDraft) {
    setHistory((rows) => [transaction, ...rows]);
    setDraft(nextSuccessiveDraft(savedDraft));
    setCreated(transaction);
  }
  function next() { setCreated(null); setLineNumber((number) => number + 1); }

  return <div className="mt-5 grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(16rem,21rem)]">
    <div className="rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5">
      {created ? <CreatedStep key={created.id} personId={personId} transaction={created} onNext={next} onFinishHref={returnHref} />
        : eligibleAccounts.length ? <EntryForm key={lineNumber} personId={personId} accounts={eligibleAccounts} categories={categories} draft={draft} onDraftChange={setDraft} onCreated={recorded} returnHref={returnHref} />
          : <div role="status"><p>Aucun compte transactionnel actif n’est disponible.</p><Link href={returnHref} className="button button-secondary mt-3">Retour au journal</Link></div>}
    </div>
    <section className="rounded-xl border border-[#E2E8F0] bg-white p-4" aria-label="Opérations enregistrées pendant cette saisie">
      <h2 className="text-base font-bold">Opérations enregistrées ({history.length})</h2>
      {history.length === 0 ? <p className="mt-2 text-sm text-[#64748B]">Aucune opération enregistrée dans cette session.</p> : <ol className="mt-3 space-y-2">{history.map((item) => <li key={item.id} className="rounded-lg border border-[#E2E8F0] p-2 text-xs"><span className="font-semibold">{item.transaction_type === "income" ? "Recette" : "Dépense"} · {formatFinancialDate(item.transaction_date)}</span><p className="mt-1 font-bold">{item.label} · {formatCurrency(item.amount)}</p>{!defaultAccountId && <p className="text-[#64748B]">{accountNames.get(item.financial_account_id) ?? "Compte"}</p>}</li>)}</ol>}
    </section>
  </div>;
}

function EntryForm({ personId, accounts, categories, draft, onDraftChange, onCreated, returnHref }: {
  personId: string; accounts: FinancialAccount[]; categories: Category[]; draft: SuccessiveDraft;
  onDraftChange: (draft: SuccessiveDraft) => void; onCreated: (created: CreatedSuccessiveTransaction, draft: SuccessiveDraft) => void; returnHref: string;
}) {
  const [state, formAction, pending] = useActionState(createSuccessiveTransactionAction.bind(null, personId), initialSuccessiveActionState);
  const submitted = useRef(false);
  const submittedDraft = useRef(draft);
  const reported = useRef<string | null>(null);
  const labelRef = useRef<HTMLInputElement>(null);
  const accountRef = useRef<HTMLSelectElement>(null);
  const initiallyHasAccount = useRef(Boolean(draft.financialAccountId));
  useEffect(() => { (initiallyHasAccount.current ? labelRef.current : accountRef.current)?.focus(); }, []);
  useEffect(() => {
    if (state.status === "error") submitted.current = false;
    if (state.created && reported.current !== state.created.id) { reported.current = state.created.id; onCreated(state.created, submittedDraft.current); }
  }, [state, onCreated]);
  const selected = categories.find((category) => category.id === draft.categoryId);
  const official = getEffectiveOfficialCategory(categories, draft.categoryId);
  const precisionRequired = official?.requires_precision === true;
  const usableCategories = categories.filter((category) => category.active && (category.usage === draft.transactionType || category.usage === "both"));
  const change = (patch: Partial<SuccessiveDraft>) => onDraftChange({ ...draft, ...patch });
  const errors = state.fieldErrors;
  const field = (name: string) => errors?.[name]?.length ? `${name}-error` : undefined;
  return <form action={formAction} onSubmit={(event) => { if (submitted.current || pending) event.preventDefault(); else { submitted.current = true; submittedDraft.current = draft; } }} className="grid gap-3 sm:grid-cols-2">
    <h2 className="sm:col-span-2 text-base font-bold">Opération suivante</h2>
    <div className="sm:col-span-2"><span className="auth-label">Type d’opération</span><div className="flex gap-2" role="group" aria-label="Type d’opération">{(["income", "expense"] as const).map((mode) => <button key={mode} type="button" className={`button ${draft.transactionType === mode ? "button-primary" : "button-secondary"}`} onClick={() => change({ transactionType: mode, categoryId: "", classificationPrecision: "" })} aria-pressed={draft.transactionType === mode}>{mode === "income" ? "Recette" : "Dépense"}</button>)}</div><input type="hidden" name="transactionType" value={draft.transactionType} /></div>
    <div><label className="auth-label" htmlFor="financialAccountId">Compte *</label><select ref={accountRef} className="auth-input" id="financialAccountId" name="financialAccountId" value={draft.financialAccountId} onChange={(event) => change({ financialAccountId: event.target.value })} aria-describedby={field("financialAccountId")} required><option value="">Choisir un compte</option>{accounts.map((account) => <option key={account.id} value={account.id}>{account.account_name} — {account.institution_name}</option>)}</select><span id="financialAccountId-error"><FieldError messages={errors?.financialAccountId} /></span></div>
    <div><label className="auth-label" htmlFor="transactionDate">Date *</label><input className="auth-input" id="transactionDate" name="transactionDate" type="date" value={draft.transactionDate} onChange={(event) => change({ transactionDate: event.target.value })} aria-describedby={field("transactionDate")} required /><span id="transactionDate-error"><FieldError messages={errors?.transactionDate} /></span></div>
    <div><label className="auth-label" htmlFor="label">Libellé *</label><input ref={labelRef} className="auth-input" id="label" name="label" value={draft.label} onChange={(event) => change({ label: event.target.value })} maxLength={160} aria-describedby={field("label")} required /><span id="label-error"><FieldError messages={errors?.label} /></span></div>
    <div><label className="auth-label" htmlFor="amount">Montant *</label><input className="auth-input" id="amount" name="amount" type="number" step="0.01" min="0.01" value={draft.amount} onChange={(event) => change({ amount: event.target.value })} aria-describedby={field("amount")} required /><span id="amount-error"><FieldError messages={errors?.amount} /></span></div>
    <div><label className="auth-label" htmlFor="categoryId">Catégorie facultative</label><select className="auth-input" id="categoryId" name="categoryId" value={draft.categoryId} onChange={(event) => change({ categoryId: event.target.value, classificationPrecision: getPrecisionAfterCategoryChange(categories, event.target.value) })} aria-describedby={field("categoryId")}><option value="">Sans catégorie</option><optgroup label="Mes catégories personnelles">{usableCategories.filter((category) => !category.is_system).map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</optgroup><optgroup label="Rubriques officielles">{usableCategories.filter((category) => category.is_system && category.official_code).map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</optgroup></select><span id="categoryId-error"><FieldError messages={errors?.categoryId} /></span></div>
    {precisionRequired ? <div><label className="auth-label" htmlFor="classificationPrecision">Précision *</label><input className="auth-input" id="classificationPrecision" name="classificationPrecision" value={draft.classificationPrecision} onChange={(event) => change({ classificationPrecision: event.target.value })} maxLength={160} required aria-describedby={field("classificationPrecision")} /><span id="classificationPrecision-error"><FieldError messages={errors?.classificationPrecision} /></span></div> : <input type="hidden" name="classificationPrecision" value="" />}
    {selected && !official && <p className="sm:col-span-2 text-xs text-[#DC2626]">Cette catégorie ne peut pas être utilisée.</p>}
    {state.status === "error" && <p role="alert" className="sm:col-span-2 text-sm text-[#DC2626]">{state.message}</p>}
    <div className="sm:col-span-2 flex flex-wrap gap-2"><button className="button button-primary" type="submit" disabled={pending}>{pending ? "Enregistrement…" : "Enregistrer cette opération"}</button><Link className="button button-secondary" href={returnHref} aria-disabled={pending} onClick={(event) => { if (pending) event.preventDefault(); }}>Terminer la saisie</Link></div>
  </form>;
}

function CreatedStep({ personId, transaction, onNext, onFinishHref }: { personId: string; transaction: CreatedSuccessiveTransaction; onNext: () => void; onFinishHref: string }) {
  const [pending, setPending] = useState(false);
  const [proofStatus, setProofStatus] = useState<"idle" | "success" | "error">("idle");
  const inputRef = useRef<HTMLInputElement>(null);
  async function upload(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setProofStatus("idle");
    try {
      const response = await fetch(`/api/dossiers/${personId}/operations/${transaction.id}/justificatif`, { method: "POST", body: new FormData(event.currentTarget) });
      if (!response.ok) throw new Error("Justificatif non enregistré");
      if (inputRef.current) inputRef.current.value = "";
      setProofStatus("success");
    } catch { setProofStatus("error"); }
    finally { setPending(false); }
  }
  return <div role="status"><h2 className="text-lg font-bold text-green-800">Opération enregistrée</h2><p className="mt-2 text-sm">{transaction.transaction_type === "income" ? "Recette" : "Dépense"} · {transaction.label} · {formatCurrency(transaction.amount)}</p>
    {transaction.transaction_type === "expense" && transaction.proof_reference && <section className="mt-4 rounded-lg border border-[#E2E8F0] p-3"><h3 className="font-semibold">Justificatif facultatif</h3><p className="mt-1 text-xs text-[#64748B]">Référence {transaction.proof_reference}</p>{proofStatus !== "success" && <form onSubmit={upload} className="mt-3 flex flex-wrap items-center gap-2"><label htmlFor="successive-proof" className="sr-only">Fichier justificatif</label><input ref={inputRef} id="successive-proof" name="file" type="file" accept="application/pdf,image/jpeg,image/png" required /><button className="button button-secondary" type="submit" disabled={pending}>{pending ? "Envoi…" : proofStatus === "error" ? "Réessayer l’ajout" : "Ajouter un justificatif"}</button></form>}{proofStatus === "success" && <p className="mt-2 text-sm text-green-800">Justificatif enregistré.</p>}{proofStatus === "error" && <p role="alert" className="mt-2 text-sm text-red-700">Le justificatif n’a pas pu être ajouté. La dépense reste enregistrée ; réessayez ou continuez.</p>}</section>}
    <div className="mt-4 flex flex-wrap gap-2"><button className="button button-primary" type="button" onClick={onNext} disabled={pending}>Saisir la suivante</button><Link className="button button-secondary" href={onFinishHref} aria-disabled={pending} onClick={(event) => { if (pending) event.preventDefault(); }}>Terminer la saisie</Link></div>
  </div>;
}
