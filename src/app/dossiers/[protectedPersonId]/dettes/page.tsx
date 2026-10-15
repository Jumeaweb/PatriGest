import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { z } from "zod";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DebtManager } from "@/domains/assets-liabilities/components/debt-manager";
import { PatrimonyAbsenceConfirmationControl } from "@/domains/assets-liabilities/components/patrimony-absence-confirmation";
import { PatrimonyNavigation } from "@/domains/assets-liabilities/components/patrimony-navigation";
import { getDebtCompleteness } from "@/domains/assets-liabilities/completeness";
import { getDebts, getPatrimonyAbsenceConfirmations } from "@/domains/assets-liabilities/services";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Dettes et emprunts" };
export const dynamic = "force-dynamic";

export default async function Page({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [items, absenceConfirmations] = await Promise.all([
    getDebts(protectedPersonId),
    getPatrimonyAbsenceConfirmations(protectedPersonId),
  ]);
  const completeness = getDebtCompleteness(items);
  const hasActiveDebt = items.some((item) => item.status === "active");
  const canManage = person.accessRole !== "read_only";

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "debts", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}` }, { label: "Dettes et emprunts" }]} />
    <p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">{person.first_name} {person.last_name}</p>
    <h1 className="mt-1 text-2xl font-bold">Dettes et emprunts</h1>
    <p className="mt-1 text-sm text-[#64748B]">Dettes permanentes et situations datées du solde restant.</p>
    <DossierNavigation protectedPersonId={protectedPersonId} current="debts" />
    <PatrimonyNavigation protectedPersonId={protectedPersonId} current="debts" />
    <p className="mt-4 text-xs text-[#64748B]">{completeness.state === "none" ? "Aucune dette renseignée." : completeness.missingRecentBalanceIds.length ? `${completeness.missingRecentBalanceIds.length} dette(s) active(s) sans situation récente.` : `${completeness.activeCount} dette(s) active(s), situations à jour.`}</p>
    {!hasActiveDebt && <PatrimonyAbsenceConfirmationControl personId={protectedPersonId} category="active_debt" confirmation={absenceConfirmations.activeDebt} canManage={canManage} />}
    <DebtManager personId={protectedPersonId} items={items} canManage={canManage} />
  </PrivateShell>;
}
