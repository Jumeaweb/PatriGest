import { z } from "zod";
import type { TransactionDocumentHistory, TransactionProofVersion } from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getTransaction, getTransactionDocument } from "./transaction-service";

export type TransactionProofHistoryItem = {
  id: string;
  documentId: string | null;
  versionNumber: number | null;
  fileName: string;
  mimeType: string;
  fileSize: number;
  createdAt: string;
  proofReference: string | null;
  lifecycleState: string;
  availabilityStatus: "unverified" | "available" | "missing";
  pathKind: "legacy" | "versioned";
};

type ProofDescriptor = TransactionProofHistoryItem & { storagePath: string };

async function readableTransaction(personId: string, transactionId: string) {
  if (!z.uuid().safeParse(personId).success || !z.uuid().safeParse(transactionId).success) return null;
  const transaction = await getTransaction(transactionId);
  return transaction?.account.protected_person_id === personId ? transaction : null;
}

function versionDescriptor(version: TransactionProofVersion, proofReference: string | null): ProofDescriptor {
  return {
    id: version.id,
    documentId: version.proof_document_id,
    versionNumber: version.version_number,
    fileName: version.file_name,
    mimeType: version.mime_type,
    fileSize: version.file_size,
    createdAt: version.created_at,
    proofReference,
    lifecycleState: version.lifecycle_state,
    availabilityStatus: version.availability_status,
    pathKind: version.path_kind,
    storagePath: version.storage_path,
  };
}

function historicalDescriptor(row: TransactionDocumentHistory): ProofDescriptor {
  return {
    id: row.proof_version_id ?? row.id,
    documentId: row.proof_document_id,
    versionNumber: null,
    fileName: row.file_name,
    mimeType: row.mime_type,
    fileSize: row.file_size,
    createdAt: row.archived_at,
    proofReference: row.proof_reference,
    lifecycleState: "historical",
    availabilityStatus: row.availability_status,
    pathKind: row.storage_path.endsWith("/proof") ? "legacy" : "versioned",
    storagePath: row.storage_path,
  };
}

export async function listTransactionProofHistory(
  personId: string,
  transactionId: string,
): Promise<TransactionProofHistoryItem[] | null> {
  if (!await readableTransaction(personId, transactionId)) return null;
  const { supabase } = await getAuthenticatedUser();
  const [documentsResult, historyResult] = await Promise.all([
    supabase.from("transaction_proof_documents").select("*").eq("transaction_id", transactionId),
    supabase.from("transaction_document_history").select("*").eq("transaction_id", transactionId).order("archived_at", { ascending: false }),
  ]);
  if (documentsResult.error || historyResult.error) throw new Error("Impossible de charger l’historique des justificatifs.");
  const documents = documentsResult.data ?? [];
  const documentIds = documents.map((document) => document.id);
  const versionsResult = documentIds.length
    ? await supabase.from("transaction_proof_versions").select("*").in("proof_document_id", documentIds).order("version_number", { ascending: false })
    : { data: [], error: null };
  if (versionsResult.error) throw new Error("Impossible de charger l’historique des justificatifs.");
  const references = new Map(documents.map((document) => [document.id, document.proof_reference]));
  const versionItems = (versionsResult.data ?? []).map((version) => versionDescriptor(version, references.get(version.proof_document_id) ?? null));
  const versionIds = new Set(versionItems.map((item) => item.id));
  const legacyItems = (historyResult.data ?? []).filter((row) => !row.proof_version_id || !versionIds.has(row.proof_version_id)).map(historicalDescriptor);
  return [...versionItems, ...legacyItems].sort((left, right) => right.createdAt.localeCompare(left.createdAt)).map(({ storagePath, ...item }) => {
    void storagePath;
    return item;
  });
}

export async function getTransactionProofDescriptor(
  personId: string,
  transactionId: string,
  versionId?: string | null,
): Promise<ProofDescriptor | null> {
  if (!await readableTransaction(personId, transactionId)) return null;
  const { supabase } = await getAuthenticatedUser();
  if (!versionId) {
    const current = await getTransactionDocument(transactionId);
    if (!current) return null;
    return {
      id: current.proof_version_id ?? current.id,
      documentId: current.proof_document_id,
      versionNumber: null,
      fileName: current.file_name,
      mimeType: current.mime_type,
      fileSize: current.file_size,
      createdAt: current.updated_at,
      proofReference: null,
      lifecycleState: "current",
      availabilityStatus: "unverified",
      pathKind: current.storage_path.endsWith("/proof") ? "legacy" : "versioned",
      storagePath: current.storage_path,
    };
  }
  if (!z.uuid().safeParse(versionId).success) return null;
  const versionResult = await supabase.from("transaction_proof_versions").select("*").eq("id", versionId).maybeSingle();
  if (versionResult.error) throw new Error("Impossible de charger le justificatif.");
  if (versionResult.data) {
    const documentResult = await supabase.from("transaction_proof_documents").select("transaction_id,protected_person_id,proof_reference").eq("id", versionResult.data.proof_document_id).maybeSingle();
    if (documentResult.error) throw new Error("Impossible de charger le justificatif.");
    if (!documentResult.data || documentResult.data.transaction_id !== transactionId || documentResult.data.protected_person_id !== personId) return null;
    return versionDescriptor(versionResult.data, documentResult.data.proof_reference);
  }
  const historyResult = await supabase.from("transaction_document_history").select("*").eq("id", versionId).eq("transaction_id", transactionId).eq("protected_person_id", personId).maybeSingle();
  if (historyResult.error) throw new Error("Impossible de charger le justificatif.");
  return historyResult.data ? historicalDescriptor(historyResult.data) : null;
}
