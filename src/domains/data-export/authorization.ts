import type { DossierAccessRole } from "@/types/database";
import type { DataExportDossierScope, DataExportSafeError } from "./contracts";

export type DossierExportAuthorization =
  | { allowed: true; scope: DataExportDossierScope }
  | { allowed: false; error: DataExportSafeError };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function getDossierExportAuthorization(
  dossierId: string,
  role: DossierAccessRole,
): DossierExportAuthorization {
  if (!UUID.test(dossierId)) {
    return {
      allowed: false,
      error: {
        code: "invalid_scope",
        message: "Le périmètre demandé pour l’export est invalide.",
        retryable: false,
      },
    };
  }

  if (role === "owner" || role === "manager") {
    return { allowed: true, scope: { dossierId, role } };
  }

  return {
    allowed: false,
    error: {
      code: "forbidden",
      message: "L’export complet n’est pas autorisé pour cet accès en lecture seule.",
      retryable: false,
    },
  };
}
