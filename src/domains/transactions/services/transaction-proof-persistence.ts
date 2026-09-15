export class ProofPersistenceError extends Error {
  readonly stage: "backup" | "upload" | "database" | "compensation";
  constructor(stage: "backup" | "upload" | "database" | "compensation") { super("Impossible d’enregistrer le justificatif."); this.stage = stage; }
}

type ProofPersistenceSteps = {
  existing: boolean;
  backup: () => Promise<Uint8Array>;
  upload: () => Promise<void>;
  writeDocument: () => Promise<void>;
  remove: () => Promise<void>;
  verifyRemoved: () => Promise<void>;
  restore: (bytes: Uint8Array) => Promise<void>;
  verifyRestored: (bytes: Uint8Array) => Promise<void>;
};

export async function persistProof(steps: ProofPersistenceSteps) {
  let previous: Uint8Array | null = null;
  if (steps.existing) {
    try { previous = await steps.backup(); }
    catch { throw new ProofPersistenceError("backup"); }
  }
  try { await steps.upload(); }
  catch {
    // A failed non-upsert upload may mean another request owns the canonical path.
    // Never delete that request's file merely because this upload failed.
    if (steps.existing) await compensate(steps, previous);
    throw new ProofPersistenceError("upload");
  }
  try { await steps.writeDocument(); }
  catch {
    await compensate(steps, previous);
    throw new ProofPersistenceError("database");
  }
}

async function compensate(steps: ProofPersistenceSteps, previous: Uint8Array | null) {
  try {
    if (previous) {
      await steps.restore(previous);
      await steps.verifyRestored(previous);
    } else {
      await steps.remove();
      await steps.verifyRemoved();
    }
  } catch { throw new ProofPersistenceError("compensation"); }
}
