export type TransactionQuickActionMode = "income" | "expense" | "transfer";

export function getTransactionQuickActions(personId: string, accountId: string | undefined, ordinaryAllowed: boolean, transferAllowed: boolean) {
  const destination = `/dossiers/${personId}/operations/nouvelle`;
  const accountQuery = accountId ? `account=${encodeURIComponent(accountId)}&` : "";
  const actions: Array<{ mode: TransactionQuickActionMode; label: string; href: string }> = [];
  if (ordinaryAllowed) {
    actions.push({ mode: "income", label: "Ajouter une recette", href: `${destination}?${accountQuery}mode=income` });
    actions.push({ mode: "expense", label: "Ajouter une dépense", href: `${destination}?${accountQuery}mode=expense` });
  }
  if (transferAllowed) actions.push({ mode: "transfer", label: "Effectuer un virement", href: `${destination}?${accountQuery}mode=transfer` });
  return actions;
}
