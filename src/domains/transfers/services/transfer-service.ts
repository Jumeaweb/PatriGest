import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { TransferInput } from "../schemas/transfer-schema";
import { CLOSED_PERIOD_ERROR } from "@/domains/transactions/errors";
import { z } from "zod";

const mutationResultSchema = z.object({ id: z.uuid(), revision: z.coerce.number().int().positive(), replayed: z.boolean() });
type TransferMutationOptions = { requestId: string };
type TransferCancellationOptions = TransferMutationOptions & { expectedRevision: number; reason: string };

function transferMutationError(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return new Error(fallback);
  if (error.code === "40001") return new Error("Le virement a été modifié. Rechargez la page.");
  if (error.code === "22007") return new Error("La date d’une opération réelle ne peut pas être future.");
  if (error.message?.toLocaleLowerCase("fr-FR").includes("exercice clôturé")) return new Error(CLOSED_PERIOD_ERROR);
  if (error.code === "42501") return new Error("Dossier introuvable ou accès refusé.");
  if (error.code === "P0002") return new Error("Virement introuvable.");
  if (error.code === "55000" && error.message) return new Error(error.message);
  return new Error(fallback);
}

export async function createTransfer(personId: string, input: TransferInput, options: TransferMutationOptions) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.rpc("create_internal_transfer_v2", {
    p_protected_person_id: personId,
    p_source_account_id: input.sourceAccountId,
    p_destination_account_id: input.destinationAccountId,
    p_transfer_date: input.transferDate,
    p_amount: input.amount,
    p_label: input.label || null,
    p_comment: input.comment || null,
    p_request_id: options.requestId,
  });
  if (error) throw transferMutationError(error, "Impossible de créer le virement.");
  return mutationResultSchema.parse(data);
}

export async function deleteTransfer(personId: string, id: string, options: TransferCancellationOptions) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase.rpc("cancel_internal_transfer_v2", {
    p_protected_person_id: personId,
    p_transfer_id: id,
    p_expected_revision: options.expectedRevision,
    p_reason: options.reason,
    p_request_id: options.requestId,
  });
  if (error) throw transferMutationError(error, "Impossible d’annuler le virement.");
  return mutationResultSchema.parse(data);
}
