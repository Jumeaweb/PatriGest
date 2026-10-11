import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { Building2, CalendarDays, History, MapPin, NotebookText, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { PropertyActions } from "@/domains/assets-liabilities/components/property-manager";
import { propertyEntryModeLabels, propertyEventTypeLabels, propertyTypeLabels, safePropertyText } from "@/domains/assets-liabilities/property-format";
import { getProperty } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Bien immobilier" };
export const dynamic = "force-dynamic";
const formatDate = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
const formatCurrency = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);

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
    <section className="mt-6"><div className="flex items-center gap-2"><History className="text-[#2563EB]" size={18} /><h2 className="text-lg font-bold">Historique du bien</h2></div><div className="mt-3 space-y-2">{property.events.length ? property.events.map((event) => { const description = safePropertyText(event.description); const reference = safePropertyText(event.document_reference); return <article key={event.id} className="rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3"><div className="flex flex-wrap items-center justify-between gap-2"><div><p className="text-sm font-bold">{propertyEventTypeLabels[event.event_type]}</p><p className="text-xs text-[#64748B]">{formatDate(event.event_date)}</p></div>{event.amount !== null && <p className="text-sm font-bold">{formatCurrency(event.amount)}</p>}</div>{description && <p className="mt-2 whitespace-pre-wrap text-sm text-[#475569]">{description}</p>}{reference && <p className="mt-2 text-xs text-[#64748B]">Référence documentaire : {reference}</p>}</article>; }) : <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B]">Aucun événement enregistré.</p>}</div></section>
  </PrivateShell>;
}

function Info({ icon: Icon, title, children }: { icon: typeof Building2; title: string; children: React.ReactNode }) { return <article className="self-start rounded-xl border border-[#E2E8F0] bg-white p-3.5"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon size={14} /></span><h2 className="text-sm font-bold">{title}</h2></div><div className="mt-2.5">{children}</div></article>; }
function Data({ label, value }: { label: string; value: string }) { return <div className="mb-2 last:mb-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-[#94A3B8]">{label}</p><p className="mt-0.5 text-sm text-[#334155]">{value}</p></div>; }
