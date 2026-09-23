import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { PrivateShell } from "@/components/layout/private-shell";
import { getPrivateAccessContext } from "@/domains/administration/services/private-access-context";
import { ProtectedPersonForm } from "@/domains/protected-persons/components/protected-person-form";

export const metadata: Metadata = { title: "Nouveau dossier" };
export const dynamic = "force-dynamic";

export default async function NewProtectedPersonPage() {
  const { canCreateDossier } = await getPrivateAccessContext();
  if (!canCreateDossier) redirect("/dossiers");
  return <PrivateShell current="dossiers">
    <div className="max-w-4xl"><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">Dossiers</p><h1 className="mt-1 text-2xl font-bold tracking-tight sm:text-[28px]">Nouveau dossier</h1><p className="mt-1 text-sm text-[#64748B]">Renseignez les informations essentielles de la personne protégée.</p>
      <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_6px_18px_rgba(15,23,42,0.035)] sm:p-5"><ProtectedPersonForm /></section>
    </div>
  </PrivateShell>;
}
