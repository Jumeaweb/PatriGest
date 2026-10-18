import { z } from "zod";

export const protectedPersonArchiveTransitionSchema = z.object({
  protectedPersonId: z.uuid("Dossier invalide."),
  expectedRevision: z.number().int().positive("Révision invalide."),
  reason: z.string()
    .trim()
    .min(1, "Saisissez un motif.")
    .max(2000, "Le motif ne peut pas dépasser 2 000 caractères."),
}).strict();

export type ProtectedPersonArchiveTransitionInput = z.infer<
  typeof protectedPersonArchiveTransitionSchema
>;

export type ProtectedPersonArchiveTransitionOperation = "archive" | "restore";

export type ProtectedPersonArchiveTransitionResult = {
  archiveRevision: number;
};

export type ProtectedPersonArchiveTransitionErrorCode =
  | "forbidden"
  | "not_found"
  | "invalid_reason"
  | "incompatible_state"
  | "stale_revision"
  | "quota_reached"
  | "subscription_missing"
  | "configuration_unavailable"
  | "rpc_unavailable"
  | "invalid_response"
  | "technical";

export const PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES = {
  forbidden: "Vous ne disposez pas des droits nécessaires pour archiver ou restaurer ce dossier.",
  not_found: "Dossier introuvable.",
  invalid_reason: "Le motif d’archivage ou de restauration est invalide.",
  incompatible_state: "Le dossier n’est pas dans un état compatible avec cette opération.",
  stale_revision: "Ce dossier a changé depuis l’ouverture du formulaire. Actualisez la page puis réessayez.",
  quota_reached: "Vous avez atteint le nombre maximal de dossiers actifs autorisé par votre abonnement.",
  subscription_missing: "Aucun abonnement actif ne permet actuellement de créer ou de restaurer un dossier.",
  configuration_unavailable: "La capacité de votre abonnement est temporairement indisponible.",
  rpc_unavailable: "Le service d’archivage des dossiers est temporairement indisponible.",
  invalid_response: "La réponse du service d’archivage des dossiers est invalide.",
  technical: "Impossible de modifier l’archivage du dossier pour le moment.",
} as const satisfies Record<ProtectedPersonArchiveTransitionErrorCode, string>;

export class ProtectedPersonArchiveTransitionError extends Error {
  readonly code: ProtectedPersonArchiveTransitionErrorCode;

  constructor(code: ProtectedPersonArchiveTransitionErrorCode, message?: string) {
    super(message ?? PROTECTED_PERSON_ARCHIVE_TRANSITION_ERROR_MESSAGES[code]);
    this.name = "ProtectedPersonArchiveTransitionError";
    this.code = code;
  }
}

export type ProtectedPersonArchiveRpcError = {
  code?: string | null;
  message?: string | null;
};

export type ProtectedPersonArchiveRpcResult = {
  data: unknown;
  error: ProtectedPersonArchiveRpcError | null;
};

export interface ProtectedPersonArchiveRpcGateway {
  transition(
    operation: ProtectedPersonArchiveTransitionOperation,
    input: ProtectedPersonArchiveTransitionInput,
  ): Promise<ProtectedPersonArchiveRpcResult>;
}

export type DossierCapacityTransitionErrorMapper = (
  error: ProtectedPersonArchiveRpcError,
) => { code: string; message: string };

const archiveRevisionSchema = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);

export function mapProtectedPersonArchiveRpcError(
  error: ProtectedPersonArchiveRpcError | null | undefined,
  mapCapacityError?: DossierCapacityTransitionErrorMapper,
): ProtectedPersonArchiveTransitionError {
  switch (error?.code) {
    case "P4A01":
    case "42501":
      return new ProtectedPersonArchiveTransitionError("forbidden");
    case "P4A02":
      return new ProtectedPersonArchiveTransitionError("not_found");
    case "P4A03":
      return new ProtectedPersonArchiveTransitionError("invalid_reason");
    case "P4A04":
      return new ProtectedPersonArchiveTransitionError("incompatible_state");
    case "P4A05":
      return new ProtectedPersonArchiveTransitionError("stale_revision");
    case "P4D01":
    case "P4D02":
    case "P4D03": {
      const failure = mapCapacityError?.(error);
      if (failure?.code === "quota_reached"
          || failure?.code === "subscription_missing"
          || failure?.code === "configuration_unavailable") {
        return new ProtectedPersonArchiveTransitionError(failure.code, failure.message);
      }
      return new ProtectedPersonArchiveTransitionError("technical");
    }
    case "PGRST202":
    case "42883":
      return new ProtectedPersonArchiveTransitionError("rpc_unavailable");
    default:
      return new ProtectedPersonArchiveTransitionError("technical");
  }
}

export async function executeProtectedPersonArchiveTransition(
  gateway: ProtectedPersonArchiveRpcGateway,
  operation: ProtectedPersonArchiveTransitionOperation,
  input: ProtectedPersonArchiveTransitionInput,
  mapCapacityError?: DossierCapacityTransitionErrorMapper,
): Promise<ProtectedPersonArchiveTransitionResult> {
  let result: ProtectedPersonArchiveRpcResult;
  try {
    result = await gateway.transition(operation, input);
  } catch {
    throw new ProtectedPersonArchiveTransitionError("technical");
  }

  if (result.error) {
    throw mapProtectedPersonArchiveRpcError(result.error, mapCapacityError);
  }

  const revision = archiveRevisionSchema.safeParse(result.data);
  if (!revision.success) {
    throw new ProtectedPersonArchiveTransitionError("invalid_response");
  }

  return { archiveRevision: revision.data };
}
