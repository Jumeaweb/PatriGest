import type { Metadata } from "next";
import { PrivateShell } from "@/components/layout/private-shell";
import { getPrivateAccessContext } from "@/domains/administration/services/private-access-context";
import { ProtectedPersonList } from "@/domains/protected-persons/components/protected-person-list";
import { getProtectedPersons } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Dossiers" };
export const dynamic = "force-dynamic";

export default async function ProtectedPersonsPage() {
  const [persons, { isPlatformAdmin }] = await Promise.all([getProtectedPersons(), getPrivateAccessContext()]);
  return <PrivateShell current="dossiers"><ProtectedPersonList persons={persons} canCreate={!isPlatformAdmin} /></PrivateShell>;
}
