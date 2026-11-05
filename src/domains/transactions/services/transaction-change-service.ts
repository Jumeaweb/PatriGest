import type { TransactionChange, TransferChange } from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

export async function listTransactionChanges(personId: string, transactionId: string): Promise<TransactionChange[]> {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("transaction_changes")
    .select("*")
    .eq("protected_person_id", personId)
    .eq("transaction_id", transactionId)
    .order("changed_at", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw new Error("Impossible de charger l’historique de l’opération.");
  return data;
}

export async function listTransferChanges(personId: string, transferId: string): Promise<TransferChange[]> {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("transfer_changes")
    .select("*")
    .eq("protected_person_id", personId)
    .eq("transfer_id", transferId)
    .order("changed_at", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw new Error("Impossible de charger l’historique du virement.");
  return data;
}
