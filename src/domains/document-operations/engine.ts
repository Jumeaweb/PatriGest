import { createHash } from "node:crypto";
import type {
  DocumentContentBinding,
  DocumentOperationErrorCode,
  DocumentOperationProgress,
  DocumentOperationRpcGateway,
  DocumentOperationStage,
  DocumentOperationTarget,
  DocumentStorageGateway,
  DurableDocumentBackupStore,
  ExecuteDocumentOperationInput,
  StoredDocumentObject,
} from "./contracts";

export class DocumentOperationError extends Error {
  readonly operationId: string;
  readonly stage: DocumentOperationStage;
  readonly code: DocumentOperationErrorCode;

  constructor(
    operationId: string,
    stage: DocumentOperationStage,
    code: DocumentOperationErrorCode,
    message = "L’opération documentaire n’a pas pu être confirmée.",
  ) {
    super(message);
    this.name = "DocumentOperationError";
    this.operationId = operationId;
    this.stage = stage;
    this.code = code;
  }
}

export class DocumentOperationRpcError extends Error {
  readonly reason: "authorization_lost" | "revision_conflict" | "storage_diverged" | "rpc_rejected";

  constructor(reason: DocumentOperationRpcError["reason"]) {
    super("La confirmation PostgreSQL de l’opération documentaire a échoué.");
    this.name = "DocumentOperationRpcError";
    this.reason = reason;
  }
}

const unavailableDocumentBackupStore: DurableDocumentBackupStore = {
  available: false,
  async save() { throw new Error("Sauvegarde documentaire durable indisponible."); },
  async load() { return null; },
  async markRestored() { throw new Error("Sauvegarde documentaire durable indisponible."); },
  async remove() { return; },
};

export function describeDocumentContent(
  content: DocumentContentBinding["content"],
): StoredDocumentObject {
  return {
    ...content,
    byteSize: content.bytes.byteLength,
    sha256: createHash("sha256").update(content.bytes).digest("hex"),
  };
}

export function sameStoredDocument(
  left: StoredDocumentObject | null,
  right: StoredDocumentObject | null,
) {
  if (left === null || right === null) return left === right;
  return left.byteSize === right.byteSize
    && left.sha256 === right.sha256
    && left.mimeType === right.mimeType;
}

const TERMINAL_STATES = new Set([
  "completed",
  "compensated",
  "cancelled",
  "administratively_resolved",
]);

type EngineDependencies = {
  rpc: DocumentOperationRpcGateway;
  storage: DocumentStorageGateway;
  backups?: DurableDocumentBackupStore;
};

function safeError(
  operationId: string,
  stage: DocumentOperationStage,
  code: DocumentOperationErrorCode,
  message?: string,
) {
  return new DocumentOperationError(operationId, stage, code, message);
}

function safeRpcError(operationId: string, stage: DocumentOperationStage, error: unknown) {
  return safeError(
    operationId,
    stage,
    error instanceof DocumentOperationRpcError ? error.reason : "rpc_rejected",
  );
}

function desiredFor(
  operationId: string,
  target: DocumentOperationTarget,
  contents: Map<string, StoredDocumentObject>,
) {
  if (target.forwardAction === "delete") return null;
  const desired = contents.get(target.role);
  if (!desired) {
    throw safeError(
      operationId,
      "preflight",
      "invalid_contract",
      `Le contenu de la cible « ${target.role} » est absent.`,
    );
  }
  return desired;
}

function assertOperationContract(
  progress: DocumentOperationProgress,
  input: ExecuteDocumentOperationInput,
) {
  const expectedKind = progress.workflow.startsWith("transaction_proof_")
    ? "transaction_proof"
    : progress.workflow.startsWith("bank_statement_")
      ? "bank_statement"
      : progress.workflow.startsWith("management_report_")
        ? "management_report"
        : null;
  if (!expectedKind || input.finalization.kind !== expectedKind) {
    throw safeError(
      input.operationId,
      "preflight",
      "invalid_contract",
      "Le contrat métier ne correspond pas à la réservation documentaire.",
    );
  }
  const roles = new Set<string>();
  for (const binding of input.contents) {
    if (roles.has(binding.targetRole) || binding.content.bytes.byteLength === 0) {
      throw safeError(input.operationId, "preflight", "invalid_contract");
    }
    const maxSize = expectedKind === "management_report" ? 20 * 1024 * 1024 : 10 * 1024 * 1024;
    const allowedMimeTypes = expectedKind === "transaction_proof"
      ? new Set(["application/pdf", "image/jpeg", "image/png"])
      : new Set(["application/pdf"]);
    if (
      binding.content.bytes.byteLength > maxSize
      || !allowedMimeTypes.has(binding.content.mimeType)
    ) {
      throw safeError(input.operationId, "preflight", "invalid_contract");
    }
    roles.add(binding.targetRole);
  }
  for (const target of progress.targets) {
    if (target.forwardAction !== "delete" && !roles.has(target.role)) {
      throw safeError(
        input.operationId,
        "preflight",
        "invalid_contract",
        `Le contenu de la cible « ${target.role} » est absent.`,
      );
    }
  }
  const expectedRoles = new Set(progress.targets
    .filter(({ forwardAction }) => forwardAction !== "delete")
    .map(({ role }) => role));
  if ([...roles].some((role) => !expectedRoles.has(role as DocumentOperationTarget["role"]))) {
    throw safeError(input.operationId, "preflight", "invalid_contract");
  }
  if (input.contents.length === 1) {
    const expectedSize = input.contents[0].content.bytes.byteLength;
    if (input.finalization.fileSize !== expectedSize) {
      throw safeError(input.operationId, "preflight", "invalid_contract");
    }
  }
}

export class DocumentOperationEngine {
  private readonly rpc: DocumentOperationRpcGateway;
  private readonly storage: DocumentStorageGateway;
  private readonly backups: DurableDocumentBackupStore;

  constructor({ rpc, storage, backups = unavailableDocumentBackupStore }: EngineDependencies) {
    this.rpc = rpc;
    this.storage = storage;
    this.backups = backups;
  }

  getProgress(operationId: string) {
    return this.rpc.getProgress(operationId);
  }

  async start(operationId: string) {
    const progress = await this.rpc.getProgress(operationId);
    if (progress.state !== "reserved") return progress;
    await this.prepareBackupsForStart(progress);
    return this.rpc.start(operationId, progress.revision);
  }

  private async prepareBackupsForStart(progress: DocumentOperationProgress) {
    for (const target of progress.targets) {
      if (target.forwardAction === "insert") continue;
      if (!this.backups.available) {
        throw safeError(progress.operationId, "backup", "backup_unavailable");
      }
      const key = { operationId: progress.operationId, targetId: target.id };
      const existingBackup = await this.backups.load(key);
      if (existingBackup) continue;
      const current = await this.storage.inspect(target);
      if (!current) throw safeError(progress.operationId, "backup", "storage_diverged");
      await this.backups.save(key, current);
      if (!sameStoredDocument(await this.backups.load(key), current)) {
        throw safeError(progress.operationId, "backup", "storage_unverified");
      }
    }
  }

  async execute(input: ExecuteDocumentOperationInput): Promise<DocumentOperationProgress> {
    let progress = await this.rpc.getProgress(input.operationId);
    if (TERMINAL_STATES.has(progress.state)) return progress;
    if (progress.state === "attention_required") {
      throw safeError(input.operationId, "progress", "attention_required");
    }

    assertOperationContract(progress, input);
    const contents = new Map(
      input.contents.map((binding: DocumentContentBinding) => [
        binding.targetRole,
        describeDocumentContent(binding.content),
      ]),
    );

    if (progress.state === "compensating") {
      return this.compensate(progress, contents, "RESUME_COMPENSATION");
    }

    await this.prepareBackups(progress, contents);

    if (progress.state === "reserved") {
      try {
        progress = await this.rpc.start(input.operationId, progress.revision);
      } catch (error) {
        throw safeRpcError(input.operationId, "start", error);
      }
    }
    if (progress.state !== "executing") {
      throw safeError(input.operationId, "progress", "invalid_contract");
    }

    try {
      for (const initialTarget of progress.targets) {
        progress = await this.rpc.getProgress(input.operationId);
        const target = progress.targets.find(({ id }) => id === initialTarget.id);
        if (!target) throw safeError(input.operationId, "progress", "invalid_contract");
        if (target.state === "applied") continue;
        if (target.state !== "pending") {
          throw safeError(input.operationId, "progress", "storage_diverged");
        }
        await this.applyTarget(input.operationId, target, contents);
        const recorded = await this.rpc.recordApplied(
          input.operationId,
          target.id,
          progress.revision,
          target.revision,
        );
        progress = {
          ...progress,
          revision: recorded.operationRevision,
          targets: progress.targets.map((item) => item.id === target.id
            ? { ...item, revision: recorded.targetRevision, state: "applied" }
            : item),
        };
      }

      progress = await this.rpc.getProgress(input.operationId);
      await this.rpc.finalize(input.operationId, progress.revision, input.finalization);
      const completed = await this.rpc.getProgress(input.operationId);
      if (completed.state !== "completed") {
        throw safeError(input.operationId, "finalization", "storage_unverified");
      }
      await this.removeBackups(completed);
      return completed;
    } catch (error) {
      if (error instanceof DocumentOperationError && error.code === "storage_diverged") {
        await this.requireAttention(input.operationId, "STORAGE_DIVERGED", progress.revision);
        throw error;
      }
      return this.compensateAfterFailure(input.operationId, contents, error, progress);
    }
  }

  private async prepareBackups(
    progress: DocumentOperationProgress,
    contents: Map<string, StoredDocumentObject>,
  ) {
    for (const target of progress.targets) {
      desiredFor(progress.operationId, target, contents);
      if (target.forwardAction === "insert") continue;
      if (!this.backups.available) {
        throw safeError(
          progress.operationId,
          "backup",
          "backup_unavailable",
          "Une sauvegarde durable vérifiée est requise pour cette opération.",
        );
      }
      const key = { operationId: progress.operationId, targetId: target.id };
      let backup = await this.backups.load(key);
      if (progress.state === "reserved" && !backup) {
        await this.prepareBackupsForStart(progress);
        backup = await this.backups.load(key);
      }
      if (!backup) throw safeError(progress.operationId, "backup", "backup_missing");
    }
  }

  private async applyTarget(
    operationId: string,
    target: DocumentOperationTarget,
    contents: Map<string, StoredDocumentObject>,
  ) {
    const desired = desiredFor(operationId, target, contents);
    const before = await this.storage.inspect(target);
    if (sameStoredDocument(before, desired)) return;

    if (target.forwardAction === "insert") {
      if (before) throw safeError(operationId, "mutation", "storage_diverged");
      try {
        await this.storage.upload(target, desired!, false);
      } catch {
        const afterUnknown = await this.storage.inspect(target);
        if (sameStoredDocument(afterUnknown, desired)) return;
        if (afterUnknown) throw safeError(operationId, "mutation", "storage_diverged");
        throw safeError(operationId, "mutation", "ambiguous_mutation");
      }
    } else if (target.forwardAction === "update") {
      const backup = await this.loadBackup(operationId, target.id);
      if (!sameStoredDocument(before, backup)) {
        throw safeError(operationId, "mutation", "storage_diverged");
      }
      try {
        await this.storage.upload(target, desired!, true);
      } catch {
        const afterUnknown = await this.storage.inspect(target);
        if (sameStoredDocument(afterUnknown, desired)) return;
        if (!sameStoredDocument(afterUnknown, backup)) {
          throw safeError(operationId, "mutation", "storage_diverged");
        }
        throw safeError(operationId, "mutation", "ambiguous_mutation");
      }
    } else {
      const backup = await this.loadBackup(operationId, target.id);
      if (!sameStoredDocument(before, backup)) {
        throw safeError(operationId, "mutation", "storage_diverged");
      }
      try {
        await this.storage.remove(target);
      } catch {
        const afterUnknown = await this.storage.inspect(target);
        if (afterUnknown === null) return;
        if (!sameStoredDocument(afterUnknown, backup)) {
          throw safeError(operationId, "mutation", "storage_diverged");
        }
        throw safeError(operationId, "mutation", "ambiguous_mutation");
      }
    }

    const after = await this.storage.inspect(target);
    if (!sameStoredDocument(after, desired)) {
      throw safeError(operationId, "verification", "storage_unverified");
    }
  }

  private async compensateAfterFailure(
    operationId: string,
    contents: Map<string, StoredDocumentObject>,
    cause: unknown,
    knownProgress: DocumentOperationProgress,
  ) {
    let progress: DocumentOperationProgress;
    try {
      progress = await this.rpc.getProgress(operationId);
      if (progress.state === "completed") return progress;
      await this.compensate(progress, contents, "ENGINE_FAILURE");
    } catch {
      await this.requireAttention(operationId, "COMPENSATION_FAILED", knownProgress.revision);
      throw safeError(operationId, "compensation", "compensation_failed");
    }
    if (cause instanceof DocumentOperationError) throw cause;
    throw safeRpcError(operationId, "confirmation", cause);
  }

  private async compensate(
    initial: DocumentOperationProgress,
    contents: Map<string, StoredDocumentObject>,
    safeCode: string,
  ) {
    let progress = initial;
    if (progress.state !== "compensating") {
      progress = await this.rpc.beginCompensation(
        progress.operationId,
        progress.revision,
        safeCode,
      );
      progress = await this.rpc.getProgress(progress.operationId);
    }

    for (const initialTarget of progress.targets) {
      progress = await this.rpc.getProgress(progress.operationId);
      const target = progress.targets.find(({ id }) => id === initialTarget.id);
      if (!target) throw safeError(progress.operationId, "compensation", "compensation_failed");
      if (target.state === "compensated") continue;

      const desired = desiredFor(progress.operationId, target, contents);
      if (target.forwardAction === "insert") {
        const current = await this.storage.inspect(target);
        if (current && !sameStoredDocument(current, desired)) {
          throw safeError(progress.operationId, "compensation", "storage_diverged");
        }
        if (current) await this.storage.remove(target);
        if (await this.storage.inspect(target)) {
          throw safeError(progress.operationId, "compensation", "storage_unverified");
        }
      } else {
        const backup = await this.loadBackup(progress.operationId, target.id);
        const current = await this.storage.inspect(target);
        if (!sameStoredDocument(current, backup) && !sameStoredDocument(current, desired)) {
          throw safeError(progress.operationId, "compensation", "storage_diverged");
        }
        if (!sameStoredDocument(current, backup)) {
          await this.storage.upload(target, backup, true);
        }
        if (!sameStoredDocument(await this.storage.inspect(target), backup)) {
          throw safeError(progress.operationId, "compensation", "storage_unverified");
        }
        await this.backups.markRestored({
          operationId: progress.operationId,
          targetId: target.id,
        });
      }

      if (target.state === "compensating") {
        const recorded = await this.rpc.recordCompensated(
          progress.operationId,
          target.id,
          progress.revision,
          target.revision,
        );
        progress = {
          ...progress,
          revision: recorded.operationRevision,
        };
      }
    }
    progress = await this.rpc.getProgress(progress.operationId);
    await this.rpc.completeCompensation(progress.operationId, progress.revision);
    const compensated = await this.rpc.getProgress(progress.operationId);
    if (compensated.state !== "compensated") {
      throw safeError(progress.operationId, "compensation", "compensation_failed");
    }
    await this.removeBackups(compensated);
    return compensated;
  }

  private async loadBackup(operationId: string, targetId: string) {
    if (!this.backups.available) {
      throw safeError(operationId, "backup", "backup_unavailable");
    }
    const backup = await this.backups.load({ operationId, targetId });
    if (!backup) throw safeError(operationId, "backup", "backup_missing");
    return backup;
  }

  private async removeBackups(progress: DocumentOperationProgress) {
    if (!this.backups.available) return;
    await Promise.all(progress.targets.map((target) => this.backups.remove({
      operationId: progress.operationId,
      targetId: target.id,
    })));
  }

  private async requireAttention(
    operationId: string,
    safeCode: string,
    fallbackRevision?: number,
  ) {
    let revision = fallbackRevision;
    try {
      const progress = await this.rpc.getProgress(operationId);
      if (progress.state === "attention_required" || TERMINAL_STATES.has(progress.state)) return;
      revision = progress.revision;
    } catch {
      // La RPC d’attention reste autorisée à l’initiateur après perte de droits.
    }
    if (revision === undefined) return;
    try {
      await this.rpc.markAttention(operationId, revision, safeCode);
    } catch {
      // L’état reste volontairement non terminal si la révision a aussi changé.
    }
  }
}
