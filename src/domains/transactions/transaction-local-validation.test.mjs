import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../../scripts/local/transactions-validation/", import.meta.url);
const { createTransactionFixturePdf, hasReadablePdfStructure } = await import(new URL("fixture-pdf.mjs", root));
const start = readFileSync(new URL("start.ps1", root), "utf8");
const seed = readFileSync(new URL("seed.ps1", root), "utf8");
const fixtures = readFileSync(new URL("transactions-validation-fixtures.sql", root), "utf8");
const uploader = readFileSync(new URL("upload-proof-fixtures.mjs", root), "utf8");
const fixturePdf = readFileSync(new URL("fixture-pdf.mjs", root), "utf8");
const resumeProofs = readFileSync(new URL("resume-proofs.ps1", root), "utf8");
const repairProofs = readFileSync(new URL("repair-proof-fixtures.ps1", root), "utf8");
const repairProofsScript = readFileSync(new URL("repair-proof-fixtures.mjs", root), "utf8");

test("le lancement local refuse toute URL autre que Supabase local", () => {
  assert.match(start, /http:\/\/127\.0\.0\.1:54321/);
  assert.match(start, /Demarrage refuse/);
  assert.match(start, /Test-NetConnection.+54321/s);
  assert.match(start, /Test-NetConnection.+54322/s);
  assert.doesNotMatch(start + seed + resumeProofs + uploader, /supabase\.co|patrigest-dev/);
});

test("la réparation privilégiée est bornée aux deux objets locaux invalides", () => {
  assert.match(repairProofs, /http:\/\/127\.0\.0\.1:54321/);
  assert.match(repairProofs, /businessHashBefore/);
  assert.match(repairProofs, /businessHashAfter -ne \$businessHashBefore/);
  assert.match(repairProofsScript, /INVALID_SIZE = 69/);
  assert.match(repairProofsScript, /1bbc324fd49ac1b6e692f4520dcc42d7/);
  assert.equal((repairProofsScript.match(/path: "protected-persons\//g) ?? []).length, 2);
  assert.match(repairProofsScript, /\.update\(fixture\.path, pdf/);
  assert.doesNotMatch(repairProofsScript, /\.remove\(|\.from\("transactions"\).*\.(?:insert|update|delete)/s);
  assert.doesNotMatch(repairProofs + repairProofsScript, /supabase\.co|patrigest-dev/);
});

test("les services externes et indicateurs expérimentaux restent désactivés", () => {
  for (const variable of ["RESEND_API_KEY", "RESEND_MONITORING_API_KEY", "VERCEL_ACCESS_TOKEN", "GANDI_ACCESS_TOKEN"]) {
    assert.match(start, new RegExp(`\\$env:${variable} = ""`));
  }
  assert.match(start, /PATRIGEST_ENABLE_TRANSACTION_PROOF_DURABLE_OPERATIONS = "false"/);
  assert.match(start, /PATRIGEST_ENABLE_BANK_STATEMENT_DURABLE_OPERATIONS = "false"/);
});

test("les fixtures sont locales, fictives, idempotentes et sans mot de passe suivi", () => {
  assert.match(seed, /Read-Host.+-AsSecureString/);
  assert.match(seed, /Get-Content -LiteralPath \$sqlFile -Raw -Encoding UTF8/);
  assert.match(seed, /exists\(select 1 from public\.protected_persons/);
  assert.match(fixtures, /__LOCAL_PASSWORD__/);
  assert.match(fixtures, /@example\.test/g);
  assert.doesNotMatch(fixtures, /Local-only|Password123|motdepasse/i);
  assert.match(uploader, /upsert: false/);
  assert.match(uploader, /transaction_date/);
  assert.doesNotMatch(uploader, /\.in\("label"/);
  assert.match(uploader, /generateLink/);
  assert.match(uploader, /verifyOtp/);
  assert.match(uploader, /hasReadablePdfStructure/);
  assert.match(uploader, /Aucune écriture effectuée/);
  assert.match(fixturePdf, /\/Type\\s\*\\\/Pages/);
  assert.match(fixturePdf, /startxref/);
  assert.match(fixturePdf, /PDFDocument/);
  assert.match(resumeProofs, /fixtureCount\.Trim\(\) -ne "5"/);
  assert.doesNotMatch(resumeProofs, /Read-Host/);
  assert.match(seed, /alreadySeeded[\s\S]+if \(\[string\]::IsNullOrWhiteSpace\(\$Password\)\)/);
  assert.doesNotMatch(fixtures, /delete from|truncate|drop table/i);
});

test("le justificatif fictif est un PDF déterministe réellement structuré", async () => {
  const first = await createTransactionFixturePdf();
  const second = await createTransactionFixturePdf();
  assert.equal(Buffer.from(first.subarray(0, 5)).toString("ascii"), "%PDF-");
  assert.equal(hasReadablePdfStructure(first), true);
  assert.deepEqual(first, second);
  assert.ok(first.byteLength > 1_000);
});
