import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { parseAdministrationUsersPage } from "@/domains/administration/administration-user-pagination";
import { AdministrationUserPagination } from "@/domains/administration/components/administration-user-pagination";
import { AdministrationUsersTable } from "@/domains/administration/components/administration-users-table";
import { getPlatformUsers } from "@/domains/administration/services/administration-service";

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
      <AdministrationUsersTable users={result.users} />
      {result.users.length === 0 && <p className="mt-4 rounded-xl border border-dashed border-[#CBD5E1] p-4 text-sm text-[#64748B]">Aucun compte utilisateur sur cette page.</p>}
      <AdministrationUserPagination page={result.page} totalPages={result.totalPages} />
      <p className="mt-3 text-xs leading-5 text-[#64748B]">La suppression est vérifiée une nouvelle fois côté serveur. Les dossiers, accès, invitations actives, relations administratives ou données métier associées peuvent la bloquer.</p>
    </PrivateShell>
  );
}
