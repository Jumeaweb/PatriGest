import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import { Building2, CalendarDays, Landmark, LayoutDashboard, MapPin, Scale, UserRound, WalletCards } from "lucide-react";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { getDebts, getProperties } from "@/domains/assets-liabilities/services";
import { getFinancialAccounts } from "@/domains/financial-accounts/services/financial-account-service";
import { formatCurrency, getCurrentPatrimonyValue } from "@/domains/financial-accounts/utils/financial-account-utils";
import { DeleteProtectedPerson } from "@/domains/protected-persons/components/delete-protected-person";
import { DossierNavigation } from "@/domains/protected-persons/components/dossier-navigation";
import { getDossierAddressStates, getDossierAssetActionLabel, getDossierDebtState, getDossierPropertyState } from "@/domains/protected-persons/dossier-information-states";
import { EditProtectedPersonButton, EditProtectionMeasureButton } from "@/domains/protected-persons/components/regulatory-edit-dialogs";
import { getProtectedPersonRegulatoryCompleteness, getProtectionMeasureRegulatoryCompleteness } from "@/domains/protected-persons/regulatory-helpers";
import { getMeasureLabel } from "@/domains/protected-persons/schemas/protection-measure-schema";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";

export const metadata: Metadata = { title: "Fiche dossier" };
export const dynamic = "force-dynamic";

export default async function ProtectedPersonDetailPage({ params }: { params: Promise<{ protectedPersonId: string }> }) {
  const { protectedPersonId } = await params;
  if (!z.uuid().safeParse(protectedPersonId).success) notFound();
  const person = await getProtectedPerson(protectedPersonId);
  if (!person) notFound();
  const [accounts, properties, debts] = await Promise.all([
    getFinancialAccounts(protectedPersonId),
    getProperties(protectedPersonId),
    getDebts(protectedPersonId),
  ]);
  const activeMeasure = person.protectionMeasures.find((measure) => measure.active) ?? null;
  const openPeriod = person.managementPeriods.find((period) => period.status === "open");
  const { domicile, residence } = getDossierAddressStates(person);
  const currentPatrimony = getCurrentPatrimonyValue(accounts);
  const personCompleteness = getProtectedPersonRegulatoryCompleteness(person);
  const measureCompleteness = getProtectionMeasureRegulatoryCompleteness(activeMeasure);
  const canManage = person.accessRole !== "read_only";
  const propertyState = getDossierPropertyState(properties);
  const debtState = getDossierDebtState(debts);

  return <PrivateShell current="dossiers" dossier={{ id: protectedPersonId, name: `${person.first_name} ${person.last_name}`, current: "overview", accessRole: person.accessRole }}>
    <AppBreadcrumb items={[{ label: "Dossiers", href: "/dossiers" }, { label: `${person.first_name} ${person.last_name}`, href: `/dossiers/${protectedPersonId}/comptes` }, { label: "Informations du dossier" }]} />
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-sm font-bold uppercase tracking-[0.14em] text-[#2563EB]">Fiche dossier</p><h1 className="mt-1 text-3xl font-bold tracking-tight">{person.first_name} {person.last_name}</h1><p className="mt-1 text-sm text-[#64748B]">Dossier {person.status === "active" ? "actif" : "archivé"}</p></div><Link href={`/dossiers/${protectedPersonId}/tableau-de-bord`} className="button button-secondary gap-2 self-start sm:self-auto"><LayoutDashboard aria-hidden="true" size={16} />Tableau de bord</Link></div>
    <DossierNavigation protectedPersonId={protectedPersonId} current="overview" />
    <div className="mt-6 grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <InfoCard icon={WalletCards} title="Patrimoine actuel"><p className="text-2xl font-bold">{accounts.length ? formatCurrency(currentPatrimony) : "Non renseigné"}</p><Link href={`/dossiers/${protectedPersonId}/comptes`} className="auth-link mt-2 inline-block text-xs">Voir les comptes</Link></InfoCard>
      <InfoCard icon={UserRound} title="Identité" action={canManage ? <EditProtectedPersonButton person={person} /> : undefined}><CompletenessBadge complete={personCompleteness.complete} count={personCompleteness.missingFields.length} />{personCompleteness.missingFields.length > 0 && <p className="mb-3 text-xs text-[#64748B]">À compléter : {personCompleteness.missingFields.map((field) => field.label).join(" · ")}</p>}<DataLine label="Nom d’usage" value={person.last_name} /><DataLine label="Prénom(s)" value={person.first_name} />{person.birth_name && <DataLine label="Nom de naissance" value={person.birth_name} />}{person.birth_date && <DataLine label="Date de naissance" value={formatDate(person.birth_date)} />}{person.birth_place && <DataLine label="Lieu de naissance" value={person.birth_place} />}{person.phone && <DataLine label="Téléphone" value={person.phone} />}{person.email && <DataLine label="Email" value={person.email} />}</InfoCard>
      <InfoCard icon={MapPin} title="Domicile et résidence" action={canManage ? <EditProtectedPersonButton person={person} /> : undefined}><DataLine label="Domicile" value={domicile} /><DataLine label="Résidence" value={residence} /></InfoCard>
      <div id="mesure-protection" className="scroll-mt-28"><InfoCard icon={Scale} title="Mesure de protection" action={canManage ? <EditProtectionMeasureButton protectedPersonId={person.id} measure={activeMeasure} /> : undefined}><CompletenessBadge complete={measureCompleteness.complete} count={measureCompleteness.missingFields.length} />{activeMeasure ? <><DataLine label="Type" value={getMeasureLabel(activeMeasure.measure_type)} />{activeMeasure.start_date && <DataLine label="Ouverture / renouvellement" value={formatDate(activeMeasure.start_date)} />}{activeMeasure.case_reference && <DataLine label="Numéro RG" value={activeMeasure.case_reference} />}{activeMeasure.court_cabinet && <DataLine label="Cabinet" value={activeMeasure.court_cabinet} />}{activeMeasure.court_name && <DataLine label="Juridiction" value={[activeMeasure.court_name, activeMeasure.court_city].filter(Boolean).join(" — ")} />}{(activeMeasure.representative_first_name || activeMeasure.representative_last_name) && <DataLine label="Personne en charge" value={[activeMeasure.representative_first_name, activeMeasure.representative_last_name].filter(Boolean).join(" ")} />}{activeMeasure.representative_appointment_date && <DataLine label="Date de nomination" value={formatDate(activeMeasure.representative_appointment_date)} />}{activeMeasure.representative_phone && <DataLine label="Téléphone" value={activeMeasure.representative_phone} />}{activeMeasure.representative_email && <DataLine label="Email" value={activeMeasure.representative_email} />}</> : <p className="text-sm text-[#64748B]">{person.protectionMeasures.length ? "Aucune mesure active" : "Non renseigné"}</p>}</InfoCard></div>
      <InfoCard icon={CalendarDays} title="Exercice de gestion">{openPeriod ? <><p className="text-sm font-semibold">Exercice ouvert</p><p className="mt-1 text-xs text-[#64748B]">Du {formatDate(openPeriod.start_date)} au {formatDate(openPeriod.end_date)}</p></> : <p className="text-sm text-[#64748B]">{person.managementPeriods.length ? "Aucun exercice ouvert" : "Non renseigné"}</p>}<Link href={`/dossiers/${protectedPersonId}/exercices`} className="button button-secondary mt-3 min-h-9 px-4">Gérer les exercices</Link></InfoCard>
      <InfoCard icon={Building2} title="Patrimoine immobilier"><p className="text-sm font-semibold">{propertyState.label}</p>{properties.length > 0 && <><p className="mt-1 text-xs text-[#64748B]">{propertyState.knownValue === null ? "Valeur non renseignée" : `Valeurs connues : ${formatCurrency(propertyState.knownValue)}`}</p>{propertyState.missingValues > 0 && propertyState.knownValue !== null && <p className="mt-1 text-xs text-[#64748B]">{propertyState.missingValues} bien(s) sans valeur renseignée</p>}</>}<Link href={`/dossiers/${protectedPersonId}/patrimoine-immobilier`} className={`mt-3 inline-flex ${canManage ? `button ${properties.length ? "button-secondary" : "button-primary"}` : "auth-link text-xs"}`}>{getDossierAssetActionLabel("properties", properties.length, canManage)}</Link></InfoCard>
      <InfoCard icon={Landmark} title="Dettes et emprunts"><p className="text-sm font-semibold">{debtState.label}</p>{debtState.knownBalance !== null && <p className="mt-1 text-xs text-[#64748B]">Soldes connus : {formatCurrency(debtState.knownBalance)}</p>}{debtState.missingBalances > 0 && <p className="mt-1 text-xs text-[#64748B]">{debtState.missingBalances} solde(s) restant(s) non renseigné(s)</p>}<Link href={`/dossiers/${protectedPersonId}/dettes`} className={`mt-3 inline-flex ${canManage ? `button ${debts.length ? "button-secondary" : "button-primary"}` : "auth-link text-xs"}`}>{getDossierAssetActionLabel("debts", debts.length, canManage)}</Link></InfoCard>
    </div>
    {person.accessRole === "owner" && <section className="mt-4 rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3"><h2 className="text-sm font-bold">Gestion du dossier</h2><p className="mt-1 text-xs text-[#64748B]">La suppression définitive est disponible uniquement lorsque le dossier ne contient plus aucune donnée associée.</p><div className="mt-2"><DeleteProtectedPerson protectedPersonId={protectedPersonId} personName={`${person.first_name} ${person.last_name}`} /></div></section>}
  </PrivateShell>;
}

function InfoCard({ icon: Icon, title, children, action }: { icon: typeof UserRound; title: string; children: React.ReactNode; action?: React.ReactNode }) { return <section className="self-start rounded-xl border border-[#E2E8F0] bg-white px-3.5 py-3 shadow-[0_6px_18px_rgba(15,23,42,0.035)]"><div className="flex items-center justify-between gap-2"><div className="flex items-center gap-2"><span className="flex size-7 items-center justify-center rounded-lg bg-blue-50 text-[#2563EB]"><Icon aria-hidden="true" size={15} /></span><h2 className="text-sm font-bold">{title}</h2></div>{action}</div><div className="mt-2.5">{children}</div></section>; }
function DataLine({ label, value }: { label: string; value: string }) { return <div className="mb-2 last:mb-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-[#94A3B8]">{label}</p><p className="mt-0.5 text-sm text-[#334155]">{value}</p></div>; }
function CompletenessBadge({ complete, count }: { complete: boolean; count: number }) { return <p className={`mb-2 rounded-md px-2 py-1 text-[11px] font-semibold ${complete ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>{complete ? "Informations complètes" : `${count} information${count > 1 ? "s" : ""} à compléter`}</p>; }
function formatDate(value: string) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)); }
