import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import { createServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";
import { createClient } from "@supabase/supabase-js";
import PDFDocument from "pdfkit";

const container = "supabase_db_PatriGest-PAT-STRIPE-02GA";
const api = process.env.PAT02F_API_URL;
const anon = process.env.PAT02F_ANON_KEY;
const service = process.env.PAT02F_SERVICE_ROLE_KEY;
assert.equal(api, "http://127.0.0.1:57321");
assert.ok(anon && service);
assert.match(spawnSync("docker.exe", ["port", container, "5432/tcp"], { encoding: "utf8" }).stdout, /:57322\s*$/);
const args = ["exec", "-i", container, "psql", "-XqAt", "-U", "postgres", "-d", "postgres",
  "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"];
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(api, service, options);
const run = randomUUID().slice(0, 8);
const children = new Set();

function sql(statement) {
  const child = spawnSync("docker.exe", args, { input: statement, encoding: "utf8", timeout: 16000 });
  assert.equal(child.status, 0, child.stderr);
  return child.stdout.trim();
}

function result(response) {
  if (response.error) throw new Error(`Appel local refusé : ${response.error.code ?? response.error.statusCode ?? response.error.status ?? "inconnu"}`);
  return response.data;
}

const actor = (id) => `set local role authenticated; select set_config('request.jwt.claim.sub','${id}',true);`;

function session(side, statement, hold = false) {
  const child = spawn("docker.exe", args, { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  children.add(child);
  let output = "";
  let error = "";
  child.stdin.on("error", () => {});
  child.stdout.setEncoding("utf8").on("data", (chunk) => { output += chunk; });
  child.stderr.setEncoding("utf8").on("data", (chunk) => { error += chunk; });
  const closed = new Promise((resolve) => child.once("close", (code) => {
    children.delete(child);
    resolve({ code, error, output });
  }));
  child.stdin.write(`set application_name='stripe02ga-${run}-${side}';
    set idle_in_transaction_session_timeout='30s'; set statement_timeout='30s';
    begin;\n${statement}\n\\echo READY\n`);
  if (!hold) child.stdin.end("commit;\n");
  return { child, closed, get output() { return output; } };
}

async function until(predicate, message) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await delay(100);
  }
  throw new Error(message);
}

async function race(label, first, second, verify) {
  const left = session("first", first, true);
  await until(() => left.output.includes("READY"), `${label}: première transaction sans verrou observable`);
  const right = session("second", second);
  await until(() => sql(`select exists(select 1 from pg_stat_activity
    where application_name='stripe02ga-${run}-second' and wait_event_type='Lock')`) === "t",
  `${label}: seconde transaction sans attente de verrou`);
  left.child.stdin.end("commit;\n");
  const [a, b] = await Promise.all([left.closed, right.closed]);
  assert.equal(a.code, 0, a.error);
  verify(a, b);
  console.log(`OK ${label} — attente de verrou constatée`);
}

async function makeUser(name, collaborator = false) {
  const email = `stripe02ga-${run}-${name}@example.test`;
  const password = randomUUID() + randomUUID();
  const { user } = result(await admin.auth.admin.createUser({ email, password, email_confirm: true,
    user_metadata: collaborator ? { patrigest_registration_intent: "collaborator" } : {} }));
  const mode = collaborator ? "collaborator" : "autonomous";
  sql(`update public.application_user_authorizations set status='active',status_changed_at=now(),
    account_mode='${mode}',registration_intent='${mode}'${collaborator ? "" : ",autonomous_registration_status='active'"}
    where user_id='${user.id}'`);
  const client = createClient(api, anon, options);
  const { session: authSession } = result(await client.auth.signInWithPassword({ email, password }));
  const cookie = "sb-127-auth-token=base64-" + Buffer.from(JSON.stringify(authSession)).toString("base64url");
  return { id: user.id, client, token: authSession.access_token, cookie };
}

async function pdf(title) {
  const doc = new PDFDocument();
  const buffers = [];
  doc.on("data", (data) => buffers.push(data));
  doc.text(title);
  doc.end();
  await once(doc, "end");
  return Buffer.concat(buffers);
}

const person = randomUUID();
const account = randomUUID();
const docReport = randomUUID();
const bank = admin.storage.from("bank-statements");
const contentType = "application/pdf";
const original = await pdf("PatriGest 02G-A original fictif");
const revised = await pdf("PatriGest 02G-A correction fictive");
const sha = createHash("sha256").update(revised).digest("hex");

async function assertStored(path, bytes) {
  const data = result(await bank.download(path));
  assert.deepEqual(Buffer.from(await data.arrayBuffer()), bytes);
}

async function statement(owner, month) {
  const id = randomUUID();
  const path = `protected-persons/${person}/accounts/${account}/statements/${id}/statement`;
  const end = `2024-${month}-28`;
  sql(`insert into public.bank_statements(id,financial_account_id,statement_end_date,statement_balance,
    storage_path,original_file_name,mime_type,file_size,created_by)
    values('${id}','${account}','${end}',0,'${path}','fixture.pdf','application/pdf',${original.length},'${owner.id}');`);
  result(await bank.upload(path, original, { contentType }));
  return { id, path, end };
}

async function stage(user, entry) {
  const [edit] = result(await user.client.rpc("reserve_unreconciled_bank_statement_file", {
    p_person: person, p_account: account, p_statement: entry.id,
    p_expected_updated_at: sql(`select updated_at from public.bank_statements where id='${entry.id}'`),
    p_request: randomUUID(),
    p_payload: { endDate: entry.end, startDate: null, balance: 0, note: null,
      size: revised.length, sha256: sha, fileName: "nouveau.pdf" },
  }));
  result(await user.client.storage.from("bank-statements").upload(edit.storage_path, revised, { contentType }));
  const info = result(await bank.info(edit.storage_path));
  assert.equal(result(await admin.rpc("verify_staged_bank_statement_file", {
    p_edit: edit.id, p_object: info.id, p_version: info.version, p_sha256: sha,
  })), true);
  return edit;
}

async function retire(edit) {
  assert.equal(result(await admin.rpc("reconcile_unpublished_bank_statement_file", { p_edit: edit.id })), "retired");
  result(await bank.remove([edit.storage_path]));
  assert.ok((await bank.download(edit.storage_path)).error);
}

const publish = (edit) => `select public.publish_unreconciled_bank_statement_file('${edit.id}');`;
const capture = (entry) => sql(`select storage_path from public.bank_statements where id='${entry.id}'`);
const fixtureDossier = (id, owner, archived = false) => `insert into public.protected_persons(id,owner_id,first_name,last_name,status,archived_at)
  values ('${id}','${owner}','Fixture','02GA',${archived ? "'archived', now()" : "'active', null"});`;

function payment(owner, conversion = false) {
  const ids = Array.from({ length: 6 }, () => randomUUID());
  const [context, price, customer, sub, invoice, attempt] = ids;
  const suffix = context.replaceAll("-", "");
  sql(`begin;
    insert into public.billing_stripe_contexts(id,stripe_account_id,mode) values ('${context}','acct_${suffix}','live');
    insert into public.billing_price_mappings(id,context_id,stripe_price_id,plan_key,billing_cycle,currency,amount_cents,sale_enabled)
      values ('${price}','${context}','price_${suffix}','essential','monthly','eur',300,true);
    insert into public.billing_customers(id,context_id,owner_id,stripe_customer_id)
      values ('${customer}','${context}','${owner}','cus_${suffix}');
    ${conversion ? `insert into public.billing_checkout_attempts(id,context_id,billing_customer_id,price_mapping_id,intent,state,
      consent_version,consented_at,expires_at,finished_at)
      values ('${attempt}','${context}','${customer}','${price}','subscribe_now','completed',
       'administrative-to-essential-v1',clock_timestamp(),now()+interval '1 day',clock_timestamp());` : ""}
    insert into public.billing_subscriptions(id,context_id,billing_customer_id,price_mapping_id,checkout_attempt_id,
      stripe_subscription_id,stripe_status,started_at)
      values ('${sub}','${context}','${customer}','${price}',${conversion ? `'${attempt}'` : "null"},'sub_${suffix}','active',now()-interval '1 day');
    insert into public.billing_invoice_periods(id,context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,
      billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents,stripe_reported_paid_at,
      payment_evidence,payment_verified_at,stripe_payment_intent_id)
      values ('${invoice}','${context}','${sub}','${price}','in_${suffix}','initial','paid',
       now()-interval '1 day',now()+interval '29 days','eur',300,clock_timestamp(),'stripe_verified',clock_timestamp(),'pi_${suffix}');
    commit;`);
  return `select public.billing_accept_verified_invoice_at('${invoice}',clock_timestamp());`;
}

assert.equal(sql("select count(*) from public.protected_persons"), "0");
assert.equal(sql("select commercial_access_enabled from public.billing_runtime_config"), "f");
try {
  const owner = await makeUser("owner");
  const reader = await makeUser("reader", true);
  const manager = await makeUser("manager", true);
  sql(`begin;
    ${fixtureDossier(person, owner.id)}
    insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
      values ('${account}','${person}','checking','Fixture','Banque fictive',0,'2024-01-01');
    insert into public.protected_person_access(protected_person_id,user_id,role,invited_by)
      values ('${person}','${manager.id}','manager','${owner.id}'),('${person}','${reader.id}','read_only','${owner.id}');
    commit;`);

  const reconciled = await statement(owner, "02");
  const recId = randomUUID();
  sql(`insert into public.bank_reconciliations(id,bank_statement_id,created_by)
    values ('${recId}','${reconciled.id}','${owner.id}');`);
  const before = await stage(owner, reconciled);
  await race("validation bancaire contre publication", actor(owner.id) + `select public.validate_bank_reconciliation('${recId}');`,
    actor(owner.id) + publish(before), (_, b) => { assert.notEqual(b.code, 0); assert.match(b.error, /55000/); });
  assert.equal(capture(reconciled), reconciled.path);
  assert.equal(sql(`select status::text from public.bank_reconciliations where id='${recId}'`), "validated");
  await assertStored(reconciled.path, original);
  await retire(before);

  const [initial] = result(await owner.client.rpc("get_bank_statement_document_history", { p_statement_id: reconciled.id }));
  const draft = { report: { id: docReport, protected_person_id: person, report_year: "2024", period_start: "2024-01-01",
    period_end: "2024-12-31", status: "generated" }, person: { id: person }, statements: [{ statementId: reconciled.id }] };
  const reportPath = `protected-persons/${person}/management-reports/${docReport}/management-report`;
  sql(`begin;
    insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by)
      values('${docReport}','${person}',2024,'2024-01-01','2024-12-31','generated',now(),'${owner.id}');
    insert into public.management_report_documents(management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      generated_by,preview_snapshot,snapshot_schema_version)
      values ('${docReport}','management_report_draft','${reportPath}-draft.pdf','projet.pdf','application/pdf',${original.length},
        '${owner.id}','${JSON.stringify(draft)}',1),
        ('${docReport}','management_report','${reportPath}.pdf','final.pdf','application/pdf',${original.length},
        '${owner.id}','${JSON.stringify({ ...draft, report: { ...draft.report, status: "finalized" } })}',1);
    commit;`);
  const pinned = () => sql(`select document_version_id from public.management_report_bank_statement_document_versions where bank_statement_id='${reconciled.id}'`);
  assert.equal(pinned(), initial.version_id);
  const reserved = result(await owner.client.rpc("begin_bank_statement_document_correction", {
    p_protected_person_id: person, p_financial_account_id: account, p_statement_id: reconciled.id,
    p_expected_active_revision: initial.active_revision, p_client_request_id: randomUUID(),
    p_reason: "Correction fictive", p_file_name: "correction.pdf", p_file_size: revised.length, p_sha256: sha,
  }));
  result(await owner.client.storage.from("bank-statements").upload(reserved.storagePath, revised, { contentType, metadata: { sha256: sha } }));
  const correctedObject = result(await bank.info(reserved.storagePath));
  result(await owner.client.rpc("finalize_bank_statement_document_correction", {
    p_operation_id: reserved.operationId, p_expected_operation_revision: reserved.revision,
    p_storage_object_id: correctedObject.id, p_storage_object_version: correctedObject.version,
  }));
  const history = result(await reader.client.rpc("get_bank_statement_document_history", { p_statement_id: reconciled.id }));
  assert.deepEqual(history.map(({ is_active, version_number }) => [is_active, version_number]), [[true, 2], [false, 1]]);
  assert.equal(pinned(), initial.version_id);
  assert.equal(history[1].storage_path, reconciled.path);
  await assertStored(history[1].storage_path, original);
  await assertStored(history[0].storage_path, revised);
  assert.equal(result(await admin.rpc("list_retired_bank_statement_files", { p_statement: reconciled.id })).length, 0);
  assert.ok((await bank.remove([reconciled.path])).error, "Le nettoyage privilégié du fichier épinglé doit être refusé");
  await assertStored(reconciled.path, original);
  const site = "http://127.0.0.1:57401";
  const server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "-H", "127.0.0.1", "-p", "57401"], {
    env: { ...process.env, NEXT_PUBLIC_SUPABASE_URL: api, NEXT_PUBLIC_SUPABASE_ANON_KEY: anon,
      SUPABASE_SERVICE_ROLE_KEY: service, NEXT_TELEMETRY_DISABLED: "1" },
    windowsHide: true, stdio: "ignore",
  });
  const exited = once(server, "exit");
  try {
    let ready = false;
    for (let attempt = 0; attempt < 60 && server.exitCode === null; attempt++) {
      if (await fetch(site + "/connexion").then((response) => response.ok).catch(() => false)) {
        ready = true;
        break;
      }
      await delay(200);
    }
    assert.ok(ready && server.exitCode === null);
    const response = await fetch(`${site}/api/dossiers/${person}/comptes/${account}/releves/${reconciled.id}/versions/${initial.version_id}`, {
      headers: { cookie: reader.cookie }, redirect: "manual",
    });
    assert.equal(response.status, 200);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), original);
  } finally {
    server.kill();
    await exited;
  }
  console.log("OK correction d’un relevé validé : historique, version épinglée et deux fichiers présents");

  const revocation = await statement(owner, "03");
  const pending = await stage(manager, revocation);
  await race("révocation contre publication documentaire",
    `select 1 from public.bank_statements where id='${revocation.id}' for update;
      delete from public.protected_person_access where protected_person_id='${person}' and user_id='${manager.id}';`,
    actor(manager.id) + publish(pending), (_, b) => { assert.notEqual(b.code, 0); assert.match(b.error, /42501/); });
  assert.equal(capture(revocation), revocation.path);
  await assertStored(revocation.path, original);
  await retire(pending);
  assert.ok((await manager.client.rpc("get_bank_statement_document_history", { p_statement_id: revocation.id })).error);

  const network = await statement(owner, "04");
  const waiting = await stage(owner, network);
  let upstreamSuccess = false;
  const cut = createServer(async (_request, response) => {
    try {
      const remote = await fetch(`${api}/rest/v1/rpc/publish_unreconciled_bank_statement_file`, {
        method: "POST", headers: { apikey: anon, authorization: "Bearer " + owner.token, "content-type": "application/json" },
        body: JSON.stringify({ p_edit: waiting.id }),
      });
      await remote.arrayBuffer();
      upstreamSuccess = remote.ok;
    } finally { response.socket.destroy(); }
  });
  cut.listen(0, "127.0.0.1");
  await once(cut, "listening");
  try {
    await assert.rejects(fetch(`http://127.0.0.1:${cut.address().port}`, { method: "POST" }), /fetch failed/);
  } finally {
    await new Promise((resolve) => cut.close(resolve));
  }
  assert.equal(upstreamSuccess, true);
  assert.equal(capture(network), waiting.storage_path);
  assert.equal(result(await admin.rpc("reconcile_unpublished_bank_statement_file", { p_edit: waiting.id })), "published");
  result(await owner.client.rpc("publish_unreconciled_bank_statement_file", { p_edit: waiting.id }));
  const retired = result(await admin.rpc("list_retired_bank_statement_files", { p_statement: network.id }));
  assert.deepEqual(retired.map((row) => row.storage_path), [network.path]);
  result(await bank.remove([network.path]));
  await assertStored(waiting.storage_path, revised);
  console.log("OK rupture HTTP après réponse SQL : publication relue, rejeu sans doublon et nettoyage du seul ancien objet");

  const subjects = [];
  for (const name of ["create", "restore", "convert"]) {
    const user = await makeUser(name);
    const id = randomUUID();
    const old = randomUUID();
    sql(fixtureDossier(old, user.id) + (name === "create" ? "" : fixtureDossier(id, user.id, name === "restore")));
    if (name === "convert") sql(`insert into public.account_administrative_plan_assignments(owner_id,plan_key,billing_period,
      dossier_capacity_key,reason,created_by) values ('${user.id}','comfort','monthly','five','Fixture','${owner.id}');`);
    subjects.push({ name, user, id, pay: payment(user.id, name === "convert") });
  }
  sql("update public.protected_person_archive_runtime_config set lifecycle_enabled=true; update public.billing_runtime_config set commercial_access_enabled=true;");
  for (const { name, user, id, pay } of subjects) {
    const ownerId = user.id;
    const newId = name === "convert" ? randomUUID() : id;
    const write = actor(ownerId) + (name === "restore"
      ? `select public.restore_protected_person('${id}',1,'Fixture');` : fixtureDossier(newId, ownerId));
    if (name === "convert") {
      await race("conversion administrative contre troisième dossier", write, pay,
        (_, b) => { assert.equal(b.code, 0, b.error); assert.match(b.output, /active_dossier_limit_exceeded/); });
    } else {
      await race(`paiement contre ${name === "create" ? "création" : "restauration"}`, pay, write,
        (a, b) => { assert.match(a.output, /applied/); assert.equal(b.code, 0, b.error); });
    }
    assert.equal(sql(`select access_source || ':' || active_dossier_limit || ':' || active_dossier_count
      from public.billing_resolve_entitlements_at('${ownerId}', clock_timestamp())`),
    name === "convert" ? "administrative:5:3" : "commercial:2:2");
  }
} finally {
  for (const child of children) child.stdin.end("rollback;\n");
  sql(`select pg_terminate_backend(pid) from pg_stat_activity where application_name like 'stripe02ga-${run}-%';
    update public.billing_runtime_config set commercial_access_enabled=false;
    update public.protected_person_archive_runtime_config set lifecycle_enabled=false;`);
}
