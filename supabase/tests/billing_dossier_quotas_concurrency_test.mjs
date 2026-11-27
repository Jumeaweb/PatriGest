import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

const container = "supabase_db_" + (process.env.PAT_LOCAL_STACK ?? "PatriGest-PAT-STRIPE-02B");
assert.ok(["supabase_db_PatriGest-PAT-STRIPE-02B", "supabase_db_PatriGest-PAT-STRIPE-02GA"].includes(container));
const docker = "docker.exe";
const args = ["exec", "-i", container, "psql", "-X", "-U", "postgres", "-d", "postgres",
  "-qAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"];
const runId = randomUUID();
const app = (name) => `quota-${runId}-${name}`;
const sqlList = (ids) => ids.map((id) => `'${id}'`).join(",");
const owners = Array.from({ length: 6 }, () => randomUUID());
const admin = randomUUID();
const assignment = randomUUID();
const people = owners.map(() => Array.from({ length: 4 }, () => randomUUID()));
const children = new Set();

function command(commandArgs, input) {
  const result = spawnSync(docker, commandArgs, { input, encoding: "utf8", timeout: 15000 });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return result.stdout.trim();
}
const query = (text) => command(args, text);
const flag = () => query(`select commercial_access_enabled or stripe_sales_enabled or shared_access_enforcement_enabled
  or notifications_enabled or purges_enabled from public.billing_runtime_config;
  select enforcement_enabled from public.account_trial_runtime_config;`);
const auth = (id) => `set local role authenticated;
  select set_config('request.jwt.claim.sub','${id}',true);`;
const create = (i, j) => `insert into public.protected_persons(id,owner_id,first_name,last_name)
  values ('${people[i][j]}','${owners[i]}','Fixture','Quota');`;
const transition = (operation, i, j) => `select public.${operation}_protected_person('${people[i][j]}',1,'Fixture');`;

function session(name, body, waitForCommit = false) {
  const process = spawn(docker, args, { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
  let output = "";
  let error = "";
  children.add(process);
  process.stdin.on("error", () => {});
  process.stdout.setEncoding("utf8").on("data", (chunk) => { output += chunk; });
  process.stderr.setEncoding("utf8").on("data", (chunk) => { error += chunk; });
  const closed = new Promise((resolve) => process.once("close", (code) => {
    children.delete(process);
    resolve({ code, error });
  }));
  process.stdin.write(`set application_name='${app(name)}';
    set statement_timeout='25s'; set idle_in_transaction_session_timeout='25s';
    begin;\n${body}\n\\echo READY\n`);
  if (!waitForCommit) process.stdin.end("commit;\n");
  return { process, closed, get output() { return output; } };
}

async function until(check, description) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    if (check()) return;
    await delay(80);
  }
  throw new Error(description);
}

async function race(label, owner, leftSql, rightSql, rightError, expected, beforeCommit = async () => {}) {
  const left = session("left", leftSql, true);
  await until(() => left.output.includes("READY"), `${label}: first operation did not reach the lock barrier`);
  const right = session("right", rightSql);
  await until(() => query(`select exists(select 1 from pg_stat_activity
    where application_name='${app("right")}' and wait_event_type='Lock')`) === "t",
    `${label}: no lock contention observed`);
  await beforeCommit();
  left.process.stdin.end("commit;\n");
  const [first, second] = await Promise.all([left.closed, right.closed]);
  assert.equal(first.code, 0, first.error);
  if (rightError) {
    assert.notEqual(second.code, 0);
    assert.match(second.error, new RegExp(rightError));
  } else {
    assert.equal(second.code, 0, second.error);
  }
  assert.equal(query(`select string_agg(status, ',' order by id) from public.protected_persons
    where owner_id='${owners[owner]}' and id in (${sqlList(people[owner])});`), expected);
  console.log(`PASS ${label} | verrou observé | ${expected}`);
}

assert.match(command(["port", container, "5432/tcp"]), /:57322\s*$/);
assert.equal(flag(), "f\nf");
const lifecycle = query("select lifecycle_enabled from public.protected_person_archive_runtime_config;");
assert.match(lifecycle, /^[tf]$/);
const subjects = [...owners, admin];

try {
  query(`begin;
    insert into auth.users(id,email,raw_user_meta_data)
    select id, 'quota-02e-' || id || '@test.invalid', '{}'::jsonb
    from unnest(array[${sqlList(subjects)}]::uuid[]) id;
    update public.application_user_authorizations set status='active',status_changed_at=now(),
      account_mode='autonomous',registration_intent='autonomous',autonomous_registration_status='active'
      where user_id in (${sqlList(subjects)});
    insert into public.platform_administrators(user_id) values ('${admin}');
    insert into public.account_administrative_plan_assignments(id,owner_id,plan_key,billing_period,dossier_capacity_key,
      reason,created_by) values ('${assignment}','${owners[4]}','comfort','monthly','five','Fixture','${admin}');
    insert into public.protected_persons(id,owner_id,first_name,last_name,status,archived_at)
    values ${[[0], [1, 1, 2], [2, 1], [3], [4], [5]].flatMap(([i, ...archives]) =>
      [0, ...(i === 3 || i === 4 ? [1] : []), ...archives].map((j) =>
        `('${people[i][j]}','${owners[i]}','Fixture','Quota',${archives.includes(j) ? "'archived',now()" : "'active',null"})`)).join(",")};
    update public.protected_person_archive_runtime_config set lifecycle_enabled=true where singleton;
    update public.billing_runtime_config set commercial_access_enabled=true where singleton;
    commit;`);

  await race("Deux créations", 0, auth(owners[0]) + create(0, 1), auth(owners[0]) + create(0, 2), "P4D01", "active,active");
  const states = (i, entries) => entries.sort(([a], [b]) => people[i][a].localeCompare(people[i][b])).map(([, status]) => status).join(",");
  await race("Deux restaurations", 1, auth(owners[1]) + transition("restore", 1, 1),
    auth(owners[1]) + transition("restore", 1, 2), "P4D01", states(1, [[0,"active"],[1,"active"],[2,"archived"]]));
  await race("Création et restauration", 2, auth(owners[2]) + create(2, 2),
    auth(owners[2]) + transition("restore", 2, 1), "P4D01", states(2, [[0,"active"],[1,"archived"],[2,"active"]]));
  await race("Archivage et création", 3, auth(owners[3]) + transition("archive", 3, 0),
    auth(owners[3]) + create(3, 2), null, states(3, [[0,"archived"],[1,"active"],[2,"active"]]));
  await race("Création et réduction administrative", 4, auth(owners[4]) + create(4, 2),
    auth(admin) + `select * from public.replace_administrative_plan(
      '${owners[4]}','${assignment}','essential','monthly','included','Fixture','${randomUUID()}',1);`,
    "P5A13", "active,active,active");
  assert.equal(query(`select dossier_capacity_key from public.account_administrative_plan_assignments where id='${assignment}';`), "five");

  query(`insert into public.account_trials(user_id,terms_version,terms_accepted_at,started_at,ends_at,deletion_eligible_at)
    select '${owners[5]}','fixture', t-interval '30 days', t-interval '30 days', t,t+interval '30 days'
    from (select clock_timestamp()+interval '8 seconds' t) clock;`);
  await race("Expiration J30 et création", 5, `select public.lock_owner_dossier_capacity('${owners[5]}');`,
    auth(owners[5]) + create(5, 1), "P4D04", "active", async () => {
      await until(() => query(`select ends_at <= clock_timestamp() from public.account_trials where user_id='${owners[5]}';`) === "t",
        "The trial did not expire before the owner lock was released");
    });

  for (const level of ["repeatable read", "serializable"]) {
    const isolated = await session("isolation", `set transaction isolation level ${level};` +
      auth(owners[0]) + create(0, 3)).closed;
    assert.notEqual(isolated.code, 0);
    assert.match(isolated.error, /25000/);
  }
  assert.equal(query(`select count(*) from public.protected_persons where id='${people[0][3]}';`), "0");
  console.log("PASS quota : REPEATABLE READ et SERIALIZABLE refusés sans création");
} finally {
  for (const child of children) child.stdin.end("rollback;\n");
  query(`select pg_terminate_backend(pid) from pg_stat_activity
    where application_name in ('${app("left")}','${app("right")}','${app("isolation")}') and pid <> pg_backend_pid();`);
  query(`begin;
    update public.billing_runtime_config set commercial_access_enabled=false where singleton;
    update public.protected_person_archive_runtime_config set lifecycle_enabled=${lifecycle === "t"} where singleton;
    delete from public.protected_person_archive_changes where protected_person_id in (${sqlList(people.flat())});
    delete from public.protected_persons where owner_id in (${sqlList(owners)});
    delete from public.platform_administrators where user_id='${admin}';
    delete from auth.users where id in (${sqlList(subjects)});
    commit;`);
  assert.equal(query(`select count(*) from auth.users where id in (${sqlList(subjects)});`), "0");
  assert.equal(flag(), "f\nf");
}
