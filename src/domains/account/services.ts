import "server-only";

import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import type { PasswordInput, ProfileInput } from "./schemas";
import {
  loadAccountDataForUser,
  updateOwnPasswordWithAuth,
  updateOwnProfileRow,
} from "./account-operations";

export async function getAccountData() {
  const { supabase, userId } = await getAuthenticatedUser();
  return loadAccountDataForUser(supabase, userId);
}

export async function updateOwnProfile(input: ProfileInput) {
  const { supabase, userId } = await getAuthenticatedUser();
  await updateOwnProfileRow(supabase, userId, input);
}

export async function updateOwnPassword(input: PasswordInput) {
  const { supabase } = await getAuthenticatedUser();
  return updateOwnPasswordWithAuth(supabase, input);
}
