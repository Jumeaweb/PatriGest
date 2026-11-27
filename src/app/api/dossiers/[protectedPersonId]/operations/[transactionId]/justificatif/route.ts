import { NextResponse } from "next/server";
import { prepareProofFile, ProofFileError } from "@/domains/transactions/services/transaction-proof-file";
import { deleteTransactionProof, ProofServiceError, saveTransactionProof } from "@/domains/transactions/services/transaction-proof-service";
import { getTransactionProofDescriptor, listTransactionProofHistory } from "@/domains/transactions/services/transaction-proof-read-service";
import { managementReportContentDisposition } from "@/domains/management-reports/document-helpers";
import { protectedStorageResponse } from "@/lib/supabase/protected-storage-response";

type RouteParams = { params: Promise<{ protectedPersonId: string; transactionId: string }> };

export async function GET(request: Request, { params }: RouteParams) {
  const { protectedPersonId, transactionId } = await params;
  const url = new URL(request.url);
  if (url.searchParams.get("history") === "1") {
    const history = await listTransactionProofHistory(protectedPersonId, transactionId);
    return history ? NextResponse.json({ documents: history }) : NextResponse.json({ message: "Opération introuvable." }, { status: 404 });
  }
  const proof = await getTransactionProofDescriptor(protectedPersonId, transactionId, url.searchParams.get("versionId"));
  if (!proof) return NextResponse.json({ message: "Justificatif introuvable." }, { status: 404 });
  if (proof.availabilityStatus === "missing") return NextResponse.json({ message: "Ce document est actuellement indisponible." }, { status: 410 });
  const download = url.searchParams.get("download") === "1";
  return protectedStorageResponse({ request, bucket: "transaction-proofs", storagePath: proof.storagePath,
    contentType: proof.mimeType,
    contentDisposition: managementReportContentDisposition(proof.fileName, download) });
}

export async function POST(request: Request, { params }: RouteParams) {
  const { protectedPersonId, transactionId } = await params;
  try {
    const formData = await request.formData();
    const proof = await prepareProofFile(formData.get("file"), false);
    if (!proof) throw new ProofFileError("Sélectionnez un fichier.");
    const clientRequestId = formData.get("clientRequestId");
    await saveTransactionProof(protectedPersonId, transactionId, proof, typeof clientRequestId === "string" && clientRequestId ? clientRequestId : undefined);
    return NextResponse.json({ message: "Le justificatif a été enregistré." });
  } catch (error) {
    if (error instanceof ProofFileError) return NextResponse.json({ message: error.message }, { status: 400 });
    if (error instanceof ProofServiceError) return NextResponse.json({ message: error.message }, { status: error.status });
    return NextResponse.json({ message: "Impossible d’enregistrer le justificatif." }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: RouteParams) {
  const { protectedPersonId, transactionId } = await params;
  try {
    await deleteTransactionProof(protectedPersonId, transactionId);
    return NextResponse.json({ message: "Le justificatif a été supprimé." });
  } catch (error) {
    if (error instanceof ProofServiceError) {
      return NextResponse.json({ message: error.message }, {
        status: error.status,
        headers: error.status === 405 ? { Allow: "GET, POST" } : undefined,
      });
    }
    return NextResponse.json({ message: "Impossible de supprimer le justificatif." }, { status: 500 });
  }
}
