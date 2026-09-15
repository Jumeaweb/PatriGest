"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { managementPeriodSchema } from "./schemas/management-period-schema";
import { protectedPersonSchema } from "./schemas/protected-person-schema";
import { protectionMeasureSchema } from "./schemas/protection-measure-schema";
import {
  createManagementPeriod,
  closeManagementPeriod,
  createProtectedPerson,
  createProtectionMeasure,
  deleteProtectedPerson,
  reopenManagementPeriod,
  updateProtectedPerson,
  updateProtectionMeasure,
  updateManagementPeriod,
} from "./services/protected-person-service";
import type { ProtectedPersonActionState } from "./state";

function validationError(error: z.ZodError): ProtectedPersonActionState {
  return { status: "error", message: "Vérifiez les informations saisies.", fieldErrors: error.flatten().fieldErrors };
}

function protectedPersonValues(formData: FormData) {
  return {
    firstName: formData.get("firstName"), lastName: formData.get("lastName"), birthName: formData.get("birthName"),
    birthDate: formData.get("birthDate"), birthPlace: formData.get("birthPlace"), addressLine1: formData.get("addressLine1"),
    addressLine2: formData.get("addressLine2"), postalCode: formData.get("postalCode"), city: formData.get("city"),
    country: formData.get("country"), phone: formData.get("phone"), email: formData.get("email"),
    residenceAddressLine1: formData.get("residenceAddressLine1"), residenceAddressLine2: formData.get("residenceAddressLine2"),
    residencePostalCode: formData.get("residencePostalCode"), residenceCity: formData.get("residenceCity"), residenceCountry: formData.get("residenceCountry"),
  };
}

function protectionMeasureValues(formData: FormData) {
  return {
    measureType: formData.get("measureType"), startDate: formData.get("startDate"), decisionDate: formData.get("decisionDate"),
    caseReference: formData.get("caseReference"), courtCabinet: formData.get("courtCabinet"), courtName: formData.get("courtName"), courtCity: formData.get("courtCity"),
    representativeFirstName: formData.get("representativeFirstName"), representativeLastName: formData.get("representativeLastName"),
    representativeAppointmentDate: formData.get("representativeAppointmentDate"), representativeAddressLine1: formData.get("representativeAddressLine1"),
    representativeAddressLine2: formData.get("representativeAddressLine2"), representativePostalCode: formData.get("representativePostalCode"),
    representativeCity: formData.get("representativeCity"), representativeCountry: formData.get("representativeCountry"),
    representativePhone: formData.get("representativePhone"), representativeEmail: formData.get("representativeEmail"),
  };
}

export async function createProtectedPersonAction(
  _state: ProtectedPersonActionState,
  formData: FormData,
): Promise<ProtectedPersonActionState> {
  const parsed = protectedPersonSchema.safeParse(protectedPersonValues(formData));
  if (!parsed.success) return validationError(parsed.error);

  let person;
  try {
    person = await createProtectedPerson(parsed.data);
  } catch {
    return { status: "error", message: "Impossible de créer le dossier. Veuillez réessayer." };
  }

  revalidatePath("/dossiers");
  revalidatePath("/tableau-de-bord");
  redirect(`/dossiers/${person.id}`);
}

export async function addProtectionMeasureAction(
  protectedPersonId: string,
  _state: ProtectedPersonActionState,
  formData: FormData,
): Promise<ProtectedPersonActionState> {
  if (!z.uuid().safeParse(protectedPersonId).success) return { status: "error", message: "Dossier invalide." };
  const parsed = protectionMeasureSchema.safeParse(protectionMeasureValues(formData));
  if (!parsed.success) return validationError(parsed.error);

  try {
    await createProtectionMeasure(protectedPersonId, parsed.data);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    return { status: "success", message: "La mesure de protection a été ajoutée." };
  } catch {
    return { status: "error", message: "Impossible d’ajouter la mesure. Veuillez réessayer." };
  }
}

export async function updateProtectedPersonAction(protectedPersonId: string, _state: ProtectedPersonActionState, formData: FormData): Promise<ProtectedPersonActionState> {
  if (!z.uuid().safeParse(protectedPersonId).success) return { status: "error", message: "Dossier invalide." };
  const parsed = protectedPersonSchema.safeParse(protectedPersonValues(formData));
  if (!parsed.success) return validationError(parsed.error);
  try {
    await updateProtectedPerson(protectedPersonId, parsed.data);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    return { status: "success", message: "Les informations de la personne protégée ont été modifiées." };
  } catch {
    return { status: "error", message: "Impossible de modifier ces informations." };
  }
}

export async function updateProtectionMeasureAction(protectedPersonId: string, measureId: string, _state: ProtectedPersonActionState, formData: FormData): Promise<ProtectedPersonActionState> {
  if (![protectedPersonId, measureId].every((id) => z.uuid().safeParse(id).success)) return { status: "error", message: "Mesure invalide." };
  const parsed = protectionMeasureSchema.safeParse(protectionMeasureValues(formData));
  if (!parsed.success) return validationError(parsed.error);
  try {
    await updateProtectionMeasure(protectedPersonId, measureId, parsed.data);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    return { status: "success", message: "La mesure de protection a été modifiée." };
  } catch {
    return { status: "error", message: "Impossible de modifier la mesure de protection." };
  }
}

export async function deleteProtectedPersonAction(protectedPersonId: string, _state: ProtectedPersonActionState, _formData: FormData): Promise<ProtectedPersonActionState> {
  void _state;
  void _formData;
  if (!z.uuid().safeParse(protectedPersonId).success) return { status: "error", message: "Dossier invalide." };
  try { await deleteProtectedPerson(protectedPersonId); }
  catch (error) { return { status: "error", message: error instanceof Error ? error.message : "Impossible de supprimer ce dossier." }; }
  revalidatePath("/dossiers");
  revalidatePath("/tableau-de-bord");
  redirect("/dossiers");
}

export async function addManagementPeriodAction(
  protectedPersonId: string,
  _state: ProtectedPersonActionState,
  formData: FormData,
): Promise<ProtectedPersonActionState> {
  if (!z.uuid().safeParse(protectedPersonId).success) return { status: "error", message: "Dossier invalide." };
  const parsed = managementPeriodSchema.safeParse({ startDate: formData.get("startDate"), endDate: formData.get("endDate") });
  if (!parsed.success) return validationError(parsed.error);

  try {
    await createManagementPeriod(protectedPersonId, parsed.data);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    revalidatePath(`/dossiers/${protectedPersonId}/exercices`);
    return { status: "success", message: "L’exercice de gestion a été créé." };
  } catch {
    return { status: "error", message: "Impossible de créer l’exercice. Vérifiez qu’il n’existe pas déjà." };
  }
}

export async function updateManagementPeriodAction(protectedPersonId: string, periodId: string, _state: ProtectedPersonActionState, formData: FormData): Promise<ProtectedPersonActionState> {
  if (![protectedPersonId, periodId].every((id) => z.uuid().safeParse(id).success)) return { status: "error", message: "Exercice invalide." };
  const parsed = managementPeriodSchema.safeParse({ startDate: formData.get("startDate"), endDate: formData.get("endDate") });
  if (!parsed.success) return validationError(parsed.error);
  try { await updateManagementPeriod(protectedPersonId, periodId, parsed.data); revalidatePath(`/dossiers/${protectedPersonId}`); revalidatePath(`/dossiers/${protectedPersonId}/exercices`); return { status: "success", message: "L’exercice a été modifié." }; }
  catch { return { status: "error", message: "Impossible de modifier cet exercice." }; }
}

export async function closeManagementPeriodAction(protectedPersonId: string, periodId: string) {
  if (![protectedPersonId, periodId].every((id) => z.uuid().safeParse(id).success)) return;
  await closeManagementPeriod(protectedPersonId, periodId);
  revalidatePath(`/dossiers/${protectedPersonId}`);
  revalidatePath(`/dossiers/${protectedPersonId}/exercices`);
  redirect(`/dossiers/${protectedPersonId}/exercices`);
}

export async function reopenManagementPeriodAction(protectedPersonId: string, periodId: string, _state: ProtectedPersonActionState, _formData: FormData): Promise<ProtectedPersonActionState> {
  void _state;
  void _formData;
  if (![protectedPersonId, periodId].every((id) => z.uuid().safeParse(id).success)) return { status: "error", message: "Exercice invalide." };
  try {
    await reopenManagementPeriod(protectedPersonId, periodId);
    revalidatePath(`/dossiers/${protectedPersonId}`);
    revalidatePath(`/dossiers/${protectedPersonId}/exercices`);
    return { status: "success", message: "L’exercice a été réouvert." };
  } catch {
    return { status: "error", message: "Impossible de réouvrir cet exercice." };
  }
}
