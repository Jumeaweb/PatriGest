import { z } from "zod";

export const DOSSIER_CAPACITY_STATES = [
  "unlimited",
  "available",
  "reached",
  "exceeded",
] as const;

export type DossierCapacityState = (typeof DOSSIER_CAPACITY_STATES)[number];

type DossierCapacityValues = {
  activeDossierCount: number;
  exceededBy: number;
};

export type OwnedDossierCapacity =
  | DossierCapacityValues & {
      state: "unlimited";
      unlimited: true;
      activeDossierLimit: null;
      remainingDossierCount: null;
      exceededBy: 0;
    }
  | DossierCapacityValues & {
      state: "available" | "reached" | "exceeded";
      unlimited: false;
      activeDossierLimit: number;
      remainingDossierCount: number;
    };

export type DossierCapacityErrorCode =
  | "quota_reached"
  | "subscription_missing"
  | "configuration_unavailable"
  | "access_denied"
  | "rpc_unavailable"
  | "invalid_response"
  | "technical";

export type DossierCapacityFailure = {
  code: DossierCapacityErrorCode;
  message: string;
};

export class DossierCapacityServiceError extends Error {
  readonly code: DossierCapacityErrorCode;

  constructor(failure: DossierCapacityFailure) {
    super(failure.message);
    this.name = "DossierCapacityServiceError";
    this.code = failure.code;
  }
}

export type DossierCapacityRpcError = {
  code?: string | null;
  message?: string | null;
};

export type DossierCapacityRpcResult = {
  data: unknown;
  error: DossierCapacityRpcError | null;
};

export interface DossierCapacityRpcGateway {
  getOwnedCapacity(): Promise<DossierCapacityRpcResult>;
}

export const DOSSIER_CAPACITY_ERROR_MESSAGES = {
  quota_reached: "Vous avez atteint le nombre maximal de dossiers actifs autorisé par votre abonnement.",
  subscription_missing: "Aucun abonnement actif ne permet actuellement de créer ou de restaurer un dossier.",
  configuration_unavailable: "La capacité de votre abonnement est temporairement indisponible.",
  access_denied: "Vous ne disposez pas des droits nécessaires pour consulter cette capacité.",
  rpc_unavailable: "Le service de capacité des dossiers est temporairement indisponible.",
  invalid_response: "La réponse du service de capacité des dossiers est invalide.",
  technical: "Impossible de vérifier la capacité des dossiers pour le moment.",
} as const satisfies Record<DossierCapacityErrorCode, string>;

const safeCountSchema = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);

const capacityRowSchema = z.object({
  unlimited: z.boolean(),
  active_dossier_limit: safeCountSchema.min(1).nullable(),
  active_dossier_count: safeCountSchema,
  remaining_dossier_count: safeCountSchema.nullable(),
  exceeded_by: safeCountSchema,
}).strict().superRefine((row, context) => {
  if (row.unlimited) {
    if (row.active_dossier_limit !== null || row.remaining_dossier_count !== null) {
      context.addIssue({ code: "custom", message: "Capacité illimitée incohérente." });
    }
    if (row.exceeded_by !== 0) {
      context.addIssue({ code: "custom", message: "Dépassement illimité incohérent." });
    }
    return;
  }

  if (row.active_dossier_limit === null || row.remaining_dossier_count === null) {
    context.addIssue({ code: "custom", message: "Capacité plafonnée incomplète." });
    return;
  }

  if (row.remaining_dossier_count !== Math.max(
    row.active_dossier_limit - row.active_dossier_count,
    0,
  )) {
    context.addIssue({ code: "custom", message: "Nombre de places restantes incohérent." });
  }
  if (row.exceeded_by !== Math.max(
    row.active_dossier_count - row.active_dossier_limit,
    0,
  )) {
    context.addIssue({ code: "custom", message: "Dépassement incohérent." });
  }
});

const capacityRowsSchema = z.array(capacityRowSchema).length(1);

export function parseOwnedDossierCapacity(value: unknown): OwnedDossierCapacity {
  const [row] = capacityRowsSchema.parse(value);

  if (row.unlimited) {
    return {
      state: "unlimited",
      unlimited: true,
      activeDossierLimit: null,
      activeDossierCount: row.active_dossier_count,
      remainingDossierCount: null,
      exceededBy: 0,
    };
  }

  const activeDossierLimit = row.active_dossier_limit as number;
  const remainingDossierCount = row.remaining_dossier_count as number;
  const state = row.exceeded_by > 0
    ? "exceeded"
    : remainingDossierCount === 0
      ? "reached"
      : "available";

  return {
    state,
    unlimited: false,
    activeDossierLimit,
    activeDossierCount: row.active_dossier_count,
    remainingDossierCount,
    exceededBy: row.exceeded_by,
  };
}

function failure(code: DossierCapacityErrorCode): DossierCapacityFailure {
  return { code, message: DOSSIER_CAPACITY_ERROR_MESSAGES[code] };
}

export function mapDossierCapacityRpcError(
  error: DossierCapacityRpcError | null | undefined,
): DossierCapacityFailure {
  switch (error?.code) {
    case "P4D01":
      return failure("quota_reached");
    case "P4D02":
      return failure("subscription_missing");
    case "P4D03":
      return failure("configuration_unavailable");
    case "42501":
      return failure("access_denied");
    case "PGRST202":
    case "42883":
      return failure("rpc_unavailable");
    default:
      return failure("technical");
  }
}

export function classifyDossierCapacityMutationError(
  error: DossierCapacityRpcError | null | undefined,
): DossierCapacityServiceError | null {
  switch (error?.code) {
    case "P4D01":
    case "P4D02":
    case "P4D03":
    case "42501":
      return new DossierCapacityServiceError(mapDossierCapacityRpcError(error));
    default:
      return null;
  }
}

export async function loadOwnedDossierCapacity(
  gateway: DossierCapacityRpcGateway,
): Promise<OwnedDossierCapacity> {
  let result: DossierCapacityRpcResult;
  try {
    result = await gateway.getOwnedCapacity();
  } catch {
    throw new DossierCapacityServiceError(failure("technical"));
  }

  if (result.error) {
    throw new DossierCapacityServiceError(mapDossierCapacityRpcError(result.error));
  }

  try {
    return parseOwnedDossierCapacity(result.data);
  } catch {
    throw new DossierCapacityServiceError(failure("invalid_response"));
  }
}
