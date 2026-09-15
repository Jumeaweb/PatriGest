import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { Landmark, Plus, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { FinancialNavigation } from "@/domains/financial-accounts/components/financial-navigation";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { getFinancialAccounts, type FinancialAccountWithValuations } from "@/domains/financial-accounts/services/financial-account-service";
import { financialAccountLabels, formatCurrency, formatFinancialDate, getCurrentAccountValue, getCurrentPatrimonyValue, isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";

export const metadata: Metadata = { title: "Comptes et patrimoine" };
export const dynamic = "force-dynamic";

export default async function FinancialAccountsPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const accounts = await getFinancialAccounts(protectedPersonId);
  const active = accounts.filter((account) => account.status === "active");
  const closed = accounts.filter((account) => account.status === "closed");
  const total = getCurrentPatrimonyValue(accounts);
  const canManage = person.accessRole !== "read_only";
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "accounts", accessRole: person.accessRole }}><AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Comptes et patrimoine" }]} /><div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-sm font-bold uppercase tracking-[0.14em] text-[#2563EB]">{person.first_name} {person.last_name}</p><h1 className="mt-2 text-3xl font-bold tracking-tight">Comptes et patrimoine</h1></div>{canManage && <Link href={`/dossiers/${protectedPersonId}/comptes/nouveau`} className="button button-primary gap-2"><Plus aria-hidden="true" size={18} />Ajouter un compte</Link>}</div><DossierNavigation protectedPersonId={protectedPersonId} current="accounts" /><FinancialNavigation protectedPersonId={protectedPersonId} current="accounts" />
    <div className="mt-6 grid gap-4 sm:grid-cols-2"><section className="flex items-center gap-4 rounded-2xl border border-blue-100 bg-blue-50 p-4"><span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white/70 text-[#2563EB]"><WalletCards aria-hidden="true" size={18} /></span><div><p className="text-xs font-semibold text-[#64748B]">Patrimoine total actif</p><p className="mt-0.5 text-2xl font-bold">{formatCurrency(total)}</p></div></section><section className="flex items-center gap-4 rounded-2xl border border-emerald-100 bg-emerald-50 p-4"><span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white/70 text-[#16A34A]"><Landmark aria-hidden="true" size={18} /></span><div><p className="text-xs font-semibold text-[#64748B]">Comptes actifs</p><p className="mt-0.5 text-2xl font-bold">{active.length}</p></div></section></div>
    {accounts.length === 0 ? <section className="mt-6 rounded-2xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center"><h2 className="text-lg font-bold">Aucun compte enregistré</h2><p className="mt-1 text-sm text-[#64748B]">{canManage ? "Ajoutez le premier support financier de ce dossier." : "Aucun support financier n’est actuellement enregistré."}</p>{canManage && <Link href={`/dossiers/${protectedPersonId}/comptes/nouveau`} className="button button-primary mt-4 min-h-9 px-4">Ajouter un compte</Link>}</section> : <><AccountSection title="Comptes actifs" accounts={active} protectedPersonId={protectedPersonId} />{closed.length > 0 && <AccountSection title="Comptes clôturés" accounts={closed} protectedPersonId={protectedPersonId} muted />}</>}
  </PrivateShell>;
}

function AccountSection({ title, accounts, protectedPersonId, muted = false }: { title: string; accounts: FinancialAccountWithValuations[]; protectedPersonId: string; muted?: boolean }) {
  if (!accounts.length) return null;
  return <section className="mt-6"><h2 className="text-lg font-bold">{title}</h2><div className="mt-3 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">{accounts.map((account) => {
    const current = getCurrentAccountValue(account, account.valuations);
    const href = isValuationAccount(account.account_type) ? `/dossiers/${protectedPersonId}/comptes/${account.id}` : `/dossiers/${protectedPersonId}/comptes/${account.id}/operations`;
    return <Link key={account.id} href={href} className={`focus-ring self-start rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3 shadow-[0_6px_18px_rgba(15,23,42,0.035)] transition hover:border-blue-200 ${muted ? "opacity-70" : ""}`}><div className="flex items-start justify-between gap-2"><div className="min-w-0"><h3 className="truncate text-sm font-bold leading-5">{account.account_name}</h3><p className="truncate text-[11px] leading-4 text-[#64748B]">{account.institution_name}</p></div><span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold leading-4 ${account.status === "active" ? "bg-green-50 text-[#15803D]" : "bg-slate-100 text-[#64748B]"}`}>{account.status === "active" ? "Actif" : "Clôturé"}</span></div><p className="mt-1.5 truncate text-[11px] font-semibold leading-4 text-[#2563EB]">{financialAccountLabels[account.account_type]}</p><p className="text-xl font-bold leading-7">{formatCurrency(current.value)}</p>{current.valuation && <p className="text-[10px] leading-4 text-[#94A3B8]">Valorisation au {formatFinancialDate(current.valuation.valuation_date)}</p>}</Link>;
  })}</div></section>;
}
