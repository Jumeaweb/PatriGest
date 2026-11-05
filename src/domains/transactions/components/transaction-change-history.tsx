import type { Json, Transaction, TransactionChange } from "@/types/database";
import { formatCurrency, formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";

const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
const fields = [
  ["transaction_date", "Date"], ["transaction_type", "Nature"], ["label", "Libellé"],
  ["amount", "Montant"], ["financial_account_id", "Compte"], ["category_id", "Catégorie"],
  ["classification_precision", "Précision"], ["comment", "Commentaire"], ["proof_reference", "Référence du justificatif"],
] as const;

function record(value: Json): Record<string, Json | undefined> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, Json | undefined> : {};
}

function display(field: string, value: Json | undefined) {
  if (value === null || value === undefined || value === "") return "Non renseigné";
  if (field === "amount" && typeof value === "number") return formatCurrency(value);
  if (field === "transaction_date" && typeof value === "string") return formatFinancialDate(value);
  if (field === "transaction_type") return value === "income" ? "Recette" : value === "expense" ? "Dépense" : String(value);
  return String(value);
}

function changes(item: TransactionChange) {
  const before = record(item.previous_values);
  const after = record(item.new_values);
  return fields.filter(([field]) => JSON.stringify(before[field]) !== JSON.stringify(after[field])).map(([field, label]) => ({ label, before: display(field, before[field]), after: display(field, after[field]) }));
}

function title(item: TransactionChange) {
  if (item.change_kind === "cancellation") return "Annulation";
  const before = record(item.previous_values).transaction_type;
  const after = record(item.new_values).transaction_type;
  return before !== after ? `Conversion en ${after === "income" ? "recette" : "dépense"}` : "Correction";
}

export function TransactionChangeHistory({ transaction, items }: { transaction: Transaction; items: TransactionChange[] }) {
  return <section className="mt-4 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5">
    <h2 className="text-base font-bold">Historique de l’opération</h2>
    <ol className="mt-3 space-y-3">
      <li className="rounded-lg border border-[#E2E8F0] p-3"><div className="flex flex-wrap items-start justify-between gap-2"><strong className="text-sm">Création</strong><time className="text-xs text-[#64748B]" dateTime={transaction.created_at}>{dateTime(transaction.created_at)}</time></div><p className="mt-1 text-xs text-[#64748B]">L’auteur de la création n’est pas enregistré dans l’historique disponible.</p></li>
      {items.map((item) => { const details = changes(item); return <li key={item.id} className="rounded-lg border border-[#E2E8F0] p-3"><div className="flex flex-wrap items-start justify-between gap-2"><div><strong className="text-sm">{title(item)}</strong><p className="text-xs text-[#64748B]">Par {item.changed_by_name}</p></div><time className="text-xs text-[#64748B]" dateTime={item.changed_at}>{dateTime(item.changed_at)}</time></div><p className="mt-2 rounded-md bg-slate-50 px-2.5 py-2 text-xs"><span className="font-semibold">Motif :</span> {item.reason}</p>{details.length > 0 && <dl className="mt-2 divide-y divide-[#E2E8F0] text-xs">{details.map((detail) => <div key={detail.label} className="grid gap-1 py-2 sm:grid-cols-[9rem_1fr_1fr]"><dt className="font-semibold text-[#475569]">{detail.label}</dt><dd><span className="text-[#64748B]">Avant : </span>{detail.before}</dd><dd><span className="text-[#64748B]">Après : </span>{detail.after}</dd></div>)}</dl>}</li>; })}
    </ol>
  </section>;
}
