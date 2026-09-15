import { z } from "zod";

export type FinancialNavigationCurrent = "accounts" | "details" | "operations" | "statements";

export type FinancialNavigationItem = {
  label: string;
  href: string;
  active: boolean;
};

export function getFinancialNavigationItems(
  protectedPersonId: string,
  current: FinancialNavigationCurrent,
  accountId?: string,
): FinancialNavigationItem[] {
  if (!z.uuid().safeParse(protectedPersonId).success) {
    throw new Error("Dossier invalide.");
  }

  const base = `/dossiers/${protectedPersonId}`;
  if (!accountId) {
    if (current === "details" || current === "statements") {
      throw new Error("Une navigation de compte exige un compte.");
    }
    return [
      { label: "Comptes", href: `${base}/comptes`, active: current === "accounts" },
      { label: "Opérations", href: `${base}/operations`, active: current === "operations" },
    ];
  }

  if (!z.uuid().safeParse(accountId).success) {
    throw new Error("Compte invalide.");
  }
  if (current === "accounts") {
    throw new Error("La navigation d'un compte exige une rubrique contextualisée.");
  }

  const accountBase = `${base}/comptes/${accountId}`;
  return [
    { label: "Informations du compte", href: accountBase, active: current === "details" },
    { label: "Opérations du compte", href: `${accountBase}/operations`, active: current === "operations" },
    { label: "Relevés", href: `${accountBase}/releves`, active: current === "statements" },
  ];
}
