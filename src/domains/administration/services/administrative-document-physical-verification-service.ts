import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import {
  physicalVerificationDescriptorSchema,
  physicalVerificationHistorySchema,
  physicalVerificationObservationSchema,
  type PhysicalVerificationObservation,
} from "../administrative-document-physical-verification";
import { requirePlatformAdministrator } from "./administration-service";
import { inspectAdministrativeDocumentPhysicalObject } from "../administrative-document-physical-verification-core";

type RpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>;
};

function rpc(client: unknown, name: string, args: Record<string, unknown>) {
  return (client as RpcClient).rpc(name, args);
}
export async function getAdministrativeDocumentPhysicalObservations(inventoryKey: string) {
  const { supabase } = await requirePlatformAdministrator();
  const result = await rpc(supabase, "get_administrative_document_physical_observations", {
    p_inventory_key: inventoryKey, p_limit: 20, p_before_observed_at: null,
  });
  if (result.error) throw new Error("Impossible de charger l’historique des vérifications physiques.");
  return physicalVerificationHistorySchema.parse(result.data).items;
}

export async function verifyAdministrativeDocumentPhysicalObject(input: {
  inventoryKey: string;
  requestId: string;
}): Promise<PhysicalVerificationObservation> {
  const { supabase } = await requirePlatformAdministrator();
  const beginning = await rpc(supabase, "begin_administrative_document_physical_verification", {
    p_inventory_key: input.inventoryKey, p_client_request_id: input.requestId,
  });
  if (beginning.error || !beginning.data || typeof beginning.data !== "object") {
    throw new Error(beginning.error?.code === "P4V04" ? "Trop de vérifications ont été demandées. Réessayez dans un instant." : "Impossible d’autoriser la vérification physique.");
  }
  const started = beginning.data as {
    verificationRequestId?: unknown;
    state?: unknown;
    observation?: unknown;
  };
  const verificationRequestId = zUuid(started.verificationRequestId);
  if (started.state === "completed") {
    return physicalVerificationObservationSchema.parse(started.observation);
  }
  const admin = createAdminClient();
  const descriptorResult = await rpc(admin, "get_administrative_document_physical_verification_descriptor", {
    p_verification_request_id: verificationRequestId,
  });
  if (descriptorResult.error) throw new Error("Impossible de préparer la lecture physique.");
  const descriptor = physicalVerificationDescriptorSchema.parse(descriptorResult.data);
  let completion;
  if (descriptor.state === "stale") {
    completion = {
      outcome: "stale_inventory_finding" as const,
      proofLevel: "stale" as const,
      catalogObjectId: null,
      catalogObjectVersion: null,
      byteSize: null,
      sha256: null,
      limitationCode: "INVENTORY_FINDING_CHANGED",
    };
  } else {
    if (!descriptor.bucketId || !descriptor.objectPath) throw new Error("Le constat ne possède pas de cible physique autorisée.");
    const storage = admin.storage.from(descriptor.bucketId);
    completion = await inspectAdministrativeDocumentPhysicalObject({
      info: () => storage.info(descriptor.objectPath!),
      download: async (signal, maximumBytes) => {
        const signed = await storage.createSignedUrl(descriptor.objectPath!, 60);
        if (signed.error || !signed.data?.signedUrl) {
          return { data: null, error: signed.error ?? { message: "Signed URL unavailable" } };
        }
        const response = await fetch(signed.data.signedUrl, {
          cache: "no-store",
          headers: { Range: `bytes=0-${maximumBytes}` },
          signal,
        });
        if (!response.ok || !response.body) {
          return { data: null, error: { status: response.status } };
        }
        return {
          data: {
            chunks: readResponseChunks(response),
            totalByteSize: getResponseTotalByteSize(response),
          },
          error: null,
        };
      },
    }, descriptor);
  }
  const completed = await rpc(admin, "complete_administrative_document_physical_verification", {
    p_verification_request_id: descriptor.verificationRequestId,
    p_server_capability: descriptor.serverCapability,
    p_outcome: completion.outcome,
    p_proof_level: completion.proofLevel,
    p_catalog_object_id: completion.catalogObjectId,
    p_catalog_object_version: completion.catalogObjectVersion,
    p_observed_byte_size: completion.byteSize,
    p_observed_sha256: completion.sha256,
    p_limitation_code: completion.limitationCode,
  });
  if (completed.error) throw new Error("Impossible d’enregistrer la vérification physique.");
  if (!completed.data || typeof completed.data !== "object") throw new Error("Le résultat de la vérification est indisponible.");
  return physicalVerificationObservationSchema.parse((completed.data as { observation?: unknown }).observation);
}

function getResponseTotalByteSize(response: Response) {
  const contentRange = response.headers.get("content-range");
  const rangeMatch = contentRange?.match(/\/(\d+)$/);
  if (rangeMatch) return Number(rangeMatch[1]);
  if (response.status === 200) {
    const contentLength = response.headers.get("content-length");
    if (contentLength && /^\d+$/.test(contentLength)) return Number(contentLength);
  }
  return null;
}

async function* readResponseChunks(response: Response): AsyncGenerator<Uint8Array> {
  const reader = response.body!.getReader();
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) return;
      yield result.value;
    }
  } finally {
    await reader.cancel().catch(() => undefined);
    reader.releaseLock();
  }
}

function zUuid(value: unknown) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error("Identifiant de vérification invalide.");
  }
  return value;
}
