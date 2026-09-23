import type { Metadata } from "next";
import { PrivateShell } from "@/components/layout/private-shell";
import { getPrivateAccessContext } from "@/domains/administration/services/private-access-context";
import { ProtectedPersonList } from "@/domains/protected-persons/components/protected-person-list";
import { getProtectedPersons } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Dossiers" };
export const dynamic = "force-dynamic";

export default async function ProtectedPersonsPage({ searchParams }: { searchParams: Promise<{ deleted?: string | string[] }> }) {
  const deletionConfirmed = (await searchParams).deleted === "1";
  const [persons, { canCreateDossier }] = await Promise.all([getProtectedPersons(), getPrivateAccessContext()]);
  return <PrivateShell current="dossiers">{deletionConfirmed && <p role="status" aria-live="polite" className="mb-4 rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-semibold text-green-800">Le dossier a bien été supprimé.</p>}<ProtectedPersonList persons={persons} canCreate={canCreateDossier} /></PrivateShell>;
}
