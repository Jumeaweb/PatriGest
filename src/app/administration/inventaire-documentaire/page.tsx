import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { AdministrativeDocumentInventory } from "@/domains/administration/components/administrative-document-inventory";
import { parseAdministrativeDocumentInventoryQuery } from "@/domains/administration/administrative-document-inventory";
import {
  getAdministrativeDocumentInventory,
} from "@/domains/administration/services/administrative-document-inventory-service";
import { getAdministrativeDocumentPhysicalObservations } from "@/domains/administration/services/administrative-document-physical-verification-service";

export const dynamic = "force-dynamic";

export default async function AdministrativeDocumentInventoryPage({
  searchParams,
}: {
  searchParams: Promise<{
    cursor?: string | string[];
    category?: string | string[];
    anomaly?: string | string[];
    limit?: string | string[];
    finding?: string | string[];
  }>;
}) {
  const query = parseAdministrativeDocumentInventoryQuery(await searchParams);
  const inventory = await getAdministrativeDocumentInventory(query);
  const selectedObservations = query.finding
    ? await getAdministrativeDocumentPhysicalObservations(query.finding)
    : [];
  return <PrivateShell current="administration">
    <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Inventaire documentaire" }]} />
    <header><p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p><h1>Inventaire documentaire</h1><p className="mt-1 text-sm text-[#64748B]">Diagnostic en lecture seule du catalogue documentaire historique.</p></header>
    <div className="mt-4 rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm leading-6 text-blue-900"><strong>Aucune réparation n’est effectuée.</strong> La présence au catalogue ne prouve pas la disponibilité des octets. La vérification physique est strictement limitée à une lecture serveur de l’objet sélectionné.</div>
    <AdministrativeDocumentInventory items={inventory.items} nextCursor={inventory.nextCursor} query={query} selectedObservations={selectedObservations} />
  </PrivateShell>;
}
