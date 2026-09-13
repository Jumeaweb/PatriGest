import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import type { EmailChangeInput, PasswordInput, ProfileInput } from "./schemas";

type AccountClient = SupabaseClient<Database>;

export class EmailReauthenticationError extends Error {}
export class EmailUnchangedError extends Error {}

export async function loadAccountDataForUser(
  supabase: AccountClient,
  userId: string,
) {
  const [
    { data: userData, error: userError },
    { data: profile, error: profileError },
    { data: administrator, error: administratorError },
  ] = await Promise.all([
    supabase.auth.getUser(),
    supabase.from("profiles").select("first_name,last_name").eq("id", userId).single(),
    supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);

  if (userError || !userData.user?.email) throw new Error("Impossible de charger l’adresse e-mail du compte.");
  if (profileError || !profile) throw new Error("Impossible de charger le profil.");
  if (administratorError) throw new Error("Impossible de vérifier le rôle du compte.");

  return {
    firstName: profile.first_name ?? "",
    lastName: profile.last_name ?? "",
    email: userData.user.email,
    pendingEmail: userData.user.new_email && userData.user.new_email.toLowerCase() !== userData.user.email.toLowerCase()
      ? userData.user.new_email
      : null,
    isPlatformAdmin: Boolean(administrator),
  };
}

export async function updateOwnProfileRow(
  supabase: AccountClient,
  userId: string,
  input: ProfileInput,
) {
  const { data, error } = await supabase
    .from("profiles")
    .update({ first_name: input.firstName, last_name: input.lastName })
    .eq("id", userId)
    .select("id")
    .single();

  if (error || !data) throw new Error("Impossible de modifier le profil.");
}

export async function updateOwnPasswordWithAuth(
  supabase: AccountClient,
  input: PasswordInput,
) {
  return supabase.auth.updateUser({
    password: input.newPassword,
    current_password: input.currentPassword,
  });
}

export async function requestOwnEmailChangeWithAuth(
  supabase: AccountClient,
  userId: string,
  input: EmailChangeInput,
  emailRedirectTo: string,
) {
  const { data: currentUserData, error: currentUserError } = await supabase.auth.getUser();
  const currentUser = currentUserData.user;
  if (currentUserError || !currentUser?.email || currentUser.id !== userId) {
    throw new Error("Impossible de vérifier la session.");
  }

  const currentEmail = currentUser.email.trim().toLowerCase();
  if (input.newEmail === currentEmail) throw new EmailUnchangedError("Adresse e-mail inchangée.");

  const { data: reauthenticated, error: reauthenticationError } = await supabase.auth.signInWithPassword({
    email: currentUser.email,
    password: input.currentPassword,
  });
  if (reauthenticationError || reauthenticated.user?.id !== userId) {
    throw new EmailReauthenticationError("Réauthentification refusée.");
  }

  const { data, error } = await supabase.auth.updateUser(
    { email: input.newEmail },
    { emailRedirectTo },
  );
  if (error || !data.user) throw new Error("Impossible de demander le changement d’adresse e-mail.");

  const returnedEmail = data.user.email?.trim().toLowerCase();
  const pendingEmail = data.user.new_email?.trim().toLowerCase();
  if (pendingEmail === input.newEmail && pendingEmail !== returnedEmail) {
    return { status: "pending" as const, pendingEmail: data.user.new_email as string };
  }
  if (!pendingEmail && returnedEmail === input.newEmail) {
    return { status: "updated" as const };
  }

  throw new Error("État du changement d’adresse e-mail indéterminé.");
}
