import "server-only";

import { buildResendResult } from "../infrastructure-monitoring";
import { fetchInfrastructureJson, readFiniteNumber } from "./infrastructure-http";

export async function getResendInfrastructure(signal: AbortSignal) {
  const token = process.env.RESEND_MONITORING_API_KEY;
  if (!token) throw new Error("Resend unavailable");
  const end = new Date();
  const start = new Date(end.getTime() - 30 * 86_400_000);
  const url = new URL("https://api.resend.com/emails/metrics");
  url.searchParams.set("start_date", start.toISOString());
  url.searchParams.set("end_date", end.toISOString());
  url.searchParams.set("metrics", "sent,delivery_rate,bounced,bounce_rate,complained,complaint_rate");
  const data = await fetchInfrastructureJson(url, token, signal);
  if (!data || typeof data !== "object" || !("totals" in data) || !data.totals || typeof data.totals !== "object") throw new Error("Resend metrics unavailable");
  const totals = data.totals as Record<string, unknown>;
  return buildResendResult({
    sent: readFiniteNumber(totals.sent ?? 0),
    deliveryRate: readFiniteNumber(totals.delivery_rate ?? 0),
    bounced: readFiniteNumber(totals.bounced ?? 0),
    bounceRate: readFiniteNumber(totals.bounce_rate ?? 0),
    complained: readFiniteNumber(totals.complained ?? 0),
    complaintRate: readFiniteNumber(totals.complaint_rate ?? 0),
  }, new Date().toISOString());
}
