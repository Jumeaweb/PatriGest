import type { Json, Transfer, TransferChange } from "@/types/database";
import { formatCurrency, formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";

const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
const fields = [
  ["transfer_date", "Date"], ["amount", "Montant"], ["source_account_id", "Compte de départ"],
  ["destination_account_id", "Compte d’arrivée"], ["label", "Libellé"], ["comment", "Commentaire"],
] as const;

function record(value: Json): Record<string, Json | undefined> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, Json | undefined> : {};
}

function display(field: string, value: Json | undefined, accountNames: ReadonlyMap<string, string>) {
  if (value === null || value === undefined || value === "") return "Non renseigné";
  if (field === "amount" && typeof value === "number") return formatCurrency(value);
  if (field === "transfer_date" && typeof value === "string") return formatFinancialDate(value);
  if ((field === "source_account_id" || field === "destination_account_id") && typeof value === "string") return accountNames.get(value) ?? "Compte historique";
  return String(value);
}

export function TransferChangeHistory({ transfer, items, accountNames }: { transfer: Transfer; items: TransferChange[]; accountNames: ReadonlyMap<string, string> }) {
  return <section className="mt-4 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4 sm:p-5">
    <h2 className="text-base font-bold">Historique du virement</h2>
    <ol className="mt-3 space-y-3">
      <li className="rounded-lg border border-[#E2E8F0] p-3"><div className="flex flex-wrap items-start justify-between gap-2"><strong className="text-sm">Création du virement</strong><time className="text-xs text-[#64748B]" dateTime={transfer.created_at}>{dateTime(transfer.created_at)}</time></div><p className="mt-1 text-xs text-[#64748B]">Les deux mouvements ont été enregistrés ensemble.</p></li>
      {items.map((item) => {
        const before = record(item.previous_values);
        const after = record(item.new_values);
        const details = fields.filter(([field]) => JSON.stringify(before[field]) !== JSON.stringify(after[field]));
        return <li key={item.id} className="rounded-lg border border-[#E2E8F0] p-3"><div className="flex flex-wrap items-start justify-between gap-2"><div><strong className="text-sm">{item.change_kind === "cancellation" ? "Annulation du virement" : "Correction du virement"}</strong><p className="text-xs text-[#64748B]">Par {item.changed_by_name}</p></div><time className="text-xs text-[#64748B]" dateTime={item.changed_at}>{dateTime(item.changed_at)}</time></div><p className="mt-2 rounded-md bg-slate-50 px-2.5 py-2 text-xs"><span className="font-semibold">Motif :</span> {item.reason}</p>{details.length > 0 && <dl className="mt-2 divide-y divide-[#E2E8F0] text-xs">{details.map(([field, label]) => <div key={field} className="grid gap-1 py-2 sm:grid-cols-[9rem_1fr_1fr]"><dt className="font-semibold text-[#475569]">{label}</dt><dd><span className="text-[#64748B]">Avant : </span>{display(field, before[field], accountNames)}</dd><dd><span className="text-[#64748B]">Après : </span>{display(field, after[field], accountNames)}</dd></div>)}</dl>}</li>;
      })}
    </ol>
  </section>;
}
