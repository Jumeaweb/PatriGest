import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import type { EmailChangeInput, PasswordInput, ProfileInput } from "./schemas";

type AccountClient = SupabaseClient<Database>;

export class EmailReauthenticationError extends Error {}
export class EmailUnchangedError extends Error {}
export class PendingEmailChangeError extends Error {}
export class EmailAddressCollisionError extends Error {}

const EMAIL_COLLISION_MESSAGE = "Cette adresse e-mail est déjà utilisée ou réservée dans PatriGest.";

async function assertOwnEmailChangeAvailable(
  supabase: AccountClient,
  newEmail: string,
) {
  const { data, error } = await supabase.rpc("check_own_email_change_availability", {
    p_new_email: newEmail,
  });
  if (!error && data === true) return;
  if (error?.message?.includes(EMAIL_COLLISION_MESSAGE)) {
    throw new EmailAddressCollisionError(EMAIL_COLLISION_MESSAGE);
  }
  throw new Error("Impossible de vérifier la disponibilité de l’adresse e-mail.");
}

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
  const pendingEmail = currentUser.new_email?.trim().toLowerCase();
  if (input.newEmail === currentEmail) throw new EmailUnchangedError("Adresse e-mail inchangée.");
  if (pendingEmail && pendingEmail !== currentEmail) {
    throw new PendingEmailChangeError("Un changement d’adresse e-mail est déjà en attente.");
  }

  const { data: reauthenticated, error: reauthenticationError } = await supabase.auth.signInWithPassword({
    email: currentUser.email,
    password: input.currentPassword,
  });
  if (reauthenticationError || reauthenticated.user?.id !== userId) {
    throw new EmailReauthenticationError("Réauthentification refusée.");
  }

  await assertOwnEmailChangeAvailable(supabase, input.newEmail);

  const { data, error } = await supabase.auth.updateUser(
    { email: input.newEmail },
    { emailRedirectTo },
  );
  if (error || !data.user) {
    if (error?.code === "email_exists") {
      throw new EmailAddressCollisionError(EMAIL_COLLISION_MESSAGE);
    }

    // Une invitation ou réservation peut avoir gagné la course après le
    // pré-contrôle. Le second contrôle transforme ce rejet DB en erreur UX
    // explicite sans exposer la nature du tiers.
    try {
      await assertOwnEmailChangeAvailable(supabase, input.newEmail);
    } catch (availabilityError) {
      if (availabilityError instanceof EmailAddressCollisionError) throw availabilityError;
    }
    throw new Error("Impossible de demander le changement d’adresse e-mail.");
  }

  const returnedEmail = data.user.email?.trim().toLowerCase();
  const returnedPendingEmail = data.user.new_email?.trim().toLowerCase();
  if (returnedPendingEmail === input.newEmail && returnedPendingEmail !== returnedEmail) {
    return { status: "pending" as const, pendingEmail: data.user.new_email as string };
  }
  if (!returnedPendingEmail && returnedEmail === input.newEmail) {
    return { status: "updated" as const };
  }

  throw new Error("État du changement d’adresse e-mail indéterminé.");
}

export async function resendOwnEmailChangeWithAuth(
  supabase: AccountClient,
  userId: string,
  emailRedirectTo: string,
) {
  const { data: currentUserData, error: currentUserError } = await supabase.auth.getUser();
  const currentUser = currentUserData.user;
  const currentEmail = currentUser?.email?.trim().toLowerCase();
  const pendingEmail = currentUser?.new_email?.trim().toLowerCase();

  if (currentUserError || !currentUser || currentUser.id !== userId || !currentEmail) {
    throw new Error("Impossible de vérifier la session.");
  }
  if (!pendingEmail || pendingEmail === currentEmail) {
    throw new PendingEmailChangeError("Aucun changement d’adresse e-mail n’est en attente.");
  }

  const { error } = await supabase.auth.resend({
    type: "email_change",
    email: currentEmail,
    options: { emailRedirectTo },
  });
  if (error) throw new Error("Impossible de renvoyer les confirmations du changement d’adresse e-mail.");
}
