import "server-only";

import { buildGandiResult } from "../infrastructure-monitoring";
import { fetchInfrastructureJson } from "./infrastructure-http";

type GandiDomain = { fqdn?: unknown; autorenew?: unknown; dates?: { registry_ends_at?: unknown } };

export async function getGandiInfrastructure(signal: AbortSignal) {
  const token = process.env.GANDI_ACCESS_TOKEN;
  if (!token) throw new Error("Gandi unavailable");
  const url = new URL("https://api.gandi.net/v5/domain/domains");
  url.searchParams.set("fqdn", "patrigest.fr");
  url.searchParams.set("per_page", "1");
  const data = await fetchInfrastructureJson(url, token, signal);
  const domain = Array.isArray(data) ? data.find((item): item is GandiDomain => Boolean(item && typeof item === "object" && (item as GandiDomain).fqdn === "patrigest.fr")) : undefined;
  const expiresAt = domain?.dates?.registry_ends_at;
  if (!domain || typeof expiresAt !== "string" || typeof domain.autorenew !== "boolean" || Number.isNaN(new Date(expiresAt).getTime())) throw new Error("Gandi domain unavailable");
  return buildGandiResult(expiresAt, domain.autorenew, new Date(), new Date().toISOString());
}
