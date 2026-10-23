import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { deletePlatformUserWithDurableNeutralization } from "../../src/domains/administration/administrative-account-deletion-durable.ts";

const url = process.env.PAT_TEST_SUPABASE_URL;
const anonKey = process.env.PAT_TEST_SUPABASE_ANON_KEY;
const serviceKey = process.env.PAT_TEST_SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.PAT_TEST_PASSWORD;
if (!url || !anonKey || !serviceKey || !password) throw new Error("Configuration locale absente.");
const endpoint = new URL(url);
if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(endpoint.hostname) || endpoint.port !== "54321") {
  throw new Error("Exécution refusée hors de Supabase local.");
}

const ids = {
  admin: "ac000000-0000-4000-8000-000000000001", owner: "ac000000-0000-4000-8000-000000000002",
  target: "ac000000-0000-4000-8000-000000000003", empty: "ac000000-0000-4000-8000-000000000004",
  blocked: "ac000000-0000-4000-8000-000000000005", person: "ac000000-0000-4000-8100-000000000001",
  account: "ac000000-0000-4000-8200-000000000001", transaction: "ac000000-0000-4000-8300-000000000001",
  statement: "ac000000-0000-4000-8400-000000000001", report: "ac000000-0000-4000-8500-000000000001",
};
const email = (name) => `admin-deletion-${name}@example.test`;
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const client = () => createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
async function login(name) {
  const value = client();
  const result = await value.auth.signInWithPassword({ email: email(name), password });
  assert.ifError(result.error);
  return value;
}
const pdf = (name) => new TextEncoder().encode(`%PDF-1.4\n% ${name}\n%%EOF\n`);
const documents = [
  { bucket: "transaction-proofs", path: `protected-persons/${ids.person}/transactions/${ids.transaction}/proof`, bytes: pdf("preuve") },
  { bucket: "bank-statements", path: `protected-persons/${ids.person}/accounts/${ids.account}/statements/${ids.statement}/statement`, bytes: pdf("releve") },
  { bucket: "management-reports", path: `protected-persons/${ids.person}/management-reports/${ids.report}/management-report-draft.pdf`, bytes: pdf("compte") },
];

const administrator = await login("admin");
const target = await login("target");
const owner = await login("owner");
const blocked = await login("blocked");
for (const document of documents) {
  const uploaded = await target.storage.from(document.bucket).upload(document.path, document.bytes, {
    contentType: "application/pdf", cacheControl: "3600", metadata: { integration: "admin-deletion" }, upsert: false,
  });
  if (uploaded.error) throw new Error(`${document.bucket}: ${uploaded.error.message}`);
}
const reportReference = await admin.from("management_report_documents").insert({
  management_report_id: ids.report,
  document_type: "management_report_draft",
  storage_path: documents[2].path,
  file_name: "compte-projet.pdf",
  mime_type: "application/pdf",
  file_size: documents[2].bytes.byteLength,
  preview_snapshot: { report: { id: ids.report } },
  snapshot_schema_version: 1,
  generated_by: ids.owner,
});
assert.ifError(reportReference.error);
const accessRemoval = await admin.from("protected_person_access").delete().eq("user_id", ids.target);
assert.ifError(accessRemoval.error);

let interrupted = false;
const interruptedAdmin = {
  storage: admin.storage,
  auth: admin.auth,
  async rpc(name, args) {
    const result = await admin.rpc(name, args);
    if (!interrupted && name === "confirm_account_storage_neutralization_backup" && !result.error) {
      interrupted = true;
      throw new Error("Interruption locale après sauvegarde vérifiée.");
    }
    return result;
  },
};
const attemptId = randomUUID();
await assert.rejects(deletePlatformUserWithDurableNeutralization(administrator, interruptedAdmin, {
  administratorUserId: ids.admin, targetUserId: ids.target, attemptId, reason: "Nettoyage du compte de test local",
}));
assert.equal(interrupted, true);
const frozenUpload = await target.storage.from("transaction-proofs").upload(
  `protected-persons/${ids.person}/transactions/${ids.transaction}/proof-concurrent`, pdf("concurrent"),
  { contentType: "application/pdf", upsert: false },
);
assert.ok(frozenUpload.error);

const completed = await deletePlatformUserWithDurableNeutralization(administrator, admin, {
  administratorUserId: ids.admin, targetUserId: ids.target, attemptId, reason: "Nettoyage du compte de test local",
});
assert.equal(completed.accountDeleted, true);
assert.ok((await admin.auth.admin.getUserById(ids.target)).error);
for (const document of documents) {
  const downloaded = await owner.storage.from(document.bucket).download(document.path);
  assert.ifError(downloaded.error, `${document.bucket}/${document.path}`);
  assert.deepEqual(new Uint8Array(await downloaded.data.arrayBuffer()), document.bytes);
}
const diagnostic = await administrator.rpc("get_administrative_account_deletion_diagnostic", { p_target_user_id: ids.target });
assert.ifError(diagnostic.error);
assert.equal(diagnostic.data.storageObjects.length, 0);
assert.equal(diagnostic.data.unclearedBackupCount, 0);

await assert.rejects(deletePlatformUserWithDurableNeutralization(administrator, admin, {
  administratorUserId: ids.admin, targetUserId: ids.blocked, attemptId: randomUUID(), reason: "Doit rester bloqué",
}));
assert.ifError((await admin.auth.admin.getUserById(ids.blocked)).error);

const lostResponseAdmin = {
  storage: admin.storage,
  rpc: admin.rpc.bind(admin),
  auth: { admin: {
    async deleteUser(userId) {
      const result = await admin.auth.admin.deleteUser(userId);
      assert.ifError(result.error);
      throw new Error("Réponse Auth perdue après suppression.");
    },
    getUserById: admin.auth.admin.getUserById.bind(admin.auth.admin),
  } },
};
const lost = await deletePlatformUserWithDurableNeutralization(administrator, lostResponseAdmin, {
  administratorUserId: ids.admin, targetUserId: ids.empty, attemptId: randomUUID(), reason: "Compte local sans document",
});
assert.equal(lost.accountDeleted, true);
assert.ok((await admin.auth.admin.getUserById(ids.empty)).error);
assert.ok((await blocked.from("profiles").select("id").eq("id", ids.blocked).maybeSingle()).data);
console.log("Harnais administratif durable local : succès.");
