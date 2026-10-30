import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Building2, CircleAlert, ExternalLink, Mail, Server } from "lucide-react";
import { PublicFooter } from "@/components/marketing/public-footer";
import { PublicHeader } from "@/components/marketing/public-header";
import {
  APP_CONTACT_EMAIL,
  APP_NAME,
  APP_PUBLISHER_NAME,
  APP_PUBLISHER_URL,
  APP_SUPPORT_EMAIL,
} from "@/lib/app";
import { LEGAL_NOTICE_PUBLICATION_READY_VARIABLE } from "@/lib/legal-notice-config-core";
import { getLegalNoticeConfiguration } from "@/lib/legal-notice-config";

export const metadata: Metadata = {
  title: "Mentions légales — PatriGest",
  description: "Informations légales relatives au site et au service PatriGest, édités par Jumeaweb.",
};

export default function LegalNoticePage() {
  const configuration = getLegalNoticeConfiguration();

  return (
    <div className="min-h-screen bg-brand-background text-brand-foreground">
      <PublicHeader />
      <main className="mx-auto w-full max-w-5xl px-5 py-10 sm:px-8 sm:py-14 lg:px-10">
        <Link className="focus-ring inline-flex items-center gap-2 rounded-md text-sm font-semibold text-brand-accent hover:text-brand-foreground" href="/">
          <ArrowLeft aria-hidden="true" size={16} />Retour à l’accueil
        </Link>

        <header className="mt-7 max-w-3xl">
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-brand-accent">Informations légales</p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">Mentions légales</h1>
          <p className="mt-4 text-sm leading-7 text-[#64748B] sm:text-base">Informations relatives à l’édition et à l’hébergement de {APP_NAME}.</p>
        </header>

        {!configuration.readyForPublication ? (
          <IncompleteLegalNotice
            missingVariables={configuration.missingVariables}
            publicationApproved={configuration.publicationApproved}
          />
        ) : (
          <CompleteLegalNotice values={configuration.values as Record<keyof typeof configuration.values, string>} />
        )}
      </main>
      <PublicFooter />
    </div>
  );
}

function IncompleteLegalNotice({
  missingVariables,
  publicationApproved,
}: {
  missingVariables: string[];
  publicationApproved: boolean;
}) {
  return (
    <section className="mt-8 rounded-2xl border border-amber-200 bg-amber-50 p-5 sm:p-6" aria-labelledby="legal-notice-incomplete-title">
      <div className="flex items-start gap-3">
        <CircleAlert aria-hidden="true" className="mt-0.5 shrink-0 text-amber-700" size={22} />
        <div>
          <h2 id="legal-notice-incomplete-title" className="font-bold text-amber-950">Configuration juridique à finaliser</h2>
          <p className="mt-2 text-sm leading-6 text-amber-900">Cette prévisualisation n’est pas présentée comme une version définitive. Aucune coordonnée personnelle fictive ou incomplète n’est affichée.</p>
        </div>
      </div>
      <dl className="mt-5 grid gap-3 text-sm sm:grid-cols-2">
        <ConfigurationState label="Informations obligatoires" value={missingVariables.length ? `${missingVariables.length} rubrique${missingVariables.length > 1 ? "s" : ""} à configurer` : "Complètes"} />
        <ConfigurationState label="Validation de publication" value={publicationApproved ? "Confirmée" : "En attente"} />
      </dl>
      {(missingVariables.length > 0 || !publicationApproved) && (
        <div className="mt-5 border-t border-amber-200 pt-4">
          <p className="text-xs font-bold uppercase tracking-wide text-amber-900">Contrôle de préparation</p>
          <ul className="mt-2 space-y-1 font-mono text-xs text-amber-950">
            {missingVariables.map((name) => <li key={name}>{name}</li>)}
            {!publicationApproved && <li>{LEGAL_NOTICE_PUBLICATION_READY_VARIABLE}=true</li>}
          </ul>
        </div>
      )}
    </section>
  );
}

function CompleteLegalNotice({ values }: { values: Record<string, string> }) {
  return (
    <div className="mt-8 space-y-5">
      <LegalSection icon={Building2} title="Éditeur du site">
        <p>{APP_NAME} est édité sous le nom commercial <strong>{APP_PUBLISHER_NAME}</strong>, entreprise individuelle relevant du régime de la micro-entreprise.</p>
        <dl className="mt-4 grid gap-3 sm:grid-cols-2">
          <LegalValue label="Identité légale" value={values.LEGAL_PUBLISHER_NAME} />
          <LegalValue label="SIREN" value={values.LEGAL_PUBLISHER_SIREN} />
          <LegalValue className="sm:col-span-2" label="Adresse de domiciliation" value={values.LEGAL_PUBLISHER_ADDRESS} />
        </dl>
        <p className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm">
          <a className="focus-ring inline-flex items-center gap-1.5 rounded-md font-semibold text-brand-accent hover:text-brand-foreground" href={`${APP_PUBLISHER_URL}/`} target="_blank" rel="noopener noreferrer">Site de Jumeaweb<ExternalLink aria-hidden="true" size={14} /></a>
          <a className="focus-ring inline-flex items-center gap-1.5 rounded-md font-semibold text-brand-accent hover:text-brand-foreground" href={`mailto:${APP_CONTACT_EMAIL}`}><Mail aria-hidden="true" size={14} />{APP_CONTACT_EMAIL}</a>
          <a className="focus-ring inline-flex items-center gap-1.5 rounded-md font-semibold text-brand-accent hover:text-brand-foreground" href={`mailto:${APP_SUPPORT_EMAIL}`}><Mail aria-hidden="true" size={14} />{APP_SUPPORT_EMAIL}</a>
        </p>
      </LegalSection>

      <LegalSection icon={Building2} title="Directeur de la publication">
        <p>{values.LEGAL_PUBLICATION_DIRECTOR}</p>
      </LegalSection>

      <LegalSection icon={Server} title="Hébergement de l’application">
        <dl className="grid gap-3 sm:grid-cols-2">
          <LegalValue label="Hébergeur" value={values.LEGAL_HOST_NAME} />
          <LegalValue label="Téléphone" value={values.LEGAL_HOST_PHONE} />
          <LegalValue className="sm:col-span-2" label="Adresse" value={values.LEGAL_HOST_ADDRESS} />
        </dl>
        <p className="mt-4 text-xs leading-5 text-[#64748B]">Ces informations concernent l’hébergement de l’application web. Les services de base de données, d’authentification, de stockage documentaire et d’envoi d’e-mails relèvent de prestataires techniques distincts.</p>
      </LegalSection>

      <LegalSection title="Propriété intellectuelle">
        <p>Les éléments composant {APP_NAME}, notamment sa structure, ses textes, ses interfaces, ses éléments graphiques et ses signes distinctifs, sont protégés par les règles applicables à la propriété intellectuelle. Toute reproduction ou réutilisation non autorisée est interdite, sous réserve des exceptions prévues par la loi et des droits appartenant à des tiers.</p>
      </LegalSection>

      <LegalSection title="Responsabilité">
        <p>{APP_NAME} est un outil d’aide à l’organisation et au suivi des dossiers de personnes protégées. Il ne se substitue pas aux autorités, juridictions ou professionnels compétents. L’éditeur s’efforce d’assurer l’exactitude et la disponibilité du service, sans pouvoir garantir l’absence permanente d’erreur ou d’interruption.</p>
      </LegalSection>
    </div>
  );
}

function LegalSection({ icon: Icon, title, children }: { icon?: typeof Building2; title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-[0_8px_24px_rgba(15,23,42,0.035)] sm:p-6">
      <div className="flex items-center gap-3">
        {Icon && <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-navigation/25 text-brand-foreground"><Icon aria-hidden="true" size={18} /></span>}
        <h2 className="text-lg font-bold">{title}</h2>
      </div>
      <div className="mt-4 text-sm leading-7 text-[#475569]">{children}</div>
    </section>
  );
}

function LegalValue({ label, value, className = "" }: { label: string; value: string; className?: string }) {
  return <div className={`rounded-xl bg-[#F8FAFC] px-4 py-3 ${className}`}><dt className="text-xs font-semibold text-[#64748B]">{label}</dt><dd className="mt-1 whitespace-pre-line font-semibold text-brand-foreground">{value}</dd></div>;
}

function ConfigurationState({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-white/70 px-4 py-3"><dt className="text-xs font-semibold text-amber-800">{label}</dt><dd className="mt-1 font-bold text-amber-950">{value}</dd></div>;
}
