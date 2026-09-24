import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { parseAdministrationUsersPage } from "@/domains/administration/administration-user-pagination";
import { AdministrationUserPagination } from "@/domains/administration/components/administration-user-pagination";
import { DeleteUserButton } from "@/domains/administration/components/delete-user-button";
import { ResendActivationEmailButton } from "@/domains/administration/components/registration-review-actions";
import { getPlatformUsers, type PlatformUserSummary } from "@/domains/administration/services/administration-service";

export const dynamic = "force-dynamic";

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ page?: string | string[] }> }) {
  const query = await searchParams;
  const result = await getPlatformUsers(parseAdministrationUsersPage(query.page));
  return (
    <PrivateShell current="administration-users">
      <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Comptes utilisateurs" }]} />
      <header>
        <p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p>
        <h1>Comptes utilisateurs</h1>
        <p className="mt-1 text-sm text-[#64748B]">{result.total} compte{result.total === 1 ? "" : "s"} Auth — modes et accès métier chargés par page.</p>
      </header>
      <AdministrationUserPagination page={result.page} totalPages={result.totalPages} />
      <div className="mt-4 hidden rounded-xl border border-[#E2E8F0] bg-white xl:block">
        <table className="w-full table-fixed text-left text-sm">
          <colgroup><col className="w-[23%]" /><col className="w-[18%]" /><col className="w-[11%]" /><col className="w-[23%]" /><col className="w-[25%]" /></colgroup>
          <thead className="bg-slate-50 text-[#64748B]"><tr><th className="p-3">Utilisateur</th><th className="p-3">Statut / type</th><th className="p-3 text-center">Dossiers possédés</th><th className="p-3">Accès partagés</th><th className="p-3 text-right">Actions</th></tr></thead>
          <tbody>{result.users.map((user) => <UserRow key={user.id} user={user} />)}</tbody>
        </table>
      </div>
      <div className="mt-4 grid gap-3 xl:hidden">{result.users.map((user) => <UserCard key={user.id} user={user} />)}</div>
      {result.users.length === 0 && <p className="mt-4 rounded-xl border border-dashed border-[#CBD5E1] p-4 text-sm text-[#64748B]">Aucun compte utilisateur sur cette page.</p>}
      <AdministrationUserPagination page={result.page} totalPages={result.totalPages} />
      <p className="mt-3 text-xs leading-5 text-[#64748B]">La suppression est vérifiée une nouvelle fois côté serveur. Les dossiers, accès, invitations actives, relations administratives ou données métier associées peuvent la bloquer.</p>
    </PrivateShell>
  );
}

function UserRow({ user }: { user: PlatformUserSummary }) {
  const name = `${user.firstName} ${user.lastName}`.trim() || "Nom non renseigné";
  return (
    <tr className="border-t border-[#E2E8F0] align-top">
      <td className="p-3"><UserIdentity user={user} name={name} /></td>
      <td className="p-3"><StatusAndMode user={user} /></td>
      <td className="p-3 text-center font-semibold">{user.ownedDossiers}</td>
      <td className="p-3"><SharedAccessList accesses={user.sharedAccesses} /></td>
      <td className="p-3"><UserActions user={user} name={name} align="end" /></td>
    </tr>
  );
}

function UserCard({ user }: { user: PlatformUserSummary }) {
  const name = `${user.firstName} ${user.lastName}`.trim() || "Nom non renseigné";
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_4px_14px_rgba(15,23,42,0.03)]">
    <UserIdentity user={user} name={name} />
    <dl className="mt-4 grid gap-4 sm:grid-cols-2">
      <div><dt className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Statut / type</dt><dd className="mt-2"><StatusAndMode user={user} /></dd></div>
      <div><dt className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Dossiers possédés</dt><dd className="mt-2 font-semibold">{user.ownedDossiers}</dd></div>
      <div className="sm:col-span-2"><dt className="text-xs font-bold uppercase tracking-wide text-[#64748B]">Accès partagés</dt><dd className="mt-2"><SharedAccessList accesses={user.sharedAccesses} /></dd></div>
    </dl>
    <div className="mt-4 border-t border-[#E2E8F0] pt-4"><p className="mb-2 text-xs font-bold uppercase tracking-wide text-[#64748B]">Actions</p><UserActions user={user} name={name} /></div>
  </article>;
}

function UserIdentity({ user, name }: { user: PlatformUserSummary; name: string }) {
  return <div><p className="font-semibold">{name}</p><p className="mt-0.5 break-all text-xs text-[#64748B]">{user.email || "Adresse e-mail indisponible"}</p><p className="mt-1 text-xs text-[#64748B]">Inscription : {new Date(user.createdAt).toLocaleDateString("fr-FR")}</p>{!user.emailConfirmed && <p className="mt-1 text-xs font-semibold text-amber-700">E-mail non confirmé</p>}</div>;
}

function StatusAndMode({ user }: { user: PlatformUserSummary }) {
  return <div className="flex flex-col items-start gap-1.5"><AuthorizationStatusBadge status={user.authorizationStatus} /><AccountModeBadge mode={user.accountMode} isPlatformAdmin={user.deletionBlockReasons.includes("Administrateur PatriGest")} /></div>;
}

function AuthorizationStatusBadge({ status }: { status: PlatformUserSummary["authorizationStatus"] }) {
  const presentation = status === "active"
    ? { label: "Actif", classes: "bg-green-50 text-green-800" }
    : status === "pending"
      ? { label: "En attente", classes: "bg-amber-50 text-amber-800" }
      : status === "rejected"
        ? { label: "Refusé", classes: "bg-red-50 text-red-800" }
        : { label: "Sans autorisation", classes: "bg-slate-100 text-slate-700" };
  return <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-bold ${presentation.classes}`}>{presentation.label}</span>;
}

function AccountModeBadge({ mode, isPlatformAdmin }: { mode: PlatformUserSummary["accountMode"]; isPlatformAdmin: boolean }) {
  const presentation = isPlatformAdmin
    ? { label: "Administration de la plateforme", classes: "bg-[#214660] text-white" }
    : mode === "autonomous"
      ? { label: "Compte autonome", classes: "bg-[#DDECEA] text-[#214660] ring-1 ring-inset ring-[#377E84]/30" }
      : mode === "collaborator"
        ? { label: "Compte collaborateur", classes: "bg-[#F4EAD5] text-[#6F531E] ring-1 ring-inset ring-[#BC9955]/40" }
        : { label: "Mode non défini", classes: "bg-slate-100 text-slate-700" };
  return <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-bold ${presentation.classes}`}>{presentation.label}</span>;
}

function SharedAccessList({ accesses }: { accesses: PlatformUserSummary["sharedAccesses"] }) {
  if (!accesses.length) return <span className="text-xs text-[#64748B]">Aucun</span>;
  return <ul className="space-y-2 text-xs">{accesses.map((access) => <li key={access.protectedPersonId}><span className="block font-semibold">{access.protectedPersonName}</span><span className="mt-0.5 inline-flex rounded-full bg-slate-100 px-2 py-0.5 font-semibold text-[#475569]">{access.role === "manager" ? "Gestionnaire" : "Lecture seule"}</span></li>)}</ul>;
}

function UserActions({ user, name, align = "start" }: { user: PlatformUserSummary; name: string; align?: "start" | "end" }) {
  return <div className={`flex flex-col gap-2 ${align === "end" ? "items-end" : "items-start"}`}>{user.canResendActivationEmail && <ResendActivationEmailButton userId={user.id} email={user.email} />}{user.canDelete ? <DeleteUserButton userId={user.id} name={name} email={user.email} /> : <div className="max-w-64 text-left"><p className="text-xs font-bold text-[#64748B]">Suppression indisponible</p><ul className="mt-1 list-disc pl-4 text-xs leading-5 text-[#64748B]">{user.deletionBlockReasons.map((reason) => <li key={reason}>{reason}</li>)}</ul></div>}</div>;
}
