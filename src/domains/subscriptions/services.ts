import "server-only";

import { createClient } from "@/lib/supabase/server";
import {
  loadDossierFeatureCapabilities,
  verifyDossierFeatureAccess,
  type DossierFeatureAccessMode,
  type DossierFeatureKey,
  type DossierFeatureRpcGateway,
  type DossierFeatureRpcResult,
} from "./entitlements";

type EntitlementRpcInvoker = {
  (
    name: "get_protected_person_feature_capabilities",
    args: { p_protected_person_id: string },
  ): PromiseLike<DossierFeatureRpcResult>;
  (
    name: "check_protected_person_feature_access",
    args: {
      p_protected_person_id: string;
      p_feature_key: DossierFeatureKey;
      p_access_mode: DossierFeatureAccessMode;
    },
  ): PromiseLike<DossierFeatureRpcResult>;
};

type ServerSupabaseClient = Awaited<ReturnType<typeof createClient>>;

function createDossierFeatureRpcGateway(
  supabase: ServerSupabaseClient,
): DossierFeatureRpcGateway {
  // Ces deux RPC seront ajoutées à Database lors de la prochaine régénération
  // des types Supabase. Le cast reste volontairement local et surchargé.
  const rpc = supabase.rpc.bind(supabase) as unknown as EntitlementRpcInvoker;
  return {
    async getCapabilities(protectedPersonId) {
      return await rpc("get_protected_person_feature_capabilities", {
        p_protected_person_id: protectedPersonId,
      });
    },
    async checkAccess(input) {
      return await rpc("check_protected_person_feature_access", {
        p_protected_person_id: input.protectedPersonId,
        p_feature_key: input.featureKey,
        p_access_mode: input.accessMode,
      });
    },
  };
}

export async function getDossierFeatureCapabilities(protectedPersonId: string) {
  const supabase = await createClient();
  return loadDossierFeatureCapabilities(
    createDossierFeatureRpcGateway(supabase),
    protectedPersonId,
  );
}

export async function checkDossierFeatureAccess(input: {
  protectedPersonId: string;
  featureKey: DossierFeatureKey;
  accessMode: DossierFeatureAccessMode;
}) {
  const supabase = await createClient();
  return verifyDossierFeatureAccess(createDossierFeatureRpcGateway(supabase), input);
}
