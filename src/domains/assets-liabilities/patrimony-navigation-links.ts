import { z } from "zod";

export type PatrimonyNavigationCurrent = "patrimony" | "accounts" | "properties" | "debts";

export type PatrimonyNavigationItem = {
  label: string;
  href: string;
  active: boolean;
};

export function getPatrimonyNavigationItems(
  protectedPersonId: string,
  current: PatrimonyNavigationCurrent,
): PatrimonyNavigationItem[] {
  if (!z.uuid().safeParse(protectedPersonId).success) {
    throw new Error("Dossier invalide.");
  }

  const base = `/dossiers/${protectedPersonId}`;
  return [
    { label: "Patrimoine", href: `${base}?vue=patrimoine`, active: current === "patrimony" },
    { label: "Comptes bancaires", href: `${base}/comptes`, active: current === "accounts" },
    { label: "Patrimoine immobilier", href: `${base}/patrimoine-immobilier`, active: current === "properties" },
    { label: "Dettes et emprunts", href: `${base}/dettes`, active: current === "debts" },
  ];
}
