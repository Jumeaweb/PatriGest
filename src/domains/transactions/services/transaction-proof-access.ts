import type { DossierAccessRole, TransactionType } from "@/types/database";

export function getProofWriteDenial(input: {
  personId: string;
  transactionPersonId: string;
  transactionType: TransactionType;
  transferId: string | null;
  proofReference: string | null;
  role: DossierAccessRole;
  closed: boolean;
}): "not_found" | "read_only" | "closed" | null {
  if (input.personId !== input.transactionPersonId || input.transactionType !== "expense" || input.transferId || !input.proofReference) return "not_found";
  if (input.role === "read_only") return "read_only";
  if (input.closed) return "closed";
  return null;
}
