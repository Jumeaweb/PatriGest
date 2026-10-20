export const DOCUMENT_OPERATION_BUCKETS = [
  "transaction-proofs",
  "bank-statements",
  "management-reports",
] as const;

export type DocumentOperationBucket = (typeof DOCUMENT_OPERATION_BUCKETS)[number];
export type DocumentTargetRole = "primary" | "source" | "destination";
export type DocumentMutationAction = "insert" | "update" | "delete";
export type DocumentOperationState =
  | "reserved"
  | "executing"
  | "compensating"
  | "attention_required"
  | "completed"
  | "compensated"
  | "cancelled"
  | "administratively_resolved";
export type DocumentTargetState = "pending" | "applied" | "compensating" | "compensated";

export type DocumentOperationTarget = {
  id: string;
  ordinal: number;
  bucketId: DocumentOperationBucket;
  objectPath: string;
  role: DocumentTargetRole;
  forwardAction: DocumentMutationAction;
  compensationAction: DocumentMutationAction | null;
  state: DocumentTargetState;
  revision: number;
  expectedObjectId: string | null;
  expectedObjectVersion: string | null;
  appliedObjectId: string | null;
  appliedObjectVersion: string | null;
  compensatedObjectId: string | null;
  compensatedObjectVersion: string | null;
};

export type DocumentOperationProgress = {
  operationId: string;
  workflow: string;
  state: DocumentOperationState;
  revision: number;
  safeErrorCode: string | null;
  targets: DocumentOperationTarget[];
};

export type DocumentContent = {
  bytes: Uint8Array;
  mimeType: string;
};

export type StoredDocumentObject = DocumentContent & {
  byteSize: number;
  sha256: string;
  objectId?: string | null;
  objectVersion?: string | null;
};

export type DocumentContentBinding = {
  targetRole: DocumentTargetRole;
  content: DocumentContent;
};

export type TransactionProofFinalization = {
  kind: "transaction_proof";
  fileName: string | null;
  mimeType: string | null;
  fileSize: number | null;
};

export type BankStatementFinalization = {
  kind: "bank_statement";
  statementStartDate: string | null;
  statementEndDate: string | null;
  statementBalance: number | null;
  note: string | null;
  fileName: string | null;
  mimeType: string | null;
  fileSize: number | null;
};

export type ManagementReportFinalization = {
  kind: "management_report";
  fileName: string | null;
  mimeType: string | null;
  fileSize: number | null;
  previewSnapshot: unknown | null;
  snapshotSchemaVersion: number | null;
};

export type DocumentOperationFinalization =
  | TransactionProofFinalization
  | BankStatementFinalization
  | ManagementReportFinalization;

export type ExecuteDocumentOperationInput = {
  operationId: string;
  contents: DocumentContentBinding[];
  finalization: DocumentOperationFinalization;
};

export type DocumentBackupKey = {
  operationId: string;
  targetId: string;
};

export interface DurableDocumentBackupStore {
  readonly available: boolean;
  save(key: DocumentBackupKey, object: StoredDocumentObject): Promise<void>;
  load(key: DocumentBackupKey): Promise<StoredDocumentObject | null>;
  markRestored(key: DocumentBackupKey): Promise<void>;
  remove(key: DocumentBackupKey): Promise<void>;
}

export interface DocumentStorageGateway {
  inspect(target: DocumentOperationTarget): Promise<StoredDocumentObject | null>;
  upload(target: DocumentOperationTarget, content: DocumentContent, upsert: boolean): Promise<void>;
  remove(target: DocumentOperationTarget): Promise<void>;
}

export interface DocumentOperationRpcGateway {
  getProgress(operationId: string): Promise<DocumentOperationProgress>;
  start(operationId: string, expectedRevision: number): Promise<DocumentOperationProgress>;
  recordApplied(
    operationId: string,
    targetId: string,
    expectedOperationRevision: number,
    expectedTargetRevision: number,
  ): Promise<{ operationRevision: number; targetRevision: number }>;
  finalize(
    operationId: string,
    expectedRevision: number,
    finalization: DocumentOperationFinalization,
  ): Promise<number>;
  beginCompensation(
    operationId: string,
    expectedRevision: number,
    safeCode: string,
  ): Promise<DocumentOperationProgress>;
  recordCompensated(
    operationId: string,
    targetId: string,
    expectedOperationRevision: number,
    expectedTargetRevision: number,
  ): Promise<{ operationRevision: number; targetRevision: number }>;
  completeCompensation(operationId: string, expectedRevision: number): Promise<number>;
  markAttention(operationId: string, expectedRevision: number, safeCode: string): Promise<number>;
}

export type DocumentOperationStage =
  | "progress"
  | "preflight"
  | "start"
  | "backup"
  | "mutation"
  | "verification"
  | "confirmation"
  | "finalization"
  | "compensation"
  | "attention";

export type DocumentOperationErrorCode =
  | "invalid_contract"
  | "backup_unavailable"
  | "backup_missing"
  | "storage_diverged"
  | "storage_unverified"
  | "rpc_rejected"
  | "revision_conflict"
  | "authorization_lost"
  | "ambiguous_mutation"
  | "compensation_failed"
  | "attention_required";
