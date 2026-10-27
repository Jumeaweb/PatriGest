import Link from "next/link";
import {
  documentInventoryAnomalyLabels,
  documentInventoryAnomalySchema,
  documentInventoryCategoryLabels,
  documentInventoryCategorySchema,
  getAdministrativeDocumentInventoryHref,
  type AdministrativeDocumentInventoryQuery,
  type DocumentInventoryFinding,
} from "../administrative-document-inventory";
import type { PhysicalVerificationObservation } from "../administrative-document-physical-verification";
import { AdministrativeDocumentPhysicalVerification } from "./administrative-document-physical-verification";

const findingLabels = {
  sql_fact: "Fait SQL démontré",
  possible_anomaly: "Anomalie possible",
  historical_legitimate: "État historique potentiellement légitime",
} as const;

export function AdministrativeDocumentInventory({
  items,
  nextCursor,
  query,
  selectedObservations,
}: {
  items: DocumentInventoryFinding[];
  nextCursor: string | null;
  query: AdministrativeDocumentInventoryQuery;
  selectedObservations: PhysicalVerificationObservation[];
}) {
  return <>
    <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4">
      <h2 className="text-base font-bold">Filtres bornés</h2>
      <form method="get" className="mt-3 grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
        <div><label className="auth-label" htmlFor="inventory-category">Catégorie</label><select id="inventory-category" name="category" className="auth-input" defaultValue={query.category ?? ""}><option value="">Toutes les catégories</option>{documentInventoryCategorySchema.options.map((value) => <option key={value} value={value}>{documentInventoryCategoryLabels[value]}</option>)}</select></div>
        <div><label className="auth-label" htmlFor="inventory-anomaly">Constat</label><select id="inventory-anomaly" name="anomaly" className="auth-input" defaultValue={query.anomaly ?? ""}><option value="">Tous les constats</option>{documentInventoryAnomalySchema.options.map((value) => <option key={value} value={value}>{documentInventoryAnomalyLabels[value]}</option>)}</select></div>
        <button className="button button-secondary" type="submit">Appliquer</button>
      </form>
      <p className="mt-3 text-xs leading-5 text-[#64748B]">Pagination stable par curseur, limitée à {query.limit} résultats. Une écriture concurrente peut modifier les pages suivantes : cet inventaire ne constitue pas un instantané transactionnel.</p>
    </section>
    <section className="mt-5" aria-labelledby="inventory-results-title">
      <div className="flex items-center justify-between gap-3"><h2 id="inventory-results-title" className="text-base font-bold">Constats documentaires</h2><span className="text-xs text-[#64748B]">{items.length} résultat{items.length > 1 ? "s" : ""}</span></div>
      {items.length === 0 ? <div className="mt-3 rounded-xl border border-dashed border-[#CBD5E1] p-6 text-center text-sm text-[#64748B]">Aucun constat pour ces filtres.</div> : <div className="mt-3 grid gap-3">{items.map((item) => <InventoryFinding key={item.inventoryKey} item={item} query={query} observations={query.finding === item.inventoryKey ? selectedObservations : []} />)}</div>}
      <nav className="mt-4 flex items-center gap-3" aria-label="Pagination de l’inventaire">
        {query.cursor && <Link className="button button-secondary" href={getAdministrativeDocumentInventoryHref(query, null)}>Revenir au début</Link>}
        {nextCursor && <Link className="button button-secondary" href={getAdministrativeDocumentInventoryHref(query, nextCursor)}>Page suivante</Link>}
      </nav>
    </section>
  </>;
}

function InventoryFinding({ item, query, observations }: { item: DocumentInventoryFinding; query: AdministrativeDocumentInventoryQuery; observations: PhysicalVerificationObservation[] }) {
  const physicallyVerifiable = item.physicalVerificationRequired && ["transaction_proof", "bank_statement", "management_report", "backup"].includes(item.documentCategory);
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-4">
    <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
      <div><p className="text-xs font-semibold uppercase tracking-wide text-[#64748B]">{documentInventoryCategoryLabels[item.documentCategory]}</p><h3 className="mt-1 text-sm font-bold">{documentInventoryAnomalyLabels[item.anomalyType]}</h3></div>
      <span className={`w-fit rounded-full px-2.5 py-1 text-xs font-semibold ${item.findingStatus === "sql_fact" ? "bg-red-50 text-red-800" : item.findingStatus === "possible_anomaly" ? "bg-amber-50 text-amber-900" : "bg-blue-50 text-blue-800"}`}>{findingLabels[item.findingStatus]}</span>
    </div>
    <dl className="mt-3 grid gap-2 text-xs sm:grid-cols-3">
      <div><dt className="text-[#64748B]">Catalogue</dt><dd className="font-semibold">{item.catalogObjectPresent === null ? "Non applicable" : item.catalogObjectPresent ? "Objet présent" : "Objet absent"}</dd></div>
      <div><dt className="text-[#64748B]">Octets physiques</dt><dd className="font-semibold">Non vérifiés{item.physicalVerificationRequired ? " — contrôle requis" : ""}</dd></div>
      <div><dt className="text-[#64748B]">État d’action</dt><dd className="font-semibold">{item.actionBlocked ? "Action bloquée" : "Aucune réparation engagée"}</dd></div>
    </dl>
    {item.storageGuardRequired && <p className="mt-3 rounded-lg bg-amber-50 p-2 text-xs font-semibold text-amber-900">La future garde Storage est requise avant toute mutation associée.</p>}
    {item.operationId && <Link className="mt-3 inline-flex text-xs font-semibold text-[#2563EB]" href={`/administration/reparations-documentaires?operation=${item.operationId}`}>Ouvrir le diagnostic de l’opération</Link>}
    {physicallyVerifiable && query.finding !== item.inventoryKey && <Link className="mt-3 inline-flex text-xs font-semibold text-[#2563EB]" href={getAdministrativeDocumentInventoryHref({ ...query, finding: item.inventoryKey })}>Sélectionner pour vérification physique</Link>}
    {physicallyVerifiable && query.finding === item.inventoryKey && <AdministrativeDocumentPhysicalVerification inventoryKey={item.inventoryKey} observations={observations} />}
  </article>;
}
