import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { RegenerateAccountInvitation, RequestReviewActions } from "@/domains/administration/components/request-review-actions";
import { RegistrationReviewActions } from "@/domains/administration/components/registration-review-actions";
import { getAccountRequests, getPendingApplicationRegistrations } from "@/domains/administration/services/administration-service";

export const dynamic = "force-dynamic";

export default async function RequestsPage() {
  const [requests, registrations] = await Promise.all([getAccountRequests(), getPendingApplicationRegistrations()]);
  return <PrivateShell current="administration-requests">
    <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Inscriptions à valider" }]} />
    <header><p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p><h1>Inscriptions à valider</h1></header>
    <section className="mt-5"><h2 className="text-base font-bold">Inscriptions confirmées en attente</h2><p className="mt-1 text-xs text-[#64748B]">Comptes dont l’adresse e-mail est confirmée et qui attendent une décision administrative.</p><div className="mt-3 space-y-3">{registrations.length ? registrations.map((registration) => <article key={registration.userId} className="rounded-xl border border-[#E2E8F0] bg-white p-4"><div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start"><div><p className="font-bold">{registration.firstName} {registration.lastName}</p><p className="text-sm text-[#64748B]">{registration.email}</p><p className="mt-1 text-xs text-[#64748B]">Inscription : {new Date(registration.createdAt).toLocaleDateString("fr-FR")} · E-mail confirmé : {new Date(registration.emailConfirmedAt).toLocaleDateString("fr-FR")}</p></div><RegistrationReviewActions userId={registration.userId} email={registration.email} /></div></article>) : <p className="rounded-xl border border-dashed border-[#CBD5E1] p-4 text-sm text-[#64748B]">Aucune inscription à valider.</p>}</div></section>
    <section className="mt-7"><h2 className="text-base font-bold">Historique de l’ancien système</h2><p className="mt-1 text-xs text-[#64748B]">Anciennes demandes d’accès conservées à titre transitoire.</p><div className="mt-3 space-y-3">{requests.map((request) => {
      const canRegenerate = request.status === "approved" && request.invitation_used_at === null;
      return <article key={request.id} className="rounded-xl border border-[#E2E8F0] bg-white p-4">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
          <div className="min-w-0"><p className="font-bold">{request.first_name} {request.last_name}</p><p className="text-sm text-[#64748B]">{request.email} · {new Date(request.created_at).toLocaleDateString("fr-FR")}</p>{request.message && <p className="mt-2 text-sm">{request.message}</p>}{request.status !== "pending" && <span className={`mt-2 inline-block rounded-full px-2 py-1 text-xs font-semibold ${request.status === "approved" ? "bg-green-50 text-green-800" : "bg-red-50 text-red-800"}`}>{request.status === "approved" ? "Approuvée" : "Refusée"}</span>}{request.status === "approved" && !canRegenerate && request.invitation_expires_at && <p className="mt-1 text-[11px] text-[#64748B]">Expiration : {new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" }).format(new Date(request.invitation_expires_at))}</p>}{request.invitation_used_at && <p className="mt-1 text-[11px] font-semibold text-green-700">Invitation utilisée</p>}</div>
          <div className="shrink-0">{request.status === "pending" ? <RequestReviewActions id={request.id} email={request.email} /> : canRegenerate ? <RegenerateAccountInvitation id={request.id} email={request.email} expiresAt={request.invitation_expires_at} /> : null}</div>
        </div>
      </article>;
    })}</div></section>
  </PrivateShell>;
}
