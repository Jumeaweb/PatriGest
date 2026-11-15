import { NextResponse } from "next/server";
import { z } from "zod";
import { downloadBankStatementDocument } from "@/domains/bank-statements/bank-statement-document-versioning";
import { bankStatementContentDisposition } from "@/domains/bank-statements/helpers";
import { getBankStatementAccountContext } from "@/domains/bank-statements/server";
import { getBankStatement } from "@/domains/bank-statements/services";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";

type Params = { params: Promise<{ protectedPersonId: string; accountId: string; statementId: string; versionId: string }> };

export async function GET(request: Request, { params }: Params) {
  const ids = await params;
  if (![ids.protectedPersonId, ids.accountId, ids.statementId, ids.versionId].every((id) => z.uuid().safeParse(id).success)) {
    return NextResponse.json({ message: "Version documentaire introuvable." }, { status: 404 });
  }
  const [context, statement] = await Promise.all([
    getBankStatementAccountContext(ids.protectedPersonId, ids.accountId),
    getBankStatement(ids.accountId, ids.statementId),
  ]);
  if (!context || !statement) return NextResponse.json({ message: "Version documentaire introuvable." }, { status: 404 });
  try {
    const { supabase } = await getAuthenticatedUser();
    const document = await downloadBankStatementDocument({ client: supabase, statementId: ids.statementId, versionId: ids.versionId });
    if (!document) return NextResponse.json({ message: "Version documentaire introuvable." }, { status: 404 });
    const download = new URL(request.url).searchParams.get("download") === "1";
    const name = document.version.originalFileName;
    return new Response(document.bytes, {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": download ? bankStatementContentDisposition(name) : `inline; filename*=UTF-8''${encodeURIComponent(name)}`,
        "Content-Length": String(document.bytes.byteLength),
        "Cache-Control": "private, no-store",
      },
    });
  } catch {
    return NextResponse.json({ message: "Impossible de charger cette version documentaire." }, { status: 500 });
  }
}
