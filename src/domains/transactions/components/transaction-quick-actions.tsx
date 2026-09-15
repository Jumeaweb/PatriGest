import Link from "next/link";
import type { DossierAccessRole } from "@/types/database";
import { getTransactionQuickActions } from "../transaction-quick-actions";
import { withTransactionReturnTo } from "../return-to";

export function TransactionQuickActions({ personId, accountId, accessRole, ordinaryAllowed, transferAllowed, returnTo }: { personId: string; accountId?: string; accessRole: DossierAccessRole; ordinaryAllowed: boolean; transferAllowed: boolean; returnTo?: string }) {
  const actions = getTransactionQuickActions(personId, accountId, accessRole !== "read_only" && ordinaryAllowed, accessRole !== "read_only" && transferAllowed);
  if (!actions.length) return null;
  return <nav aria-label="Ajouter une opération" className="flex flex-wrap gap-2">
    {actions.map((action) => <Link key={action.mode} href={action.href} className={`button min-h-9 px-3 text-xs ${action.mode === "income" ? "button-primary" : "button-secondary"}`}>{action.label}</Link>)}
    {accessRole !== "read_only" && ordinaryAllowed && <Link href={returnTo ? withTransactionReturnTo(`/dossiers/${personId}/operations/saisie-successive${accountId ? `?account=${encodeURIComponent(accountId)}` : ""}`, returnTo) : `/dossiers/${personId}/operations/saisie-successive${accountId ? `?account=${encodeURIComponent(accountId)}` : ""}`} className="button button-secondary min-h-9 px-3 text-xs">Saisie successive</Link>}
  </nav>;
}
