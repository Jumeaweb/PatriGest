import Link from "next/link";
import { FolderOpen, Plus, UserRound } from "lucide-react";
import type { ProtectedPersonListItem } from "../services/protected-person-service";

export function ProtectedPersonList({ persons, canCreate }: { persons: ProtectedPersonListItem[]; canCreate: boolean }) {
  return <>
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div><p className="text-xs font-bold uppercase tracking-[0.12em] text-[#2563EB]">Personnes protégées</p><h1 className="mt-1 font-bold tracking-tight">Dossiers</h1><p className="mt-1 text-sm text-[#64748B]">Retrouvez et gérez les dossiers qui vous sont confiés.</p></div>
      {canCreate && <Link href="/dossiers/nouveau" className="button button-primary gap-2"><Plus aria-hidden="true" size={16} />Nouveau dossier</Link>}
    </div>
    {persons.length === 0 ? <section className="mt-6 rounded-xl border border-dashed border-[#CBD5E1] bg-white p-6 text-center">
      <div className="mx-auto flex size-10 items-center justify-center rounded-xl bg-blue-50 text-[#2563EB]"><FolderOpen aria-hidden="true" size={20} /></div>
      <h2 className="mt-3 text-lg font-bold">Aucun dossier accessible</h2>
      <p className="mx-auto mt-1 max-w-md text-sm leading-6 text-[#64748B]">{canCreate ? "Créez votre premier dossier ou attendez qu’un accès vous soit accordé." : "Les dossiers que vous pouvez consulter apparaîtront ici lorsqu’un accès vous sera accordé."}</p>
      {canCreate && <Link href="/dossiers/nouveau" className="button button-primary mt-4 gap-2"><Plus aria-hidden="true" size={16} />Créer mon premier dossier</Link>}
    </section> : <div className="mt-5 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">{persons.map((person) => <Link key={person.id} href={`/dossiers/${person.id}/comptes`} className="focus-ring group self-start rounded-xl border border-[#E2E8F0] bg-white p-3.5 shadow-[0_6px_18px_rgba(15,23,42,0.035)] transition hover:border-blue-200">
      <div className="flex items-start justify-between gap-3"><div className="flex size-8 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><UserRound aria-hidden="true" size={16} /></div><span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${person.status === "active" ? "bg-green-50 text-[#16A34A]" : "bg-slate-100 text-[#64748B]"}`}>{person.status === "active" ? "Actif" : "Archivé"}</span></div>
      <h2 className="mt-2.5 text-sm font-bold group-hover:text-[#2563EB]">{person.first_name} {person.last_name}</h2>
      <p className="mt-0.5 text-xs text-[#64748B]">{person.city || "Commune non renseignée"}</p>
      <p className="mt-2 text-[11px] font-semibold text-[#64748B]">{person.accessRole === "owner" ? "Propriétaire" : person.accessRole === "manager" ? "Gestionnaire" : "Lecture seule"}</p>
    </Link>)}</div>}
  </>;
}
