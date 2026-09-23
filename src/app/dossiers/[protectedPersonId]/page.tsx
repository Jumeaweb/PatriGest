import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { Building2, CalendarDays, FileText, Landmark, MapPin, Scale, Trash2, UserRound, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getDebts, getProperties } from "@/domains/assets-liabilities/services";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { formatCurrency, getCurrentAccountValue, getCurrentPatrimonyValue } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DeleteProtectedPerson } from "@/domains/protected-persons/components/delete-protected-person";
import { DossierInformationNavigation, type DossierInformationView } from "@/domains/protected-persons/components/dossier-information-navigation";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getDossierAddressStates, getDossierAssetActionLabel, getDossierDebtState, getDossierPropertyState } from "@/domains/protected-persons/dossier-information-states";
import { EditProtectedPersonButton, EditProtectionMeasureButton } from "@/domains/protected-persons/components/regulatory-edit-dialogs";
import { getProtectedPersonRegulatoryCompleteness, getProtectionMeasureRegulatoryCompleteness } from "@/domains/protected-persons/regulatory-helpers";
import { getMeasureLabel } from "@/domains/protected-persons/schemas/protection-measure-schema";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import type { ManagementReportStatus } from "@/types/database";

export const metadata: Metadata = { title: "Fiche dossier" };
export const dynamic = "force-dynamic";

const reportStatusLabels: Record<ManagementReportStatus, string> = {
  draft: "En préparation",
  ready: "Prêt",
  generated: "Projet généré",
  finalized: "Finalisé",
  transmitted: "Transmis",
  approved: "Approuvé",
  difficulty: "Difficulté signalée",
};

export default async function ProtectedPersonDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ protectedPersonId: string }>;
  searchParams: Promise<{ vue?: string | string[] }>;
}) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [accounts, properties, debts] = await Promise.all([
    getFinancialAccounts(protectedPersonId),
    getProperties(protectedPersonId),
    getDebts(protectedPersonId),
  ]);

  const rawView = (await searchParams).vue;
  const requestedView = Array.isArray(rawView) ? rawView[0] : rawView;
  const canManage = person.accessRole !== "read_only";
  const canDelete = person.accessRole === "owner";
  const currentView: DossierInformationView = requestedView === "patrimoine"
    ? "assets"
    : requestedView === "gestion"
      ? "management"
      : requestedView === "suppression" && canDelete
        ? "deletion"
        : "person";

  const activeMeasure = person.protectionMeasures.find((measure) => measure.active) ?? null;
  const openPeriod = person.managementPeriods.find((period) => period.status === "open") ?? null;
  const currentReport = openPeriod
    ? person.managementReports.find((report) => report.management_period_id === openPeriod.id) ?? null
    : null;
  const { domicile, residence } = getDossierAddressStates(person);
  const currentPatrimony = getCurrentPatrimonyValue(accounts);
  const personCompleteness = getProtectedPersonRegulatoryCompleteness(person);
  const measureCompleteness = getProtectionMeasureRegulatoryCompleteness(activeMeasure);
  const propertyState = getDossierPropertyState(properties);
  const debtState = getDossierDebtState(debts);
  const activeAccounts = accounts.filter((account) => account.status === "active");
  const closedAccountCount = accounts.filter((account) => account.status === "closed").length;

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "overview", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/tableau-de-bord` }, { label: "Informations du dossier" }]} />
    <header>
      <p className="text-sm font-bold uppercase tracking-[0.14em] text-[#2563EB]">Fiche dossier</p>
      <h1 className="mt-1 text-3xl font-bold tracking-tight">{person.first_name} {person.last_name}</h1>
      <p className="mt-1 text-sm text-[#64748B]">Dossier {person.status === "active" ? "actif" : "archivé"}</p>
    </header>
    <DossierNavigation protectedPersonId={protectedPersonId} current="overview" />
    <DossierInformationNavigation protectedPersonId={protectedPersonId} current={currentView} canDelete={canDelete} />

    {currentView === "person" && <div className="mt-6 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <InfoCard icon={UserRound} title="Identité" action={canManage ? <EditProtectedPersonButton person={person} /> : undefined}>
        <CompletenessBadge complete={personCompleteness.complete} count={personCompleteness.missingFields.length} />
        {personCompleteness.missingFields.length > 0 && <p className="mb-3 text-xs text-[#64748B]">À compléter : {personCompleteness.missingFields.map((field) => field.label).join(" · ")}</p>}
        <DataLine label="Nom d’usage" value={person.last_name} />
        <DataLine label="Prénom(s)" value={person.first_name} />
        {person.birth_name && <DataLine label="Nom de naissance" value={person.birth_name} />}
        {person.birth_date && <DataLine label="Date de naissance" value={formatDate(person.birth_date)} />}
        {person.birth_place && <DataLine label="Lieu de naissance" value={person.birth_place} />}
        {person.phone && <DataLine label="Téléphone" value={person.phone} />}
        {person.email && <DataLine label="Email" value={person.email} />}
      </InfoCard>
      <InfoCard icon={MapPin} title="Domicile et résidence" action={canManage ? <EditProtectedPersonButton person={person} /> : undefined}>
        <DataLine label="Domicile" value={domicile} />
        <DataLine label="Résidence" value={residence} />
      </InfoCard>
      <div id="mesure-protection" className="scroll-mt-28">
        <InfoCard icon={Scale} title="Mesure de protection" action={canManage ? <EditProtectionMeasureButton protectedPersonId={person.id} measure={activeMeasure} /> : undefined}>
          <CompletenessBadge complete={measureCompleteness.complete} count={measureCompleteness.missingFields.length} />
          {activeMeasure ? <>
            <DataLine label="Type" value={getMeasureLabel(activeMeasure.measure_type)} />
            {activeMeasure.start_date && <DataLine label="Ouverture / renouvellement" value={formatDate(activeMeasure.start_date)} />}
            {activeMeasure.case_reference && <DataLine label="Numéro RG" value={activeMeasure.case_reference} />}
            {activeMeasure.court_cabinet && <DataLine label="Cabinet" value={activeMeasure.court_cabinet} />}
            {activeMeasure.court_name && <DataLine label="Juridiction" value={[activeMeasure.court_name, activeMeasure.court_city].filter(Boolean).join(" — ")} />}
            {(activeMeasure.representative_first_name || activeMeasure.representative_last_name) && <DataLine label="Personne en charge" value={[activeMeasure.representative_first_name, activeMeasure.representative_last_name].filter(Boolean).join(" ")} />}
            {activeMeasure.representative_appointment_date && <DataLine label="Date de nomination" value={formatDate(activeMeasure.representative_appointment_date)} />}
            {activeMeasure.representative_phone && <DataLine label="Téléphone" value={activeMeasure.representative_phone} />}
            {activeMeasure.representative_email && <DataLine label="Email" value={activeMeasure.representative_email} />}
          </> : <p className="text-sm text-[#64748B]">{person.protectionMeasures.length ? "Aucune mesure active" : "Non renseigné"}</p>}
        </InfoCard>
      </div>
    </div>}

    {currentView === "assets" && <div className="mt-6 grid items-start gap-3 lg:grid-cols-2">
      <InfoCard icon={WalletCards} title="Patrimoine actuel">
        <p className="text-2xl font-bold">{accounts.length ? formatCurrency(currentPatrimony) : "Non renseigné"}</p>
        <p className="mt-1 text-xs text-[#64748B]">Valeur actuelle calculée à partir des comptes actifs.</p>
      </InfoCard>
      <InfoCard icon={WalletCards} title="Comptes">
        <p className="text-sm font-semibold">{activeAccounts.length} actif{activeAccounts.length > 1 ? "s" : ""} · {closedAccountCount} clôturé{closedAccountCount > 1 ? "s" : ""}</p>
        {activeAccounts.length ? <div className="mt-3 divide-y divide-[#E2E8F0] border-y border-[#E2E8F0]">
          {activeAccounts.map((account) => <div key={account.id} className="flex items-center justify-between gap-3 py-2">
            <span className="min-w-0 truncate text-sm font-semibold">{account.account_name}</span>
            <span className="shrink-0 text-sm font-bold">{formatCurrency(getCurrentAccountValue(account, account.valuations, account.transactions).value)}</span>
          </div>)}
        </div> : <p className="mt-2 text-sm text-[#64748B]">Aucun compte actif</p>}
        <Link href={`/dossiers/${protectedPersonId}/comptes`} className="auth-link mt-3 inline-block text-xs">Voir les comptes →</Link>
      </InfoCard>
      <InfoCard icon={Building2} title="Patrimoine immobilier">
        <p className="text-sm font-semibold">{propertyState.label}</p>
        {properties.length > 0 && <>
          <p className="mt-1 text-xs text-[#64748B]">{propertyState.knownValue === null ? "Valeur non renseignée" : `Valeurs connues : ${formatCurrency(propertyState.knownValue)}`}</p>
          {propertyState.missingValues > 0 && propertyState.knownValue !== null && <p className="mt-1 text-xs text-[#64748B]">{propertyState.missingValues} bien(s) sans valeur renseignée</p>}
        </>}
        <Link href={`/dossiers/${protectedPersonId}/patrimoine-immobilier`} className="auth-link mt-3 inline-block text-xs">{getDossierAssetActionLabel("properties", properties.length, canManage)} →</Link>
      </InfoCard>
      <InfoCard icon={Landmark} title="Dettes et emprunts">
        <p className="text-sm font-semibold">{debtState.label}</p>
        {debtState.knownBalance !== null && <p className="mt-1 text-xs text-[#64748B]">Soldes connus : {formatCurrency(debtState.knownBalance)}</p>}
        {debtState.missingBalances > 0 && <p className="mt-1 text-xs text-[#64748B]">{debtState.missingBalances} solde(s) restant(s) non renseigné(s)</p>}
        <Link href={`/dossiers/${protectedPersonId}/dettes`} className="auth-link mt-3 inline-block text-xs">{getDossierAssetActionLabel("debts", debts.length, canManage)} →</Link>
      </InfoCard>
    </div>}

    {currentView === "management" && <div className="mt-6 grid items-start gap-3 md:grid-cols-2">
      <InfoCard icon={CalendarDays} title="Exercice de gestion">
        {openPeriod ? <>
          <p className="text-sm font-semibold">Exercice ouvert</p>
          <p className="mt-1 text-xs text-[#64748B]">Du {formatDate(openPeriod.start_date)} au {formatDate(openPeriod.end_date)}</p>
        </> : <p className="text-sm text-[#64748B]">{person.managementPeriods.length ? "Aucun exercice ouvert" : "Non renseigné"}</p>}
        <Link href={`/dossiers/${protectedPersonId}/exercices`} className="auth-link mt-3 inline-block text-xs">Voir les exercices →</Link>
      </InfoCard>
      <InfoCard icon={FileText} title="Compte de gestion">
        {currentReport ? <>
          <p className="text-sm font-semibold">Compte de gestion {currentReport.report_year}</p>
          <p className="mt-1 text-xs text-[#64748B]">{reportStatusLabels[currentReport.status]}</p>
          <Link href={`/dossiers/${protectedPersonId}/comptes-de-gestion/${currentReport.id}`} className="auth-link mt-3 inline-block text-xs">Voir le compte de gestion →</Link>
        </> : <>
          <p className="text-sm text-[#64748B]">{openPeriod ? "Aucun compte de gestion correspondant" : "Aucun exercice courant"}</p>
          <Link href={`/dossiers/${protectedPersonId}/comptes-de-gestion`} className="auth-link mt-3 inline-block text-xs">Voir les comptes de gestion →</Link>
        </>}
      </InfoCard>
    </div>}

    {currentView === "deletion" && canDelete && <section className="mt-6 rounded-xl border border-red-200 bg-white p-5 shadow-[0_6px_18px_rgba(15,23,42,0.035)]">
      <div className="flex items-start gap-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-red-50 text-red-700"><Trash2 aria-hidden="true" size={18} /></span>
        <div>
          <h2 className="text-lg font-bold text-red-800">Suppression définitive du dossier</h2>
          <p className="mt-1 text-sm text-[#64748B]">Cette action est irréversible et réservée au propriétaire. Le dossier doit être pratiquement vide avant sa suppression.</p>
        </div>
      </div>
      <div className="mt-4 rounded-lg bg-red-50/70 p-4 text-sm text-[#334155]">
        <p className="font-semibold">La suppression sera refusée tant que des données associées subsistent.</p>
        <p className="mt-2 leading-6">Les comptes financiers, mesures de protection, exercices, accès collaborateurs, invitations, virements et affectations de justificatifs bloquent notamment la suppression. Les biens immobiliers, dettes et comptes de gestion peuvent également l’empêcher.</p>
        <p className="mt-2 leading-6">Lorsque toutes les dépendances ont été retirées, seul le dossier devenu vide est supprimé physiquement.</p>
      </div>
      <div className="mt-4"><DeleteProtectedPerson protectedPersonId={protectedPersonId} personName={`${person.first_name} ${person.last_name}`} /></div>
    </section>}
  </PrivateShell>;
}

function InfoCard({ icon: Icon, title, children, action }: { icon: typeof UserRound; title: string; children: React.ReactNode; action?: React.ReactNode }) {
  return <section className="self-start rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3 shadow-[0_6px_18px_rgba(15,23,42,0.035)]">
    <div className="flex items-center justify-between gap-2"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon aria-hidden="true" size={15} /></span><h2 className="text-sm font-bold">{title}</h2></div>{action}</div>
    <div className="mt-2.5">{children}</div>
  </section>;
}

function DataLine({ label, value }: { label: string; value: string }) {
  return <div className="mb-2 last:mb-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-[#94A3B8]">{label}</p><p className="mt-0.5 text-sm text-[#334155]">{value}</p></div>;
}

function CompletenessBadge({ complete, count }: { complete: boolean; count: number }) {
  return <p className={`mb-2 rounded-md px-2 py-1 text-[11px] font-semibold ${complete ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>{complete ? "Informations complètes" : `${count} information${count > 1 ? "s" : ""} à compléter`}</p>;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}
