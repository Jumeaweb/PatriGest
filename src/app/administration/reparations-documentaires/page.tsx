import { randomUUID } from "node:crypto";
import Link from "next/link";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { AdministrativeDocumentRepairPanel } from "@/domains/administration/components/administrative-document-repair-panel";
import { getAdministrativeDocumentRepairPageData } from "@/domains/administration/services/administrative-document-repair-service";

export const dynamic = "force-dynamic";

export default async function AdministrativeDocumentRepairsPage({
  searchParams,
}: {
  searchParams: Promise<{ operation?: string | string[] }>;
}) {
  const query = await searchParams;
  const operationId = typeof query.operation === "string" ? query.operation : undefined;
  const data = await getAdministrativeDocumentRepairPageData(operationId);
  return <PrivateShell current="administration">
    <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Réparations documentaires" }]} />
    <header>
      <p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p>
      <h1>Réparations documentaires</h1>
      <p className="mt-1 text-sm text-[#64748B]">Diagnostic, décision explicite et progression auditée des seules opérations en intervention requise.</p>
    </header>
    {!data.enabled ? <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-5"><h2 className="text-base font-bold">Fonction désactivée</h2><p className="mt-2 text-sm leading-6 text-[#64748B]">Aucune réparation ne peut être consultée ou exécutée tant que l’indicateur serveur dédié n’est pas activé.</p></section> : <div className="mt-5 grid gap-5 lg:grid-cols-[minmax(16rem,0.7fr)_minmax(0,1.5fr)]">
      <aside className="rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="text-sm font-bold">Opérations à examiner</h2>
        <div className="mt-3 grid gap-2">{data.operations.map((operation) => <Link key={operation.id} href={`/administration/reparations-documentaires?operation=${operation.id}`} className={`focus-ring rounded-lg border p-3 text-sm ${operation.id === operationId ? "border-blue-300 bg-blue-50" : "border-[#E2E8F0] hover:bg-slate-50"}`}><span className="block font-semibold">{operation.workflow.replaceAll("_", " ")}</span><span className="mt-1 block text-xs text-[#64748B]">{operation.safe_error_code ?? "Intervention requise"}</span></Link>)}</div>
        {!data.operations.length && <p className="mt-3 text-sm text-[#64748B]">Aucune opération ne requiert d’intervention.</p>}
      </aside>
      <section>
        {data.diagnostic ? <><div className="rounded-xl border border-[#E2E8F0] bg-white p-4"><h2 className="text-base font-bold">Diagnostic SQL</h2><dl className="mt-3 grid gap-3 text-sm sm:grid-cols-2"><div><dt className="text-xs text-[#64748B]">Workflow</dt><dd className="font-semibold">{data.diagnostic.workflow.replaceAll("_", " ")}</dd></div><div><dt className="text-xs text-[#64748B]">Erreur sûre</dt><dd className="font-semibold">{data.diagnostic.safeErrorCode ?? "Non renseignée"}</dd></div><div><dt className="text-xs text-[#64748B]">Cibles</dt><dd className="font-semibold">{data.diagnostic.targets.length}</dd></div><div><dt className="text-xs text-[#64748B]">Révision</dt><dd className="font-semibold">{data.diagnostic.revision}</dd></div></dl>{data.diagnostic.ownedByAnotherAdministrator && <p role="alert" className="mt-3 rounded-lg bg-amber-50 p-3 text-sm font-semibold text-amber-900">Une tentative active appartient à un autre administrateur.</p>}</div>{data.diagnostic.repairable && !data.diagnostic.ownedByAnotherAdministrator && <AdministrativeDocumentRepairPanel operationId={data.diagnostic.operationId} attemptId={data.diagnostic.activeAttemptId ?? randomUUID()} targets={data.diagnostic.targets} blocked={data.diagnostic.blocked} canRenew={data.diagnostic.activeAttemptId !== null} />}</> : <div className="rounded-xl border border-dashed border-[#CBD5E1] p-6 text-center text-sm text-[#64748B]">Sélectionnez une opération pour consulter son diagnostic.</div>}
      </section>
    </div>}
  </PrivateShell>;
}
