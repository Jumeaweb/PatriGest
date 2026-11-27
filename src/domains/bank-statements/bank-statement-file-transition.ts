import "server-only";

import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Database } from "@/types/database";
import type { BankStatementReservationClient } from "./bank-statement-durable-reservation";

const reservationSchema = z.object({ id: z.uuid(), storage_path: z.string(), state: z.enum(["reserved", "published", "retired"]) });
const rowsSchema = z.array(z.object({ storage_path: z.string() }));

export async function cleanRetiredBankStatementFiles(statementId: string) {
  try {
    const admin = createAdminClient();
    const result = await (admin as unknown as BankStatementReservationClient).rpc("list_retired_bank_statement_files", { p_statement: statementId });
    const rows = rowsSchema.safeParse(result.data);
    if (result.error || !rows.success) throw new Error("list");
    for (const row of rows.data) {
      const removed = await admin.storage.from("bank-statements").remove([row.storage_path]);
      if (removed.error) throw new Error("remove");
    }
  } catch {
    console.error("BANK_STATEMENT_RETIREMENT_PENDING", { statementId });
  }
}

export async function publishBankStatementFile(input: {
  client: SupabaseClient<Database>; personId: string; accountId: string; statementId: string;
  expectedUpdatedAt: string | null; requestId: string; bytes: Uint8Array; fileName: string;
  metadata: { startDate: string | null; endDate: string; balance: number | null; note: string | null };
}) {
  const sha256 = createHash("sha256").update(input.bytes).digest("hex");
  const caller = input.client as unknown as BankStatementReservationClient;
  const args = {
    p_person: input.personId, p_account: input.accountId, p_statement: input.statementId,
    p_expected_updated_at: input.expectedUpdatedAt, p_request: input.requestId,
    p_payload: { ...input.metadata, fileName: input.fileName, sha256, size: input.bytes.length },
  };
  async function reserve(request: string) {
    const result = await caller.rpc("reserve_unreconciled_bank_statement_file", { ...args, p_request: request });
    if (result.error) throw result.error;
    return z.array(reservationSchema).length(1).parse(result.data)[0];
  }
  const first = await reserve(input.requestId);
  if (first.state === "retired") {
    const old = createAdminClient() as unknown as BankStatementReservationClient;
    await old.rpc("reconcile_unpublished_bank_statement_file", { p_edit: first.id });
    await cleanRetiredBankStatementFiles(input.statementId);
  }
  const draft = first.state === "retired" ? await reserve(randomUUID()) : first;
  if (draft.state === "published") {
    await cleanRetiredBankStatementFiles(input.statementId);
    return;
  }
  if (draft.state === "retired") throw new Error("Ce dépôt a été annulé.");

  const admin = createAdminClient();
  const service = admin as unknown as BankStatementReservationClient;
  const storage = admin.storage.from("bank-statements");
  try {
    // Even if upload returns an error, the unique reserved path may already
    // hold these exact bytes after a lost Storage response.
    const uploaded = await fetchExistingOrUpload(storage, input.client.storage.from("bank-statements"), draft.storage_path, input.bytes);
    if (uploaded.error || !uploaded.data?.id || !uploaded.data.version) throw new Error("PDF non disponible.");

    const candidate = await storage.download(draft.storage_path);
    if (candidate.error || !candidate.data || candidate.data.size !== input.bytes.length
        || createHash("sha256").update(new Uint8Array(await candidate.data.arrayBuffer())).digest("hex") !== sha256) {
      throw new Error("Le PDF réservé ne correspond pas au document téléversé.");
    }
    const verified = await service.rpc("verify_staged_bank_statement_file", {
      p_edit: draft.id, p_object: uploaded.data.id, p_version: uploaded.data.version, p_sha256: sha256,
    });
    if (verified.error || verified.data !== true) throw new Error("Le PDF n’a pas pu être vérifié.");
    const published = await caller.rpc("publish_unreconciled_bank_statement_file", { p_edit: draft.id });
    if (published.error) throw published.error;
  } catch (error) {
    const reconciled = await service.rpc("reconcile_unpublished_bank_statement_file", { p_edit: draft.id });
    if (!reconciled.error && (reconciled.data === "retired" || reconciled.data === "published")) {
      await cleanRetiredBankStatementFiles(input.statementId);
    }
    if (reconciled.error || reconciled.data !== "published") throw error;
    return;
  }
  await cleanRetiredBankStatementFiles(input.statementId);
}

async function fetchExistingOrUpload(
  storage: ReturnType<ReturnType<typeof createAdminClient>["storage"]["from"]>,
  writer: typeof storage,
  path: string,
  bytes: Uint8Array,
) {
  const existing = await storage.info(path);
  if (!existing.error) return existing;
  try {
    await writer.upload(path, bytes, { contentType: "application/pdf", upsert: false });
  } catch {
    // Check the authoritative object rather than relying on a transport error.
  }
  return storage.info(path);
}
