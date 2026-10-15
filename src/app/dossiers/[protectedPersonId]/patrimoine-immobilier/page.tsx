import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Archive } from "lucide-react";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { PropertyManager } from "@/domains/assets-liabilities/components/property-manager";
import { PatrimonyAbsenceConfirmationControl } from "@/domains/assets-liabilities/components/patrimony-absence-confirmation";
import { PatrimonyNavigation } from "@/domains/assets-liabilities/components/patrimony-navigation";
import { getPropertyCompleteness } from "@/domains/assets-liabilities/completeness";
import { getArchivedProperties, getPatrimonyAbsenceConfirmations, getProperties } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Patrimoine immobilier" };
export const dynamic = "force-dynamic";

export default async function Page({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [items, archivedItems, absenceConfirmations] = await Promise.all([
    getProperties(protectedPersonId),
    getArchivedProperties(protectedPersonId),
    getPatrimonyAbsenceConfirmations(protectedPersonId),
  ]);
  const completeness = getPropertyCompleteness(items);
  const hasActiveProperty = items.some((item) => item.status === "active");
  const canManage = person.accessRole !== "read_only";
  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "properties", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}` }, { label: "Patrimoine immobilier" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <div className="mt-1 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div><h1 className="text-2xl font-bold">Patrimoine immobilier</h1><p className="mt-1 text-sm text-[#64748B]">Biens permanents et événements significatifs associés.</p></div>
      <Link className="button button-secondary gap-1.5 self-start" href={`/dossiers/${protectedPersonId}/patrimoine-immobilier/archives`}><Archive aria-hidden="true" size={15} />Biens archivés{archivedItems.length ? ` (${archivedItems.length})` : ""}</Link>
    </div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="properties" />
    <PatrimonyNavigation protectedPersonId={protectedPersonId} current="properties" />
    <p className="mt-4 text-xs text-[#64748B]">{completeness.state === "none" ? "Aucun bien renseigné." : completeness.incompleteIds.length ? `${completeness.incompleteIds.length} bien(s) avec informations essentielles à compléter.` : "Informations essentielles renseignées."}</p>
    {!hasActiveProperty && <PatrimonyAbsenceConfirmationControl personId={protectedPersonId} category="real_estate" confirmation={absenceConfirmations.realEstate} canManage={canManage} />}
    <PropertyManager personId={protectedPersonId} items={items} canManage={canManage} />
  </PrivateShell>;
}
