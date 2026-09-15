import type { PreparedProofFile } from "./transaction-proof-file";

export async function createTransactionWithOptionalProof<T extends { id: string }>(
  create: () => Promise<T>,
  proof: PreparedProofFile | null,
  save: (transactionId: string, proof: PreparedProofFile) => Promise<void>,
): Promise<{ transaction: T; proofSaved: boolean }> {
  const transaction = await create();
  if (!proof) return { transaction, proofSaved: true };
  try {
    await save(transaction.id, proof);
    return { transaction, proofSaved: true };
  } catch {
    return { transaction, proofSaved: false };
  }
}
