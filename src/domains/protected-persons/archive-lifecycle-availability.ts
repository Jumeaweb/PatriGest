import type { DossierAccessRole } from "@/types/database";

export const PROTECTED_PERSON_ARCHIVE_LIFECYCLE_ENV =
  "PATRIGEST_ENABLE_DOSSIER_ARCHIVE_LIFECYCLE";

export const PROTECTED_PERSON_ARCHIVE_LIFECYCLE_DISABLED_MESSAGE =
  "L’archivage et la restauration des dossiers ne sont pas encore activés.";

export function isProtectedPersonArchiveLifecycleEnabled(
  configuredValue = process.env[PROTECTED_PERSON_ARCHIVE_LIFECYCLE_ENV],
) {
  return configuredValue === "true";
}

export function canChangeProtectedPersonArchiveState(
  enabled: boolean,
  accessRole: DossierAccessRole,
) {
  return enabled && accessRole === "owner";
}
