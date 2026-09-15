import { NextResponse } from "next/server";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { getTransactionDocument } from "@/domains/transactions/services/transaction-service";
import { prepareProofFile, ProofFileError } from "@/domains/transactions/services/transaction-proof-file";
import { getExpenseProofContext, ProofServiceError, saveTransactionProof } from "@/domains/transactions/services/transaction-proof-service";

type RouteParams = { params: Promise<{ protectedPersonId: string; transactionId: string }> };

export async function GET(request: Request, { params }: RouteParams) {
  const { protectedPersonId, transactionId } = await params;
  const context = await getExpenseProofContext(protectedPersonId, transactionId);
  if (!context) return NextResponse.json({ message: "Justificatif introuvable." }, { status: 404 });
  const proof = await getTransactionDocument(transactionId);
  if (!proof) return NextResponse.json({ message: "Justificatif introuvable." }, { status: 404 });
  const { supabase } = await getAuthenticatedUser();
  const download = new URL(request.url).searchParams.get("download") === "1";
  const { data, error } = await supabase.storage.from("transaction-proofs").createSignedUrl(proof.storage_path, 60, download ? { download: proof.file_name } : undefined);
  if (error || !data) return NextResponse.json({ message: "Impossible d’ouvrir le justificatif." }, { status: 500 });
  return NextResponse.redirect(data.signedUrl);
}

export async function POST(request: Request, { params }: RouteParams) {
  const { protectedPersonId, transactionId } = await params;
  try {
    const proof = await prepareProofFile((await request.formData()).get("file"), false);
    if (!proof) throw new ProofFileError("Sélectionnez un fichier.");
    await saveTransactionProof(protectedPersonId, transactionId, proof);
    return NextResponse.json({ message: "Le justificatif a été enregistré." });
  } catch (error) {
    if (error instanceof ProofFileError) return NextResponse.json({ message: error.message }, { status: 400 });
    if (error instanceof ProofServiceError) return NextResponse.json({ message: error.message }, { status: error.status });
    return NextResponse.json({ message: "Impossible d’enregistrer le justificatif." }, { status: 500 });
  }
}
