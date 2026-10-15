"use client";

import { useState } from "react";
import { Check, Clock3, Sparkles } from "lucide-react";
import { PRICING_PLANS, type BillingCycle, type PricingPlan } from "@/lib/pricing";

export function PricingSelector() {
  const [cycle, setCycle] = useState<BillingCycle>("monthly");

  return <div>
    <div className="mx-auto flex w-fit rounded-xl border border-brand-navigation/50 bg-white p-1 shadow-sm" role="group" aria-label="Périodicité de facturation">
      <CycleButton active={cycle === "monthly"} onClick={() => setCycle("monthly")}>Mensuel</CycleButton>
      <CycleButton active={cycle === "annual"} onClick={() => setCycle("annual")}>Annuel <span className="ml-1 text-[10px] font-bold">−17 %</span></CycleButton>
    </div>
    <p className="mt-3 text-center text-xs text-[#64748B]">Prix par utilisateur. Les trois forfaits comprennent 2 dossiers actifs. La remise annuelle réelle de 16,67 % est arrondie à 17 %.</p>

    <div className="mt-8 grid items-stretch gap-5 lg:grid-cols-3">
      {PRICING_PLANS.map((plan) => <PricingCard key={plan.id} plan={plan} cycle={cycle} />)}
    </div>
  </div>;
}

function CycleButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return <button
    type="button"
    aria-pressed={active}
    className={`focus-ring min-h-10 rounded-lg px-4 text-sm font-bold transition sm:px-6 ${active ? "bg-brand-accent text-white shadow-sm" : "text-[#64748B] hover:bg-brand-background hover:text-brand-foreground"}`}
    onClick={onClick}
  >{children}</button>;
}

function PricingCard({ plan, cycle }: { plan: PricingPlan; cycle: BillingCycle }) {
  const price = cycle === "monthly" ? plan.monthlyPrice : plan.annualPrice;
  const period = cycle === "monthly" ? "/mois" : "/an";

  return <article className={`relative flex h-full flex-col rounded-2xl border bg-white p-6 shadow-[0_12px_32px_rgba(15,23,42,0.06)] ${plan.highlighted ? "border-brand-accent ring-2 ring-brand-accent/15" : "border-[#E2E8F0]"}`}>
    {plan.highlighted && <p className="absolute right-4 top-4 inline-flex items-center gap-1 rounded-full bg-brand-background px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-brand-accent"><Sparkles aria-hidden="true" size={12} />Intermédiaire</p>}
    <h2 className="pr-24 text-xl font-bold">{plan.name}</h2>
    <p className="mt-2 min-h-12 text-sm leading-6 text-[#64748B]">{plan.description}</p>
    <div className="mt-5 border-y border-[#E2E8F0] py-5" aria-live="polite">
      <p><span className="text-4xl font-bold tracking-tight">{price} €</span><span className="ml-1 text-sm font-semibold text-[#64748B]">{period}</span></p>
      <p className="mt-2 text-xs font-semibold text-emerald-700">Économie annuelle : {plan.annualSavings} € · remise {plan.discountPercent} %</p>
      {cycle === "monthly" && <p className="mt-1 text-xs text-[#64748B]">Ou {plan.annualPrice} €/an avec la facturation annuelle.</p>}
    </div>
    <ul className="mt-5 space-y-3 text-sm leading-5">
      {plan.features.map((feature) => <li key={feature.label} className="flex items-start gap-2.5">
        {feature.availability === "available"
          ? <Check aria-hidden="true" className="mt-0.5 shrink-0 text-emerald-600" size={17} />
          : <Clock3 aria-hidden="true" className="mt-0.5 shrink-0 text-amber-600" size={17} />}
        <span><span className="font-medium">{feature.label}</span>{feature.availability === "upcoming" && <span className="ml-2 inline-flex rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-amber-800">À venir</span>}</span>
      </li>)}
    </ul>
  </article>;
}
