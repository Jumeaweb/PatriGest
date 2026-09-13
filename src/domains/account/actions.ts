"use server";

import { revalidatePath } from "next/cache";
import { passwordSchema, profileSchema } from "./schemas";
import { updateOwnPassword, updateOwnProfile } from "./services";
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
