export const BANK_STATEMENT_DURABLE_OPERATIONS_ENV =
  "PATRIGEST_ENABLE_BANK_STATEMENT_DURABLE_OPERATIONS";

export function isBankStatementDurableOperationsEnabled(
  configuredValue = process.env[BANK_STATEMENT_DURABLE_OPERATIONS_ENV],
) {
  return configuredValue === "true";
}

export async function runBankStatementDocumentWrite<T>(
  durableEnabled: boolean,
  historicalWrite: () => Promise<T>,
  durableWrite: () => Promise<T>,
) {
  return durableEnabled ? durableWrite() : historicalWrite();
}
