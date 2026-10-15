import type { PatrimonyAbsenceConfirmation } from "@/types/database";

export type PatrimonyAbsenceConfirmationState = {
  realEstate: PatrimonyAbsenceConfirmation | null;
  activeDebt: PatrimonyAbsenceConfirmation | null;
};

export function buildPatrimonyAbsenceConfirmationState(
  confirmations: readonly PatrimonyAbsenceConfirmation[],
): PatrimonyAbsenceConfirmationState {
  return {
    realEstate: confirmations.find((confirmation) => confirmation.category === "real_estate") ?? null,
    activeDebt: confirmations.find((confirmation) => confirmation.category === "active_debt") ?? null,
  };
}
