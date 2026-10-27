import { z } from "zod";

export const physicalVerificationOutcomeSchema = z.enum([
  "verified_readable",
  "missing_physical_bytes",
  "version_mismatch",
  "hash_mismatch",
  "verification_inconclusive",
  "stale_inventory_finding",
]);

export const physicalVerificationProofLevelSchema = z.enum([
  "catalog_only",
  "physical_readability",
  "physical_integrity",
  "inconclusive",
  "stale",
]);

export const physicalVerificationObservationSchema = z.object({
  id: z.uuid(),
  inventoryKey: z.string().min(1).max(200),
  outcome: physicalVerificationOutcomeSchema,
  proofLevel: physicalVerificationProofLevelSchema,
  observedByteSize: z.number().int().nonnegative().nullable(),
  limitationCode: z.string().regex(/^[A-Z0-9_:-]+$/).nullable(),
  observedAt: z.string(),
});

export const physicalVerificationHistorySchema = z.object({
  items: z.array(physicalVerificationObservationSchema),
  limit: z.number().int().min(1).max(50),
});

export const physicalVerificationRequestSchema = z.object({
  inventoryKey: z.string().min(1).max(200).regex(/^[a-z0-9_:-]+$/),
  requestId: z.uuid(),
  confirmation: z.literal("on"),
});

export const physicalVerificationDescriptorSchema = z.object({
  verificationRequestId: z.uuid(),
  state: z.enum(["authorized", "stale"]),
  inventoryKey: z.string().min(1).max(200),
  bucketId: z.enum([
    "transaction-proofs", "bank-statements", "management-reports", "document-operation-backups",
  ]).nullable(),
  objectPath: z.string().min(1).max(1024).nullable(),
  catalogObjectId: z.uuid().nullable(),
  catalogObjectVersion: z.string().min(1).nullable(),
  expectedByteSize: z.number().int().nonnegative().nullable(),
  expectedSha256: z.string().regex(/^[0-9a-f]{64}$/).nullable(),
  contextFingerprint: z.string().regex(/^[0-9a-f]{64}$/),
  serverCapability: z.string().regex(/^[0-9a-f]{64}$/),
  expiresAt: z.string(),
});

export type PhysicalVerificationObservation = z.infer<typeof physicalVerificationObservationSchema>;

export const physicalVerificationOutcomeLabels: Record<z.infer<typeof physicalVerificationOutcomeSchema>, string> = {
  verified_readable: "Octets accessibles et vérifiés",
  missing_physical_bytes: "Octets physiques absents",
  version_mismatch: "Version Storage divergente",
  hash_mismatch: "Empreinte SHA-256 divergente",
  verification_inconclusive: "Vérification non concluante",
  stale_inventory_finding: "Constat d’inventaire devenu obsolète",
};
export const physicalVerificationProofLabels: Record<z.infer<typeof physicalVerificationProofLevelSchema>, string> = {
  catalog_only: "Catalogue uniquement",
  physical_readability: "Lisibilité physique",
  physical_integrity: "Intégrité physique comparée",
  inconclusive: "Preuve insuffisante",
  stale: "Contexte obsolète",
};
