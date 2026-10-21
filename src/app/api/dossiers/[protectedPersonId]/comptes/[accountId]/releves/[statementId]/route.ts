import { NextResponse } from "next/server";
import { z } from "zod";
import { isBankStatementDurableOperationsEnabled } from "@/domains/bank-statements/bank-statement-durable-availability";
import {
  BankStatementWriteError,
  deleteBankStatement,
  deleteBankStatementDocument,
  updateBankStatement,
} from "@/domains/bank-statements/bank-statement-write";
import {
  bankStatementContentDisposition,
  bankStatementDownloadName,
} from "@/domains/bank-statements/helpers";
import {
  getBankStatementAccountContext,
  parseStatementMetadata,
  readPdf,
} from "@/domains/bank-statements/server";
import { getBankStatement } from "@/domains/bank-statements/services";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

type Params = {
  params: Promise<{
    protectedPersonId: string;
    accountId: string;
    statementId: string;
  }>;
};

async function context(params: Params["params"]) {
  const ids = await params;
  if (!z.uuid().safeParse(ids.statementId).success) return null;
  const accountContext = await getBankStatementAccountContext(
    ids.protectedPersonId,
    ids.accountId,
  );
  if (!accountContext) return null;
  const statement = await getBankStatement(ids.accountId, ids.statementId);
  if (!statement) return null;
  return { ...ids, ...accountContext, statement };
}

export async function GET(request: Request, { params }: Params) {
  const value = await context(params);
  if (
    !value
    || !value.statement.original_file_name
    || !value.statement.mime_type
    || value.statement.file_size === null
  ) {
    return NextResponse.json({ message: "Aucun PDF n’est associé à ce relevé." }, { status: 404 });
  }

  const { supabase } = await getAuthenticatedUser();
  const download = new URL(request.url).searchParams.get("download") === "1";
  const name = bankStatementDownloadName(
    value.statement.statement_end_date,
    value.account.institution_name,
    value.account.account_reference,
  );
  if (download) {
    const { data, error } = await supabase.storage.from("bank-statements")
      .download(value.statement.storage_path);
    if (error || !data) {
      return NextResponse.json({ message: "Impossible de télécharger le relevé." }, { status: 500 });
    }
    return new Response(await data.arrayBuffer(), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": bankStatementContentDisposition(name),
        "Content-Length": String(data.size),
        "Cache-Control": "private, no-store",
      },
    });
  }

  const { data, error } = await supabase.storage.from("bank-statements")
    .createSignedUrl(value.statement.storage_path, 60);
  if (error || !data) {
    return NextResponse.json({ message: "Impossible d’ouvrir le relevé." }, { status: 500 });
  }
  return NextResponse.redirect(data.signedUrl);
}

export async function POST(request: Request, { params }: Params) {
  const value = await context(params);
  if (!value) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (value.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas modifier ce relevé." }, { status: 403 });
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

  try {
    await updateBankStatement({
      personId: value.protectedPersonId,
      accountId: value.accountId,
      statement: value.statement,
      metadata: metadata.data,
      pdf: pdf.file && pdf.bytes ? { file: pdf.file, bytes: pdf.bytes } : null,
    });
    return NextResponse.json({
      message: pdf.file ? "Le relevé a été remplacé." : "Le relevé a été modifié.",
    });
  } catch (error) {
    if (error instanceof BankStatementWriteError) {
      return NextResponse.json({ message: error.message }, { status: error.status });
    }
    return NextResponse.json({ message: "Impossible de modifier le relevé." }, { status: 500 });
  }
}

export async function DELETE(request: Request, { params }: Params) {
  const value = await context(params);
  if (!value) return NextResponse.json({ message: "Relevé introuvable." }, { status: 404 });
  if (value.person.accessRole === "read_only") {
    return NextResponse.json({ message: "Vous ne pouvez pas supprimer ce relevé." }, { status: 403 });
  }

  const documentOnly = isBankStatementDurableOperationsEnabled()
    && new URL(request.url).searchParams.get("document") === "1";
  try {
    if (documentOnly) {
      await deleteBankStatementDocument({
        personId: value.protectedPersonId,
        accountId: value.accountId,
        statement: value.statement,
      });
      return NextResponse.json({ message: "Le PDF du relevé a été supprimé." });
    }

    await deleteBankStatement({
      accountId: value.accountId,
      statement: value.statement,
    });
    return NextResponse.json({ message: "Le relevé a été supprimé." });
  } catch (error) {
    if (error instanceof BankStatementWriteError) {
      return NextResponse.json({ message: error.message }, { status: error.status });
    }
    return NextResponse.json({ message: "Impossible de supprimer le relevé." }, { status: 500 });
  }
}
