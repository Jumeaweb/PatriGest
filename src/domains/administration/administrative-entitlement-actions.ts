"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requirePlatformAdministrator } from "./services/administration-service";
import type { AdministrativeEntitlementActionState } from "./state";

const nullableOverridePlan = z.preprocess((value) => value === "" ? null : value, z.enum(["comfort", "premium"]).nullable());
const nullableOverrideCapacity = z.preprocess((value) => value === "" ? null : value, z.enum(["five", "ten"]).nullable());
const optionalEntityId = z.preprocess((value) => value === "" ? null : value, z.uuid().nullable());

const mutationSchema = z.object({
  entityType: z.enum(["plan", "override"]),
  operation: z.enum(["assign", "replace", "revoke"]),
  ownerId: z.uuid(),
  entityId: optionalEntityId,
  expectedRevision: z.coerce.number().int().nonnegative(),
  requestId: z.uuid(),
  reason: z.string().trim().min(1, "Le motif est obligatoire.").max(2000, "Le motif ne peut pas dépasser 2 000 caractères."),
  planKey: z.enum(["essential", "comfort", "premium"]).optional(),
  billingPeriod: z.enum(["monthly", "annual"]).optional(),
  capacityKey: z.enum(["included", "five", "ten"]).optional(),
  featurePlanKey: nullableOverridePlan.optional(),
  overrideCapacityKey: nullableOverrideCapacity.optional(),
}).superRefine((value, context) => {
  if (value.operation !== "assign" && !value.entityId) {
    context.addIssue({ code: "custom", message: "Référence administrative manquante.", path: ["entityId"] });
  }
  if (value.operation === "assign" && (value.entityId || value.expectedRevision !== 0)) {
    context.addIssue({ code: "custom", message: "Révision initiale invalide.", path: ["expectedRevision"] });
  }
  if (value.entityType === "plan" && value.operation !== "revoke") {
    if (!value.planKey || !value.billingPeriod || !value.capacityKey) {
      context.addIssue({ code: "custom", message: "Formule, périodicité ou capacité manquante.", path: ["planKey"] });
    } else if (value.planKey === "essential" && value.capacityKey !== "included") {
      context.addIssue({ code: "custom", message: "Essentiel est limité à 2 dossiers actifs.", path: ["capacityKey"] });
    }
  }
  if (value.entityType === "override" && value.operation !== "revoke"
      && !value.featurePlanKey && !value.overrideCapacityKey) {
    context.addIssue({ code: "custom", message: "La dérogation doit modifier au moins un droit.", path: ["featurePlanKey"] });
  }
});

type RpcError = { code?: string; message?: string };

function administrativeMutationError(error: RpcError): string {
  const messages: Record<string, string> = {
    "40001": "Les droits ont été modifiés depuis leur affichage. Actualisez la page avant de recommencer.",
    "42501": "Vous n’êtes pas autorisé à modifier ces droits.",
    P5A02: "Cette demande ne correspond plus à l’intention initiale. Fermez puis recommencez l’opération.",
    P5A04: "Ce compte n’est pas éligible à une attribution administrative.",
    P5A05: "Un abonnement commercial actif interdit cette attribution administrative.",
    P5A06: "L’attribution active est introuvable ou a déjà été modifiée.",
    P5A07: "Révoquez d’abord la dérogation active.",
    P5A08: "Une attribution administrative est déjà active.",
    P5A09: "La formule ou la capacité choisie est invalide.",
    P5A10: "Une base commerciale ou administrative active est requise pour cette dérogation.",
    P5A11: "Le niveau fonctionnel choisi est invalide.",
    P5A12: "La capacité de dérogation choisie est invalide.",
    P5A13: "Cette capacité est inférieure au nombre de dossiers actifs du compte.",
    P5A14: "La dérogation active est introuvable ou a déjà été modifiée.",
    P5A15: "Une dérogation administrative est déjà active.",
    P5A16: "La dérogation doit modifier au moins un droit.",
    P5A17: "Une suppression de compte en cours interdit cette modification.",
  };
  return error.code && messages[error.code]
    ? messages[error.code]
    : "Impossible d’enregistrer cette modification administrative.";
}

export async function mutateAdministrativeEntitlementAction(
  _state: AdministrativeEntitlementActionState,
  formData: FormData,
): Promise<AdministrativeEntitlementActionState> {
  void _state;
  const parsed = mutationSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    const fields = parsed.error.flatten().fieldErrors;
    return {
      status: "error",
      message: parsed.error.issues[0]?.message ?? "Vérifiez les informations saisies.",
      fieldErrors: { reason: fields.reason },
    };
  }

  const { supabase, userId } = await requirePlatformAdministrator();
  const input = parsed.data;
  if (input.ownerId === userId) {
    return { status: "error", message: "Vous ne pouvez pas modifier vos propres droits depuis cet écran." };
  }

  let error: RpcError | null = null;
  if (input.entityType === "plan") {
    if (input.operation === "assign") {
      ({ error } = await supabase.rpc("assign_administrative_plan", {
        p_owner_id: input.ownerId,
        p_plan_key: input.planKey!,
        p_billing_period: input.billingPeriod!,
        p_dossier_capacity_key: input.capacityKey!,
        p_reason: input.reason,
        p_request_id: input.requestId,
        p_expected_revision: 0,
      }));
    } else if (input.operation === "replace") {
      ({ error } = await supabase.rpc("replace_administrative_plan", {
        p_owner_id: input.ownerId,
        p_assignment_id: input.entityId!,
        p_plan_key: input.planKey!,
        p_billing_period: input.billingPeriod!,
        p_dossier_capacity_key: input.capacityKey!,
        p_reason: input.reason,
        p_request_id: input.requestId,
        p_expected_revision: input.expectedRevision,
      }));
    } else {
      ({ error } = await supabase.rpc("revoke_administrative_plan", {
        p_owner_id: input.ownerId,
        p_assignment_id: input.entityId!,
        p_reason: input.reason,
        p_request_id: input.requestId,
        p_expected_revision: input.expectedRevision,
      }));
    }
  } else if (input.operation === "assign") {
    ({ error } = await supabase.rpc("assign_administrative_entitlement_override", {
      p_owner_id: input.ownerId,
      p_feature_plan_key: input.featurePlanKey ?? null,
      p_dossier_capacity_key: input.overrideCapacityKey ?? null,
      p_reason: input.reason,
      p_request_id: input.requestId,
      p_expected_revision: 0,
    }));
  } else if (input.operation === "replace") {
    ({ error } = await supabase.rpc("replace_administrative_entitlement_override", {
      p_owner_id: input.ownerId,
      p_override_id: input.entityId!,
      p_feature_plan_key: input.featurePlanKey ?? null,
      p_dossier_capacity_key: input.overrideCapacityKey ?? null,
      p_reason: input.reason,
      p_request_id: input.requestId,
      p_expected_revision: input.expectedRevision,
    }));
  } else {
    ({ error } = await supabase.rpc("revoke_administrative_entitlement_override", {
      p_owner_id: input.ownerId,
      p_override_id: input.entityId!,
      p_reason: input.reason,
      p_request_id: input.requestId,
      p_expected_revision: input.expectedRevision,
    }));
  }

  if (error) return { status: "error", message: administrativeMutationError(error) };
  revalidatePath("/administration/utilisateurs");
  return { status: "success", message: "Les droits administratifs ont été enregistrés et audités." };
}
