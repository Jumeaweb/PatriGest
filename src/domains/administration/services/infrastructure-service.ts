import "server-only";

import { unstable_cache } from "next/cache";
import { collectInfrastructureStatuses, type InfrastructureAdapters } from "../infrastructure-monitoring";
import { requirePlatformAdministrator } from "./administration-service";
import { getGandiInfrastructure } from "./gandi-infrastructure-service";
import { withInfrastructureTimeout } from "./infrastructure-http";
import { getResendInfrastructure } from "./resend-infrastructure-service";
import { getSupabaseInfrastructure } from "./supabase-infrastructure-service";
import { getVercelInfrastructure } from "./vercel-infrastructure-service";

const adapters: InfrastructureAdapters = {
  supabase: () => withInfrastructureTimeout(getSupabaseInfrastructure),
  vercel: () => withInfrastructureTimeout(getVercelInfrastructure),
  resend: () => withInfrastructureTimeout(getResendInfrastructure),
  gandi: () => withInfrastructureTimeout(getGandiInfrastructure),
};

const getCachedInfrastructureStatuses = unstable_cache(
  () => collectInfrastructureStatuses(adapters),
  ["administration-infrastructure-v1"],
  { revalidate: 300 },
);

export async function getInfrastructureDashboard() {
  await requirePlatformAdministrator();
  return getCachedInfrastructureStatuses();
}
