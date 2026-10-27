import { createHash } from "node:crypto";

export const MAX_PHYSICAL_VERIFICATION_BYTES = 20 * 1024 * 1024;
export const PHYSICAL_VERIFICATION_TIMEOUT_MS = 10_000;

type StorageFailure = { status?: number | string; statusCode?: number | string; message?: string; error?: string; code?: string };
type StorageInfo = { id?: string; version?: string; size?: number };
type StorageDownload = {
  chunks: AsyncIterable<Uint8Array>;
  totalByteSize: number | null;
};

export type PhysicalVerificationDescriptor = {
  catalogObjectId: string | null;
  catalogObjectVersion: string | null;
  expectedByteSize: number | null;
  expectedSha256: string | null;
};

export type PhysicalReadGateway = {
  info(): PromiseLike<{ data: StorageInfo | null; error: StorageFailure | null }>;
  download(signal: AbortSignal, maximumBytes: number): PromiseLike<{
    data: StorageDownload | null;
    error: StorageFailure | null;
  }>;
};

export type PhysicalCompletion = {
  outcome: "verified_readable" | "missing_physical_bytes" | "version_mismatch" | "hash_mismatch" | "verification_inconclusive";
  proofLevel: "catalog_only" | "physical_readability" | "physical_integrity" | "inconclusive";
  catalogObjectId: string | null;
  catalogObjectVersion: string | null;
  byteSize: number | null;
  sha256: string | null;
  limitationCode: string | null;
};

async function bounded<T>(promise: PromiseLike<T>): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      Promise.resolve(promise),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => reject(new Error("STORAGE_TIMEOUT")), PHYSICAL_VERIFICATION_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}
async function boundedDownload<T>(operation: (signal: AbortSignal) => PromiseLike<T>): Promise<T> {
  const controller = new AbortController();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      Promise.resolve(operation(controller.signal)),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          controller.abort();
          reject(new Error("STORAGE_TIMEOUT"));
        }, PHYSICAL_VERIFICATION_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
    controller.abort();
  }
}

function statusOf(error: unknown) {
  if (!error || typeof error !== "object") return "";
  const value = error as StorageFailure;
  return String(value.statusCode ?? value.status ?? "");
}

function isMissing(error: unknown) {
  if (["400", "404"].includes(statusOf(error))) return true;
  if (!error || typeof error !== "object") return false;
  const value = error as StorageFailure;
  return /not[ _-]?found|no[ _-]?such[ _-]?(key|object)|object.*absent/i.test(
    [value.message, value.error, value.code].filter(Boolean).join(" "),
  );
}

const empty = (outcome: PhysicalCompletion["outcome"], proofLevel: PhysicalCompletion["proofLevel"], limitationCode: string): PhysicalCompletion => ({
  outcome, proofLevel, limitationCode, catalogObjectId: null, catalogObjectVersion: null, byteSize: null, sha256: null,
});

export async function inspectAdministrativeDocumentPhysicalObject(
  gateway: PhysicalReadGateway,
  descriptor: PhysicalVerificationDescriptor,
): Promise<PhysicalCompletion> {
  let info;
  try { info = await bounded(gateway.info()); }
  catch { return empty("verification_inconclusive", "inconclusive", "STORAGE_TIMEOUT"); }
  if (info.error || !info.data) {
    if (isMissing(info.error)) return empty("missing_physical_bytes", "catalog_only", "PHYSICAL_OBJECT_NOT_FOUND");
    return empty("verification_inconclusive", "inconclusive", ["401", "403"].includes(statusOf(info.error)) ? "STORAGE_ACCESS_DENIED" : "STORAGE_INFO_FAILED");
  }
  const identity = { catalogObjectId: info.data.id ?? null, catalogObjectVersion: info.data.version ?? null };
  if (descriptor.catalogObjectId !== identity.catalogObjectId || descriptor.catalogObjectVersion !== identity.catalogObjectVersion) {
    return { ...empty("version_mismatch", "catalog_only", "CATALOG_IDENTITY_CHANGED"), ...identity };
  }
  if (typeof info.data.size === "number" && info.data.size < 0) {
    return { ...empty("verification_inconclusive", "inconclusive", "STORAGE_SIZE_INVALID"), ...identity };
  }
  if (typeof info.data.size === "number" && info.data.size > MAX_PHYSICAL_VERIFICATION_BYTES) {
    return { ...empty("verification_inconclusive", "inconclusive", "OBJECT_TOO_LARGE"), ...identity };
  }
  let downloaded: {
    data: { byteSize: number; sha256: string } | null;
    error: StorageFailure | null;
  };
  try {
    downloaded = await boundedDownload(async (signal) => {
      const response = await gateway.download(signal, MAX_PHYSICAL_VERIFICATION_BYTES);
      if (response.error || !response.data) return { data: null, error: response.error };
      if (response.data.totalByteSize !== null && response.data.totalByteSize > MAX_PHYSICAL_VERIFICATION_BYTES) {
        throw new Error("STORAGE_TOO_LARGE");
      }
      const digest = createHash("sha256");
      let byteSize = 0;
      for await (const chunk of response.data.chunks) {
        if (signal.aborted) throw new Error("STORAGE_TIMEOUT");
        if (!(chunk instanceof Uint8Array)) throw new Error("STORAGE_INVALID_CHUNK");
        byteSize += chunk.byteLength;
        if (byteSize > MAX_PHYSICAL_VERIFICATION_BYTES) throw new Error("STORAGE_TOO_LARGE");
        digest.update(chunk);
      }
      return { data: { byteSize, sha256: digest.digest("hex") }, error: null };
    });
  } catch (error) {
    const limitationCode = error instanceof Error && error.message === "STORAGE_TOO_LARGE"
      ? "OBJECT_TOO_LARGE"
      : error instanceof Error && error.message === "STORAGE_INVALID_CHUNK"
        ? "STORAGE_DOWNLOAD_FAILED"
        : "STORAGE_TIMEOUT";
    return { ...empty("verification_inconclusive", "inconclusive", limitationCode), ...identity };
  }
  if (downloaded.error || !downloaded.data) {
    if (isMissing(downloaded.error)) return { ...empty("missing_physical_bytes", "catalog_only", "PHYSICAL_BYTES_NOT_FOUND"), ...identity };
    return { ...empty("verification_inconclusive", "inconclusive", ["401", "403"].includes(statusOf(downloaded.error)) ? "STORAGE_ACCESS_DENIED" : "STORAGE_DOWNLOAD_FAILED"), ...identity };
  }
  const { byteSize, sha256 } = downloaded.data;
  const base = { ...identity, byteSize, sha256 };
  if (descriptor.expectedSha256 && descriptor.expectedSha256 !== sha256) {
    return { ...base, outcome: "hash_mismatch", proofLevel: "physical_integrity", limitationCode: "REFERENCE_HASH_MISMATCH" };
  }
  if (descriptor.expectedByteSize !== null && descriptor.expectedByteSize !== byteSize) {
    return { ...base, outcome: "verification_inconclusive", proofLevel: "physical_readability", limitationCode: "REFERENCE_SIZE_MISMATCH" };
  }
  return { ...base, outcome: "verified_readable", proofLevel: descriptor.expectedSha256 ? "physical_integrity" : "physical_readability", limitationCode: descriptor.expectedSha256 ? null : "NO_RELIABLE_REFERENCE_HASH" };
}
