import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { Building2, CalendarDays, History, MapPin, NotebookText, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { PropertyActions, PropertyEventCancellationButton, PropertyEventEditButton, PropertySalePriceCorrectionButton } from "@/domains/assets-liabilities/components/property-manager";
import { propertyEntryModeLabels, propertyEventTypeLabels, propertyTypeLabels, safePropertyText } from "@/domains/assets-liabilities/property-format";
import { getProperty } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import type { Json } from "@/types/database";

export const metadata: Metadata = { title: "Bien immobilier" };
export const dynamic = "force-dynamic";
const formatDate = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
const formatDateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeStyle: "short", timeZone: "Europe/Paris" }).format(new Date(value));
const formatCurrency = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);
const auditFields = [
  ["event_type", "Type"],
  ["event_date", "Date"],
  ["description", "Description"],
  ["amount", "Valeur / montant"],
  ["document_reference", "Référence documentaire"],
  ["property_entry_date", "Date d’entrée du bien"],
  ["property_entry_mode", "Mode d’entrée du bien"],
  ["property_disposal_date", "Date de cession du bien"],
] as const;
const asAuditRecord = (value: Json): Record<string, Json | undefined> => value && typeof value === "object" && !Array.isArray(value) ? value : {};
function formatAuditValue(key: string, value: Json | undefined) {
  if (value === null || value === undefined || value === "") return "Non renseigné";
  if (key === "event_type" && typeof value === "string" && value in propertyEventTypeLabels) return propertyEventTypeLabels[value as keyof typeof propertyEventTypeLabels];
  if (key === "property_entry_mode" && typeof value === "string" && value in propertyEntryModeLabels) return propertyEntryModeLabels[value as keyof typeof propertyEntryModeLabels];
  if ((key.endsWith("date") || key === "event_date") && typeof value === "string") return formatDate(value);
  if (key === "amount" && typeof value === "number") return formatCurrency(value);
  return typeof value === "string" || typeof value === "number" || typeof value === "boolean" ? String(value) : "Valeur structurée";
}
function EventCorrectionHistory({ changes }: { changes: Array<{ id: string; old_values: Json; new_values: Json; reason: string; changed_by_name: string; changed_at: string }> }) {
  if (!changes.length) return null;
  return <div className="mt-3 border-t border-[#E2E8F0] pt-3"><p className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Corrections de l’événement</p><ol className="mt-2 space-y-2">{changes.map((change) => { const oldValues=asAuditRecord(change.old_values);const newValues=asAuditRecord(change.new_values);const differences=auditFields.filter(([key])=>JSON.stringify(oldValues[key])!==JSON.stringify(newValues[key]));return <li key={change.id} className="rounded-lg bg-[#F8FAFC] px-3 py-2 text-xs text-[#475569]"><p className="font-bold text-[#334155]">{formatDateTime(change.changed_at)} · Par {change.changed_by_name}</p><ul className="mt-1 space-y-1">{differences.map(([key,label])=><li key={key}><span className="font-semibold">{label} :</span> {formatAuditValue(key,oldValues[key])} → {formatAuditValue(key,newValues[key])}</li>)}</ul><p className="mt-1 whitespace-pre-wrap">Motif : {change.reason}</p></li>;})}</ol></div>;
}

export default async function PropertyPage({ params }: { params: Promise<{ protectedPersonId: string; propertyId: string }> }) {
  const { protectedPersonId, propertyId } = await params;
  if (![protectedPersonId, propertyId].every((id) => z.uuid().safeParse(id).success)) notFound();
  const [person, property] = await Promise.all([getProtectedPerson(protectedPersonId), getProperty(protectedPersonId, propertyId)]);
  if (!person || !property) notFound();
  const title = safePropertyText(property.designation) ?? "Bien immobilier";
  const address = [property.address_line1, property.address_line2, [property.postal_code, property.city].filter(Boolean).join(" "), property.country].map((part) => safePropertyText(part)).filter((part): part is string => Boolean(part));
  const notes = safePropertyText(property.notes);
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "properties", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}` }, { label: "Patrimoine immobilier", href: `/dossiers/${protectedPersonId}/patrimoine-immobilier` }, { label: title }]} />
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p><h1 className="mt-1 text-2xl font-bold">{title}</h1><p className="mt-1 text-sm text-[#64748B]">{propertyTypeLabels[property.property_type]}</p></div>{person.accessRole !== "read_only" && <PropertyActions personId={protectedPersonId} item={property} />}</div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="properties" />
    <section className="mt-5 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <Info icon={Building2} title="Statut"><p className="text-sm font-bold">{property.status === "active" ? "Actif" : "Cédé"}</p>{property.disposal_date && <p className="mt-1 text-xs text-[#64748B]">Cédé le {formatDate(property.disposal_date)}</p>}</Info>
      {address.length > 0 && <Info icon={MapPin} title="Adresse"><address className="text-sm not-italic text-[#475569]">{address.map((line) => <div key={line}>{line}</div>)}</address></Info>}
      {(property.entry_date || property.entry_mode) && <Info icon={CalendarDays} title="Entrée dans le patrimoine">{property.entry_date && <Data label="Date" value={formatDate(property.entry_date)} />}{property.entry_mode && <Data label="Mode" value={propertyEntryModeLabels[property.entry_mode]} />}</Info>}
      {property.estimated_value !== null && <Info icon={WalletCards} title={property.status === "disposed" ? "Dernière estimation connue" : "Estimation retenue dans la synthèse actuelle"}><p className="text-xl font-bold">{formatCurrency(property.estimated_value)}</p>{property.valuation_date && <p className="mt-1 text-xs text-[#64748B]">Au {formatDate(property.valuation_date)}</p>}</Info>}
      {notes && <Info icon={NotebookText} title="Notes"><p className="whitespace-pre-wrap text-sm text-[#475569]">{notes}</p></Info>}
    </section>
    <section className="mt-6"><div className="flex items-center gap-2"><History className="text-[#2563EB]" size={18} /><h2 className="text-lg font-bold">Historique du bien</h2></div><div className="mt-3 space-y-2">{property.events.length ? property.events.map((event) => { const description = safePropertyText(event.description); const reference = safePropertyText(event.document_reference); const cancellation=event.changes.find((change)=>change.change_type==="cancellation"); return <article key={event.id} className={`rounded-xl border bg-white px-3.5 py-3 ${event.cancelled_at?"border-amber-200":"border-[#E2E8F0]"}`}><div className="flex flex-wrap items-center justify-between gap-2"><div className="flex flex-wrap items-center gap-2"><div><p className="text-sm font-bold">{propertyEventTypeLabels[event.event_type]}</p><p className="text-xs text-[#64748B]">{formatDate(event.event_date)}</p></div>{event.cancelled_at&&<span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">Annulée</span>}</div><div className="flex flex-wrap items-center justify-end gap-2">{event.amount !== null && <p className="text-sm font-bold">{formatCurrency(event.amount)}</p>}{person.accessRole !== "read_only" && <PropertyEventEditButton personId={protectedPersonId} propertyId={property.id} propertyName={title} event={event} />}{person.accessRole !== "read_only" && event.event_type === "sale" && <PropertySalePriceCorrectionButton personId={protectedPersonId} propertyId={property.id} propertyName={title} event={event} />}{person.accessRole !== "read_only" && <PropertyEventCancellationButton personId={protectedPersonId} propertyId={property.id} propertyName={title} event={event} />}</div></div>{event.cancelled_at&&<div className="mt-2 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-900"><p className="font-bold">Annulée le {formatDateTime(event.cancelled_at)}</p><p className="mt-1 whitespace-pre-wrap">Motif : {event.cancellation_reason}</p>{cancellation&&<p className="mt-1">Par {cancellation.changed_by_name}</p>}</div>}{description && <p className="mt-2 whitespace-pre-wrap text-sm text-[#475569]">{description}</p>}{reference && <p className="mt-2 text-xs text-[#64748B]">Référence documentaire : {reference}</p>}<EventCorrectionHistory changes={event.changes}/>{event.priceCorrections.length > 0 && <div className="mt-3 border-t border-[#E2E8F0] pt-3"><p className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Corrections du prix</p><ol className="mt-2 space-y-2">{event.priceCorrections.map((correction) => <li key={correction.id} className="rounded-lg bg-[#F8FAFC] px-3 py-2 text-xs text-[#475569]"><p><span className="font-bold text-[#334155]">{formatCurrency(correction.old_price)} → {formatCurrency(correction.new_price)}</span> · {formatDateTime(correction.corrected_at)}</p><p className="mt-1 whitespace-pre-wrap">Motif : {correction.reason}</p><p className="mt-1 text-[#64748B]">Par {correction.corrected_by_name}</p></li>)}</ol></div>}</article>; }) : <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun événement enregistré.</p>}</div></section>
  </PrivateShell>;
}

function Info({ icon: Icon, title, children }: { icon: typeof Building2; title: string; children: React.ReactNode }) { return <article className="self-start rounded-xl border border-[#E2E8F0] bg-white p-3.5"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon size={14} /></span><h2 className="text-sm font-bold">{title}</h2></div><div className="mt-2.5">{children}</div></article>; }
function Data({ label, value }: { label: string; value: string }) { return <div className="mb-2 last:mb-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-[#94A3B8]">{label}</p><p className="mt-0.5 text-sm text-[#334155]">{value}</p></div>; }
