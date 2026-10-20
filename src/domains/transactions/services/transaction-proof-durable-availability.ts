export const TRANSACTION_PROOF_DURABLE_OPERATIONS_ENV =
  "PATRIGEST_ENABLE_TRANSACTION_PROOF_DURABLE_OPERATIONS";

export function isTransactionProofDurableOperationsEnabled(
  configuredValue = process.env[TRANSACTION_PROOF_DURABLE_OPERATIONS_ENV],
) {
  return configuredValue === "true";
}

export async function runTransactionProofWrite<T>(
  durableEnabled: boolean,
  historicalWrite: () => Promise<T>,
  durableWrite: () => Promise<T>,
) {
  return durableEnabled ? durableWrite() : historicalWrite();
}
