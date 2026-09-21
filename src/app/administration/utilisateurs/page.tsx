import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { DeleteUserButton } from "@/domains/administration/components/delete-user-button";
import { ResendActivationEmailButton } from "@/domains/administration/components/registration-review-actions";
import { getPlatformUsers } from "@/domains/administration/services/administration-service";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const users = await getPlatformUsers();
  return <PrivateShell current="administration-users">
    <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Comptes utilisateurs" }]} />
    <header><p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p><h1>Comptes utilisateurs</h1></header>
    <div className="mt-5 overflow-x-auto rounded-xl border border-[#E2E8F0] bg-white"><table className="w-full min-w-[840px] text-left text-sm"><thead className="bg-slate-50 text-[#64748B]"><tr><th className="p-3">Nom</th><th className="p-3">Email</th><th className="p-3">Inscription</th><th className="p-3">Statut</th><th className="p-3">Dossiers possédés</th><th className="p-3 text-right">Action</th></tr></thead><tbody>{users.map((user) => { const name = `${user.firstName} ${user.lastName}`.trim(); return <tr className="border-t border-[#E2E8F0]" key={user.id}><td className="p-3 font-semibold">{name}</td><td className="p-3">{user.email}</td><td className="p-3">{new Date(user.createdAt).toLocaleDateString("fr-FR")}</td><td className="p-3 text-xs font-semibold">{user.authorizationStatus === "active" ? "Actif" : user.authorizationStatus === "pending" ? "En attente" : user.authorizationStatus === "rejected" ? "Refusé" : "—"}</td><td className="p-3">{user.ownedDossiers}</td><td className="p-3 text-right"><div className="flex flex-col items-end">{user.canResendActivationEmail && <ResendActivationEmailButton userId={user.id} />}{user.canDelete ? <DeleteUserButton userId={user.id} name={name} email={user.email} /> : <span className="text-xs text-[#94A3B8]">Non supprimable</span>}</div></td></tr>; })}</tbody></table></div>
    <p className="mt-3 text-xs text-[#64748B]">La suppression reste bloquée tant qu’un utilisateur possède un dossier, un accès ou toute autre relation métier conservée.</p>
  </PrivateShell>;
}
