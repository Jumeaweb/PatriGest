export type InfrastructureProvider = "supabase" | "vercel" | "resend" | "gandi";
export type InfrastructureStatus = "normal" | "warning" | "critical" | "unavailable";

type InfrastructureBase = {
  provider: InfrastructureProvider;
  status: InfrastructureStatus;
  checkedAt: string;
};

export type SupabaseInfrastructureResult = InfrastructureBase & {
  provider: "supabase";
  databaseBytes: number | null;
  databaseQuotaBytes: number;
  databasePercent: number | null;
  storageBytes: number | null;
  storageQuotaBytes: number;
  storagePercent: number | null;
  message?: string;
};

export type VercelInfrastructureResult = InfrastructureBase & {
  provider: "vercel";
  deploymentState: string | null;
  deployedAt: string | null;
  commitSha: string | null;
  message?: string;
};

export type ResendInfrastructureResult = InfrastructureBase & {
  provider: "resend";
  periodDays: 30;
  sent: number | null;
  deliveryRate: number | null;
  bounceRate: number | null;
  complaintRate: number | null;
  message?: string;
};

export type GandiInfrastructureResult = InfrastructureBase & {
  provider: "gandi";
  domain: "patrigest.fr";
  expiresAt: string | null;
  autoRenew: boolean | null;
  daysUntilExpiration: number | null;
  message?: string;
};

export type InfrastructureResult = SupabaseInfrastructureResult | VercelInfrastructureResult | ResendInfrastructureResult | GandiInfrastructureResult;
export type InfrastructureAdapters = Record<InfrastructureProvider, () => Promise<InfrastructureResult>>;

export const SUPABASE_DATABASE_QUOTA_BYTES = 500 * 1024 * 1024;
export const SUPABASE_STORAGE_QUOTA_BYTES = 1024 * 1024 * 1024;
export const INFRASTRUCTURE_UNAVAILABLE_MESSAGE = "Données temporairement indisponibles";

const severity: Record<InfrastructureStatus, number> = { normal: 0, warning: 1, critical: 2, unavailable: 3 };

export function mostSevereStatus(...statuses: InfrastructureStatus[]) {
  return statuses.reduce((current, candidate) => severity[candidate] > severity[current] ? candidate : current, "normal");
}

export function getUsageStatus(percent: number): InfrastructureStatus {
  if (percent >= 90) return "critical";
  if (percent >= 70) return "warning";
  return "normal";
}

export function buildSupabaseResult(databaseBytes: number, storageBytes: number, checkedAt: string): SupabaseInfrastructureResult {
  const databasePercent = databaseBytes / SUPABASE_DATABASE_QUOTA_BYTES * 100;
  const storagePercent = storageBytes / SUPABASE_STORAGE_QUOTA_BYTES * 100;
  return {
    provider: "supabase",
    status: mostSevereStatus(getUsageStatus(databasePercent), getUsageStatus(storagePercent)),
    checkedAt,
    databaseBytes,
    databaseQuotaBytes: SUPABASE_DATABASE_QUOTA_BYTES,
    databasePercent,
    storageBytes,
    storageQuotaBytes: SUPABASE_STORAGE_QUOTA_BYTES,
    storagePercent,
  };
}

export function getVercelStatus(state: string): InfrastructureStatus {
  const normalized = state.toUpperCase();
  if (normalized === "READY") return "normal";
  if (["BUILDING", "QUEUED", "INITIALIZING"].includes(normalized)) return "warning";
  if (["ERROR", "CANCELED", "BLOCKED"].includes(normalized)) return "critical";
  return "unavailable";
}

export function buildResendResult(metrics: { sent: number; deliveryRate: number; bounceRate: number; complaintRate: number; bounced: number; complained: number }, checkedAt: string): ResendInfrastructureResult {
  return {
    provider: "resend",
    status: metrics.bounced > 0 || metrics.complained > 0 || metrics.bounceRate > 0 || metrics.complaintRate > 0 ? "warning" : "normal",
    checkedAt,
    periodDays: 30,
    sent: metrics.sent,
    deliveryRate: metrics.deliveryRate,
    bounceRate: metrics.bounceRate,
    complaintRate: metrics.complaintRate,
  };
}

export function buildGandiResult(expiresAt: string, autoRenew: boolean, now: Date, checkedAt: string): GandiInfrastructureResult {
  const daysUntilExpiration = Math.ceil((new Date(expiresAt).getTime() - now.getTime()) / 86_400_000);
  const expirationStatus: InfrastructureStatus = daysUntilExpiration <= 30 ? "critical" : daysUntilExpiration <= 90 ? "warning" : "normal";
  return {
    provider: "gandi",
    status: mostSevereStatus(expirationStatus, autoRenew ? "normal" : "warning"),
    checkedAt,
    domain: "patrigest.fr",
    expiresAt,
    autoRenew,
    daysUntilExpiration,
  };
}

export function unavailableInfrastructureResult(provider: InfrastructureProvider, checkedAt: string): InfrastructureResult {
  const unavailable = { status: "unavailable" as const, checkedAt, message: INFRASTRUCTURE_UNAVAILABLE_MESSAGE };
  if (provider === "supabase") return { ...unavailable, provider, databaseBytes: null, databaseQuotaBytes: SUPABASE_DATABASE_QUOTA_BYTES, databasePercent: null, storageBytes: null, storageQuotaBytes: SUPABASE_STORAGE_QUOTA_BYTES, storagePercent: null };
  if (provider === "vercel") return { ...unavailable, provider, deploymentState: null, deployedAt: null, commitSha: null };
  if (provider === "resend") return { ...unavailable, provider, periodDays: 30, sent: null, deliveryRate: null, bounceRate: null, complaintRate: null };
  return { ...unavailable, provider, domain: "patrigest.fr", expiresAt: null, autoRenew: null, daysUntilExpiration: null };
}

export async function collectInfrastructureStatuses(adapters: InfrastructureAdapters, now = new Date()): Promise<InfrastructureResult[]> {
  const providers: InfrastructureProvider[] = ["supabase", "vercel", "resend", "gandi"];
  const settled = await Promise.allSettled(providers.map((provider) => adapters[provider]()));
  return settled.map((result, index) => result.status === "fulfilled" ? result.value : unavailableInfrastructureResult(providers[index], now.toISOString()));
}
