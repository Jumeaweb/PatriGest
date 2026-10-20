import "server-only";

import { z } from "zod";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { Json } from "@/types/database";
import type {
  DocumentOperationFinalization,
  DocumentOperationProgress,
  DocumentOperationRpcGateway,
  DocumentOperationTarget,
  DocumentStorageGateway,
  DurableDocumentBackupStore,
} from "./contracts";
import { DOCUMENT_OPERATION_BUCKETS } from "./contracts";
import {
  describeDocumentContent,
  DocumentOperationEngine,
  DocumentOperationRpcError,
} from "./engine";
import { createDurableDocumentBackupStore } from "./durable-backup-store";

const uuid = z.uuid();
const safePath = z.string().min(1).refine((value) => {
  if (value.startsWith("/") || value.includes("\\")) return false;
  return value.split("/").every((segment) => segment !== "" && segment !== "." && segment !== "..");
});
const targetSchema = z.object({
  id: uuid,
  ordinal: z.number().int().positive(),
  bucketId: z.enum(DOCUMENT_OPERATION_BUCKETS),
  objectPath: safePath,
  role: z.enum(["primary", "source", "destination"]),
  forwardAction: z.enum(["insert", "update", "delete"]),
  compensationAction: z.enum(["insert", "update", "delete"]).nullable(),
  state: z.enum(["pending", "applied", "compensating", "compensated"]),
  revision: z.number().int().nonnegative(),
  expectedObjectId: uuid.nullable(),
  expectedObjectVersion: z.string().nullable(),
  appliedObjectId: uuid.nullable(),
  appliedObjectVersion: z.string().nullable(),
  compensatedObjectId: uuid.nullable(),
  compensatedObjectVersion: z.string().nullable(),
});
const progressSchema = z.object({
  operationId: uuid,
  workflow: z.string().min(1),
  state: z.enum([
    "reserved",
    "executing",
    "compensating",
    "attention_required",
    "completed",
    "compensated",
    "cancelled",
    "administratively_resolved",
  ]),
  revision: z.number().int().nonnegative(),
  safeErrorCode: z.string().nullable(),
  targets: z.array(targetSchema).min(1),
});
const transitionSchema = z.object({
  revision: z.number().int().nonnegative(),
  targetRevision: z.number().int().nonnegative(),
});

type RpcResult = { data: unknown; error: unknown | null };
type RpcInvoker = (name: string, args: Record<string, unknown>) => PromiseLike<RpcResult>;

function rpcFailure(error: unknown): never {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : "";
  if (code === "P4O01") throw new DocumentOperationRpcError("authorization_lost");
  if (code === "P4S05") throw new DocumentOperationRpcError("revision_conflict");
  if (code === "P4S04") throw new DocumentOperationRpcError("storage_diverged");
  throw new DocumentOperationRpcError("rpc_rejected");
}

async function invokeRpc(
  client: { rpc: RpcInvoker },
  name: string,
  args: Record<string, unknown>,
) {
  const { data, error } = await client.rpc(name, args);
  if (error) rpcFailure(error);
  return data;
}

function createRpcGateway(client: { rpc: RpcInvoker }): DocumentOperationRpcGateway {
  const getProgress = async (operationId: string) => progressSchema.parse(await invokeRpc(
    client,
    "get_document_operation_progress",
    { p_operation_id: operationId },
  )) as DocumentOperationProgress;

  return {
    getProgress,
    async start(operationId, expectedRevision) {
      await invokeRpc(client, "start_document_operation", {
        p_operation_id: operationId,
        p_expected_revision: expectedRevision,
      });
      return getProgress(operationId);
    },
    async recordApplied(operationId, targetId, expectedOperationRevision, expectedTargetRevision) {
      const result = transitionSchema.parse(await invokeRpc(
        client,
        "record_document_operation_target_applied",
        {
          p_operation_id: operationId,
          p_target_id: targetId,
          p_expected_operation_revision: expectedOperationRevision,
          p_expected_target_revision: expectedTargetRevision,
        },
      ));
      return { operationRevision: result.revision, targetRevision: result.targetRevision };
    },
    async finalize(operationId, expectedRevision, finalization) {
      let rpcName: string;
      let args: Record<string, unknown>;
      if (finalization.kind === "transaction_proof") {
        rpcName = "finalize_transaction_proof_document_operation";
        args = proofFinalizationArgs(operationId, expectedRevision, finalization);
      } else if (finalization.kind === "bank_statement") {
        rpcName = "finalize_bank_statement_document_operation";
        args = statementFinalizationArgs(operationId, expectedRevision, finalization);
      } else {
        rpcName = "finalize_management_report_document_operation";
        args = reportFinalizationArgs(operationId, expectedRevision, finalization);
      }
      return z.number().int().nonnegative().parse(await invokeRpc(client, rpcName, args));
    },
    async beginCompensation(operationId, expectedRevision, safeCode) {
      await invokeRpc(client, "begin_document_operation_compensation", {
        p_operation_id: operationId,
        p_expected_revision: expectedRevision,
        p_safe_code: safeCode,
      });
      return getProgress(operationId);
    },
    async recordCompensated(operationId, targetId, expectedOperationRevision, expectedTargetRevision) {
      const result = transitionSchema.parse(await invokeRpc(
        client,
        "record_document_operation_target_compensated",
        {
          p_operation_id: operationId,
          p_target_id: targetId,
          p_expected_operation_revision: expectedOperationRevision,
          p_expected_target_revision: expectedTargetRevision,
        },
      ));
      return { operationRevision: result.revision, targetRevision: result.targetRevision };
    },
    async completeCompensation(operationId, expectedRevision) {
      return z.number().int().nonnegative().parse(await invokeRpc(
        client,
        "complete_document_operation_compensation",
        { p_operation_id: operationId, p_expected_revision: expectedRevision },
      ));
    },
    async markAttention(operationId, expectedRevision, safeCode) {
      return z.number().int().nonnegative().parse(await invokeRpc(
        client,
        "mark_document_operation_attention_required",
        {
          p_operation_id: operationId,
          p_expected_revision: expectedRevision,
          p_safe_code: safeCode,
        },
      ));
    },
  };
}

function proofFinalizationArgs(
  operationId: string,
  expectedRevision: number,
  value: Extract<DocumentOperationFinalization, { kind: "transaction_proof" }>,
) {
  return {
    p_operation_id: operationId,
    p_expected_revision: expectedRevision,
    p_file_name: value.fileName,
    p_mime_type: value.mimeType,
    p_file_size: value.fileSize,
  };
}

function statementFinalizationArgs(
  operationId: string,
  expectedRevision: number,
  value: Extract<DocumentOperationFinalization, { kind: "bank_statement" }>,
) {
  return {
    p_operation_id: operationId,
    p_expected_revision: expectedRevision,
    p_statement_start_date: value.statementStartDate,
    p_statement_end_date: value.statementEndDate,
    p_statement_balance: value.statementBalance,
    p_note: value.note,
    p_file_name: value.fileName,
    p_mime_type: value.mimeType,
    p_file_size: value.fileSize,
  };
}

function reportFinalizationArgs(
  operationId: string,
  expectedRevision: number,
  value: Extract<DocumentOperationFinalization, { kind: "management_report" }>,
) {
  return {
    p_operation_id: operationId,
    p_expected_revision: expectedRevision,
    p_file_name: value.fileName,
    p_mime_type: value.mimeType,
    p_file_size: value.fileSize,
    p_preview_snapshot: value.previewSnapshot as Json | null,
    p_snapshot_schema_version: value.snapshotSchemaVersion,
  };
}

function createStorageGateway(admin: ReturnType<typeof createAdminClient>): DocumentStorageGateway {
  const bucket = (target: DocumentOperationTarget) => admin.storage.from(target.bucketId);
  return {
    async inspect(target) {
      const storage = bucket(target);
      const exists = await storage.exists(target.objectPath);
      if (!exists.data) return null;
      if (exists.error) throw new Error("Vérification Storage impossible.");
      const downloaded = await storage.download(target.objectPath);
      if (downloaded.error || !downloaded.data) {
        throw new Error("Lecture Storage impossible.");
      }
      return describeDocumentContent({
        bytes: new Uint8Array(await downloaded.data.arrayBuffer()),
        mimeType: downloaded.data.type || "application/octet-stream",
      });
    },
    async upload(target, content, upsert) {
      const { error } = await bucket(target).upload(target.objectPath, content.bytes, {
        contentType: content.mimeType,
        upsert,
      });
      if (error) throw new Error("Écriture Storage impossible.");
    },
    async remove(target) {
      const { error } = await bucket(target).remove([target.objectPath]);
      if (error) throw new Error("Suppression Storage impossible.");
    },
  };
}

export async function createServerDocumentOperationEngine(options?: {
  backupStore?: DurableDocumentBackupStore;
}) {
  const userClient = await createClient();
  const { data, error } = await userClient.auth.getClaims();
  if (error || !data?.claims?.sub) throw new Error("Authentification requise.");

  const admin = createAdminClient();
  return new DocumentOperationEngine({
    rpc: createRpcGateway(userClient as unknown as { rpc: RpcInvoker }),
    storage: createStorageGateway(admin),
    backups: options?.backupStore ?? createDurableDocumentBackupStore(
      userClient as unknown as { rpc: RpcInvoker },
      admin as unknown as Parameters<typeof createDurableDocumentBackupStore>[1],
    ),
  });
}
