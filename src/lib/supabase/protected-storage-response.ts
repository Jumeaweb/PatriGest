import "server-only";

import { getSupabaseConfig } from "./config";

const noStore = {
  "Cache-Control": "private, no-store, max-age=0",
  "CDN-Cache-Control": "no-store",
  "Vercel-CDN-Cache-Control": "no-store",
};

export async function protectedStorageResponse(input: {
  request: Request;
  bucket: "transaction-proofs" | "management-reports" | "bank-statements";
  storagePath: string;
  contentType: string;
  contentDisposition: string;
}) {
  // Only one byte range is accepted. Storage decides whether it is satisfiable.
  const range = input.request.headers.get("range");
  if (range && !/^bytes=(?:\d{1,19}-\d{0,19}|-\d{1,19})$/.test(range)) {
    return new Response(null, { status: 400, headers: noStore });
  }
  const { supabaseUrl } = getSupabaseConfig();
  // Callers resolve the document with the user's RLS/RPC before this read.
  // The key stays server-side and no upstream URL is returned to the client.
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) return new Response(null, { status: 503, headers: noStore });
  const segments = input.storagePath.split("/");
  if (segments.some((segment) => !segment || segment === "." || segment === ".." || segment.includes("\\"))) {
    return new Response(null, { status: 404, headers: noStore });
  }
  const path = segments.map(encodeURIComponent).join("/");
  const upstream = await fetch(`${supabaseUrl}/storage/v1/object/authenticated/${input.bucket}/${path}`, {
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      "Accept-Encoding": "identity",
      ...(range ? { Range: range } : {}),
    },
    cache: "no-store",
    redirect: "error",
    signal: input.request.signal,
  }).catch(() => null);
  if (!upstream) return new Response(null, { status: 503, headers: noStore });
  if (upstream.status === 416) {
    const contentRange = upstream.headers.get("content-range");
    await upstream.body?.cancel();
    return new Response(null, { status: 416, headers: { ...noStore, ...(contentRange ? { "Content-Range": contentRange } : {}) } });
  }
  if (!upstream.ok || !upstream.body) {
    await upstream.body?.cancel();
    return Response.json({ message: "Ce document est actuellement indisponible." }, { status: 404, headers: noStore });
  }
  const headers = new Headers({
    ...noStore,
    "Content-Type": input.contentType,
    "Content-Disposition": input.contentDisposition,
    "X-Content-Type-Options": "nosniff",
  });
  for (const header of ["content-length", "content-range", "accept-ranges"]) {
    const value = upstream.headers.get(header);
    if (value) headers.set(header, value);
  }
  return new Response(upstream.body, { status: upstream.status, headers });
}
