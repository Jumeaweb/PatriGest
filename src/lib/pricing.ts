export type BillingCycle = "monthly" | "annual";

export type PricingFeature = {
  label: string;
  availability: "available" | "upcoming";
};

export type PricingPlan = {
  id: "essential" | "comfort" | "premium";
  name: string;
  description: string;
  monthlyPrice: number;
  annualPrice: number;
  annualSavings: number;
  discountPercent: number;
  highlighted?: boolean;
  features: readonly PricingFeature[];
};

export const PRICING_PLANS: readonly PricingPlan[] = [
  {
    id: "essential",
    name: "Essentiel",
    description: "Les outils indispensables pour tenir les dossiers à jour.",
    monthlyPrice: 3,
    annualPrice: 30,
    annualSavings: 6,
    discountPercent: 17,
    features: [
      { label: "2 dossiers actifs inclus", availability: "available" },
      { label: "Gestion des personnes protégées et des mesures", availability: "available" },
      { label: "Gestion des comptes bancaires et des opérations", availability: "available" },
      { label: "Patrimoine immobilier, dettes et emprunts", availability: "available" },
      { label: "Comptes de gestion", availability: "available" },
      { label: "Saisie manuelle des opérations", availability: "available" },
    ],
  },
  {
    id: "comfort",
    name: "Confort",
    description: "Pour préparer plus rapidement la gestion courante.",
    monthlyPrice: 5,
    annualPrice: 50,
    annualSavings: 10,
    discountPercent: 17,
    highlighted: true,
    features: [
      { label: "Toutes les fonctionnalités actuellement disponibles dans Essentiel", availability: "available" },
      { label: "Importation et préparation automatisée des opérations à partir des relevés bancaires", availability: "upcoming" },
    ],
  },
  {
    id: "premium",
    name: "Premium",
    description: "Une offre enrichie pour organiser aussi les documents.",
    monthlyPrice: 6,
    annualPrice: 60,
    annualSavings: 12,
    discountPercent: 17,
    features: [
      { label: "Toutes les fonctionnalités actuellement disponibles dans Confort", availability: "available" },
      { label: "Importation et préparation automatisée des opérations à partir des relevés bancaires", availability: "upcoming" },
      { label: "Gestion documentaire et classement des pièces justificatives", availability: "upcoming" },
    ],
  },
] as const;

export const DOSSIER_CAPACITIES = [
  { id: "included", label: "2 dossiers", monthlyLabel: "Inclus", annualLabel: "Inclus" },
  { id: "five", label: "Jusqu’à 5 dossiers", monthlyLabel: "+2 €/mois", annualLabel: "+20 €/an" },
  { id: "ten", label: "Jusqu’à 10 dossiers", monthlyLabel: "+4 €/mois", annualLabel: "+40 €/an" },
  { id: "custom", label: "Plus de 10 dossiers", monthlyLabel: "Sur devis", annualLabel: "Sur devis" },
] as const;
