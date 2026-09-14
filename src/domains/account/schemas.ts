import { z } from "zod";

export const profileSchema = z.object({
  firstName: z.string().trim().min(1, "Le prénom est obligatoire.").max(80, "Le prénom ne peut pas dépasser 80 caractères."),
  lastName: z.string().trim().min(1, "Le nom est obligatoire.").max(80, "Le nom ne peut pas dépasser 80 caractères."),
});

export const passwordSchema = z.object({
  currentPassword: z.string().min(1, "Saisissez votre mot de passe actuel."),
  newPassword: z.string().min(8, "Le mot de passe doit contenir au moins 8 caractères.").max(72, "Le mot de passe ne peut pas dépasser 72 caractères."),
  passwordConfirmation: z.string(),
}).refine((data) => data.newPassword === data.passwordConfirmation, {
  message: "Les mots de passe ne correspondent pas.",
  path: ["passwordConfirmation"],
}).refine((data) => data.currentPassword !== data.newPassword, {
  message: "Le nouveau mot de passe doit être différent de l’ancien.",
  path: ["newPassword"],
});

export const emailChangeSchema = z.object({
  currentPassword: z.string().min(1, "Saisissez votre mot de passe actuel."),
  newEmail: z.string().trim().toLowerCase().pipe(z.email("Saisissez une adresse e-mail valide.")),
  emailConfirmation: z.string().trim().toLowerCase().pipe(z.email("Saisissez une adresse e-mail valide.")),
}).refine((data) => data.newEmail === data.emailConfirmation, {
  message: "Les adresses e-mail ne correspondent pas.",
  path: ["emailConfirmation"],
});

export const accountDeletionSchema = z.object({
  currentPassword: z.string().min(1, "Saisissez votre mot de passe actuel.").max(72, "Le mot de passe ne peut pas dépasser 72 caractères."),
  confirmation: z.literal("on", { error: "Confirmez la suppression définitive de votre compte." }),
});

export function emailChangeSchemaForCurrentEmail(currentEmail: string) {
  return emailChangeSchema.refine(
    (data) => data.newEmail !== currentEmail.trim().toLowerCase(),
    {
      message: "La nouvelle adresse doit être différente de l’adresse actuelle.",
      path: ["newEmail"],
    },
  );
}

export type ProfileInput = z.infer<typeof profileSchema>;
export type PasswordInput = z.infer<typeof passwordSchema>;
export type EmailChangeInput = z.infer<typeof emailChangeSchema>;
export type AccountDeletionInput = z.infer<typeof accountDeletionSchema>;
