import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  buildGandiResult,
  buildResendResult,
  buildSupabaseResult,
  collectInfrastructureStatuses,
  getUsageStatus,
  getVercelStatus,
  SUPABASE_DATABASE_QUOTA_BYTES,
  SUPABASE_STORAGE_QUOTA_BYTES,
} from "./infrastructure-monitoring.ts";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = read("./services/infrastructure-service.ts");
const page = read("../../app/administration/infrastructure/page.tsx");
const dashboard = read("./components/infrastructure-dashboard.tsx");
const supabaseAdapter = read("./services/supabase-infrastructure-service.ts");
const vercelAdapter = read("./services/vercel-infrastructure-service.ts");
const resendAdapter = read("./services/resend-infrastructure-service.ts");
const gandiAdapter = read("./services/gandi-infrastructure-service.ts");
const http = read("./services/infrastructure-http.ts");
const resendTransport = read("../../lib/email/resend-transport.ts");

test("les seuils Supabase suivent 70 et 90 pour chaque quota", () => {
  assert.equal(getUsageStatus(69.99), "normal");
  assert.equal(getUsageStatus(70), "warning");
  assert.equal(getUsageStatus(89.99), "warning");
  assert.equal(getUsageStatus(90), "critical");
  assert.equal(buildSupabaseResult(SUPABASE_DATABASE_QUOTA_BYTES * 0.2, SUPABASE_STORAGE_QUOTA_BYTES * 0.91, "2026-09-27T00:00:00.000Z").status, "critical");
});

test("les états Vercel distinguent succès, attente, échec et valeur inconnue", () => {
  assert.equal(getVercelStatus("READY"), "normal");
  for (const state of ["BUILDING", "QUEUED", "INITIALIZING"]) assert.equal(getVercelStatus(state), "warning");
  for (const state of ["ERROR", "CANCELED", "BLOCKED"]) assert.equal(getVercelStatus(state), "critical");
  assert.equal(getVercelStatus("UNKNOWN"), "unavailable");
});

test("Resend reste normal sans rebond/plainte et passe en attention sinon", () => {
  const base = { sent: 10, deliveryRate: 100, bounceRate: 0, complaintRate: 0, bounced: 0, complained: 0 };
  assert.equal(buildResendResult(base, "2026-09-27T00:00:00.000Z").status, "normal");
  assert.equal(buildResendResult({ ...base, bounced: 1, bounceRate: 10 }, "2026-09-27T00:00:00.000Z").status, "warning");
  assert.equal(buildResendResult({ ...base, complained: 1, complaintRate: 10 }, "2026-09-27T00:00:00.000Z").status, "warning");
});

test("Gandi applique les seuils 90/30 jours et le renouvellement automatique", () => {
  const now = new Date("2026-01-01T00:00:00.000Z");
  const checkedAt = now.toISOString();
  assert.equal(buildGandiResult("2026-04-02T00:00:00.000Z", true, now, checkedAt).status, "normal");
  assert.equal(buildGandiResult("2026-04-01T00:00:00.000Z", true, now, checkedAt).status, "warning");
  assert.equal(buildGandiResult("2026-01-31T00:00:00.000Z", true, now, checkedAt).status, "critical");
  assert.equal(buildGandiResult("2026-12-31T00:00:00.000Z", false, now, checkedAt).status, "warning");
});

test("un adaptateur défaillant ne masque pas les trois autres fournisseurs", async () => {
  const checkedAt = "2026-09-27T00:00:00.000Z";
  const results = await collectInfrastructureStatuses({
    supabase: async () => buildSupabaseResult(1, 1, checkedAt),
    vercel: async () => { throw new Error("secret provider response"); },
    resend: async () => buildResendResult({ sent: 0, deliveryRate: 0, bounceRate: 0, complaintRate: 0, bounced: 0, complained: 0 }, checkedAt),
    gandi: async () => buildGandiResult("2027-12-31T00:00:00.000Z", true, new Date("2026-09-27T00:00:00.000Z"), checkedAt),
  }, new Date(checkedAt));
  assert.deepEqual(results.map((result) => result.status), ["normal", "unavailable", "normal", "normal"]);
  assert.equal(results[1].message, "Données temporairement indisponibles");
  assert.doesNotMatch(JSON.stringify(results), /secret provider response|ACCESS_TOKEN|API_KEY|SERVICE_ROLE_KEY/);
});

test("la page est protégée avant le cache et les fournisseurs restent server-only", () => {
  assert.match(service, /await requirePlatformAdministrator\(\);\s*return getCachedInfrastructureStatuses\(\)/);
  assert.match(service, /Promise\.allSettled|collectInfrastructureStatuses/);
  assert.match(service, /revalidate: 300/);
  assert.match(page, /getInfrastructureDashboard\(\)/);
  for (const source of [service, supabaseAdapter, vercelAdapter, resendAdapter, gandiAdapter, http]) assert.match(source, /import "server-only"/);
  assert.match(http, /INFRASTRUCTURE_PROVIDER_TIMEOUT_MS = 5_000/);
});

test("l'UI expose quatre états textuels et aucun secret", () => {
  for (const label of ["Normal", "Attention", "Critique", "Indisponible"]) assert.match(dashboard, new RegExp(`label: "${label}"`));
  for (const provider of ["Supabase", "Vercel", "Resend", "Gandi"]) assert.match(dashboard, new RegExp(provider));
  assert.doesNotMatch(page + dashboard, /process\.env|ACCESS_TOKEN|API_KEY|SERVICE_ROLE_KEY/);
});

test("les adaptateurs restent en lecture seule et ne renvoient jamais les jetons", () => {
  assert.match(vercelAdapter, /target", "production"/);
  assert.match(resendAdapter, /\/emails\/metrics/);
  assert.match(gandiAdapter, /\/v5\/domain\/domains/);
  assert.doesNotMatch(vercelAdapter + resendAdapter + gandiAdapter, /method:\s*"(POST|PATCH|PUT|DELETE)"/);
  assert.match(supabaseAdapter, /get_infrastructure_usage_metrics/);
});

test("la supervision Resend utilise une clé distincte du transport d'envoi", () => {
  assert.match(resendAdapter, /process\.env\.RESEND_MONITORING_API_KEY/);
  assert.doesNotMatch(resendAdapter, /process\.env\.RESEND_API_KEY/);
  assert.match(resendTransport, /process\.env\.RESEND_API_KEY/);
  assert.doesNotMatch(resendTransport, /process\.env\.RESEND_MONITORING_API_KEY/);
});
