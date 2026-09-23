import Link from "next/link";
import type { Category } from "@/types/database";
import type { FinancialAccountWithValuations } from "@/domains/financial-accounts/services/financial-account-service";
import { getFinancialAccountEntryHref } from "@/domains/financial-accounts/financial-account-entry";
import { formatCurrency, getCurrentAccountValue, isValuationAccount } from "@/domains/financial-accounts/utils/financial-account-utils";

type FilterValues = { start?: string; end?: string; account?: string; type?: string; category?: string; q?: string };

export function TransactionFilters({ personId, accounts, categories, values }: { personId: string; accounts: FinancialAccountWithValuations[]; categories: Category[]; values: FilterValues }) {
  const activeAccounts = accounts.filter((account) => account.status === "active");

  return <>
    <section className="mt-4" aria-labelledby="current-balances-title">
      <h2 id="current-balances-title" className="text-xs font-bold text-[#334155]">Soldes actuels</h2>
      {activeAccounts.length > 0 ? <div className="mt-2 overflow-x-auto rounded-xl border border-[#E2E8F0] bg-white shadow-[0_6px_18px_rgba(15,23,42,0.03)] [scrollbar-width:thin]">
        <div className="flex min-w-max divide-x divide-[#E2E8F0]">
          {activeAccounts.map((account) => {
            const current = getCurrentAccountValue(account, account.valuations, account.transactions);
            return <Link key={account.id} href={getFinancialAccountEntryHref(personId, account.id, isValuationAccount(account.account_type))} className="focus-ring block w-44 shrink-0 px-3 py-2 transition hover:bg-blue-50/50 sm:w-52 sm:px-4">
              <p className="truncate text-[11px] font-semibold leading-4 text-[#64748B]" title={account.account_name}>{account.account_name}</p>
              <p className="whitespace-nowrap text-base font-bold leading-6 tracking-tight text-[#0F172A] sm:text-lg">{formatCurrency(current.value)}</p>
            </Link>;
          })}
        </div>
      </div> : <p className="mt-3 rounded-2xl border border-dashed border-[#CBD5E1] bg-white px-4 py-3 text-sm text-[#64748B]">Aucun compte actif.</p>}
    </section>

    <form className="mt-4 rounded-xl border border-[#E2E8F0] bg-white p-3">
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-6">
        <FilterField label="Date de début"><input className="auth-input h-9! rounded-lg px-2.5 text-xs" name="start" type="date" defaultValue={values.start} /></FilterField>
        <FilterField label="Date de fin"><input className="auth-input h-9! rounded-lg px-2.5 text-xs" name="end" type="date" defaultValue={values.end} /></FilterField>
        <FilterField label="Compte"><select className="auth-input h-9! rounded-lg px-2.5 text-xs" name="account" defaultValue={values.account ?? ""}><option value="">Tous les comptes</option>{accounts.map((account) => <option key={account.id} value={account.id}>{account.account_name}</option>)}</select></FilterField>
        <FilterField label="Type"><select className="auth-input h-9! rounded-lg px-2.5 text-xs" name="type" defaultValue={values.type ?? ""}><option value="">Tous les types</option><option value="income">Recettes</option><option value="expense">Dépenses</option><option value="transfer">Virements</option></select></FilterField>
        <FilterField label="Catégorie"><select className="auth-input h-9! rounded-lg px-2.5 text-xs" name="category" defaultValue={values.category ?? ""}><option value="">Toutes catégories</option>{categories.filter((category) => category.active).map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></FilterField>
        <FilterField label="Recherche"><input className="auth-input h-9! rounded-lg px-2.5 text-xs" name="q" placeholder="Libellé…" defaultValue={values.q} /></FilterField>
      </div>
      <div className="mt-2 flex justify-end gap-2"><a className="button button-secondary min-h-9! rounded-lg px-3! text-xs" href="?">Effacer</a><button className="button button-primary min-h-9! rounded-lg px-3! text-xs" type="submit">Filtrer</button></div>
    </form>
  </>;
}

function FilterField({ label, children }: { label: string; children: React.ReactElement<{ id?: string; "aria-label"?: string }> }) {
  return <label className="min-w-0"><span className="mb-1 block text-[10px] font-semibold text-[#64748B]">{label}</span>{children}</label>;
}
