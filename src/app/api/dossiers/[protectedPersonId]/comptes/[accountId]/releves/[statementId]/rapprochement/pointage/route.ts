import { NextResponse } from "next/server";
import { z } from "zod";
import {
  activateCompleteBankReconciliation,
  BankReconciliationServiceError,
  getBankReconciliation,
  getOutstandingTransactionPage,
  setOutstandingTransaction,
} from "@/domains/bank-statements/reconciliation-service";
import { getBankStatementAccountContext } from "@/domains/bank-statements/server";
import { getBankStatement } from "@/domains/bank-statements/services";

type Params = { params: Promise<{ protectedPersonId: string; accountId: string; statementId: string }> };
const mutationSchema = z.object({ transactionId: z.uuid(), outstanding: z.boolean() });

async function context(params: Params["params"]) {
  const ids = await params;
  if (![ids.protectedPersonId, ids.accountId, ids.statementId].every((id) => z.uuid().safeParse(id).success)) return null;
  const [accountContext, statement] = await Promise.all([
    getBankStatementAccountContext(ids.protectedPersonId, ids.accountId),
    getBankStatement(ids.accountId, ids.statementId),
  ]);
  if (!accountContext || !statement) return null;
  const reconciliation = await getBankReconciliation(ids.statementId);
  if (!reconciliation) return null;
  return { ...ids, ...accountContext, statement, reconciliation };
}

function failure(error: unknown) {
  if (error instanceof BankReconciliationServiceError) {
    return NextResponse.json({ message: error.message }, { status: error.status });
  }
  return NextResponse.json({ message: "Impossible de traiter les opérations en circulation." }, { status: 500 });
}

export async function GET(request: Request, { params }: Params) {
  const value = await context(params);
  if (!value) return NextResponse.json({ message: "Rapprochement introuvable." }, { status: 404 });
  try {
    const cursor = new URL(request.url).searchParams.get("cursor");
    return NextResponse.json(await getOutstandingTransactionPage(value.reconciliation.id, cursor));
  } catch (error) {
    return failure(error);
  }
}

export async function POST(_request: Request, { params }: Params) {
  const value = await context(params);
  if (!value) return NextResponse.json({ message: "Rapprochement introuvable." }, { status: 404 });
  if (value.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas activer le rapprochement détaillé." }, { status: 403 });
  }
  try {
    await activateCompleteBankReconciliation(value.reconciliation.id);
    return NextResponse.json(await getOutstandingTransactionPage(value.reconciliation.id, null));
  } catch (error) {
    return failure(error);
  }
}

export async function PATCH(request: Request, { params }: Params) {
  const value = await context(params);
  if (!value) return NextResponse.json({ message: "Rapprochement introuvable." }, { status: 404 });
  if (value.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas modifier le rapprochement détaillé." }, { status: 403 });
  }
  const parsed = mutationSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ message: "Opération invalide." }, { status: 400 });
  try {
    await setOutstandingTransaction(value.reconciliation.id, parsed.data.transactionId, parsed.data.outstanding);
    return NextResponse.json(await getOutstandingTransactionPage(value.reconciliation.id, null));
  } catch (error) {
    return failure(error);
  }
}
