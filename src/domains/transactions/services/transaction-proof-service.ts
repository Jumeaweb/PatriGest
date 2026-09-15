import { z } from "zod";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getProtectedPerson } from "@/domains/protected-persons/services/protected-person-service";
import { isDateInClosedPeriod } from "../utils/transaction-utils";
import { getTransaction, getTransactionDocument } from "./transaction-service";
import { getProofWriteDenial } from "./transaction-proof-access";
import { buildProofFileName, type PreparedProofFile } from "./transaction-proof-file";
import { persistProof, ProofPersistenceError } from "./transaction-proof-persistence";

const BUCKET = "transaction-proofs";

export class ProofServiceError extends Error {
  constructor(message: string, public readonly status: number = 500) { super(message); }
}

export async function getExpenseProofContext(personId: string, transactionId: string) {
  if (!z.uuid().safeParse(personId).success || !z.uuid().safeParse(transactionId).success) return null;
  const [person, transaction] = await Promise.all([getProtectedPerson(personId), getTransaction(transactionId)]);
  if (!person || !transaction || transaction.transaction_type !== "expense" || transaction.transfer_id || transaction.account.protected_person_id !== personId || !transaction.proof_reference) return null;
  return { person, transaction };
}

export async function saveTransactionProof(personId: string, transactionId: string, file: PreparedProofFile) {
  const context = await getExpenseProofContext(personId, transactionId);
  if (!context) throw new ProofServiceError("Dépense introuvable.", 404);
  const denial = getProofWriteDenial({ personId, transactionPersonId: context.transaction.account.protected_person_id, transactionType: context.transaction.transaction_type, transferId: context.transaction.transfer_id, proofReference: context.transaction.proof_reference, role: context.person.accessRole, closed: isDateInClosedPeriod(context.transaction.transaction_date, context.person.managementPeriods) });
  if (denial === "read_only") throw new ProofServiceError("Vous ne pouvez pas ajouter ce justificatif.", 403);
  if (denial === "closed") throw new ProofServiceError("Cette dépense appartient à un exercice clôturé.", 403);
  if (denial) throw new ProofServiceError("Dépense introuvable.", 404);
  const { supabase, userId } = await getAuthenticatedUser();
  const existing = await getTransactionDocument(transactionId);
  const folder = `protected-persons/${personId}/transactions/${transactionId}`;
  const path = `${folder}/proof`;
  if (existing && existing.storage_path !== path) throw new ProofServiceError("Impossible de remplacer ce justificatif.");
  const storage = supabase.storage.from(BUCKET);
  const listProof = async () => {
    const { data, error } = await storage.list(folder, { limit: 10, search: "proof" });
    if (error) throw new Error("Storage unavailable");
    return (data ?? []).some((item) => item.name === "proof");
  };
  if (!existing && await listProof()) throw new ProofServiceError("Un justificatif non enregistré existe déjà. Contactez l’administrateur.");
  const fileName = buildProofFileName(context.transaction.proof_reference!, context.transaction.label, file.extension);

  try {
    await persistProof({
      existing: Boolean(existing),
      backup: async () => {
        const { data, error } = await storage.download(path);
        if (error || !data) throw new Error("Backup failed");
        return new Uint8Array(await data.arrayBuffer());
      },
      upload: async () => {
        const { error } = await storage.upload(path, file.bytes, { contentType: file.mimeType, upsert: Boolean(existing) });
        if (error) throw new Error("Upload failed");
      },
      writeDocument: async () => {
        const current = await getExpenseProofContext(personId, transactionId);
        if (!current || getProofWriteDenial({ personId, transactionPersonId: current.transaction.account.protected_person_id, transactionType: current.transaction.transaction_type, transferId: current.transaction.transfer_id, proofReference: current.transaction.proof_reference, role: current.person.accessRole, closed: isDateInClosedPeriod(current.transaction.transaction_date, current.person.managementPeriods) })) throw new Error("Proof no longer writable");
        const payload = { file_name: fileName, mime_type: file.mimeType, file_size: file.size };
        const { data, error } = existing
          ? await supabase.from("transaction_documents").update(payload).eq("id", existing.id).eq("transaction_id", transactionId).select("id").single()
          : await supabase.from("transaction_documents").insert({ ...payload, transaction_id: transactionId, storage_path: path, created_by: userId }).select("id").single();
        if (error || !data) throw new Error("Document write failed");
      },
      remove: async () => {
        const { error } = await storage.remove([path]);
        if (error) throw new Error("Cleanup failed");
      },
      verifyRemoved: async () => {
        if (await listProof()) throw new Error("Cleanup not verified");
      },
      restore: async (bytes) => {
        const { error } = await storage.upload(path, bytes, { contentType: existing!.mime_type, upsert: true });
        if (error) throw new Error("Restore failed");
      },
      verifyRestored: async (bytes) => {
        const { data, error } = await storage.download(path);
        if (error || !data) throw new Error("Restore not verified");
        const restored = new Uint8Array(await data.arrayBuffer());
        if (restored.length !== bytes.length || !restored.every((value, index) => value === bytes[index])) throw new Error("Restore mismatch");
      },
    });
  } catch (error) {
    if (error instanceof ProofPersistenceError && error.stage === "compensation") console.error("Justificatif : compensation non vérifiée", { transactionId });
    if (error instanceof ProofPersistenceError && error.stage === "upload" && !existing) {
      try {
        if (await listProof() && !await getTransactionDocument(transactionId)) console.error("Justificatif : objet sans métadonnées après échec d’upload", { transactionId });
      } catch { console.error("Justificatif : état Storage non vérifié après échec d’upload", { transactionId }); }
    }
    throw new ProofServiceError("Impossible d’enregistrer le justificatif. La dépense reste disponible.");
  }
}
