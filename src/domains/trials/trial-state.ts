import { z } from "zod";

export const ACCOUNT_TRIAL_STATES = [
  "not_authorized",
  "terms_required",
  "awaiting_activation",
  "active",
  "suspended",
  "deletion_due",
  "subscribed",
  "legacy_access",
] as const;

export type AccountTrialStateName = (typeof ACCOUNT_TRIAL_STATES)[number];

export type AccountTrialState = {
  state: AccountTrialStateName;
  termsVersion: string | null;
  termsAcceptedAt: string | null;
  startedAt: string | null;
  endsAt: string | null;
  deletionEligibleAt: string | null;
  remainingDays: number;
  activeDossierLimit: number;
  activeDossierCount: number;
  enforcementEnabled: boolean;
};

const rowSchema = z.object({
  state: z.enum(ACCOUNT_TRIAL_STATES),
  terms_version: z.string().min(1).nullable(),
  terms_accepted_at: z.string().nullable(),
  started_at: z.string().nullable(),
  ends_at: z.string().nullable(),
  deletion_eligible_at: z.string().nullable(),
  remaining_days: z.number().int().min(0),
  active_dossier_limit: z.number().int().positive(),
  active_dossier_count: z.number().int().min(0),
  enforcement_enabled: z.boolean(),
}).strict();

export function parseAccountTrialState(value: unknown): AccountTrialState {
  const rows = z.array(rowSchema).length(1).parse(value);
  const row = rows[0];
  return {
    state: row.state,
    termsVersion: row.terms_version,
    termsAcceptedAt: row.terms_accepted_at,
    startedAt: row.started_at,
    endsAt: row.ends_at,
    deletionEligibleAt: row.deletion_eligible_at,
    remainingDays: row.remaining_days,
    activeDossierLimit: row.active_dossier_limit,
    activeDossierCount: row.active_dossier_count,
    enforcementEnabled: row.enforcement_enabled,
  };
}

export function isAccountTrialRestricted(state: AccountTrialStateName) {
  return state === "suspended" || state === "deletion_due";
}
