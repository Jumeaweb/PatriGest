import { z } from "zod";
import type { SharedAccessRole } from "@/types/database";

const countSchema = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);

const shareCapacityRowSchema = z.object({
  share_role: z.enum(["manager", "read_only"]),
  role_limit: countSchema.min(1),
  active_access_count: countSchema,
  pending_invitation_count: countSchema,
  used_count: countSchema,
  remaining_count: countSchema,
  exceeded_by: countSchema,
}).strict().superRefine((row, context) => {
  const used = row.active_access_count + row.pending_invitation_count;
  if (row.used_count !== used) {
    context.addIssue({ code: "custom", message: "Total utilisé incohérent." });
  }
  if (row.remaining_count !== Math.max(row.role_limit - used, 0)) {
    context.addIssue({ code: "custom", message: "Nombre de places restantes incohérent." });
  }
  if (row.exceeded_by !== Math.max(used - row.role_limit, 0)) {
    context.addIssue({ code: "custom", message: "Dépassement incohérent." });
  }
});

const shareCapacityRowsSchema = z.array(shareCapacityRowSchema).length(2).superRefine((rows, context) => {
  if (new Set(rows.map((row) => row.share_role)).size !== 2) {
    context.addIssue({ code: "custom", message: "Rôles de partage incomplets." });
  }
});

export type ProtectedPersonShareCounter = {
  role: SharedAccessRole;
  limit: number;
  activeAccessCount: number;
  pendingInvitationCount: number;
  usedCount: number;
  remainingCount: number;
  exceededBy: number;
};

export type ProtectedPersonShareCapacity = Record<SharedAccessRole, ProtectedPersonShareCounter>;

export function parseProtectedPersonShareCapacity(value: unknown): ProtectedPersonShareCapacity {
  const rows = shareCapacityRowsSchema.parse(value);
  const counters = rows.map((row): ProtectedPersonShareCounter => ({
    role: row.share_role,
    limit: row.role_limit,
    activeAccessCount: row.active_access_count,
    pendingInvitationCount: row.pending_invitation_count,
    usedCount: row.used_count,
    remainingCount: row.remaining_count,
    exceededBy: row.exceeded_by,
  }));
  return Object.fromEntries(counters.map((counter) => [counter.role, counter])) as ProtectedPersonShareCapacity;
}

type SafeDatabaseError = { code?: string | null; message?: string | null } | null;

const MANAGER_LIMIT_MESSAGE = "La limite de gestionnaires partagés est atteinte.";
const READ_ONLY_LIMIT_MESSAGE = "La limite de collaborateurs en lecture seule est atteinte.";
const EXISTING_ACCESS_MESSAGE = "Cette personne dispose déjà d’un accès au dossier.";

export function getSafeShareErrorMessage(error: SafeDatabaseError, fallback: string) {
  if (error?.code === "23514" && error.message === MANAGER_LIMIT_MESSAGE) return MANAGER_LIMIT_MESSAGE;
  if (error?.code === "23514" && error.message === READ_ONLY_LIMIT_MESSAGE) return READ_ONLY_LIMIT_MESSAGE;
  if (error?.code === "23505" && error.message?.includes("dispose déjà d'un accès au dossier")) {
    return EXISTING_ACCESS_MESSAGE;
  }
  if (error?.code === "42501") return "Vous ne disposez pas des droits nécessaires pour cette opération.";
  return fallback;
}
