import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { AccessTabs } from "@/domains/access/components/access-tabs";
import { CollaboratorInviteForm } from "@/domains/access/components/collaborator-invite-form";
import { CollaboratorRemoveButton } from "@/domains/access/components/collaborator-remove-button";
import { CollaboratorRoleButton } from "@/domains/access/components/collaborator-role-button";
import { InvitationActions } from "@/domains/access/components/invitation-actions";
import { InvitationHistoryPagination } from "@/domains/access/components/invitation-history-pagination";
import { parseInvitationHistoryPage, type AccessPageQuery } from "@/domains/access/access-pagination";
import { dossierInvitationStatusLabels, type DossierInvitationStatus } from "@/domains/access/invitation-status";
import { getDossierAccess } from "@/domains/access/services";

export const dynamic = "force-dynamic";

const dateTime = (value: string) => new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
const first = (value: string | string[] | undefined) => Array.isArray(value) ? value[0] : value;

export default async function DossierAccessPage({
  params,
  searchParams,
}: {
  params: Promise<{ protectedPersonId: string }>;
  searchParams: Promise<AccessPageQuery>;
}) {
  const [{ protectedPersonId }, query] = await Promise.all([params, searchParams]);
  const view = first(query.vue) === "collaborateurs" ? "collaborators" as const : "invite" as const;
  const requestedHistoryPage = parseInvitationHistoryPage(query.historiquePage);
  const data = await getDossierAccess(protectedPersonId, requestedHistoryPage);
  const name = `${data.person.first_name} ${data.person.last_name}`;
  const owner = data.person.accessRole === "owner";
  const pathname = `/dossiers/${protectedPersonId}/acces`;

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name, current: "access", accessRole: data.person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: name, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Partage du dossier" }]} />
    <h1>Partage du dossier</h1>
    <AccessTabs pathname={pathname} values={query} current={view} />

    {view === "invite" ? <>
      <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="font-bold">Propriétaire</h2>
        <p className="mt-1 text-sm font-semibold text-[#214660]">{data.owner.name || "Nom non renseigné"}</p>
        <p className="text-sm text-[#64748B]">{data.owner.email}</p>
      </section>

      <section className="mt-4 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="font-bold">Inviter un collaborateur</h2>
        <CollaboratorInviteForm protectedPersonId={protectedPersonId} isOwner={owner} />
      </section>

      <section className="mt-4 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="font-bold">Invitations en attente</h2>
        <div className="mt-3 space-y-3">
          {data.pendingInvitations.length === 0 && <p className="text-sm text-[#64748B]">Aucune invitation en attente.</p>}
          {data.pendingInvitations.map((invitation) => <InvitationRow key={invitation.id} protectedPersonId={protectedPersonId} invitation={invitation} />)}
        </div>
      </section>

      <section className="mt-4 rounded-xl border border-[#E2E8F0] bg-white p-4">
        <h2 className="font-bold">Historique des invitations</h2>
        <p className="mt-1 text-sm text-[#64748B]">Invitations acceptées, annulées ou expirées.</p>
        <InvitationHistoryPagination pathname={pathname} values={query} page={data.history.page} totalPages={data.history.totalPages} />
        <div className="mt-3 space-y-3">
          {data.invitationHistory.length === 0 && <p className="text-sm text-[#64748B]">Aucune invitation dans l’historique.</p>}
          {data.invitationHistory.map((invitation) => <InvitationRow key={invitation.id} protectedPersonId={protectedPersonId} invitation={invitation} />)}
        </div>
        <InvitationHistoryPagination pathname={pathname} values={query} page={data.history.page} totalPages={data.history.totalPages} />
      </section>
    </> : <section className="mt-5 rounded-xl border border-[#E2E8F0] bg-white p-4">
      <h2 className="font-bold">Collaborateurs</h2>
      <div className="mt-3 space-y-3">
        {data.collaborators.length === 0 && <p className="text-sm text-[#64748B]">Aucun collaborateur.</p>}
        {data.collaborators.map((entry) => {
          const collaboratorName = entry.name || entry.email || "Ce collaborateur";
          return <article key={`${entry.id}-${entry.role}`} className="flex flex-col justify-between gap-3 border-t border-[#E2E8F0] pt-3 sm:flex-row sm:items-center">
            <div className="min-w-0">
              <p className="font-semibold">{entry.name || entry.email}</p>
              {entry.name && <p className="truncate text-xs text-[#64748B]">{entry.email}</p>}
              <span className="mt-2 inline-flex rounded-full bg-brand-navigation/30 px-2 py-1 text-xs font-semibold text-brand-foreground">
                {entry.role === "manager" ? "Gestionnaire" : "Lecture seule"}
              </span>
            </div>
            {owner && <div className="flex flex-wrap gap-2">
              <CollaboratorRoleButton protectedPersonId={protectedPersonId} accessId={entry.id} collaboratorName={collaboratorName} role={entry.role} />
              <CollaboratorRemoveButton protectedPersonId={protectedPersonId} accessId={entry.id} collaboratorName={collaboratorName} />
            </div>}
          </article>;
        })}
      </div>
    </section>}
  </PrivateShell>;
}

type InvitationRowData = {
  id: string;
  email: string;
  role: "manager" | "read_only";
  expires_at: string;
  created_at: string;
  status: DossierInvitationStatus;
  canManage: boolean;
};

function InvitationRow({ protectedPersonId, invitation }: { protectedPersonId: string; invitation: InvitationRowData }) {
  const statusClass = invitation.status === "pending" ? "bg-blue-50 text-blue-700" : invitation.status === "expired" ? "bg-amber-50 text-amber-800" : invitation.status === "accepted" ? "bg-green-50 text-green-700" : "bg-slate-100 text-slate-600";
  return <article className="grid gap-3 border-t border-[#E2E8F0] pt-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
    <div className="min-w-0">
      <div className="flex flex-wrap items-center gap-2">
        <p className="truncate text-sm font-semibold">{invitation.email}</p>
        <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${statusClass}`}>{dossierInvitationStatusLabels[invitation.status]}</span>
      </div>
      <p className="mt-1 text-xs text-[#64748B]">{invitation.role === "manager" ? "Gestionnaire" : "Lecture seule"} · Créée le {dateTime(invitation.created_at)} · Expire le {dateTime(invitation.expires_at)}</p>
    </div>
    <InvitationActions protectedPersonId={protectedPersonId} invitationId={invitation.id} email={invitation.email} status={invitation.status} canManage={invitation.canManage} />
  </article>;
}
