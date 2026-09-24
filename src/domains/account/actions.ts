"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getAuthCallbackOrigin } from "@/lib/auth/redirects";
import { EmailReauthenticationError, EmailUnchangedError } from "./account-operations";
import { AccountDeletionBlockedError, AccountDeletionReauthenticationError } from "./account-deletion-operations";
import { accountDeletionSchema, emailChangeSchema, passwordSchema, profileSchema } from "./schemas";
import { deleteOwnAccount, requestOwnEmailChange, updateOwnPassword, updateOwnProfile } from "./services";
import type { AccountActionState } from "./state";

function validationError(fieldErrors: Record<string, string[] | undefined>): AccountActionState {
  return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: Object.fromEntries(Object.entries(fieldErrors).filter((entry): entry is [string, string[]] => Boolean(entry[1]))) };
}

export async function updateProfileAction(_state: AccountActionState, formData: FormData): Promise<AccountActionState> {
  const parsed = profileSchema.safeParse({ firstName: formData.get("firstName"), lastName: formData.get("lastName") });
  if (!parsed.success) return validationError(parsed.error.flatten().fieldErrors);
  try {
    await updateOwnProfile(parsed.data);
    revalidatePath("/parametres/compte");
    return { status: "success", message: "Profil modifié." };
  } catch {
    return { status: "error", message: "Impossible de modifier le profil. Réessayez." };
  }
}

export async function updatePasswordAction(_state: AccountActionState, formData: FormData): Promise<AccountActionState> {
  const parsed = passwordSchema.safeParse({
    currentPassword: formData.get("currentPassword"),
    newPassword: formData.get("newPassword"),
    passwordConfirmation: formData.get("passwordConfirmation"),
  });
  if (!parsed.success) return validationError(parsed.error.flatten().fieldErrors);

  try {
    const { error } = await updateOwnPassword(parsed.data);
    if (error?.code === "current_password_invalid" || error?.code === "current_password_mismatch" || error?.code === "invalid_credentials" || error?.code === "bad_password") {
      return { status: "error", message: "Le mot de passe actuel est incorrect.", fieldErrors: { currentPassword: ["Vérifiez votre mot de passe actuel."] } };
    }
    if (error?.code === "same_password") {
      return { status: "error", message: "Choisissez un mot de passe différent.", fieldErrors: { newPassword: ["Le nouveau mot de passe doit être différent de l’ancien."] } };
    }
    if (error) return { status: "error", message: "Impossible de modifier le mot de passe. Reconnectez-vous puis réessayez." };
    return { status: "success", message: "Mot de passe modifié." };
  } catch {
    return { status: "error", message: "Votre session n’est plus valide. Reconnectez-vous puis réessayez." };
  }
}

export async function requestEmailChangeAction(_state: AccountActionState, formData: FormData): Promise<AccountActionState> {
  const parsed = emailChangeSchema.safeParse({
    currentPassword: formData.get("currentPassword"),
    newEmail: formData.get("newEmail"),
    emailConfirmation: formData.get("emailConfirmation"),
  });
  if (!parsed.success) return validationError(parsed.error.flatten().fieldErrors);

  try {
    const origin = await getAuthCallbackOrigin();
    const emailRedirectTo = `${origin}/auth/callback?next=${encodeURIComponent("/parametres/compte?vue=email")}`;
    const result = await requestOwnEmailChange(parsed.data, emailRedirectTo);
    revalidatePath("/parametres/compte");
    if (result.status === "pending") {
      return {
        status: "success",
        message: "Votre demande de changement d’adresse e-mail a été enregistrée. Consultez les messages de confirmation envoyés par PatriGest pour terminer la modification.",
      };
    }
    return { status: "success", message: "Votre adresse e-mail a été mise à jour." };
  } catch (error) {
    if (error instanceof EmailUnchangedError) {
      return {
        status: "error",
        message: "Vérifiez la nouvelle adresse e-mail.",
        fieldErrors: { newEmail: ["La nouvelle adresse doit être différente de l’adresse actuelle."] },
      };
    }
    if (error instanceof EmailReauthenticationError) {
      return {
        status: "error",
        message: "Le mot de passe actuel est incorrect ou n’a pas pu être vérifié.",
        fieldErrors: { currentPassword: ["Vérifiez votre mot de passe actuel."] },
      };
    }
    return { status: "error", message: "Impossible d’enregistrer la demande de changement d’adresse e-mail. Réessayez ultérieurement." };
  }
}

export async function deleteOwnAccountAction(_state: AccountActionState, formData: FormData): Promise<AccountActionState> {
  const parsed = accountDeletionSchema.safeParse({
    currentPassword: formData.get("currentPassword"),
    confirmation: formData.get("confirmation"),
  });
  if (!parsed.success) return validationError(parsed.error.flatten().fieldErrors);

  try {
    await deleteOwnAccount(parsed.data);
  } catch (error) {
    if (error instanceof AccountDeletionReauthenticationError) {
      return {
        status: "error",
        message: "Le mot de passe actuel est incorrect ou n’a pas pu être vérifié.",
        fieldErrors: { currentPassword: ["Vérifiez votre mot de passe actuel."] },
      };
    }
    if (error instanceof AccountDeletionBlockedError) {
      return {
        status: "error",
        message: error.reason === "blocked_owned_dossiers"
          ? "Transférez ou supprimez les dossiers dont vous êtes propriétaire avant de supprimer votre compte."
          : "Un administrateur PatriGest ne peut pas supprimer son propre compte.",
      };
    }
    return { status: "error", message: "Impossible de supprimer votre compte. Réessayez ultérieurement." };
  }

  redirect("/");
}
