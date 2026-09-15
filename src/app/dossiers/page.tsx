import type { Metadata } from "next";
import { PrivateShell } from "@/components/layout/private-shell";
import { ProtectedPersonList } from "@/domains/protected-persons/components/protected-person-list";
import { getProtectedPersons } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Dossiers" };
export const dynamic = "force-dynamic";

export default async function ProtectedPersonsPage() {
  const persons = await getProtectedPersons();
  return <PrivateShell current="dossiers"><ProtectedPersonList persons={persons} /></PrivateShell>;
}
