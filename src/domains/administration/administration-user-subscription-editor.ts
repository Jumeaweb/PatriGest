import type { AdministrativeBillingPeriod, AdministrativeDossierCapacityKey, SubscriptionPlanKey } from "@/types/database";
import type { PlatformUserSummary } from "./services/administration-service";

export const ADMIN_PLAN_OPTIONS = ["essential", "comfort", "premium"] as const;
export const ADMIN_BILLING_PERIOD_OPTIONS = ["monthly", "annual"] as const;
export const ADMIN_CAPACITY_OPTIONS = ["included", "five", "ten"] as const;
export const ADMIN_OVERRIDE_PLAN_OPTIONS = ["comfort", "premium"] as const;
export const ADMIN_OVERRIDE_CAPACITY_OPTIONS = ["five", "ten"] as const;

export type AdministrationPlanDraft = {
  planKey: SubscriptionPlanKey;
  billingPeriod: AdministrativeBillingPeriod;
  capacityKey: AdministrativeDossierCapacityKey;
};

export type AdministrationOverrideDraft = {
  featurePlanKey: "comfort" | "premium" | null;
  capacityKey: "five" | "ten" | null;
};

export function createAdministrationPlanDraft(user: PlatformUserSummary): AdministrationPlanDraft {
  const assignment = user.entitlements?.administrativeAssignment;
  return {
    planKey: assignment?.planKey ?? "essential",
    billingPeriod: assignment?.billingPeriod ?? "monthly",
    capacityKey: assignment?.dossierCapacityKey ?? "included",
  };
}

export function createAdministrationOverrideDraft(user: PlatformUserSummary): AdministrationOverrideDraft {
  const entitlementOverride = user.entitlements?.administrativeOverride;
  return {
    featurePlanKey: entitlementOverride?.featurePlanKey === "comfort" || entitlementOverride?.featurePlanKey === "premium"
      ? entitlementOverride.featurePlanKey
      : null,
    capacityKey: entitlementOverride?.dossierCapacityKey ?? null,
  };
}

export function selectAdministrationPlan(draft: AdministrationPlanDraft, planKey: SubscriptionPlanKey): AdministrationPlanDraft {
  return planKey === "essential"
    ? { ...draft, planKey, capacityKey: "included" }
    : { ...draft, planKey };
}

export function getAdministrativeCapacityLimit(capacityKey: AdministrativeDossierCapacityKey | null): number | null {
  if (capacityKey === "included") return 2;
  if (capacityKey === "five") return 5;
  if (capacityKey === "ten") return 10;
  return null;
}

export function validateAdministrationPlanDraft(draft: AdministrationPlanDraft, activeDossierCount: number): string | null {
  if (draft.planKey === "essential" && draft.capacityKey !== "included") {
    return "La formule Essentiel est limitée à 2 dossiers actifs.";
  }
  const limit = getAdministrativeCapacityLimit(draft.capacityKey);
  if (limit !== null && activeDossierCount > limit) {
    return `Ce compte possède ${activeDossierCount} dossiers actifs, soit plus que le plafond de ${limit}.`;
  }
  return null;
}

export function validateAdministrationOverrideDraft(draft: AdministrationOverrideDraft, activeDossierCount: number): string | null {
  if (!draft.featurePlanKey && !draft.capacityKey) return "Sélectionnez au moins une dérogation fonctionnelle ou de capacité.";
  const limit = getAdministrativeCapacityLimit(draft.capacityKey);
  if (limit !== null && activeDossierCount > limit) {
    return `Ce compte possède ${activeDossierCount} dossiers actifs, soit plus que le plafond de ${limit}.`;
  }
  return null;
}

const planLabels: Record<SubscriptionPlanKey, string> = { essential: "Essentiel", comfort: "Confort", premium: "Premium" };
const billingLabels: Record<AdministrativeBillingPeriod, string> = { monthly: "Mensuel", annual: "Annuel" };

export function describeAdministrationPlanDraft(draft: AdministrationPlanDraft) {
  return {
    formula: planLabels[draft.planKey],
    periodicity: billingLabels[draft.billingPeriod],
    capacity: `${getAdministrativeCapacityLimit(draft.capacityKey)} dossiers actifs`,
  };
}

export function describeAdministrationOverrideDraft(draft: AdministrationOverrideDraft, baseLimit: number | null) {
  const effectiveLimit = getAdministrativeCapacityLimit(draft.capacityKey) ?? baseLimit;
  return {
    formula: draft.featurePlanKey ? planLabels[draft.featurePlanKey] : "Formule de base conservée",
    capacity: effectiveLimit === null ? "Capacité de base conservée" : `${effectiveLimit} dossiers actifs`,
  };
}
