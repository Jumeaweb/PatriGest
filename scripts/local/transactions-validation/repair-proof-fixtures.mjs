import { createHash, createHmac } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { createTransactionFixturePdf, hasReadablePdfStructure } from "./fixture-pdf.mjs";

const LOCAL_URL = "http://127.0.0.1:54321";
const INVALID_SIZE = 69;
const INVALID_MD5 = "1bbc324fd49ac1b6e692f4520dcc42d7";
const fixtures = [
  {
    path: "protected-persons/97000000-0000-4000-8100-000000000101/transactions/bd090eaa-fd77-4714-ac48-612ee8f6320d/proof",
    fileName: "justificatif-historique.pdf",
  },
  {
    path: "protected-persons/97000000-0000-4000-8100-000000000101/transactions/f9b1a546-ab8e-4130-a084-9e7dabfeebf9/proof",
    fileName: "justificatif-courant.pdf",
  },
];

const url = process.env.PAT_LOCAL_SUPABASE_URL;
const anonKey = process.env.PAT_LOCAL_ANON_KEY;
const serviceRoleKey = process.env.PAT_LOCAL_SERVICE_ROLE_KEY;
const jwtSecret = process.env.PAT_LOCAL_JWT_SECRET;
const outsiderId = process.env.PAT_LOCAL_OUTSIDER_ID;
const outsiderEmail = process.env.PAT_LOCAL_OUTSIDER_EMAIL;
const appUrl = process.env.PAT_LOCAL_APP_URL;
if (url !== LOCAL_URL || appUrl !== "http://127.0.0.1:3000"
  || !anonKey || !serviceRoleKey || !jwtSecret || !outsiderId || !outsiderEmail) {
  throw new Error("Réparation refusée : configuration Supabase locale invalide.");
}

const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
const pdf = await createTransactionFixturePdf();
const expectedSha256 = createHash("sha256").update(pdf).digest("hex");

async function download(client, path) {
  const result = await client.storage.from("transaction-proofs").download(path);
  if (result.error || !result.data) return { error: result.error, bytes: null };
  return { error: null, bytes: new Uint8Array(await result.data.arrayBuffer()) };
}

function createLocalClient(userId, email) {
  const now = Math.floor(Date.now() / 1_000);
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    aud: "authenticated",
    exp: now + 300,
    iat: now,
    sub: userId,
    email,
    role: "authenticated",
  })).toString("base64url");
  const tokenSignature = createHmac("sha256", jwtSecret)
    .update(`${header}.${payload}`)
    .digest("base64url");
  return createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${header}.${payload}.${tokenSignature}` } },
  });
}

function createAppCookie(userId, email) {
  const now = Math.floor(Date.now() / 1_000);
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payloadObject = { aud: "authenticated", exp: now + 300, iat: now, sub: userId, email, role: "authenticated" };
  const payload = Buffer.from(JSON.stringify(payloadObject)).toString("base64url");
  const signature = createHmac("sha256", jwtSecret).update(`${header}.${payload}`).digest("base64url");
  const accessToken = `${header}.${payload}.${signature}`;
  const session = {
    access_token: accessToken,
    token_type: "bearer",
    expires_in: 300,
    expires_at: now + 300,
    refresh_token: "fixture-local-validation-not-refreshable",
    user: {
      id: userId,
      aud: "authenticated",
      role: "authenticated",
      email,
      app_metadata: { provider: "email", providers: ["email"] },
      user_metadata: {},
      created_at: new Date(now * 1_000).toISOString(),
    },
  };
  return `sb-127-auth-token=base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
}

// Toutes les préconditions sont contrôlées avant la première écriture.
const initialStates = [];
for (const fixture of fixtures) {
  const current = await download(admin, fixture.path);
  if (!current.bytes) throw new Error(`Réparation refusée : objet absent pour ${fixture.fileName}.`);
  const md5 = createHash("md5").update(current.bytes).digest("hex");
  const sha256 = createHash("sha256").update(current.bytes).digest("hex");
  if (current.bytes.byteLength === INVALID_SIZE && md5 === INVALID_MD5) initialStates.push("invalid");
  else if (sha256 === expectedSha256 && hasReadablePdfStructure(current.bytes)) initialStates.push("valid");
  else throw new Error(`Réparation refusée : contenu inattendu pour ${fixture.fileName}.`);
}

if (initialStates.every((state) => state === "invalid")) {
  for (const fixture of fixtures) {
    const replacement = await admin.storage.from("transaction-proofs").update(fixture.path, pdf, {
      contentType: "application/pdf",
      cacheControl: "3600",
    });
    if (replacement.error) throw new Error(`Échec du remplacement local de ${fixture.fileName}.`);
  }
} else if (!initialStates.every((state) => state === "valid")) {
  throw new Error("Réparation refusée : état partiel inattendu des deux objets.");
}

for (const fixture of fixtures) {
  const repaired = await download(admin, fixture.path);
  const sha256 = repaired.bytes ? createHash("sha256").update(repaired.bytes).digest("hex") : null;
  if (!repaired.bytes || !hasReadablePdfStructure(repaired.bytes) || sha256 !== expectedSha256) {
    throw new Error(`Contrôle binaire final en échec pour ${fixture.fileName}.`);
  }
}

const owner = createLocalClient(
  "97000000-0000-4000-8000-000000000001",
  "transactions-validation-owner@example.test",
);
const reader = createLocalClient(
  "97000000-0000-4000-8000-000000000003",
  "transactions-validation-reader@example.test",
);
const outsider = createLocalClient(outsiderId, outsiderEmail);
const ownerCookie = createAppCookie("97000000-0000-4000-8000-000000000001", "transactions-validation-owner@example.test");
const readerCookie = createAppCookie("97000000-0000-4000-8000-000000000003", "transactions-validation-reader@example.test");
const outsiderCookie = createAppCookie(outsiderId, outsiderEmail);

for (const fixture of fixtures) {
  for (const [role, client] of [["propriétaire", owner], ["lecteur", reader]]) {
    const direct = await download(client, fixture.path);
    const directSha256 = direct.bytes ? createHash("sha256").update(direct.bytes).digest("hex") : null;
    if (!direct.bytes || directSha256 !== expectedSha256) {
      throw new Error(`Lecture ${role} en échec pour ${fixture.fileName}.`);
    }

    const view = await client.storage.from("transaction-proofs").createSignedUrl(fixture.path, 60);
    if (view.error || !view.data?.signedUrl) throw new Error(`URL de consultation ${role} indisponible.`);
    const viewResponse = await fetch(view.data.signedUrl, { redirect: "follow" });
    const viewBytes = new Uint8Array(await viewResponse.arrayBuffer());
    if (!viewResponse.ok || !viewResponse.headers.get("content-type")?.startsWith("application/pdf")
      || createHash("sha256").update(viewBytes).digest("hex") !== expectedSha256) {
      throw new Error(`Consultation HTTP ${role} invalide pour ${fixture.fileName}.`);
    }

    const signedDownload = await client.storage.from("transaction-proofs").createSignedUrl(
      fixture.path,
      60,
      { download: fixture.fileName },
    );
    if (signedDownload.error || !signedDownload.data?.signedUrl) throw new Error(`URL de téléchargement ${role} indisponible.`);
    const downloadResponse = await fetch(signedDownload.data.signedUrl, { redirect: "follow" });
    const downloadBytes = new Uint8Array(await downloadResponse.arrayBuffer());
    const disposition = downloadResponse.headers.get("content-disposition") ?? "";
    if (!downloadResponse.ok || !/attachment/i.test(disposition)
      || createHash("sha256").update(downloadBytes).digest("hex") !== expectedSha256) {
      throw new Error(`Téléchargement HTTP ${role} invalide pour ${fixture.fileName}.`);
    }
  }

  const outsideDownload = await download(outsider, fixture.path);
  if (!outsideDownload.error || outsideDownload.bytes) {
    throw new Error(`L'utilisateur extérieur accède à tort à ${fixture.fileName}.`);
  }
  const outsideSignedUrl = await outsider.storage.from("transaction-proofs").createSignedUrl(fixture.path, 60);
  if (!outsideSignedUrl.error || outsideSignedUrl.data?.signedUrl) {
    throw new Error(`L'utilisateur extérieur obtient à tort une URL signée pour ${fixture.fileName}.`);
  }
}

const historyResult = await owner.from("transaction_document_history")
  .select("id")
  .eq("transaction_id", "bd090eaa-fd77-4714-ac48-612ee8f6320d")
  .eq("proof_reference", "2026-0004")
  .single();
if (historyResult.error || !historyResult.data) throw new Error("Historique fictif introuvable pour la validation HTTP.");

const applicationDocuments = [
  {
    transactionId: "bd090eaa-fd77-4714-ac48-612ee8f6320d",
    query: `?versionId=${encodeURIComponent(historyResult.data.id)}`,
    fileName: "justificatif-historique.pdf",
  },
  {
    transactionId: "f9b1a546-ab8e-4130-a084-9e7dabfeebf9",
    query: "",
    fileName: "justificatif-courant.pdf",
  },
];
for (const document of applicationDocuments) {
  const endpoint = `${appUrl}/api/dossiers/97000000-0000-4000-8100-000000000101/operations/${document.transactionId}/justificatif`;
  for (const [role, cookie] of [["propriétaire", ownerCookie], ["lecteur", readerCookie]]) {
    for (const downloadRequested of [false, true]) {
      const separator = document.query ? "&" : "?";
      const response = await fetch(`${endpoint}${document.query}${downloadRequested ? `${separator}download=1` : ""}`, {
        headers: { Cookie: cookie },
        redirect: "manual",
      });
      if (![307, 308].includes(response.status) || !response.headers.get("location")?.startsWith(LOCAL_URL)) {
        throw new Error(`Redirection applicative ${role} invalide pour ${document.fileName}.`);
      }
      const finalResponse = await fetch(response.headers.get("location"), { redirect: "follow" });
      const finalBytes = new Uint8Array(await finalResponse.arrayBuffer());
      const disposition = finalResponse.headers.get("content-disposition") ?? "";
      if (!finalResponse.ok || !finalResponse.headers.get("content-type")?.startsWith("application/pdf")
        || (downloadRequested && !/attachment/i.test(disposition))
        || createHash("sha256").update(finalBytes).digest("hex") !== expectedSha256) {
        throw new Error(`Réponse applicative ${role} invalide pour ${document.fileName}.`);
      }
    }
  }
  const outsideResponse = await fetch(`${endpoint}${document.query}`, {
    headers: { Cookie: outsiderCookie },
    redirect: "manual",
  });
  if (outsideResponse.status !== 404 || outsideResponse.headers.has("location")) {
    throw new Error(`La route applicative expose à tort ${document.fileName} à l'utilisateur extérieur.`);
  }
}

console.log(`Réparation locale terminée : 2 PDF valides, SHA-256 ${expectedSha256}.`);
