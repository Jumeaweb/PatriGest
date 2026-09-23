import "server-only";

import type { AccountMode } from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

export type PrivateAccessContext = {
  isPlatformAdmin: boolean;
  accountMode: AccountMode | null;
  canCreateDossier: boolean;
};

export async function getPrivateAccessContext(): Promise<PrivateAccessContext> {
  const { supabase, userId } = await getAuthenticatedUser();
  const [administratorResult, authorizationResult] = await Promise.all([
    supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
    supabase.from("application_user_authorizations").select("account_mode").eq("user_id", userId).maybeSingle(),
  ]);

  if (administratorResult.error || authorizationResult.error) {
    throw new Error("Impossible de déterminer l’espace utilisateur.");
  }

  const isPlatformAdmin = Boolean(administratorResult.data);
  const accountMode = authorizationResult.data?.account_mode ?? null;
  return {
    isPlatformAdmin,
    accountMode,
    canCreateDossier: !isPlatformAdmin && accountMode !== "collaborator",
  };
}
