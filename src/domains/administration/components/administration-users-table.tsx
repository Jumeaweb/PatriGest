"use client";

import type {
  AccountEntitlementAccessSource,
  AccountSubscriptionStatus,
  AdministrativeBillingPeriod,
  AdministrativeDossierCapacityKey,
  AdministrativeEntitlementBlockCode,
  SubscriptionDossierCapacityKey,
  SubscriptionPlanKey,
} from "@/types/database";
import type { PlatformUserSummary } from "../services/administration-service";
import { DeleteUserButton } from "./delete-user-button";
import { ResendActivationEmailButton } from "./registration-review-actions";

const planLabels: Record<SubscriptionPlanKey, string> = { essential: "Essentiel", comfort: "Confort", premium: "Premium" };
const billingLabels: Record<AdministrativeBillingPeriod, string> = { monthly: "Mensuel", annual: "Annuel" };
const accessSourceLabels: Record<AccountEntitlementAccessSource, string> = {
  none: "Aucun droit actif", commercial: "Abonnement commercial", administrative: "Attribution administrative",
  trial: "Essai gratuit", legacy: "Accès historique", development: "Accès de développement", shared_access: "Accès partagés uniquement",
};
const subscriptionStatusLabels: Record<AccountSubscriptionStatus, string> = {
  development: "Développement", active: "Actif", past_due: "Paiement en attente", canceled: "Résilié en fin de période", ended: "Terminé",
};
const blockCodeLabels: Record<AdministrativeEntitlementBlockCode, string> = {
  platform_administrator: "Compte administrateur non modifiable",
  authorization_inactive: "Autorisation utilisateur inactive",
  account_not_autonomous: "Compte collaborateur non éligible",
  purge_in_progress: "Suppression de compte en cours",
  commercial_subscription_active: "Abonnement commercial à préserver",
  active_override_must_be_revoked: "Dérogation active à traiter d’abord",
  entitlement_base_required: "Base commerciale ou administrative requise",
};

export function AdministrationUsersTable({ users }: { users: PlatformUserSummary[] }) {
  return <>
    <div className="mt-4 rounded-xl border border-blue-200 bg-blue-50/60 px-4 py-3 text-sm leading-6 text-blue-950">
      <p className="font-semibold">Droits des comptes en lecture seule</p>
      <p>Les abonnements commerciaux, attributions administratives, dérogations et droits effectifs sont affichés séparément. Les essais restent informatifs. Aucune modification de droits n’est disponible à cette étape.</p>
    </div>
    <div className="mt-4 hidden overflow-x-auto rounded-xl border border-[#E2E8F0] bg-white pb-1 [scrollbar-color:#94A3B8_#E2E8F0] [scrollbar-width:auto] lg:block" tabIndex={0} aria-label="Tableau des comptes utilisateurs, défilement horizontal disponible">
      <table className="min-w-[1770px] table-fixed text-left text-xs">
        <colgroup>
          <col className="w-[230px]" /><col className="w-[185px]" /><col className="w-[145px]" />
          <col className="w-[190px]" /><col className="w-[205px]" /><col className="w-[205px]" /><col className="w-[205px]" />
          <col className="w-[115px]" /><col className="w-[100px]" /><col className="w-[115px]" /><col className="w-[230px]" />
        </colgroup>
        <thead className="bg-slate-50 text-[#475569]"><tr className="border-b border-[#CBD5E1]">
          <th scope="col" className="sticky left-0 z-30 bg-slate-50 px-3 py-2 font-bold shadow-[4px_0_6px_-5px_rgba(15,23,42,0.55)]">Utilisateur</th>
          <th scope="col" className="px-3 py-2 font-bold">Statut</th><th scope="col" className="px-3 py-2 font-bold">Essai gratuit</th>
          <th scope="col" className="border-l border-[#CBD5E1] px-3 py-2 font-bold">Abonnement commercial</th>
          <th scope="col" className="border-l border-[#CBD5E1] px-3 py-2 font-bold">Attribution administrative</th>
          <th scope="col" className="border-l border-[#CBD5E1] px-3 py-2 font-bold">Dérogation active</th>
          <th scope="col" className="border-l border-[#CBD5E1] px-3 py-2 font-bold">Droits effectifs</th>
          <th scope="col" className="border-l border-[#CBD5E1] px-3 py-2 font-bold">Dossiers</th>
          <th scope="col" className="px-3 py-2 text-center font-bold">Accès partagés</th><th scope="col" className="px-3 py-2 font-bold">Résiliation</th>
          <th scope="col" className="px-3 py-2 font-bold">Actions</th>
        </tr></thead>
        <tbody>{users.map((user) => <DesktopUserRow key={user.id} user={user} />)}</tbody>
      </table>
    </div>
    <div className="mt-4 grid gap-4 lg:hidden">{users.map((user) => <MobileUserCard key={user.id} user={user} />)}</div>
  </>;
}

function DesktopUserRow({ user }: { user: PlatformUserSummary }) {
  return <tr className="border-t border-[#E2E8F0] align-top">
    <td className="sticky left-0 z-10 bg-white px-3 py-2 shadow-[4px_0_6px_-5px_rgba(15,23,42,0.55)]"><UserIdentity user={user} /></td>
    <td className="px-3 py-2"><UserStatus user={user} /></td><td className="px-3 py-2"><TrialSummary user={user} /></td>
    <td className="border-l border-[#CBD5E1] px-3 py-2"><CommercialSubscriptionSummary user={user} /></td>
    <td className="border-l border-[#CBD5E1] px-3 py-2"><AdministrativeAssignmentSummary user={user} /></td>
    <td className="border-l border-[#CBD5E1] px-3 py-2"><AdministrativeOverrideSummary user={user} /></td>
    <td className="border-l border-[#CBD5E1] px-3 py-2"><EffectiveEntitlementsSummary user={user} /></td>
    <td className="border-l border-[#CBD5E1] px-3 py-2"><DossierSummary user={user} /></td>
    <td className="px-3 py-2 text-center"><InformativeCheckbox label={`Accès partagés existants pour ${getUserName(user)}`} checked={user.sharedAccesses.length > 0} /></td>
    <td className="px-3 py-2">{user.subscription?.canceledAt ? formatDate(user.subscription.canceledAt) : "—"}</td>
    <td className="px-3 py-2"><UserRowActions user={user} /></td>
  </tr>;
}

function MobileUserCard({ user }: { user: PlatformUserSummary }) {
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_4px_14px_rgba(15,23,42,0.03)]">
    <UserIdentity user={user} /><div className="mt-3"><UserStatus user={user} /></div>
    <dl className="mt-4 grid gap-4 sm:grid-cols-2">
      <SummaryBlock title="Essai gratuit"><TrialSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Abonnement commercial"><CommercialSubscriptionSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Attribution administrative"><AdministrativeAssignmentSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Dérogation active"><AdministrativeOverrideSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Droits effectifs"><EffectiveEntitlementsSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Dossiers"><DossierSummary user={user} /></SummaryBlock>
      <SummaryBlock title="Accès partagés"><span>{user.sharedAccesses.length > 0 ? `Oui — ${user.sharedAccesses.length}` : "Aucun"}</span></SummaryBlock>
      <SummaryBlock title="Date de résiliation"><span>{user.subscription?.canceledAt ? formatDate(user.subscription.canceledAt) : "—"}</span></SummaryBlock>
    </dl>
    <div className="mt-4 border-t border-[#E2E8F0] pt-4"><UserRowActions user={user} /></div>
  </article>;
}

function SummaryBlock({ title, children }: { title: string; children: React.ReactNode }) {
  return <div><dt className="text-xs font-bold uppercase tracking-wide text-[#64748B]">{title}</dt><dd className="mt-1 text-sm">{children}</dd></div>;
}
function UserIdentity({ user }: { user: PlatformUserSummary }) {
  return <><p className="font-bold">{getUserName(user)}</p><p className="mt-0.5 break-all text-[#475569]">{user.email || "Adresse e-mail indisponible"}</p><p className="mt-0.5 text-[#64748B]">Inscription : {formatDate(user.createdAt)}</p></>;
}
function TrialSummary({ user }: { user: PlatformUserSummary }) {
  const active = user.accountAccessKind === "trial_active";
  if (!user.trial) return <MutedText>Aucun essai enregistré</MutedText>;
  const label = user.accountAccessKind === "trial_expired" ? "Expiré" : active ? "En cours" : user.accountAccessKind === "legacy_access" ? "Accès historique" : user.accountAccessKind === "trial_pending" ? "Non démarré" : user.accountAccessKind === "commercial_subscription" ? "Terminé — abonnement actif" : "Aucun essai actif";
  return <div className="space-y-1"><p className="flex items-center gap-2 font-semibold"><InformativeCheckbox label={`Essai gratuit en cours pour ${getUserName(user)}`} checked={active} />{label}</p>{user.trial.endsAt && <p className="text-[#64748B]">Fin : {formatDate(user.trial.endsAt)}</p>}</div>;
}
function CommercialSubscriptionSummary({ user }: { user: PlatformUserSummary }) {
  const subscription = user.subscription;
  if (!subscription?.planKey) return <MutedText>Aucun abonnement commercial</MutedText>;
  return <div className="space-y-1"><p className="font-bold">{planLabels[subscription.planKey]}</p><p>{formatCommercialCapacity(subscription.dossierCapacityKey, subscription.customActiveDossierLimit)}</p><p className="text-[#64748B]">{subscriptionStatusLabels[subscription.status]}</p></div>;
}
function AdministrativeAssignmentSummary({ user }: { user: PlatformUserSummary }) {
  const assignment = user.entitlements?.administrativeAssignment;
  if (!assignment) return <MutedText>Aucune attribution</MutedText>;
  return <div className="space-y-1"><p className="font-bold">{planLabels[assignment.planKey]}</p><p>{billingLabels[assignment.billingPeriod]} · {formatAdministrativeCapacity(assignment.dossierCapacityKey)}</p><p className="text-[#64748B]">Attribution active</p></div>;
}
function AdministrativeOverrideSummary({ user }: { user: PlatformUserSummary }) {
  const entitlementOverride = user.entitlements?.administrativeOverride;
  if (!entitlementOverride) return <MutedText>Aucune dérogation</MutedText>;
  return <div className="space-y-1"><p className="font-bold">Base {entitlementOverride.baseSource === "commercial" ? "commerciale" : "administrative"}</p>{entitlementOverride.featurePlanKey && <p>Fonctions : {planLabels[entitlementOverride.featurePlanKey]}</p>}{entitlementOverride.dossierCapacityKey && <p>Capacité : {formatAdministrativeCapacity(entitlementOverride.dossierCapacityKey)}</p>}</div>;
}
function EffectiveEntitlementsSummary({ user }: { user: PlatformUserSummary }) {
  if (user.isPlatformAdmin) return <div className="space-y-1"><p className="font-bold">Administration de la plateforme</p><p className="text-[#64748B]">Hors formule utilisateur</p></div>;
  const entitlements = user.entitlements;
  if (!entitlements) return <MutedText>Droits indisponibles</MutedText>;
  return <div className="space-y-1"><p className="font-bold">{accessSourceLabels[entitlements.accessSource]}</p><p>{entitlements.effectivePlanKey ? planLabels[entitlements.effectivePlanKey] : "Aucune formule"}</p><p>{entitlements.effectiveActiveDossierLimit === null ? "Capacité non attribuée" : `${entitlements.effectiveActiveDossierLimit} dossiers actifs`}</p></div>;
}
function DossierSummary({ user }: { user: PlatformUserSummary }) {
  return <p className="font-semibold">{user.ownedDossiers} <span className="font-normal text-[#64748B]">({user.activeOwnedDossiers} actif{user.activeOwnedDossiers === 1 ? "" : "s"})</span></p>;
}
function UserRowActions({ user }: { user: PlatformUserSummary }) {
  const blockCode = user.entitlements?.planAssignmentBlockCode ?? user.entitlements?.entitlementOverrideBlockCode;
  return <div className="flex flex-col items-start gap-2">
    <p className="max-w-64 text-xs font-semibold text-[#64748B]">Modification des droits non activée</p>
    {blockCode && <p className="max-w-64 text-xs text-amber-800">{blockCodeLabels[blockCode]}</p>}
    {user.canResendActivationEmail && <ResendActivationEmailButton userId={user.id} email={user.email} />}
    {user.canDelete ? <DeleteUserButton userId={user.id} name={getUserName(user)} email={user.email} /> : <div className="max-w-64 text-left"><p className="text-xs font-bold text-[#64748B]">Suppression indisponible</p><ul className="mt-1 list-disc pl-4 text-xs leading-5 text-[#64748B]">{user.deletionBlockReasons.map((reason) => <li key={reason}>{reason}</li>)}</ul></div>}
  </div>;
}
function UserStatus({ user }: { user: PlatformUserSummary }) {
  const authorizationLabel = user.authorizationStatus === "active" ? "Actif" : user.authorizationStatus === "pending" ? "En attente" : user.authorizationStatus === "rejected" ? "Refusé" : "Sans autorisation";
  const accountModeLabel = user.isPlatformAdmin ? "Administration de la plateforme" : user.accountMode === "autonomous" ? "Compte autonome" : user.accountMode === "collaborator" ? "Compte collaborateur" : "Mode non défini";
  return <div className="flex flex-col items-start gap-1"><span className="rounded-full bg-slate-100 px-2 py-1 font-bold">{authorizationLabel}</span><span className="leading-5 text-[#64748B]">{accountModeLabel}</span>{!user.emailConfirmed && <span className="font-semibold text-amber-700">E-mail non confirmé</span>}</div>;
}
function InformativeCheckbox({ label, checked }: { label: string; checked: boolean }) {
  return <input type="checkbox" className="size-4 shrink-0 accent-[#2563EB]" aria-label={label} checked={checked} disabled readOnly />;
}
function MutedText({ children }: { children: React.ReactNode }) { return <span className="text-[#64748B]">{children}</span>; }
function formatAdministrativeCapacity(capacity: AdministrativeDossierCapacityKey) {
  if (capacity === "included") return "2 dossiers";
  if (capacity === "five") return "5 dossiers";
  return "10 dossiers";
}
function formatCommercialCapacity(capacity: SubscriptionDossierCapacityKey | null, customLimit: number | null) {
  if (capacity === "included") return "2 dossiers";
  if (capacity === "five") return "5 dossiers";
  if (capacity === "ten") return "10 dossiers";
  if (capacity === "custom" && customLimit !== null) return `${customLimit} dossiers`;
  return "Capacité non renseignée";
}
function getUserName(user: PlatformUserSummary) { return `${user.firstName} ${user.lastName}`.trim() || "Nom non renseigné"; }
function formatDate(value: string) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeZone: "Europe/Paris" }).format(new Date(value)); }
