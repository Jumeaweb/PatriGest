import "server-only";

import { buildSupabaseResult } from "../infrastructure-monitoring";
import { createAdminClient } from "@/lib/supabase/admin";
import { readFiniteNumber } from "./infrastructure-http";

export async function getSupabaseInfrastructure(signal: AbortSignal) {
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("get_infrastructure_usage_metrics").abortSignal(signal);
  const row = data?.[0];
  if (error || !row) throw new Error("Supabase metrics unavailable");
  return buildSupabaseResult(readFiniteNumber(row.database_size_bytes), readFiniteNumber(row.storage_size_bytes), new Date().toISOString());
}
