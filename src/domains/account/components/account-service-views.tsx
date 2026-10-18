import Link from "next/link";
import { Archive, Clock3, CreditCard, Database, FileText, ShieldCheck } from "lucide-react";
import { DOSSIER_CAPACITIES, PRICING_PLANS } from "@/lib/pricing";
import type { AccountDossierCapacityResult } from "../account-dossier-capacity";
import { AccountDossierCapacity } from "./account-dossier-capacity";

export function AccountSubscriptionView({ dossierCapacity }: { dossierCapacity: AccountDossierCapacityResult | null }) {
  return <AccountServicePanel icon={CreditCard} title="Abonnement" description="Les abonnements PatriGest ne sont pas encore disponibles.">
    <AvailabilityNotice>Votre compte ne dispose actuellement d’aucun forfait attribué. Aucune date de renouvellement, capacité souscrite ou information de paiement n’est affichée.</AvailabilityNotice>
    {dossierCapacity && <AccountDossierCapacity result={dossierCapacity} />}
    <div className="mt-5 grid gap-3 lg:grid-cols-3">
      {PRICING_PLANS.map((plan) => <article key={plan.id} className="rounded-xl border border-[#E2E8F0] bg-slate-50 p-4">
        <h3 className="font-bold">{plan.name}</h3>
        <p className="mt-2 text-xl font-bold">{plan.monthlyPrice} €<span className="text-xs font-semibold text-[#64748B]">/mois</span></p>
        <p className="mt-1 text-sm font-semibold text-brand-accent">ou {plan.annualPrice} €/an</p>
        <p className="mt-3 text-xs leading-5 text-[#64748B]">2 dossiers actifs inclus.</p>
      </article>)}
    </div>
    <div className="mt-5 rounded-xl border border-[#E2E8F0] p-4">
      <h3 className="text-sm font-bold">Capacités supplémentaires prévues</h3>
      <dl className="mt-3 grid gap-3 sm:grid-cols-2">
        {DOSSIER_CAPACITIES.filter((capacity) => capacity.id !== "included").map((capacity) => <div key={capacity.id} className="rounded-lg bg-slate-50 p-3">
          <dt className="text-xs font-bold">{capacity.label}</dt>
          <dd className="mt-1 text-xs text-[#64748B]">{capacity.monthlyLabel} · {capacity.annualLabel}</dd>
        </div>)}
      </dl>
    </div>
    <Link href="/tarifs" className="button button-secondary mt-5 w-full sm:w-auto">Voir tous les tarifs</Link>
  </AccountServicePanel>;
}

export function AccountInvoicesView() {
  return <AccountServicePanel icon={FileText} title="Factures" description="La facturation sera disponible avec les futurs abonnements.">
    <AvailabilityNotice>Aucune facture n’est disponible pour le moment. Aucun document ou historique de paiement fictif n’est créé.</AvailabilityNotice>
  </AccountServicePanel>;
}

export function AccountCancellationView() {
  return <AccountServicePanel icon={Archive} title="Résiliation" description="Cet espace accueillera la gestion de la résiliation lorsqu’un abonnement réel pourra être souscrit.">
    <AvailabilityNotice>Aucune action de résiliation n’est nécessaire ou possible actuellement, puisqu’aucun abonnement n’est attribué à votre compte.</AvailabilityNotice>
    <div className="mt-4 flex items-start gap-3 rounded-xl border border-blue-100 bg-blue-50/60 p-4 text-sm leading-6 text-[#475569]">
      <ShieldCheck aria-hidden="true" className="mt-0.5 shrink-0 text-brand-accent" size={18} />
      <p>Les futures modalités préciseront l’arrêt du renouvellement, la date de fin d’accès et la récupération préalable des données, sous réserve des droits légaux applicables.</p>
    </div>
  </AccountServicePanel>;
}

export function AccountDataView() {
  return <AccountServicePanel icon={Database} title="Mes données" description="Préparation du futur export sécurisé de votre espace PatriGest.">
    <div className="mt-4 rounded-xl border border-[#E2E8F0] bg-slate-50 p-4">
      <div className="flex items-start gap-3">
        <Clock3 aria-hidden="true" className="mt-0.5 shrink-0 text-brand-accent" size={19} />
        <div><h3 className="text-sm font-bold">Export ZIP à venir</h3><p className="mt-1 text-sm leading-6 text-[#64748B]">Lorsqu’il sera disponible, l’export permettra de récupérer les données auxquelles vous êtes autorisé à accéder ainsi que les documents associés disponibles.</p></div>
      </div>
      <p className="mt-3 border-t border-[#E2E8F0] pt-3 text-xs font-semibold text-[#475569]">L’export sera inclus sans supplément dans tous les forfaits.</p>
    </div>
    <p className="mt-4 text-xs leading-5 text-[#64748B]">L’export réel et ses contrôles de sécurité seront implémentés dans le lot PAT-EXPORT-01. Aucun téléchargement n’est proposé à ce stade.</p>
  </AccountServicePanel>;
}

function AvailabilityNotice({ children }: { children: React.ReactNode }) {
  return <div className="mt-4 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50/70 p-4 text-sm leading-6 text-amber-950"><Clock3 aria-hidden="true" className="mt-0.5 shrink-0 text-amber-700" size={18} /><p>{children}</p></div>;
}

function AccountServicePanel({ icon: Icon, title, description, children }: { icon: typeof CreditCard; title: string; description: string; children: React.ReactNode }) {
  return <section className="rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-[0_8px_24px_rgba(15,23,42,0.04)] sm:p-5">
    <div className="flex items-start gap-3"><span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-navigation/35 text-brand-foreground"><Icon aria-hidden="true" size={19} /></span><div><h2 className="text-lg font-bold">{title}</h2><p className="mt-1 text-xs text-[#64748B]">{description}</p></div></div>
    {children}
  </section>;
}
