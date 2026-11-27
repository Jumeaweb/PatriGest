import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { createClient } from "@supabase/supabase-js";
import PDFDocument from "pdfkit";

const container = "supabase_db_" + (process.env.PAT_LOCAL_STACK ?? "PatriGest-PAT-STRIPE-02B");
assert.ok(["supabase_db_PatriGest-PAT-STRIPE-02B", "supabase_db_PatriGest-PAT-STRIPE-02GA"].includes(container));
const api = process.env.PAT02F_API_URL;
const anonKey = process.env.PAT02F_ANON_KEY;
const serviceKey = process.env.PAT02F_SERVICE_ROLE_KEY;
const site = "http://127.0.0.1:57400";
const options = { auth: { persistSession: false, autoRefreshToken: false } };
assert.equal(api, "http://127.0.0.1:57321");
assert.ok(anonKey && serviceKey);
assert.match(spawnSync("docker.exe", ["port", container, "5432/tcp"], { encoding: "utf8" }).stdout, /:57322\s*$/);
const admin = createClient(api, serviceKey, options);
const runId = randomUUID();
const ids = Object.fromEntries(["person", "other", "account", "otherAccount", "expense", "closedExpense", "report", "bank"].map((key) => [key, randomUUID()]));
const quotaFixtureIds = Array.from({ length: 4 }, () => randomUUID());
const finalReportId = randomUUID();
const users = new Map();
const checked = [];
const flags = `select stripe_sales_enabled,commercial_access_enabled,shared_access_enforcement_enabled,
  notifications_enabled,purges_enabled from public.billing_runtime_config;
  select enforcement_enabled from public.account_trial_runtime_config;`;

function sql(input) {
  const result = spawnSync("docker.exe", ["exec", "-i", container, "psql", "-XqAt",
    "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], { input, encoding: "utf8", timeout: 15000 });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function result(response, context) {
  if (response.error) throw new Error(`${context}: ${response.error.code ?? response.error.statusCode ?? response.error.status ?? "failure"}`);
  return response.data;
}

async function check(label, fn) {
  try {
    await fn();
    checked.push(label);
    console.log(`OK ${label}`);
  } catch (error) {
    throw new Error(`${label}: ${error.message}`, { cause: error });
  }
}

async function makeUser(name, collaborator = false) {
  const email = `stripe02f-${runId}-${name}@example.test`;
  const password = randomUUID() + randomUUID();
  const { user } = result(await admin.auth.admin.createUser({
    email, password, email_confirm: true,
    user_metadata: collaborator ? { patrigest_registration_intent: "collaborator" } : {},
  }), "Auth fixture");
  users.set(name, { id: user.id });
  const mode = collaborator ? "collaborator" : "autonomous";
  sql(`update public.application_user_authorizations set status='active',status_changed_at=now(),
    account_mode='${mode}',registration_intent='${mode}'${collaborator ? "" : ",autonomous_registration_status='active'"}
    where user_id='${user.id}';`);
  const client = createClient(api, anonKey, options);
  const { session } = result(await client.auth.signInWithPassword({ email, password }), "Auth session");
  const cookie = "sb-127-auth-token=base64-" + Buffer.from(JSON.stringify(session)).toString("base64url");
  users.set(name, { id: user.id, cookie, client });
}

function request(path, actor, init = {}) {
  const headers = new Headers(init.headers);
  if (actor) headers.set("cookie", users.get(actor).cookie);
  return fetch(site + path, { ...init, headers, redirect: "manual" });
}

async function status(path, actor, expected, init) {
  const response = await request(path, actor, init);
  if (response.status !== expected) {
    const detail = (response.headers.get("content-type") ?? "").includes("application/json")
      ? (await response.json()).message : "";
    assert.fail(`HTTP ${response.status}, attendu ${expected}${detail ? ` (${detail})` : ""}`);
  }
  return response;
}

async function makePdf(label) {
  const doc = new PDFDocument({ info: { Title: label } });
  const chunks = [];
  doc.on("data", (chunk) => chunks.push(chunk));
  doc.text(label);
  doc.end();
  await once(doc, "end");
  return Buffer.concat(chunks);
}

function uploadForm(pdf, label, key) {
  const form = new FormData();
  form.set("file", new Blob([pdf], { type: "application/pdf" }), label);
  if (key) form.set("clientRequestId", key);
  return form;
}

const scoped = `/api/dossiers/${ids.person}`;
const proof = `${scoped}/operations/${ids.expense}/justificatif`;
const closedProof = `${scoped}/operations/${ids.closedExpense}/justificatif`;
const bank = `${scoped}/comptes/${ids.account}/releves/${ids.bank}`;
const report = `${scoped}/comptes-de-gestion/${ids.report}/document`;
const bankPath = `protected-persons/${ids.person}/accounts/${ids.account}/statements/${ids.bank}/statement`;
const reportPath = `protected-persons/${ids.person}/management-reports/${ids.report}/management-report-draft.pdf`;
assert.equal(sql(flags), "f|f|f|f|f\nf");
const server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "-H", "127.0.0.1", "-p", "57400"], {
  env: { ...process.env, NEXT_PUBLIC_SUPABASE_URL: api, NEXT_PUBLIC_SUPABASE_ANON_KEY: anonKey,
    SUPABASE_SERVICE_ROLE_KEY: serviceKey, NEXT_TELEMETRY_DISABLED: "1",
    PATRIGEST_ENABLE_BANK_STATEMENT_DURABLE_OPERATIONS: "false",
    PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS: "false" },
  windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
});
const exited = once(server, "exit");
server.stdout.resume();
server.stderr.on("data", (chunk) => {
  if (/EADDRINUSE/.test(chunk.toString())) console.error("Port Next.js local déjà utilisé.");
});

try {
  let ready = false;
  for (let attempt = 0; attempt < 60 && server.exitCode === null; attempt++) {
    if (await fetch(site + "/connexion").then((res) => res.status === 200).catch(() => false)) {
      ready = true;
      break;
    }
    await delay(200);
  }
  assert.ok(ready && server.exitCode === null, "Next.js isolé indisponible");
  const pdf = await makePdf("PatriGest 02F — original fictif");
  const replacement = await makePdf("PatriGest 02F — remplacement fictif");
  await makeUser("owner");
  await makeUser("other");
  await makeUser("manager", true);
  await makeUser("reader", true);
  await makeUser("outsider");
  const owner = users.get("owner").id;
  const other = users.get("other").id;
  const manager = users.get("manager").id;
  const reader = users.get("reader").id;
  sql(`begin;
    insert into public.protected_persons(id,owner_id,first_name,last_name)
      values ('${ids.person}','${owner}','Fixture','Stripe 02F'),('${ids.other}','${other}','Fixture','Stripe 02F');
    insert into public.protected_person_access(protected_person_id,user_id,role,invited_by) values
      ('${ids.person}','${manager}','manager','${owner}'),('${ids.person}','${reader}','read_only','${owner}'),
      ('${ids.other}','${manager}','manager','${other}');
    insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
      values ('${ids.account}','${ids.person}','checking','Fixture','Actif',0,'2024-01-01'),
             ('${ids.otherAccount}','${ids.other}','checking','Fixture','Autre',0,'2024-01-01');
    insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
      values ('${ids.expense}','${ids.account}','2024-10-01','expense','Fixture',10),
             ('${ids.closedExpense}','${ids.account}','2024-09-10','expense','Fixture',20);
    insert into public.management_periods(protected_person_id,start_date,end_date,status,closed_at)
      values ('${ids.person}','2024-09-01','2024-09-30','closed',now());
    insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by)
      values('${ids.report}','${ids.person}',2023,'2023-01-01','2023-12-31','generated',now(),'${owner}');
    insert into public.management_report_documents(management_report_id,document_type,storage_path,file_name,mime_type,file_size,generated_by)
      values('${ids.report}','management_report_draft','${reportPath}','fixture.pdf','application/pdf',${pdf.length},'${owner}');
    insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,statement_balance,
      storage_path,original_file_name,mime_type,file_size,created_by)
      values('${ids.bank}','${ids.account}','2024-08-01','2024-08-31',0,'${bankPath}','fixture.pdf','application/pdf',${pdf.length},'${owner}');
    commit;`);
  for (const [bucket, path] of [["management-reports", reportPath], ["bank-statements", bankPath]]) {
    result(await admin.storage.from(bucket).upload(path, pdf, { contentType: "application/pdf" }), "Storage fixture");
  }
  await check("justificatif : dépôt par la route officielle", () => status(proof, "owner", 200,
    { method: "POST", body: uploadForm(pdf, "original.pdf", randomUUID()) }));
  await check("exercice clôturé : refus de dépôt et de réservation", async () => {
    await status(closedProof, "owner", 403, { method: "POST", body: uploadForm(pdf, "closed.pdf") });
    const denied = await users.get("owner").client.rpc("reserve_transaction_proof_for_storage", {
      p_protected_person_id: ids.person, p_transaction_id: ids.closedExpense, p_intent: "create", p_client_request_id: randomUUID(),
    });
    assert.equal(denied.error?.code, "P4O03");
  });
  const firstProof = sql(`select storage_path from public.transaction_proof_versions where storage_path like 'protected-persons/${ids.person}/%'`);
  assert.match(firstProof, new RegExp(`^protected-persons/${ids.person}/transactions/${ids.expense}/proofs/`));
  for (const [bucket, route, path] of [["transaction-proofs", proof, firstProof], ["management-reports", report, reportPath], ["bank-statements", bank, bankPath]]) {
    for (const actor of ["owner", "manager", "reader"]) {
      await check(`${bucket} : ${actor} lit les mêmes octets`, async () => {
        const response = await status(route, actor, 200);
        assert.match(response.headers.get("cache-control"), /private, no-store/);
        assert.match(response.headers.get("cdn-cache-control"), /no-store/);
        assert.match(response.headers.get("content-type"), /application\/pdf/);
        assert.deepEqual(Buffer.from(await response.arrayBuffer()), pdf);
      });
    }
    await check(`${bucket} : tiers refusé`, () => status(route, "outsider", 404));
    await check(`${bucket} : dossier substitué refusé`, () => status(route.replace(ids.person, ids.other), "manager", 404));
    await check(`${bucket} : accès direct refusé`, async () => {
      assert.ok((await users.get("owner").client.storage.from(bucket).download(path)).error);
    });
    await check(`${bucket} : lien signé direct refusé`, async () => {
      assert.ok((await users.get("owner").client.storage.from(bucket).createSignedUrl(path, 60)).error);
    });
    await check(`${bucket} : Range 206 et octets`, async () => {
      const response = await status(route, "owner", 206, { headers: { Range: "bytes=0-4" } });
      assert.equal(response.headers.get("content-range"), `bytes 0-4/${pdf.length}`);
      assert.deepEqual(Buffer.from(await response.arrayBuffer()), pdf.subarray(0, 5));
    });
    await check(`${bucket} : Range 416`, () => status(route, "owner", 416, { headers: { Range: "bytes=99999-" } }));
    await check(`${bucket} : multirange rejeté`, () => status(route, "reader", 400, { headers: { Range: "bytes=0-2,5-6" } }));
    await check(`${bucket} : téléchargement forcé`, async () => {
      const response = await status(route + "?download=1", "reader", 200);
      assert.match(response.headers.get("content-disposition"), /^attachment/i);
      await response.arrayBuffer();
    });
  }
  await check("relevé : compte substitué refusé", () => status(bank.replace(ids.account, ids.otherAccount), "manager", 404));
  await check("relevé : version inconnue refusée", () => status(bank + "/versions/" + randomUUID(), "owner", 404));
  await check("justificatif : version inconnue refusée", () => status(proof + "?versionId=" + randomUUID(), "owner", 404));
  await check("justificatif : remplacement versionné, rejeu et conservation physique de l’original", async () => {
    const key = randomUUID();
    for (let attempt = 0; attempt < 2; attempt++) {
      await status(proof, "owner", 200, { method: "POST", body: uploadForm(replacement, "replace.pdf", key) });
    }
    assert.equal(sql(`select count(*) from public.transaction_proof_versions where storage_path like 'protected-persons/${ids.person}/%'`), "2");
    const response = await status(proof, "owner", 200);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), replacement);
    assert.deepEqual(Buffer.from(await result(await admin.storage.from("transaction-proofs").download(firstProof), "physical original").arrayBuffer()), pdf);
  });

  const caller = users.get("owner").client;
  const sha256 = createHash("sha256").update(replacement).digest("hex");
  const bankArgs = {
    p_person: ids.person, p_account: ids.account, p_statement: ids.bank,
    p_expected_updated_at: sql(`select updated_at from public.bank_statements where id='${ids.bank}'`),
    p_payload: { startDate: "2024-08-01", endDate: "2024-08-31", balance: 0, note: null,
      fileName: "staged.pdf", sha256, size: replacement.length },
  };
  const [staged] = result(await caller.rpc("reserve_unreconciled_bank_statement_file", {
    ...bankArgs, p_request: randomUUID(),
  }), "réserve le remplacement");
  assert.ok((await caller.rpc("reserve_unreconciled_bank_statement_file", {
    ...bankArgs, p_request: randomUUID(),
  })).error);
  result(await caller.storage.from("bank-statements").upload(staged.storage_path, replacement, { contentType: "application/pdf" }), "dépôt réservé");
  const stagedObject = result(await admin.storage.from("bank-statements").info(staged.storage_path), "objet réservé");
  assert.equal(result(await admin.rpc("verify_staged_bank_statement_file", {
    p_edit: staged.id, p_object: stagedObject.id, p_version: stagedObject.version, p_sha256: sha256,
  }), "vérification du dépôt réservé"), true);

  sql(`insert into public.account_trials(user_id,terms_version,terms_accepted_at,started_at,ends_at,deletion_eligible_at)
     values ('${owner}','fixture',now()-interval '31 days',now()-interval '31 days',now()-interval '1 day',now()+interval '29 days');
     update public.billing_runtime_config set commercial_access_enabled=true,shared_access_enforcement_enabled=true where singleton;`);
  await check("ancienne session : Mon compte et Abonnement accessibles", async () => {
    await status("/parametres/compte", "owner", 200);
    await status("/parametres/compte?vue=abonnement", "owner", 200);
  });
  await check("ancienne session : création redirigée vers l’abonnement", async () => {
    const response = await status("/dossiers/nouveau", "owner", 307);
    const destination = new URL(response.headers.get("location"), site);
    assert.equal(destination.pathname + destination.search, "/parametres/compte?vue=abonnement");
  });
  await check("ancienne session : les trois API documentaires refusent le propriétaire suspendu", async () => {
    for (const route of [proof, bank, report]) await status(route, "owner", 403);
  });
  await check("ancienne session : suspension isolée au seul propriétaire", async () => {
    for (const route of [proof, bank, report]) await status(route, "manager", 404);
    const people = result(await users.get("manager").client.from("protected_persons").select("id"), "shared dossiers");
    assert.deepEqual(people.map(({ id }) => id), [ids.other]);
  });
  const rejectedResume = await caller.rpc("resume_management_report_preparation", { p_report_id: ids.report });
  assert.ok(rejectedResume.error);
  const rejectedFinal = await caller.rpc("finalize_management_report", {
    p_report_id: ids.report, p_storage_path: reportPath.replace("-draft.pdf", ".pdf"),
    p_file_name: "fixture.pdf", p_mime_type: "application/pdf", p_file_size: pdf.length,
    p_preview_snapshot: {}, p_snapshot_schema_version: 1,
  });
  assert.ok(rejectedFinal.error);
  assert.equal(sql(`select status from public.management_reports where id='${ids.report}'`), "generated");
  assert.deepEqual(Buffer.from(await result(await admin.storage.from("management-reports").download(reportPath), "protected draft").arrayBuffer()), pdf);
  console.log("OK CRG : reprise et finalisation refusées après expiration, projet intact physiquement");
  const rejectedPublish = await caller.rpc("publish_unreconciled_bank_statement_file", { p_edit: staged.id });
  assert.equal(rejectedPublish.error?.code, "42501");
  const rejectedDelete = await caller.rpc("delete_unreconciled_bank_statement", {
    p_person: ids.person, p_account: ids.account, p_statement: ids.bank,
  });
  assert.equal(rejectedDelete.error?.code, "42501");
  assert.equal(sql(`select storage_path from public.bank_statements where id='${ids.bank}'`), bankPath);
  assert.deepEqual(Buffer.from(await result(await admin.storage.from("bank-statements").download(bankPath), "ancien PDF bancaire").arrayBuffer()), pdf);
  for (let attempt = 0; attempt < 2; attempt++) {
    assert.equal(result(await admin.rpc("reconcile_unpublished_bank_statement_file", { p_edit: staged.id }), "rejeu de compensation"), "retired");
    if (attempt === 0) result(await admin.storage.from("bank-statements").remove([staged.storage_path]), "retrait du candidat non publié");
  }
  assert.ok((await admin.storage.from("bank-statements").download(staged.storage_path)).error);
  console.log("OK relevé : deuxième réservation refusée, suspension avant publication, ancien PDF intact, compensation rejouée");
  sql(`delete from public.protected_person_access where protected_person_id='${ids.person}' and user_id='${reader}';
     insert into public.account_administrative_plan_assignments(owner_id,plan_key,billing_period,dossier_capacity_key,reason,created_by)
     values ('${owner}','essential','monthly','included','Fixture','${other}');`);
  await check("reprise : le gestionnaire retrouve les documents, le lecteur révoqué reste exclu", async () => {
    for (const route of [proof, bank, report]) {
      await status(route, "manager", 200);
      await status(route, "reader", 404);
    }
  });
  assert.equal(checked.length, 44);
  console.log(`Contrôles HTTP/Storage réussis : ${checked.length}`);

  const metadata = uploadForm(replacement, "remplacement.pdf");
  metadata.set("statementStartDate", "2024-08-01");
  metadata.set("statementEndDate", "2024-08-31");
  metadata.set("statementBalance", "0");
  metadata.set("note", "");
  await status(bank, "owner", 200, { method: "POST", body: metadata });
  assert.deepEqual(Buffer.from(await (await status(bank, "owner", 200)).arrayBuffer()), replacement);
  assert.ok((await admin.storage.from("bank-statements").download(bankPath)).error);
  await status(bank, "owner", 200, { method: "DELETE" });
  await status(bank, "owner", 404);
  assert.equal(sql(`select count(*) from storage.objects where bucket_id='bank-statements' and name like 'protected-persons/${ids.person}/%'`), "0");
  result(await caller.rpc("delete_unreconciled_bank_statement", {
    p_person: ids.person, p_account: ids.account, p_statement: ids.bank,
  }), "rejeu de suppression de relevé");
  console.log("OK relevé : remplacement et suppression, contrôles physiques et rejeu SQL");

  await status(report, "owner", 200, { method: "DELETE" });
  assert.equal(sql(`select status from public.management_reports where id='${ids.report}'`), "draft");
  assert.ok((await admin.storage.from("management-reports").download(reportPath)).error);
  console.log("OK CRG : reprise validée et fichier projet retiré après bascule SQL");

  const reportBase = `protected-persons/${ids.person}/management-reports/${finalReportId}/management-report`;
  const draftPath = reportBase + "-draft.pdf";
  const finalPath = reportBase + ".pdf";
  const draftSnapshot = {
    report: { id: finalReportId, protected_person_id: ids.person, report_year: "2022",
      period_start: "2022-01-01", period_end: "2022-12-31", status: "generated" },
    person: { id: ids.person },
  };
  sql(`begin;
    insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by)
      values('${finalReportId}','${ids.person}',2022,'2022-01-01','2022-12-31','generated',now(),'${owner}');
    insert into public.management_report_documents(management_report_id,document_type,storage_path,file_name,mime_type,
      file_size,generated_by,preview_snapshot,snapshot_schema_version)
      values('${finalReportId}','management_report_draft','${draftPath}','fixture.pdf','application/pdf',
      ${pdf.length},'${owner}','${JSON.stringify(draftSnapshot)}'::jsonb,1);
    commit;`);
  result(await admin.storage.from("management-reports").upload(draftPath, pdf, { contentType: "application/pdf" }), "projet à finaliser");
  result(await caller.storage.from("management-reports").upload(finalPath, replacement, { contentType: "application/pdf" }), "dépôt définitif autorisé");
  const finalObject = result(await admin.storage.from("management-reports").info(finalPath), "objet à vérifier");
  assert.equal(result(await admin.rpc("record_management_report_final_verification", {
    p_report_id: finalReportId, p_object_id: finalObject.id, p_object_version: finalObject.version,
    p_size: replacement.length, p_sha256: sha256,
  }), "preuve des octets définitifs"), true);
  const publications = await Promise.all([0, 1].map(() => caller.rpc("publish_verified_management_report_final", {
    p_report_id: finalReportId, p_storage_object_id: finalObject.id, p_file_name: "final.pdf", p_file_size: replacement.length,
    p_preview_snapshot: { ...draftSnapshot, report: { ...draftSnapshot.report, status: "finalized" } },
    p_snapshot_schema_version: 1,
  })));
  assert.equal(publications.filter((entry) => !entry.error).length, 1,
    publications.map((entry) => entry.error?.message ?? "published").join(" / "));
  assert.equal(sql(`select status::text || ':' || (select count(*) from public.management_report_documents
    where management_report_id='${finalReportId}' and document_type='management_report')
    from public.management_reports where id='${finalReportId}'`), "finalized:1");
  assert.equal(result(await admin.rpc("retire_unpublished_management_report_final", {
    p_report_id: finalReportId, p_object_id: finalObject.id,
  }), "relecture du résultat incertain"), "published");
  const finalResponse = await status(`${scoped}/comptes-de-gestion/${finalReportId}/document`, "owner", 200);
  assert.deepEqual(Buffer.from(await finalResponse.arrayBuffer()), replacement);
  const retired = result(await admin.rpc("list_management_report_retired_files", { p_report_id: finalReportId }), "projets retirables");
  assert.deepEqual(retired.map(({ storage_path }) => storage_path), [draftPath]);
  result(await admin.storage.from("management-reports").remove([draftPath]), "nettoyage du projet après finalisation");
  assert.deepEqual(result(await admin.rpc("list_management_report_retired_files", { p_report_id: finalReportId }), "rejeu du nettoyage"), []);
  assert.deepEqual(Buffer.from(await result(await admin.storage.from("management-reports").download(finalPath), "définitif conservé").arrayBuffer()), replacement);
  console.log("OK CRG : une seule finalisation concurrente, relecture du résultat et nettoyage sans perte du PDF définitif");

  sql(`begin;
    update public.account_administrative_plan_assignments
      set valid_from=now()-interval '2 days',valid_until=now()-interval '1 day' where owner_id='${owner}';
    update public.account_trials set terms_accepted_at=now()-interval '1 day',started_at=now()-interval '1 day',
      ends_at=now()+interval '29 days',deletion_eligible_at=now()+interval '59 days' where user_id='${owner}';
    commit;`);
  const duringTrial = await status(`${scoped}/comptes-de-gestion/${finalReportId}/document?download=1`, "owner", 200);
  assert.deepEqual(Buffer.from(await duringTrial.arrayBuffer()), replacement);
  await status(report, "owner", 403, { method: "POST" });
  await status(report, "owner", 403, { method: "PATCH" });
  assert.deepEqual(result(await caller.rpc("get_management_report_commercial_capabilities", {
    p_protected_person_id: ids.person,
  }), "capacités CRG pendant l’essai"), [{ can_generate: false, can_finalize: false, can_print: false }]);
  await status(proof, "owner", 200, { method: "POST", body: uploadForm(pdf, "pendant-essai.pdf", randomUUID()) });
  console.log("OK essai : PDF définitif existant lisible et dépôt autorisé, nouveaux PDF et finalisation refusés");

  const outsider = users.get("outsider");
  const dossier = (index) => ({ id: quotaFixtureIds[index], owner_id: outsider.id, first_name: "Fixture", last_name: "Stripe 02F" });
  for (const index of [0, 1]) result(await outsider.client.from("protected_persons").insert(dossier(index)), "dossier sous le plafond");
  const overQuota = await outsider.client.from("protected_persons").insert(dossier(2));
  assert.equal(overQuota.error?.code, "P4D01");
  const privileged = await admin.from("protected_persons").insert(dossier(3));
  assert.equal(privileged.error?.code, "42501");
  const gate = result(await outsider.client.rpc("get_owned_dossier_quota_gate").single(), "projection du quota");
  assert.equal(gate.block_reason, "quota_reached");
  assert.equal(gate.active_dossier_count, 2);
  console.log("Contrôles PostgREST des quotas réussis : 5");
} catch (error) {
  console.error(`Contrôle interrompu : ${error.message}`);
  throw error;
} finally {
  try {
    sql("update public.billing_runtime_config set commercial_access_enabled=false,shared_access_enforcement_enabled=false where singleton;");
    const objects = sql(`select bucket_id || '|' || name from storage.objects where name like 'protected-persons/${ids.person}/%'`);
    for (const line of objects.split(/\r?\n/).filter(Boolean)) {
      const [bucket, path] = line.split("|");
      result(await admin.storage.from(bucket).remove([path]), "cleanup Storage");
    }
    assert.equal(sql(`select count(*) from storage.objects where name like 'protected-persons/${ids.person}/%'`), "0");
    sql(`begin;
      delete from public.transaction_proof_replacement_retirements where replacement_version_id in
        (select id from public.transaction_proof_versions where storage_path like 'protected-persons/${ids.person}/%');
      delete from public.transaction_proof_version_reservations where protected_person_id='${ids.person}';
      delete from public.transaction_documents where transaction_id in ('${ids.expense}','${ids.closedExpense}');
      delete from public.transaction_proof_versions where storage_path like 'protected-persons/${ids.person}/%';
      delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id='${ids.person}');
      delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id='${ids.person}');
      delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id='${ids.person}');
      delete from public.document_operations where protected_person_id='${ids.person}';
      delete from public.transaction_proof_documents where protected_person_id='${ids.person}';
      delete from public.proof_reference_assignments where protected_person_id='${ids.person}';
      delete from public.management_periods where protected_person_id='${ids.person}';
      delete from public.transactions where financial_account_id='${ids.account}';
      delete from public.bank_statements where financial_account_id='${ids.account}';
      delete from public.bank_statement_file_retirements where statement_id='${ids.bank}';
      delete from public.bank_statement_file_transitions where statement_id='${ids.bank}';
      delete from public.bank_statement_deletion_receipts where statement_id='${ids.bank}';
      delete from public.management_report_file_retirements where report_id in ('${ids.report}','${finalReportId}');
      delete from public.management_report_final_verifications where report_id='${finalReportId}';
      delete from public.management_report_documents where management_report_id in ('${ids.report}','${finalReportId}');
      delete from public.management_reports where id in ('${ids.report}','${finalReportId}');
      delete from public.financial_accounts where id in ('${ids.account}','${ids.otherAccount}');
      delete from public.proof_reference_counters where protected_person_id='${ids.person}';
      delete from public.protected_persons where id in ('${ids.person}','${ids.other}');
      delete from public.protected_persons where id in (${quotaFixtureIds.map((id) => `'${id}'`).join(",")});
      delete from auth.users where email like 'stripe02f-${runId}-%@example.test';
      commit;`);
    assert.equal(sql(`select count(*) from auth.users where email like 'stripe02f-${runId}-%@example.test'`), "0");
    assert.equal(sql(flags), "f|f|f|f|f\nf");
  } finally {
    server.kill();
    await exited;
  }
}
