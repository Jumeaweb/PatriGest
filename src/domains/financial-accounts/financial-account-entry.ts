import { z } from "zod";

export function getFinancialAccountEntryHref(
  protectedPersonId: string,
  accountId: string,
  valuationAccount: boolean,
) {
  if (![protectedPersonId, accountId].every((id) => z.uuid().safeParse(id).success)) {
    throw new Error("Compte invalide.");
  }
  const accountBase = `/dossiers/${protectedPersonId}/comptes/${accountId}`;
  return valuationAccount ? accountBase : `${accountBase}/operations`;
}
