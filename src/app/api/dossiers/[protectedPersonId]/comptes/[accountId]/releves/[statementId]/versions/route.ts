import { NextResponse } from "next/server";
import { z } from "zod";
import {
  BankStatementDocumentError,
  correctValidatedBankStatementDocument,
  getBankStatementDocumentHistory,
} from "@/domains/bank-statements/bank-statement-document-versioning";
import { getBankReconciliation } from "@/domains/bank-statements/reconciliation-service";
import { getBankStatementAccountContext, readPdf } from "@/domains/bank-statements/server";
import { getBankStatement } from "@/domains/bank-statements/services";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

type Params = { params: Promise<{ protectedPersonId: string; accountId: string; statementId: string }> };

async function getContext(params: Params["params"]) {
  const ids = await params;
  if (![ids.protectedPersonId, ids.accountId, ids.statementId].every((id) => z.uuid().safeParse(id).success)) return null;
  const [accountContext, statement] = await Promise.all([
    getBankStatementAccountContext(ids.protectedPersonId, ids.accountId),
    getBankStatement(ids.accountId, ids.statementId),
  ]);
  if (!accountContext || !statement) return null;
  return { ...ids, ...accountContext, statement };
}
function failure(error: unknown) {
  if (error instanceof BankStatementDocumentError) {
    return NextResponse.json({ message: error.message }, { status: error.status });
  }
  return NextResponse.json({ message: "Impossible de traiter l’historique documentaire." }, { status: 500 });
}

export async function GET(_request: Request, { params }: Params) {
  const value = await getContext(params);
  if (!value) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  try {
    const { supabase } = await getAuthenticatedUser();
    return NextResponse.json({ versions: await getBankStatementDocumentHistory(supabase, value.statementId) });
  } catch (error) {
    return failure(error);
  }
}
export async function POST(request: Request, { params }: Params) {
  const value = await getContext(params);
  if (!value) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (value.person.accessRole === "read_only" || value.person.archived_at || value.person.status !== "active") {
    return NextResponse.json({ message: "Vous ne pouvez pas corriger ce document." }, { status: 403 });
  }
  const reconciliation = await getBankReconciliation(value.statementId);
  if (!reconciliation || reconciliation.status !== "validated") {
    return NextResponse.json({ message: "Seul le document d’un rapprochement validé peut être corrigé ici." }, { status: 409 });
  }
  const form = await request.formData();
  const parsed = z.object({
    reason: z.string().trim().min(3, "Le motif doit contenir au moins 3 caractères.").max(1000),
    clientRequestId: z.uuid(),
    expectedActiveRevision: z.coerce.number().int().nonnegative(),
  }).safeParse({
    reason: form.get("reason"),
    clientRequestId: form.get("clientRequestId"),
    expectedActiveRevision: form.get("expectedActiveRevision"),
  });
  if (!parsed.success) {
    return NextResponse.json({ message: parsed.error.issues[0]?.message ?? "Vérifiez la correction saisie." }, { status: 400 });
  }
  const pdf = await readPdf(form, true);
  if ("error" in pdf) return NextResponse.json({ message: pdf.error }, { status: 400 });
  try {
    const { supabase } = await getAuthenticatedUser();
    const result = await correctValidatedBankStatementDocument({
      client: supabase,
      protectedPersonId: value.protectedPersonId,
      financialAccountId: value.accountId,
      statementId: value.statementId,
      expectedActiveRevision: parsed.data.expectedActiveRevision,
      clientRequestId: parsed.data.clientRequestId,
      reason: parsed.data.reason,
      fileName: pdf.file.name,
      bytes: pdf.bytes,
    });
    return NextResponse.json({ message: "Le document du relevé a été corrigé et l’ancienne version a été conservée.", activeRevision: result.activeRevision });
  } catch (error) {
    return failure(error);
  }
}
