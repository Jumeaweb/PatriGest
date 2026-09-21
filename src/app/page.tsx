import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeftRight, Building2, CalendarRange, Check, ClipboardCheck, FileText, FolderHeart, Landmark, Scale, ShieldCheck, UserRound, Users, WalletCards } from "lucide-react";
import { FeatureCard } from "@/components/marketing/feature-card";
import { HeroDashboardPreview } from "@/components/marketing/hero-dashboard-preview";
import { PublicFooter } from "@/components/marketing/public-footer";
import { PublicHeader } from "@/components/marketing/public-header";
import { APP_SLOGAN } from "@/lib/app";

export const metadata: Metadata = {
  title: "PatriGest — Gestion des dossiers de personnes protégées",
  description: "Centralisez les comptes, opérations, relevés, justificatifs et éléments du patrimoine d’une personne protégée, et facilitez la préparation du compte de gestion.",
};

const benefits = [
  { title: "Centralisez le dossier", description: "Réunissez les informations de la personne protégée, sa mesure de protection et les éléments utiles à sa gestion.", icon: FolderHeart, iconClassName: "bg-blue-50 text-[#2563EB]" },
  { title: "Suivez les comptes et le patrimoine", description: "Enregistrez les comptes, opérations, placements, biens et dettes pour conserver une vision structurée du patrimoine.", icon: Landmark, iconClassName: "bg-sky-50 text-[#0EA5E9]" },
  { title: "Préparez le compte de gestion", description: "Appuyez-vous sur les informations déjà saisies pour préparer le compte de gestion au format officiel et repérer les éléments restant à compléter.", icon: ClipboardCheck, iconClassName: "bg-green-50 text-[#16A34A]" },
];

const dossierGroups = [
  { title: "Personne et mesure", description: "Informations de la personne protégée, mesure de protection et exercices de gestion.", icon: Scale },
  { title: "Comptes et opérations", description: "Comptes bancaires, recettes, dépenses et transferts entre comptes.", icon: ArrowLeftRight },
  { title: "Documents utiles", description: "Relevés bancaires et justificatifs associés aux opérations.", icon: FileText },
  { title: "Patrimoine", description: "Placements, assurances-vie, biens immobiliers, dettes et emprunts.", icon: Building2 },
];

const steps = [
  { title: "Créez le dossier", description: "Renseignez la personne protégée et sa mesure de protection." },
  { title: "Suivez la gestion courante", description: "Ajoutez les comptes, les opérations, les relevés et les justificatifs utiles." },
  { title: "Gardez une vision du patrimoine", description: "Suivez les comptes, placements, biens immobiliers et dettes depuis le même dossier." },
  { title: "Préparez le compte de gestion", description: "Réutilisez les informations déjà enregistrées pour préparer le compte de gestion et identifier ce qu’il reste à compléter." },
];

export default function Home() {
  return (
    <div className="min-h-screen bg-brand-background text-brand-foreground">
      <PublicHeader />
      <main>
        <section className="relative overflow-hidden bg-white" aria-labelledby="hero-title">
          <div className="decorative-blob left-[-7rem] top-24 h-56 w-56 bg-sky-100" />
          <div className="decorative-blob right-[-5rem] top-10 h-48 w-48 bg-emerald-100" />
          <div className="mx-auto grid max-w-7xl items-center gap-14 px-5 py-14 sm:px-8 sm:py-20 lg:grid-cols-[0.95fr_1.05fr] lg:px-10 lg:py-24">
            <div className="relative z-10 max-w-2xl">
              <p className="mb-5 inline-flex items-center gap-2 rounded-full border border-brand-navigation/40 bg-brand-background px-3 py-1.5 text-sm font-semibold text-brand-accent">
                <ShieldCheck aria-hidden="true" size={16} />Pour les particuliers exerçant une mesure de protection
              </p>
              <h1 id="hero-title" className="text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl lg:leading-[1.08]">Gérez chaque dossier de personne protégée plus simplement</h1>
              <p className="mt-5 max-w-xl text-base leading-7 text-[#64748B] sm:text-lg">Centralisez les informations, les comptes, les opérations et les justificatifs, suivez le patrimoine et préparez le compte de gestion dans un même espace.</p>
              <div className="mt-7 flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
                <Link className="button button-primary" href="/inscription">Créer un compte</Link>
                <a className="button button-secondary" href="#comment-ca-marche">Découvrir le fonctionnement</a>
              </div>
              <p className="mt-3 text-xs font-medium text-[#64748B]">Créez votre compte · L’accès est activé après validation</p>
              <p className="mt-6 flex items-center gap-2 text-sm font-semibold text-[#475569]"><Check aria-hidden="true" className="shrink-0 text-[#16A34A]" size={17} />{APP_SLOGAN}</p>
            </div>
            <HeroDashboardPreview />
          </div>
        </section>

        <section id="fonctionnalites" className="scroll-mt-24 py-16 sm:py-20" aria-labelledby="benefits-title">
          <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
            <SectionHeading eyebrow="L’essentiel au même endroit" title="Une gestion plus claire, du quotidien au compte de gestion" id="benefits-title" />
            <div className="mt-10 grid gap-6 md:grid-cols-3">{benefits.map((benefit) => <FeatureCard key={benefit.title} {...benefit} />)}</div>
          </div>
        </section>

        <section className="bg-white py-16 sm:py-20" aria-labelledby="dossier-title">
          <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
            <SectionHeading eyebrow="Votre dossier organisé" title="Les informations utiles, réunies dans un même dossier" id="dossier-title" />
            <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {dossierGroups.map(({ title, description, icon: Icon }) => <article key={title} className="rounded-2xl border border-[#E2E8F0] bg-[#F8FAFC] p-5"><span className="flex size-10 items-center justify-center rounded-xl bg-blue-50 text-[#2563EB]"><Icon aria-hidden="true" size={20} /></span><h3 className="mt-4 font-bold">{title}</h3><p className="mt-2 text-sm leading-6 text-[#64748B]">{description}</p></article>)}
            </div>
          </div>
        </section>

        <section id="comment-ca-marche" className="scroll-mt-24 py-16 sm:py-20" aria-labelledby="steps-title">
          <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
            <SectionHeading eyebrow="Comment ça marche ?" title="Un parcours simple pour garder le dossier à jour" id="steps-title" />
            <ol className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              {steps.map((step, index) => <li key={step.title} className="rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-[0_8px_24px_rgba(15,23,42,0.035)]"><span className="flex size-9 items-center justify-center rounded-full bg-[#2563EB] text-sm font-bold text-white" aria-hidden="true">{index + 1}</span><h3 className="mt-4 font-bold">{step.title}</h3><p className="mt-2 text-sm leading-6 text-[#64748B]">{step.description}</p></li>)}
            </ol>
          </div>
        </section>

        <section id="compte-de-gestion" className="scroll-mt-24 bg-white py-16 sm:py-20" aria-labelledby="management-section-title">
          <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
            <SectionHeading eyebrow="Pour aller plus loin" title="Préparez, partagez, gardez le contrôle" id="management-section-title" />
            <div className="mt-10 grid gap-6 lg:grid-cols-2">
            <article className="rounded-2xl border border-blue-100 bg-blue-50/60 p-6 sm:p-8">
              <span className="flex size-11 items-center justify-center rounded-xl bg-white text-[#2563EB] shadow-sm"><ClipboardCheck aria-hidden="true" size={22} /></span>
              <h2 id="management-title" className="mt-5 text-2xl font-bold tracking-tight">Préparez votre compte de gestion au format officiel</h2>
              <p className="mt-3 leading-7 text-[#475569]">PatriGest reprend les informations déjà enregistrées dans le dossier pour vous aider à préparer le compte de gestion selon le format officiel, contrôler les éléments à compléter et générer le document en PDF.</p>
              <ul className="mt-5 grid gap-2 text-sm font-medium text-[#334155] sm:grid-cols-2">{["Éléments à compléter", "Aperçu du compte", "Génération du document PDF", "Suivi de la préparation"].map((item) => <li key={item} className="flex items-center gap-2"><Check aria-hidden="true" className="shrink-0 text-[#16A34A]" size={16} />{item}</li>)}</ul>
              <p className="mt-5 border-t border-blue-100 pt-4 text-xs leading-5 text-[#64748B]">PatriGest accompagne la préparation du compte de gestion sans se substituer aux autorités ou professionnels compétents.</p>
            </article>
            <article className="rounded-2xl border border-[#E2E8F0] bg-[#F8FAFC] p-6 sm:p-8">
              <span className="flex size-11 items-center justify-center rounded-xl bg-white text-[#EA580C] shadow-sm"><Users aria-hidden="true" size={22} /></span>
              <h2 className="mt-5 text-2xl font-bold tracking-tight">Travaillez à plusieurs, avec le bon niveau d’accès</h2>
              <p className="mt-3 leading-7 text-[#64748B]">Invitez une autre personne à participer au dossier et choisissez le niveau d’accès adapté.</p>
              <div className="mt-5 grid gap-3 sm:grid-cols-3">
                <Role icon={UserRound} title="Propriétaire" description="Pilote le dossier et ses accès." />
                <Role icon={WalletCards} title="Gestionnaire" description="Participe à la gestion du dossier." />
                <Role icon={FileText} title="Lecture seule" description="Consulte sans modifier." />
              </div>
            </article>
            </div>
          </div>
        </section>

        <section className="px-5 py-16 sm:px-8 sm:py-20" aria-labelledby="final-cta-title">
          <div className="mx-auto max-w-5xl overflow-hidden rounded-2xl bg-[#0F172A] px-6 py-7 text-center text-white shadow-[0_20px_50px_rgba(15,23,42,0.15)] sm:px-10 sm:py-8">
            <CalendarRange aria-hidden="true" className="mx-auto text-blue-300" size={30} />
            <h2 id="final-cta-title" className="mx-auto mt-4 max-w-2xl text-2xl font-bold tracking-tight sm:text-3xl">Une gestion plus simple commence par un dossier bien organisé</h2>
            <p className="mx-auto mt-3 max-w-2xl leading-7 text-slate-300">Centralisez les informations utiles et retrouvez-les au moment de suivre le patrimoine ou de préparer le compte de gestion.</p>
            <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row"><Link className="button button-primary" href="/inscription">Créer un compte</Link><Link className="button border border-slate-600 bg-slate-800 text-white hover:bg-slate-700" href="/connexion">Se connecter</Link></div>
            <p className="mt-3 text-xs text-slate-400">L’accès est activé après validation.</p>
          </div>
        </section>
      </main>
      <PublicFooter />
    </div>
  );
}

function SectionHeading({ eyebrow, title, id }: { eyebrow: string; title: string; id: string }) {
  return <div className="mx-auto max-w-3xl text-center"><p className="text-sm font-bold uppercase tracking-[0.16em] text-brand-accent">{eyebrow}</p><h2 id={id} className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2></div>;
}

function Role({ icon: Icon, title, description }: { icon: typeof UserRound; title: string; description: string }) {
  return <div className="rounded-xl border border-[#E2E8F0] bg-white p-4"><Icon aria-hidden="true" className="text-[#2563EB]" size={18} /><h3 className="mt-3 text-sm font-bold">{title}</h3><p className="mt-1 text-xs leading-5 text-[#64748B]">{description}</p></div>;
}
