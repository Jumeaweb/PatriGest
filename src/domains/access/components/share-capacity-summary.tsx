import type {
  ProtectedPersonShareCapacity,
  ProtectedPersonShareCounter,
} from "@/domains/access/share-limits";

export function ShareCapacitySummary({ capacity }: { capacity: ProtectedPersonShareCapacity }) {
  return (
    <section
      aria-labelledby="share-capacity-title"
      className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4"
    >
      <h2 id="share-capacity-title" className="font-bold">Capacité de partage</h2>
      <p className="mt-1 text-xs text-[#64748B]">
        Les accès actifs et les invitations en attente occupent chacun une place.
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <ShareCounter label="Gestionnaires partagés" counter={capacity.manager} />
        <ShareCounter label="Collaborateurs en lecture seule" counter={capacity.read_only} />
      </div>
    </section>
  );
}

function ShareCounter({ label, counter }: { label: string; counter: ProtectedPersonShareCounter }) {
  const availability = counter.exceededBy > 0
    ? `Limite dépassée de ${places(counter.exceededBy)}`
    : counter.remainingCount === 0
      ? "Aucune place supplémentaire disponible"
      : `${places(counter.remainingCount)} disponible${counter.remainingCount > 1 ? "s" : ""}`;
  const alert = counter.remainingCount === 0;

  return (
    <article className={`rounded-lg border p-3 ${alert ? "border-amber-200 bg-amber-50/70" : "border-[#E2E8F0] bg-[#F8FAFC]"}`}>
      <h3 className="text-sm font-bold text-[#334155]">{label}</h3>
      <p className="mt-1 text-xl font-bold text-[#214660]">
        <span className="sr-only">Places utilisées : </span>{counter.usedCount} / {counter.limit}
      </p>
      <p className={`mt-1 text-xs font-semibold ${alert ? "text-amber-900" : "text-[#64748B]"}`}>
        {availability}
      </p>
      <p className="mt-2 text-[11px] text-[#64748B]">
        {counter.activeAccessCount} accès actif{counter.activeAccessCount > 1 ? "s" : ""} · {counter.pendingInvitationCount} invitation{counter.pendingInvitationCount > 1 ? "s" : ""} en attente
      </p>
    </article>
  );
}

function places(value: number) {
  return `${value} place${value > 1 ? "s" : ""}`;
}
