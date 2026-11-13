import { NextResponse } from "next/server";
import { z } from "zod";
import {
  BankReconciliationServiceError,
  acknowledgeTransactionBankingImpact,
  buildBankReconciliationControl,
  createBankReconciliationDraft,
  getBankReconciliation,
  getTransactionBankingImpacts,
  validateBankReconciliation,
} from "@/domains/bank-statements/reconciliation-service";
import { getBankStatementAccountContext } from "@/domains/bank-statements/server";
import { getBankStatement } from "@/domains/bank-statements/services";

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
  if (error instanceof BankReconciliationServiceError) {
    return NextResponse.json({ message: error.message }, { status: error.status });
  }
  return NextResponse.json({ message: "Impossible de traiter le contrôle bancaire." }, { status: 500 });
}

export async function GET(_request: Request, { params }: Params) {
  const context = await getContext(params);
  if (!context) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  try {
    const reconciliation = await getBankReconciliation(context.statementId);
    const control = await buildBankReconciliationControl(
      context.protectedPersonId,
      context.account,
      context.statement,
      reconciliation,
    );
    const impacts = control.reconciliationId && control.status === "draft" ? await getTransactionBankingImpacts(control.reconciliationId) : [];
    return NextResponse.json({ ...control, impacts });
  } catch (error) {
    return failure(error);
  }
}

export async function POST(_request: Request, { params }: Params) {
  const context = await getContext(params);
  if (!context) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas créer ce contrôle bancaire." }, { status: 403 });
  }
  try {
    const reconciliation = await createBankReconciliationDraft(context.statement, context.account);
    const control = await buildBankReconciliationControl(
      context.protectedPersonId,
      context.account,
      context.statement,
      reconciliation,
    );
    const impacts = control.reconciliationId ? await getTransactionBankingImpacts(control.reconciliationId) : [];
    return NextResponse.json({ ...control, impacts });
  } catch (error) {
    return failure(error);
  }
}

export async function PUT(request: Request, { params }: Params) {
  const context = await getContext(params);
  if (!context) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only" || context.person.archived_at) return NextResponse.json({ message: "Vous ne pouvez pas reconnaître cet impact bancaire." }, { status: 403 });
  try {
    const body = await request.json() as { impactId?: unknown; justification?: unknown };
    const impactId = z.uuid().safeParse(body.impactId);
    if (!impactId.success || typeof body.justification !== "string") return NextResponse.json({ message: "Vérifiez la reconnaissance saisie." }, { status: 400 });
    const reconciliation = await getBankReconciliation(context.statementId);
    if (!reconciliation || reconciliation.status !== "draft") return NextResponse.json({ message: "Contrôle bancaire introuvable." }, { status: 404 });
    await acknowledgeTransactionBankingImpact(reconciliation.id, impactId.data, body.justification);
    const control = await buildBankReconciliationControl(context.protectedPersonId, context.account, context.statement, reconciliation);
    const impacts = await getTransactionBankingImpacts(reconciliation.id);
    return NextResponse.json({ ...control, impacts });
  } catch (error) {
    return failure(error);
  }
}

export async function PATCH(_request: Request, { params }: Params) {
  const context = await getContext(params);
  if (!context) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas valider ce contrôle bancaire." }, { status: 403 });
  }
  try {
    const reconciliation = await getBankReconciliation(context.statementId);
    if (!reconciliation) {
      return NextResponse.json({ message: "Contrôle bancaire introuvable." }, { status: 404 });
    }
    const validated = await validateBankReconciliation(reconciliation.id);
    const control = await buildBankReconciliationControl(
      context.protectedPersonId,
      context.account,
      context.statement,
      validated,
    );
    return NextResponse.json({ ...control, impacts: [] });
  } catch (error) {
    return failure(error);
  }
}
