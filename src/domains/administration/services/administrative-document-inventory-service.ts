import "server-only";

import {
  documentInventoryResponseSchema,
  type AdministrativeDocumentInventoryQuery,
} from "../administrative-document-inventory";
import { requirePlatformAdministrator } from "./administration-service";

type RpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code?: string } | null }>;
};

export async function getAdministrativeDocumentInventory(query: AdministrativeDocumentInventoryQuery) {
  const { supabase } = await requirePlatformAdministrator();
  const result = await (supabase as unknown as RpcClient).rpc("get_administrative_document_inventory", {
    p_limit: query.limit,
    p_after_key: query.cursor,
    p_document_category: query.category,
    p_anomaly_type: query.anomaly,
  });
  if (result.error) {
    const message = result.error.code === "P4I01"
      ? "L’inventaire documentaire n’est pas autorisé."
      : "Impossible de charger l’inventaire documentaire.";
    throw new Error(message);
  }
  return documentInventoryResponseSchema.parse(result.data);
}
