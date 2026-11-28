import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { runInThisContext } from "node:vm";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const requireModule = createRequire(import.meta.url);
const compiled = new Map();

function load(path, imports) {
  if (!compiled.has(path)) {
    const url = new URL(path, import.meta.url);
    const { outputText } = ts.transpileModule(readFileSync(url, "utf8"), {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
        jsx: ts.JsxEmit.ReactJSX,
      },
      fileName: url.pathname,
    });
    compiled.set(path, runInThisContext(`(function (require, module, exports) { ${outputText}\n })`));
  }
  const target = { exports: {} };
  compiled.get(path)((name) => Object.hasOwn(imports, name) ? imports[name] : requireModule(name), target, target.exports);
  return target.exports;
}

const { AdministrationUsersTable } = load("./components/administration-users-table.tsx", {
  "./delete-user-button": { DeleteUserButton: () => null },
  "./registration-review-actions": { ResendActivationEmailButton: () => null },
  "./administration-user-entitlement-editor": { AdministrationUserEntitlementEditor: () => null },
});

function serviceHarness({ allowed = true, sharesResult, mode = "collaborator" } = {}) {
  const calls = [];
  const fixtureUsers = [
    { id: "recette-1", email: "recette-1@example.test", created_at: "2026-01-01T00:00:00Z", email_confirmed_at: "confirmed" },
    { id: "recette-2", email: "recette-2@example.test", created_at: "2026-01-01T00:00:00Z" },
  ];
  const rows = {
    profiles: [{ id: "recette-1", first_name: "Camille", last_name: "Recette" }],
    application_user_authorizations: [
      { user_id: "recette-1", status: "active", account_mode: mode },
      { user_id: "recette-2", status: "pending", account_mode: null },
    ],
    protected_person_access: [{ user_id: "recette-1" }],
  };
  function from(table) {
    const query = {
      select(fields) { calls.push({ table, fields }); return query; },
      in: () => query,
      eq: () => query,
      is: () => query,
      gt: () => query,
      maybeSingle: async () => ({ data: allowed ? { user_id: "administrator" } : null }),
      then: (resolve, reject) => Promise.resolve({ data: rows[table] ?? [], error: null }).then(resolve, reject),
    };
    return query;
  }
  const supabase = {
    auth: { getClaims: async () => ({ data: { claims: { sub: "administrator" } } }) },
    from,
    async rpc(name, args) {
      calls.push({ rpc: name, args });
      if (name === "list_administrative_collaborator_access_counts") {
        return sharesResult ?? { data: [
          { user_id: "recette-1", total_count: 3, manager_count: 2, read_only_count: 1 },
          { user_id: "recette-2", total_count: 0, manager_count: 0, read_only_count: 0 },
        ], error: null };
      }
      if (name === "list_administrative_account_trial_states") {
        return { data: [{ user_id: "recette-1", state: "awaiting_activation" }], error: null };
      }
      return { data: [], error: null };
    },
  };
  const { getPlatformUsers } = load("./services/administration-service.ts", {
    "server-only": {},
    "next/navigation": { notFound: () => { throw new Error("Refus administrateur"); } },
    "@/lib/supabase/server": { createClient: async () => supabase },
    "@/lib/supabase/admin": { createAdminClient: () => ({
      from,
      auth: { admin: { listUsers: async ({ page, perPage }) => {
        calls.push({ page, perPage });
        return { data: { users: fixtureUsers, lastPage: 2, total: 27 }, error: null };
      } } },
    }) },
    "../registration-email": {},
    "./registration-rejection-notification-service": {},
    "../administrative-account-deletion-durable-availability": {},
    "../administrative-account-deletion-durable": {},
  });
  return { calls, getPlatformUsers };
}

test("l'administration demande les compteurs en une fois pour la page de 25 comptes", async () => {
  const { calls, getPlatformUsers } = serviceHarness();
  const result = await getPlatformUsers(2);
  assert.equal(result.page, 2);
  assert.deepEqual(calls.filter((call) => call.perPage), [{ page: 2, perPage: 25 }]);
  assert.deepEqual(calls.filter((call) => call.rpc === "list_administrative_collaborator_access_counts"), [{
    rpc: "list_administrative_collaborator_access_counts", args: { p_user_ids: ["recette-1", "recette-2"] },
  }]);
  assert.equal(calls.filter((call) => call.table === "protected_persons").length, 1);
  assert.ok(calls.every((call) => call.table !== "protected_persons" || !/first_name|last_name/.test(call.fields)));
  assert.deepEqual(result.users[0].effectiveSharedAccess, { total: 3, manager: 2, readOnly: 1 });
  assert.equal(result.users[0].sharedAccessCount, null);
  assert.equal(result.users[1].effectiveSharedAccess, null);
});

test("un échec de projection laisse les compteurs indisponibles et conserve le blocage de suppression", async () => {
  const { getPlatformUsers } = serviceHarness({ sharesResult: { data: null, error: { code: "PGRST202" } } });
  const { users: [user] } = await getPlatformUsers();
  assert.equal(user.effectiveSharedAccess, null);
  assert.equal(user.canDelete, false);
  assert.ok(user.deletionBlockReasons.includes("Accès à un dossier partagé"));
  const html = renderToStaticMarkup(createElement(AdministrationUsersTable, { users: [user] }));
  assert.equal(html.match(/Compteurs des accès partagés indisponibles/g)?.length, 2);
  assert.doesNotMatch(html, /Aucun dossier partagé|Gestionnaire : 0/);
});

test("une projection incohérente ou incomplète laisse les compteurs indisponibles", async () => {
  for (const data of [[], [{ user_id: "recette-1", total_count: 1, manager_count: 2, read_only_count: 0 }]]) {
    const { users: [user] } = await serviceHarness({ sharesResult: { data, error: null } }).getPlatformUsers();
    assert.equal(user.effectiveSharedAccess, null);
  }
});

test("un non-administrateur est refusé avant tout chargement de comptes ou compteurs", async () => {
  const { getPlatformUsers, calls } = serviceHarness({ allowed: false });
  await assert.rejects(getPlatformUsers(), /Refus administrateur/);
  assert.ok(calls.every((call) => call.table === "platform_administrators"));
});

test("le tableau et les cartes mobiles partagent les libellés et les compteurs collaborateurs", async () => {
  const { users: [fixture] } = await serviceHarness().getPlatformUsers();
  for (const [total, manager, readOnly, expected] of [
    [0, 0, 0, "Aucun dossier partagé"],
    [1, 1, 0, "1 dossier partagé"],
    [1, 0, 1, "1 dossier partagé"],
    [3, 2, 1, "3 dossiers partagés"],
  ]) {
    const html = renderToStaticMarkup(createElement(AdministrationUsersTable, {
      users: [{ ...fixture, effectiveSharedAccess: { total, manager, readOnly } }],
    }));
    assert.match(html, /lg:block/);
    assert.match(html, /lg:hidden/);
    for (const text of [expected, `Gestionnaire : ${manager}`, `Lecture seule : ${readOnly}`, "Accès partagés uniquement"]) {
      assert.equal(html.split(text).length - 1, 2, text);
    }
    assert.equal(html.match(/Non applicable/g)?.length, 4);
    assert.doesNotMatch(html, /Essai gratuit en cours pour|Aucune formule|Capacité non attribuée/);
  }
});

test("les comptes autonomes et en attente conservent leurs libellés", async () => {
  const { users } = await serviceHarness({ mode: "autonomous" }).getPlatformUsers();
  const html = renderToStaticMarkup(createElement(AdministrationUsersTable, { users }));
  assert.match(html, /Compte autonome/);
  assert.match(html, /Mode non défini/);
  assert.match(html, /En attente/);
  assert.match(html, /Non démarré/);
  assert.match(html, /Aucun abonnement commercial/);
  assert.doesNotMatch(html, /Non applicable|Accès partagés uniquement/);
});
