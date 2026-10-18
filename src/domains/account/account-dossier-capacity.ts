import type { AccountMode } from "@/types/database";
import type { OwnedDossierCapacity } from "@/domains/subscriptions/dossier-capacity";

export const ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE =
  "La capacité de vos dossiers est momentanément indisponible. Veuillez réessayer ultérieurement.";

export type AccountDossierCapacityResult =
  | { status: "ready"; capacity: OwnedDossierCapacity }
  | { status: "error" };

export type AccountDossierCapacityPresentation = {
  activeDossiersLabel: string;
  capacityLabel: string | null;
  remainingPlacesLabel: string | null;
  notice: string | null;
  exceededLabel: string | null;
};

export function shouldLoadOwnedDossierCapacity(input: {
  accountMode: AccountMode | null;
  isPlatformAdmin: boolean;
}) {
  return !input.isPlatformAdmin && input.accountMode === "autonomous";
}

export function getAccountDossierCapacityPresentation(
  capacity: OwnedDossierCapacity,
): AccountDossierCapacityPresentation {
  if (capacity.unlimited) {
    return {
      activeDossiersLabel: `Dossiers actifs : ${capacity.activeDossierCount}`,
      capacityLabel: "Capacité : Illimitée",
      remainingPlacesLabel: null,
      notice: null,
      exceededLabel: null,
    };
  }

  return {
    activeDossiersLabel: `Dossiers actifs : ${capacity.activeDossierCount} / ${capacity.activeDossierLimit}`,
    capacityLabel: null,
    remainingPlacesLabel: `Places restantes : ${capacity.remainingDossierCount}`,
    notice: capacity.state === "reached" ? "Le plafond de dossiers actifs est atteint." : null,
    exceededLabel: capacity.state === "exceeded"
      ? `Dépassement : ${capacity.exceededBy} ${capacity.exceededBy === 1 ? "dossier" : "dossiers"}`
      : null,
  };
}
