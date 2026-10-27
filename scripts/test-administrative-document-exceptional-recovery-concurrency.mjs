import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

const container = "supabase_db_PatriGest";
const runId = `${process.pid}_${randomUUID().replaceAll("-", "").slice(0, 12)}`;
const database = `patrigest_exceptional_recovery_${runId}`;
const dumpPath = `/tmp/patrigest-exceptional-recovery-${runId}.dump`;
let databaseCreated = false;
let dumpCreated = false;

function docker(args, options = {}) {
  const result = spawnSync("docker", args, {
    encoding: "utf8",
    input: options.input,
    maxBuffer: 20 * 1024 * 1024,
  });
  if (!options.allowFailure && result.status !== 0) {
    throw new Error(result.stderr || result.stdout || `docker ${args.join(" ")} a échoué.`);
  }
  return result;
}

function psql(sql, options = {}) {
  return docker([
    "exec", "-i", container,
    "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database, "-At",
  ], {
    input: `set statement_timeout='15s';\nset lock_timeout='5s';\n${sql}`,
    ...options,
  });
}

function psqlAsync(sql) {
  const child = spawn("docker", [
    "exec", "-i", container,
    "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database, "-At",
  ], { stdio: ["pipe", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
  child.stdin.end(`set statement_timeout='15s';\nset lock_timeout='5s';\n${sql}`);
  return new Promise((resolve) => {
    const timeout = setTimeout(() => child.kill(), 20_000);
    child.on("close", (status, signal) => {
      clearTimeout(timeout);
      resolve({ status, signal, stdout, stderr });
    });
  });
}

function authenticated(subjectId, body) {
  return `begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','${subjectId}',true);
select set_config('request.jwt.claims','{"sub":"${subjectId}","role":"authenticated"}',true);
${body}
commit;`;
}

function serviceRole(body) {
  return `begin;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
${body}
rollback;`;
}

const admin1 = "99600000-0000-4000-8000-000000000001";
const admin2 = "99600000-0000-4000-8000-000000000002";
const admin3 = "99600000-0000-4000-8000-000000000003";
const authorization1 = "99600000-0000-4000-8600-000000000001";

const dockerEndpoint = docker([
  "context", "inspect", "--format", '{{ (index .Endpoints "docker").Host }}',
]).stdout.trim();
if (!dockerEndpoint.startsWith("npipe:////./pipe/")) {
  throw new Error(`Refus de lancer le harnais : le moteur Docker n’est pas local (${dockerEndpoint || "absent"}).`);
}
const projectLabel = docker([
  "inspect", "--format", '{{ index .Config.Labels "com.supabase.cli.project" }}', container,
]).stdout.trim();
const workdirLabel = docker([
  "inspect", "--format", '{{ index .Config.Labels "com.supabase.cli.workdir" }}', container,
]).stdout.trim();
if (projectLabel !== "PatriGest"
    || workdirLabel.toLocaleLowerCase("en-US") !== process.cwd().toLocaleLowerCase("en-US")) {
  throw new Error("Refus de lancer le harnais : le conteneur Supabase local n’appartient pas à ce dépôt PatriGest.");
}
const port = docker(["port", container, "5432/tcp"]).stdout.trim();
if (!/^(?:127\.0\.0\.1|0\.0\.0\.0|\[::\]):54322$/m.test(port)) {
  throw new Error(`Refus de lancer le harnais : PostgreSQL n’est pas borné au port local 54322 (${port || "absent"}).`);
}

try {
  docker([
    "exec", container, "pg_dump", "-U", "postgres", "-d", "postgres", "-Fc", "--schema-only",
    "--schema=public", "--schema=auth", "--schema=storage", "--schema=extensions", "-f", dumpPath,
  ]);
  dumpCreated = true;
  docker(["exec", container, "createdb", "-U", "postgres", database]);
  databaseCreated = true;
  psql(`
create schema extensions;
create extension btree_gist with schema public;
create extension pgcrypto with schema extensions;
create extension "uuid-ossp" with schema extensions;
`);
  const restore = docker([
    "exec", container, "pg_restore", "-U", "postgres", "-d", database,
    "--no-owner", "--no-privileges", dumpPath,
  ], { allowFailure: true });
  if (restore.status !== 0) {
    const unexpectedRestoreError = restore.stderr
      .split(/\r?\n/)
      .filter((line) => line.startsWith("pg_restore: error:"))
      .some((line) => !/schema \"(?:public|extensions)\" already exists/.test(line));
    if (unexpectedRestoreError) {
      throw new Error(restore.stderr || "La restauration du schéma local isolé a échoué.");
    }
  }

  const testSource = readFileSync(
    new URL("../supabase/tests/administrative_document_exceptional_recovery_test.sql", import.meta.url),
    "utf8",
  );
  const fixtureEnd = testSource.indexOf("insert into public.account_deletion_document_authorizations(");
  assert.ok(fixtureEnd > 0, "Le marqueur de fin des fixtures pgTAP est introuvable.");
  const fixtureSql = testSource.slice(testSource.indexOf("create extension"), fixtureEnd);
  psql(`begin;\n${fixtureSql}\ncommit;`);

  const recoveryId = psql(`select id from public.document_repair_exceptional_recoveries where authorization_id='${authorization1}';`).stdout.trim();
  assert.match(recoveryId, /^[0-9a-f-]{36}$/);

  const approvalA = psqlAsync(authenticated(admin2, `
select public.decide_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000001',true,'Validation concurrente A',0
);
select pg_sleep(1);`));
  await new Promise((resolve) => setTimeout(resolve, 100));
  const approvalB = await psqlAsync(authenticated(admin3, `
select public.decide_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000002',true,'Validation concurrente B',0
);`));
  const approvalAResult = await approvalA;
  assert.equal(approvalAResult.status, 0, approvalAResult.stderr);
  assert.notEqual(approvalB.status, 0, "La seconde approbation concurrente devait être refusée.");
  assert.match(approvalB.stderr, /P4X05|déjà reçu une décision|divergé/);
  assert.doesNotMatch(`${approvalAResult.stderr}${approvalB.stderr}`, /deadlock detected/i);

  const replayApproval = psql(authenticated(admin2, `
select public.decide_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000001',true,'Validation concurrente A',0
)->>'idempotent';`)).stdout;
  assert.match(replayApproval, /true/);

  const activationA = psqlAsync(authenticated(admin1, `
select public.activate_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000003',1
);
select pg_sleep(1);`));
  await new Promise((resolve) => setTimeout(resolve, 100));
  const activationB = await psqlAsync(authenticated(admin1, `
select public.activate_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000004',1
);`));
  const activationAResult = await activationA;
  assert.equal(activationAResult.status, 0, activationAResult.stderr);
  assert.notEqual(activationB.status, 0, "La seconde activation concurrente devait être refusée.");
  assert.match(activationB.stderr, /P4X05|P4X06|n’est pas activable|déjà active/);
  assert.doesNotMatch(`${activationAResult.stderr}${activationB.stderr}`, /deadlock detected/i);

  const replayActivation = psql(authenticated(admin1, `
select public.activate_administrative_document_exceptional_recovery(
  '${recoveryId}','99700000-0000-4000-8000-000000000003',1
)->>'idempotent';`)).stdout;
  assert.match(replayActivation, /true/);

  psql(`
insert into public.document_repair_exceptional_recoveries(
  id,authorization_id,operation_id,original_attempt_id,requester_subject_id,
  approver_subject_id,request_id,decision_id,reason,decision_reason,
  repair_plan_hash,requested_authorization_revision,request_context_hash,state,
  activation_count,last_activation_id,requested_at,decided_at,last_activated_at,
  active_expires_at,row_revision
)
select
  '99700000-0000-4000-8000-000000000010',authz.id,authz.operation_id,
  authz.attempt_id,'${admin1}','${admin2}',
  '99700000-0000-4000-8000-000000000011','99700000-0000-4000-8000-000000000012',
  'Expiration pendant progression','Validation indépendante',authz.repair_plan_hash,
  authz.row_revision,public.document_repair_exceptional_context_fingerprint(authz.id),
  'approved',2,'99700000-0000-4000-8000-000000000014',clock_timestamp()-interval '30 minutes',
  clock_timestamp()-interval '29 minutes',clock_timestamp(),
  clock_timestamp()+interval '1 second',3
from public.document_repair_authorizations authz
where authz.id='99600000-0000-4000-8600-000000000006';
insert into public.document_repair_exceptional_activations(
  recovery_id,authorization_id,ordinal,activation_id,activated_by,context_hash,activated_at,expires_at
) values
  ('99700000-0000-4000-8000-000000000010','99600000-0000-4000-8600-000000000006',1,'99700000-0000-4000-8000-000000000013','${admin1}',repeat('b',64),statement_timestamp()-interval '20 minutes',statement_timestamp()-interval '15 minutes'),
  ('99700000-0000-4000-8000-000000000010','99600000-0000-4000-8600-000000000006',2,'99700000-0000-4000-8000-000000000014','${admin1}',repeat('c',64),statement_timestamp(),statement_timestamp()+interval '1 second');`);
  const expiredPlanHash = psql(`
select repair_plan_hash from public.document_repair_authorizations
where id='99600000-0000-4000-8600-000000000006';`).stdout.trim();
  assert.match(expiredPlanHash, /^[0-9a-f]{64}$/);
  const expiredProgress = psql(serviceRole(`
select pg_sleep(2);
select public.start_administrative_document_repair_item(
  '99600000-0000-4000-8600-000000000006','99600000-0000-4000-8800-000000000007',
  '${admin1}','99600000-0000-4000-8700-000000000006',
  '${expiredPlanHash}',
  'confirm_already_conform','99700000-0000-4000-8000-000000000015',6,0
);`), { allowFailure: true });
  assert.notEqual(expiredProgress.status, 0, "La progression après expiration devait être refusée.");
  assert.match(expiredProgress.stderr, /P4R05|expirée/);

  console.log("Multi-session exceptional recovery: PASS");
  console.log("- approbations concurrentes sérialisées sans deadlock");
  console.log("- activations concurrentes sérialisées sans deadlock");
  console.log("- réponses perdues rejouées idempotemment");
  console.log("- progression refusée lorsque la fenêtre expire pendant la reprise");
} finally {
  if (databaseCreated) {
    docker(["exec", container, "dropdb", "-U", "postgres", "--if-exists", database], { allowFailure: true });
  }
  if (dumpCreated) {
    docker(["exec", container, "rm", "-f", dumpPath], { allowFailure: true });
  }
}
