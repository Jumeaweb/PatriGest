import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { ACCOUNT_TRIAL_TERMS_VERSION } from "./constants";
import { parseAccountTrialState } from "./trial-state";

export async function recordAccountTrialTermsAcceptance(userId: string) {
  const admin = createAdminClient();
  const { error } = await admin.rpc("record_account_trial_terms_acceptance", {
    p_user_id: userId,
    p_terms_version: ACCOUNT_TRIAL_TERMS_VERSION,
  });
  if (error) throw new Error("TRIAL_TERMS_RECORDING_FAILED");
}

export async function getCurrentAccountTrialState() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_current_account_trial_state");
  if (error) throw new Error("Impossible de charger l’état de la période d’essai.");
  try {
    return parseAccountTrialState(data);
  } catch {
    throw new Error("L’état de la période d’essai est invalide.");
  }
}
