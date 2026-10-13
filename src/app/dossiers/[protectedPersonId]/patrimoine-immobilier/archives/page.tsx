import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Archive, Building2 } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { propertyEventTypeLabels, propertyTypeLabels, safePropertyText } from "@/domains/assets-liabilities/property-format";
import { getArchivedProperties } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Biens immobiliers archivés" };
export const dynamic = "force-dynamic";
const formatDate = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "Europe/Paris" }).format(new Date(value));
const formatCurrency = (value: number) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(value);

export default async function ArchivedPropertiesPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const [person, items] = await Promise.all([getProtectedPerson(protectedPersonId), getArchivedProperties(protectedPersonId)]);
  if (!person) notFound();
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "properties", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}` }, { label: "Patrimoine immobilier", href: `/dossiers/${protectedPersonId}/patrimoine-immobilier` }, { label: "Biens archivés" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <div className="mt-1 flex items-center gap-2"><Archive className="text-[#2563EB]" size={22} /><h1 className="text-2xl font-bold">Biens archivés</h1></div>
    <p className="mt-1 text-sm text-[#64748B]">Ces biens sont conservés à titre historique et ne sont pas inclus dans le patrimoine courant.</p>
    <DossierNavigation protectedPersonId={protectedPersonId} current="properties" />
    <div className="mt-5 grid items-start gap-3 md:grid-cols-2 xl:grid-cols-3">
      {items.map((item) => {
        const lastEvent = item.events[0];
        return <Link key={item.id} href={`/dossiers/${protectedPersonId}/patrimoine-immobilier/${item.id}`} className="rounded-xl border border-amber-200 bg-white p-3.5 transition hover:border-amber-300 hover:bg-amber-50/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#2563EB]">
          <div className="flex items-start justify-between gap-2"><div className="flex gap-2"><span className="flex size-8 items-center justify-center rounded-lg bg-amber-50 text-amber-700"><Building2 size={16} /></span><div><h2 className="text-sm font-bold">{safePropertyText(item.designation) ?? "Bien immobilier"}</h2><p className="text-xs text-[#64748B]">{safePropertyText(item.city) ?? propertyTypeLabels[item.property_type]}</p></div></div><span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${item.status === "disposed" ? "bg-slate-200 text-slate-700" : "bg-blue-50 text-blue-700"}`}>{item.status === "disposed" ? "Cédé" : "Actif"}</span></div>
          {item.estimated_value !== null && <p className="mt-3 text-lg font-bold">{formatCurrency(item.estimated_value)}</p>}
          {item.archived_at && <p className="mt-2 text-xs font-semibold text-amber-800">Archivé le {formatDate(item.archived_at)}</p>}
          {lastEvent && <p className="mt-1 text-xs text-[#64748B]">Dernier événement : {propertyEventTypeLabels[lastEvent.event_type]}</p>}
        </Link>;
      })}
      {!items.length && <p className="rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center text-sm text-[#64748B] md:col-span-2 xl:col-span-3">Aucun bien immobilier archivé.</p>}
    </div>
  </PrivateShell>;
}
