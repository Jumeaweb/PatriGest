export const MANAGEMENT_REPORT_DURABLE_OPERATIONS_ENV =
  "PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS";

export function isManagementReportDurableOperationsEnabled(
  configuredValue = process.env[MANAGEMENT_REPORT_DURABLE_OPERATIONS_ENV],
) {
  return configuredValue === "true";
}

export async function runManagementReportDocumentWrite<T>(
  durableEnabled: boolean,
  historicalWrite: () => Promise<T>,
  durableWrite: () => Promise<T>,
) {
  return durableEnabled ? durableWrite() : historicalWrite();
}
