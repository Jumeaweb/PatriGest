import type { Metadata } from "next";
import { CalendarClock, DatabaseBackup, FileCheck2, FolderPlus, ShieldCheck } from "lucide-react";
import { PricingSelector } from "@/components/marketing/pricing-selector";
import { PublicFooter } from "@/components/marketing/public-footer";
import { PublicHeader } from "@/components/marketing/public-header";
import { DOSSIER_CAPACITIES } from "@/lib/pricing";

export const metadata: Metadata = {
  title: "Tarifs — PatriGest",
  description: "Découvrez les forfaits Essentiel, Confort et Premium de PatriGest, ainsi que les capacités de dossiers disponibles.",
};

const cancellationPrinciples = [
  { title: "À tout moment", description: "Vous pouvez demander la résiliation de votre abonnement quand vous le souhaitez.", icon: CalendarClock },
  { title: "Abonnement mensuel", description: "Le renouvellement s’arrête après la période déjà payée.", icon: FileCheck2 },
  { title: "Abonnement annuel", description: "Le renouvellement s’arrête à l’échéance, sans remboursement ordinaire de la période restante, sous réserve des droits légaux applicables.", icon: ShieldCheck },
  { title: "Situation exceptionnelle", description: "En cas de décès de la dernière personne protégée ou de fin de la dernière mesure, une résiliation anticipée avec remboursement au prorata de la période non utilisée peut être demandée.", icon: DatabaseBackup },
];

const questions = [
  { question: "Les tarifs sont-ils facturés par dossier ?", answer: "Non. Le forfait est facturé par utilisateur et comprend 2 dossiers actifs. Une capacité supérieure peut être choisie séparément." },
  { question: "Les capacités de dossiers sont-elles cumulables ?", answer: "Non. Chaque niveau correspond à une capacité totale : 2 dossiers, jusqu’à 5 dossiers ou jusqu’à 10 dossiers. Au-delà, une proposition sur devis est prévue." },
  { question: "Toutes les fonctionnalités annoncées sont-elles déjà disponibles ?", answer: "Les fonctions marquées « À venir » ne sont pas encore disponibles. Elles concernent l’importation automatisée des relevés bancaires et la gestion documentaire avancée." },
  { question: "Comment récupérer mes données avant la fin de l’accès ?", answer: "Il est recommandé de récupérer les données et documents utiles avant la date de fin d’accès. Les modalités détaillées seront précisées dans les futures conditions générales de vente." },
];

export default function PricingPage() {
  return <div className="min-h-screen bg-brand-background text-brand-foreground">
    <PublicHeader />
    <main>
      <section className="relative overflow-hidden bg-white px-5 py-14 text-center sm:px-8 sm:py-20" aria-labelledby="pricing-title">
        <div className="decorative-blob left-[-5rem] top-12 h-48 w-48 bg-sky-100" />
        <div className="decorative-blob right-[-4rem] top-20 h-44 w-44 bg-emerald-100" />
        <div className="relative z-10 mx-auto max-w-3xl">
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-brand-accent">Tarifs PatriGest</p>
          <h1 id="pricing-title" className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl">Des tarifs simples et accessibles</h1>
          <p className="mx-auto mt-5 max-w-2xl text-base leading-7 text-[#64748B] sm:text-lg">Choisissez un forfait par utilisateur, avec 2 dossiers actifs inclus. La facturation annuelle permet d’économiser environ 17 %.</p>
          <p className="mx-auto mt-5 w-fit rounded-full border border-amber-200 bg-amber-50 px-4 py-2 text-xs font-semibold text-amber-900">Présentation commerciale uniquement · La souscription en ligne n’est pas encore disponible.</p>
        </div>
      </section>

      <section className="py-14 sm:py-20" aria-labelledby="plans-title">
        <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
          <SectionHeading eyebrow="Trois niveaux de service" title="Choisissez la formule adaptée à votre gestion" id="plans-title" />
          <div className="mt-9"><PricingSelector /></div>
        </div>
      </section>

      <section className="bg-white py-14 sm:py-20" aria-labelledby="capacities-title">
        <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
          <SectionHeading eyebrow="Capacité du compte" title="Ajoutez les dossiers dont vous avez besoin" id="capacities-title" />
          <p className="mx-auto mt-4 max-w-3xl text-center text-sm leading-6 text-[#64748B]">Ces capacités totales sont accessibles avec chaque forfait et ne se cumulent pas entre elles.</p>
          <div className="mt-9 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {DOSSIER_CAPACITIES.map((capacity) => <article key={capacity.id} className="rounded-2xl border border-[#E2E8F0] bg-[#F8FAFC] p-5">
              <FolderPlus aria-hidden="true" className="text-brand-accent" size={22} />
              <h2 className="mt-4 font-bold">{capacity.label}</h2>
              <dl className="mt-4 grid grid-cols-2 gap-3 border-t border-[#E2E8F0] pt-4 text-sm">
                <div><dt className="text-xs text-[#64748B]">Mensuel</dt><dd className="mt-1 font-bold">{capacity.monthlyLabel}</dd></div>
                <div><dt className="text-xs text-[#64748B]">Annuel</dt><dd className="mt-1 font-bold">{capacity.annualLabel}</dd></div>
              </dl>
            </article>)}
          </div>
        </div>
      </section>

      <section className="py-14 sm:py-20" aria-labelledby="cancellation-title">
        <div className="mx-auto max-w-7xl px-5 sm:px-8 lg:px-10">
          <SectionHeading eyebrow="Vous gardez le contrôle" title="Une résiliation claire et prévisible" id="cancellation-title" />
          <div className="mt-9 grid gap-4 sm:grid-cols-2">
            {cancellationPrinciples.map(({ title, description, icon: Icon }) => <article key={title} className="rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-[0_8px_24px_rgba(15,23,42,0.035)]">
              <Icon aria-hidden="true" className="text-brand-accent" size={22} />
              <h2 className="mt-4 font-bold">{title}</h2>
              <p className="mt-2 text-sm leading-6 text-[#64748B]">{description}</p>
            </article>)}
          </div>
          <div className="mt-5 rounded-2xl border border-blue-100 bg-blue-50/60 p-5 text-sm leading-6 text-[#475569]">
            <p className="font-bold text-brand-foreground">Avant la fin de l’accès</p>
            <p className="mt-1">Pensez à récupérer les données et documents dont vous avez besoin. Ces principes commerciaux devront être confirmés par les futures conditions générales de vente et restent soumis aux droits légaux applicables.</p>
          </div>
        </div>
      </section>

      <section className="bg-white py-14 sm:py-20" aria-labelledby="faq-title">
        <div className="mx-auto max-w-4xl px-5 sm:px-8 lg:px-10">
          <SectionHeading eyebrow="Questions fréquentes" title="L’essentiel avant de choisir" id="faq-title" />
          <div className="mt-9 space-y-3">
            {questions.map((item) => <details key={item.question} className="group rounded-xl border border-[#E2E8F0] bg-[#F8FAFC] px-5 py-4 open:bg-white">
              <summary className="focus-ring cursor-pointer rounded-md pr-4 font-bold marker:text-brand-accent">{item.question}</summary>
              <p className="mt-3 text-sm leading-6 text-[#64748B]">{item.answer}</p>
            </details>)}
          </div>
        </div>
      </section>
    </main>
    <PublicFooter />
  </div>;
}

function SectionHeading({ eyebrow, title, id }: { eyebrow: string; title: string; id: string }) {
  return <div className="mx-auto max-w-3xl text-center"><p className="text-sm font-bold uppercase tracking-[0.16em] text-brand-accent">{eyebrow}</p><h2 id={id} className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2></div>;
}
