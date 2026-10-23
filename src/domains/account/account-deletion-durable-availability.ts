export const ACCOUNT_DELETION_DURABLE_NEUTRALIZATION_ENV =
  "PATRIGEST_ENABLE_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION";

export function isAccountDeletionDurableNeutralizationEnabled() {
  return process.env[ACCOUNT_DELETION_DURABLE_NEUTRALIZATION_ENV] === "true";
}
