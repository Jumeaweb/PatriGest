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
  "./registration-review-actions": { ResendActivationEmailButton: () => createElement("button", null, "Renvoyer la notification d’activation") },
  "./administration-user-entitlement-editor": { AdministrationUserEntitlementEditor: () => null },
});

function serviceHarness({ allowed = true, sharesResult, mode = "collaborator", status = "active",
  trialState = "awaiting_activation", targetIsAdmin = false, bannedUntil, email = "recette-1@example.test" } = {}) {
  const calls = [];
  const sent = [];
  const fixtureUsers = [
    { id: "recette-1", email, banned_until: bannedUntil, created_at: "2026-01-01T00:00:00Z", email_confirmed_at: "confirmed" },
    { id: "recette-2", email: "recette-2@example.test", created_at: "2026-01-01T00:00:00Z" },
  ];
  const rows = {
    profiles: [{ id: "recette-1", first_name: "Camille", last_name: "Recette" }],
    platform_administrators: targetIsAdmin ? [{ user_id: "recette-1" }] : [],
    application_user_authorizations: [
      { user_id: "recette-1", status, account_mode: mode },
      { user_id: "recette-2", status: "pending", account_mode: null },
    ],
    protected_person_access: [{ user_id: "recette-1" }],
  };
  function from(table) {
    let targetId;
    const query = {
      select(fields) { calls.push({ table, fields }); return query; },
      in: () => query,
      eq: (_column, id) => { targetId = id; return query; },
      is: () => query,
      gt: () => query,
      maybeSingle: async () => ({ data: targetId === "administrator" && table === "platform_administrators"
        ? (allowed ? { user_id: "administrator" } : null)
        : rows[table]?.find((item) => (item.id ?? item.user_id) === targetId) ?? null }),
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
        return { data: trialState ? [{ user_id: "recette-1", state: trialState }] : [], error: null };
      }
      return { data: [], error: null };
    },
  };
  const { getPlatformUsers, resendApplicationActivationEmail, reviewApplicationRegistration } = load("./services/administration-service.ts", {
    "server-only": {},
    "next/navigation": { notFound: () => { throw new Error("Refus administrateur"); } },
    "@/lib/supabase/server": { createClient: async () => supabase },
    "@/lib/supabase/admin": { createAdminClient: () => ({
      from,
      auth: { admin: { getUserById: async (id) => ({ data: { user: fixtureUsers.find((user) => user.id === id) } }), listUsers: async ({ page, perPage }) => {
        calls.push({ page, perPage });
        return { data: { users: fixtureUsers, lastPage: 2, total: 27 }, error: null };
      } } },
    }) },
    "../registration-email": { sendApplicationActivationEmail: async (payload) => { sent.push(payload); } },
    "./registration-rejection-notification-service": {},
    "../administrative-account-deletion-durable-availability": {},
    "../administrative-account-deletion-durable": {},
  });
  return { calls, sent, getPlatformUsers, resendApplicationActivationEmail, reviewApplicationRegistration };
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
    assert.equal(html.match(/>Non applicable</g)?.length, 4);
    assert.doesNotMatch(html, /Essai gratuit en cours pour|Aucune formule|Capacité non attribuée/);
  }
});

test("la notification utilise la même éligibilité sur ordinateur, sur mobile et côté serveur", async (t) => {
  for (const [name, options, eligible] of [
    ["autonome actif", {}, true],
    ["collaborateur actif", { mode: "collaborator" }, false],
    ["en attente", { status: "pending" }, false],
    ["inactif", { status: "rejected" }, false],
    ["essai suspendu", { trialState: "suspended" }, false],
    ["échéance J60", { trialState: "deletion_due" }, false],
    ["suspendu côté Auth", { bannedUntil: "2099-01-01T00:00:00Z" }, false],
    ["administrateur", { targetIsAdmin: true }, false],
    ["mode indéfini", { mode: null }, false],
    ["état indisponible", { trialState: null }, false],
    ["adresse indisponible", { email: "" }, false],
  ]) {
    await t.test(name, async () => {
      const harness = serviceHarness({ mode: "autonomous", trialState: "active", ...options });
      const { users: [user] } = await harness.getPlatformUsers();
      assert.equal(user.canResendActivationEmail, eligible);
      const html = renderToStaticMarkup(createElement(AdministrationUsersTable, { users: [user] }));
      assert.equal(html.match(/Renvoyer la notification d’activation/g)?.length ?? 0, eligible ? 2 : 0);
      if (eligible) {
        await harness.resendApplicationActivationEmail(user.id);
        assert.deepEqual(harness.sent, [{ email: user.email, firstName: "Camille", lastName: "Recette" }]);
      } else {
        await assert.rejects(harness.resendApplicationActivationEmail(user.id), /réservé aux comptes autonomes|Aucune adresse/);
        assert.equal(harness.sent.length, 0);
      }
    });
  }
});

test("un appel de renvoi par un non-administrateur n'envoie aucun message", async () => {
  const harness = serviceHarness({ allowed: false, mode: "autonomous", trialState: "active" });
  const { resendApplicationActivationEmailAction } = load("./actions.ts", {
    "next/cache": {},
    "./services/administration-service": { resendApplicationActivationEmail: harness.resendApplicationActivationEmail },
    "./services/administrative-document-repair-service": {},
    "./administrative-document-repair": {},
    "./administrative-document-exceptional-recovery": {},
    "./administrative-document-physical-verification": {},
    "./services/administrative-document-physical-verification-service": {},
    "./services/release-notification-service": {},
  });
  const formData = new FormData();
  formData.set("userId", "4e200973-7127-49a1-a754-0284e7a80003");
  const result = await resendApplicationActivationEmailAction({}, formData);
  assert.equal(result.status, "error");
  assert.match(result.message, /Refus administrateur/);
  assert.equal(harness.sent.length, 0);
  assert.ok(harness.calls.every((call) => call.table === "platform_administrators"));
});

test("la notification initiale suit toujours l'activation administrative", async () => {
  const harness = serviceHarness({ status: "pending", mode: null });
  assert.deepEqual(await harness.reviewApplicationRegistration("recette-1", "active"), { emailSent: true });
  assert.equal(harness.sent.length, 1);
  assert.ok(harness.calls.some((call) => call.rpc === "review_application_user_registration"));
});

test("les motifs d'éligibilité restent dans les rubriques associées sur ordinateur et mobile", async () => {
  const message = "Un abonnement commercial ou une attribution administrative est nécessaire pour créer une dérogation.";
  const { users: [autonomous] } = await serviceHarness({ mode: "autonomous" }).getPlatformUsers();
  const { users: [collaborator] } = await serviceHarness().getPlatformUsers();
  for (const user of [autonomous, collaborator]) {
    const html = renderToStaticMarkup(createElement(AdministrationUsersTable, { users: [{
      ...user, entitlements: { accessSource: "none", effectiveActiveDossierLimit: null, planAssignmentBlockCode: null,
        entitlementOverrideBlockCode: "entitlement_base_required" },
    }] }));
    const cells = [...html.matchAll(/<td[^>]*>(.*?)<\/td>/g)].map((match) => match[1]);
    assert.match(cells[4], /Aucune attribution/);
    assert.match(cells[5], /Aucune dérogation/);
    assert.doesNotMatch(cells[10], /Non applicable aux comptes collaborateurs|nécessaire pour créer une dérogation/);
    assert.match(cells[10], /Suppression indisponible/);
    if (user.accountMode === "collaborator") {
      assert.equal(html.match(/Non applicable aux comptes collaborateurs\./g)?.length, 4);
      assert.doesNotMatch(html, />Attribuer<\/button>/);
    } else {
      assert.ok(cells[5].includes(message));
      assert.match(html, /<dt[^>]*>Dérogation active<\/dt>[\s\S]*?nécessaire pour créer une dérogation\./);
      assert.equal(html.match(/>Attribuer<\/button>/g)?.length, 2);
    }
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
