import "server-only";

import { createHash } from "node:crypto";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Database } from "@/types/database";

const reservationSchema = z.object({
  operationId: z.uuid(),
  versionId: z.uuid(),
  storagePath: z.string().min(1),
  state: z.enum(["reserved", "completed", "attention_required", "cancelled"]),
  revision: z.coerce.number().int().nonnegative(),
  activeRevision: z.coerce.number().int().nonnegative(),
});

const finalizationSchema = z.object({
  operationId: z.uuid(),
  versionId: z.uuid(),
  state: z.literal("completed"),
  revision: z.coerce.number().int().positive(),
  activeRevision: z.coerce.number().int().positive(),
});

export type BankStatementDocumentVersion = {
  versionId: string;
  versionNumber: number;
  originalFileName: string;
  mimeType: string;
  fileSize: number;
  sha256: string | null;
  integrityStatus: "pending_hash" | "verified";
  previousVersionId: string | null;
  correctionReason: string | null;
  createdAt: string;
  isActive: boolean;
  activeRevision: number;
};

type HistoryRow = Database["public"]["Functions"]["get_bank_statement_document_history"]["Returns"][number];

export class BankStatementDocumentError extends Error {
  constructor(message: string, public readonly status = 400) {
    super(message);
  }
}
function safeRpcMessage(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return fallback;
  if (error.code === "40001") return "Le document a changé. Rechargez la page avant de recommencer.";
  if (error.code === "42501") return "Vous n’êtes pas autorisé à corriger ce document.";
  if (error.code === "P4R04") return "Cette tentative de correction ne correspond plus au fichier sélectionné.";
  if (error.code === "55000") return error.message || fallback;
  return fallback;
}

function toPublicVersion(row: HistoryRow): BankStatementDocumentVersion {
  return {
    versionId: row.version_id,
    versionNumber: row.version_number,
    originalFileName: row.original_file_name,
    mimeType: row.mime_type,
    fileSize: row.file_size,
    sha256: row.sha256,
    integrityStatus: row.integrity_status,
    previousVersionId: row.previous_version_id,
    correctionReason: row.correction_reason,
    createdAt: row.created_at,
    isActive: row.is_active,
    activeRevision: row.active_revision,
  };
}

export async function getBankStatementDocumentHistory(
  client: SupabaseClient<Database>,
  statementId: string,
) {
  const { data, error } = await client.rpc("get_bank_statement_document_history", {
    p_statement_id: statementId,
  });
  if (error) throw new BankStatementDocumentError("Impossible de charger l’historique documentaire.", 500);
  return (data ?? []).map(toPublicVersion);
}

export async function getBankStatementDocumentVersion(
  client: SupabaseClient<Database>,
  statementId: string,
  versionId?: string,
) {
  const { data, error } = await client.rpc("get_bank_statement_document_history", {
    p_statement_id: statementId,
  });
  if (error) throw new BankStatementDocumentError("Impossible de charger le document.", 500);
  const row = (data ?? []).find((item) => versionId ? item.version_id === versionId : item.is_active);
  return row ? { public: toPublicVersion(row), storagePath: row.storage_path } : null;
}

async function verifyInitialVersionIfNeeded(input: {
  client: SupabaseClient<Database>;
  version: BankStatementDocumentVersion;
  storagePath: string;
  bytes: Uint8Array;
}) {
  if (input.version.integrityStatus === "verified") return;
  const info = await input.client.storage.from("bank-statements").info(input.storagePath);
  if (info.error || !info.data) return;
  const sha256 = createHash("sha256").update(input.bytes).digest("hex");
  const admin = createAdminClient();
  const { error } = await admin.rpc("verify_bank_statement_document_version_integrity", {
    p_version_id: input.version.versionId,
    p_storage_object_id: info.data.id,
    p_storage_object_version: info.data.version,
    p_sha256: sha256,
  });
  if (error) throw new BankStatementDocumentError("L’intégrité du document historique n’a pas pu être vérifiée.", 500);
}

export async function downloadBankStatementDocument(input: {
  client: SupabaseClient<Database>;
  statementId: string;
  versionId?: string;
}) {
  const version = await getBankStatementDocumentVersion(input.client, input.statementId, input.versionId);
  if (!version) return null;
  const downloaded = await input.client.storage.from("bank-statements").download(version.storagePath);
  if (downloaded.error || !downloaded.data) {
    throw new BankStatementDocumentError("Impossible de télécharger le relevé.", 500);
  }
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  await verifyInitialVersionIfNeeded({
    client: input.client,
    version: version.public,
    storagePath: version.storagePath,
    bytes,
  });
  return { version: version.public, bytes };
}

export async function correctValidatedBankStatementDocument(input: {
  client: SupabaseClient<Database>;
  protectedPersonId: string;
  financialAccountId: string;
  statementId: string;
  expectedActiveRevision: number;
  clientRequestId: string;
  reason: string;
  fileName: string;
  bytes: Uint8Array;
}) {
  const sha256 = createHash("sha256").update(input.bytes).digest("hex");
  const reservationResponse = await input.client.rpc("begin_bank_statement_document_correction", {
    p_protected_person_id: input.protectedPersonId,
    p_financial_account_id: input.financialAccountId,
    p_statement_id: input.statementId,
    p_expected_active_revision: input.expectedActiveRevision,
    p_client_request_id: input.clientRequestId,
    p_reason: input.reason,
    p_file_name: input.fileName,
    p_file_size: input.bytes.byteLength,
    p_sha256: sha256,
  });
  if (reservationResponse.error) {
    throw new BankStatementDocumentError(safeRpcMessage(reservationResponse.error, "Impossible de réserver la correction documentaire."));
  }
  const parsedReservation = reservationSchema.safeParse(reservationResponse.data);
  if (!parsedReservation.success) throw new BankStatementDocumentError("La réservation documentaire est invalide.", 500);
  const reservation = parsedReservation.data;
  if (reservation.state === "completed") return reservation;
  if (reservation.state !== "reserved") {
    throw new BankStatementDocumentError("Cette correction documentaire nécessite une vérification administrative.", 409);
  }

  const bucket = input.client.storage.from("bank-statements");
  let info = await bucket.info(reservation.storagePath);
  if (info.error) {
    const upload = await bucket.upload(reservation.storagePath, input.bytes, {
      contentType: "application/pdf",
      metadata: { sha256 },
      upsert: false,
    });
    if (upload.error) {
      throw new BankStatementDocumentError("Le nouveau PDF n’a pas pu être téléversé. L’ancien document reste actif.", 500);
    }
    info = await bucket.info(reservation.storagePath);
  }
  if (info.error || !info.data) {
    throw new BankStatementDocumentError("Le téléversement doit être vérifié avant la finalisation. Vous pouvez réessayer sans changer le fichier.", 500);
  }
  const existing = await bucket.download(reservation.storagePath);
  if (existing.error || !existing.data) {
    throw new BankStatementDocumentError("Le nouveau PDF ne peut pas être vérifié. L’ancien document reste actif.", 500);
  }
  const existingBytes = new Uint8Array(await existing.data.arrayBuffer());
  const existingHash = createHash("sha256").update(existingBytes).digest("hex");
  if (existingBytes.byteLength !== input.bytes.byteLength || existingHash !== sha256) {
    throw new BankStatementDocumentError("Le fichier déjà réservé ne correspond pas à cette correction.", 409);
  }

  const finalizationResponse = await input.client.rpc("finalize_bank_statement_document_correction", {
    p_operation_id: reservation.operationId,
    p_expected_operation_revision: reservation.revision,
    p_storage_object_id: info.data.id,
    p_storage_object_version: info.data.version,
  });
  if (finalizationResponse.error) {
    throw new BankStatementDocumentError(
      `${safeRpcMessage(finalizationResponse.error, "La finalisation du document a échoué.")} Le fichier réservé est conservé pour une reprise avec la même demande.`,
      409,
    );
  }
  const finalization = finalizationSchema.safeParse(finalizationResponse.data);
  if (!finalization.success) throw new BankStatementDocumentError("La finalisation documentaire est invalide.", 500);
  return finalization.data;
}
