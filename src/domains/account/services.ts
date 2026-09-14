import "server-only";

import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { createAdminClient } from "@/lib/supabase/admin";
import type { AccountDeletionInput, EmailChangeInput, PasswordInput, ProfileInput } from "./schemas";
import {
  loadAccountDataForUser,
  requestOwnEmailChangeWithAuth,
  updateOwnPasswordWithAuth,
  updateOwnProfileRow,
} from "./account-operations";
import { deleteAccountWithVerifiedDependencies, getAccountDeletionEligibility } from "./account-deletion-operations";

export async function getAccountData() {
  const { supabase, userId } = await getAuthenticatedUser();
  const [account, deletionEligibility] = await Promise.all([
    loadAccountDataForUser(supabase, userId),
    getAccountDeletionEligibility(supabase, userId),
  ]);
  return { ...account, deletionEligibility };
}

export async function updateOwnProfile(input: ProfileInput) {
  const { supabase, userId } = await getAuthenticatedUser();
  await updateOwnProfileRow(supabase, userId, input);
}

export async function updateOwnPassword(input: PasswordInput) {
  const { supabase } = await getAuthenticatedUser();
  return updateOwnPasswordWithAuth(supabase, input);
}

export async function requestOwnEmailChange(input: EmailChangeInput, emailRedirectTo: string) {
  const { supabase, userId } = await getAuthenticatedUser();
  return requestOwnEmailChangeWithAuth(supabase, userId, input, emailRedirectTo);
}

export async function deleteOwnAccount(input: AccountDeletionInput) {
  const { supabase, userId } = await getAuthenticatedUser();
  await deleteAccountWithVerifiedDependencies(supabase, createAdminClient(), userId, input);
}
