import "server-only";

export const INFRASTRUCTURE_PROVIDER_TIMEOUT_MS = 5_000;

export async function withInfrastructureTimeout<T>(operation: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), INFRASTRUCTURE_PROVIDER_TIMEOUT_MS);
  try {
    return await operation(controller.signal);
  } finally {
    clearTimeout(timeout);
  }
}

export async function fetchInfrastructureJson(url: URL | string, token: string, signal: AbortSignal): Promise<unknown> {
  const response = await fetch(url, {
    method: "GET",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    signal,
    cache: "no-store",
  });
  if (!response.ok) throw new Error("Provider unavailable");
  return response.json();
}

export function readFiniteNumber(value: unknown) {
  const number = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : Number.NaN;
  if (!Number.isFinite(number) || number < 0) throw new Error("Invalid provider data");
  return number;
}
