import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { z } from "zod";
import { isBankStatementDurableOperationsEnabled } from "@/domains/bank-statements/bank-statement-durable-availability";
import {
  BankStatementWriteError,
  createBankStatement,
} from "@/domains/bank-statements/bank-statement-write";
import {
  getBankStatementAccountContext,
  parseStatementMetadata,
  readPdf,
} from "@/domains/bank-statements/server";

type Params = { params: Promise<{ protectedPersonId: string; accountId: string }> };

export async function POST(request: Request, { params }: Params) {
  const { protectedPersonId, accountId } = await params;
  const context = await getBankStatementAccountContext(protectedPersonId, accountId);
  if (!context) return NextResponse.json({ message: "Compte introuvable." }, { status: 404 });
  if (context.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas ajouter de relevé." }, { status: 403 });
  }

  const form = await request.formData();
  const metadata = parseStatementMetadata(form);
  if (!metadata.success) {
    return NextResponse.json({
      message: metadata.error.issues[0]?.message ?? "Métadonnées invalides.",
    }, { status: 400 });
  }
  const pdf = await readPdf(form, false);
  if ("error" in pdf) return NextResponse.json({ message: pdf.error }, { status: 400 });

  const requestedStatementId = z.uuid().safeParse(form.get("clientRequestId"));
  const statementId = isBankStatementDurableOperationsEnabled() && pdf.file
    ? requestedStatementId.success ? requestedStatementId.data : randomUUID()
    : randomUUID();

  try {
    await createBankStatement({
      personId: protectedPersonId,
      accountId,
      statementId,
      metadata: metadata.data,
      pdf: pdf.file && pdf.bytes ? { file: pdf.file, bytes: pdf.bytes } : null,
    });
    return NextResponse.json({ message: "Le relevé a été ajouté." });
  } catch (error) {
    if (error instanceof BankStatementWriteError) {
      return NextResponse.json({ message: error.message }, { status: error.status });
    }
    return NextResponse.json({ message: "Impossible d’enregistrer le relevé." }, { status: 500 });
  }
}
