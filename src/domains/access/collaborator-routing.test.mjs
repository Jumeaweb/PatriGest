import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { runInThisContext } from "node:vm";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";
import { getInvitationRoleLabel, getDossierInvitationSentence } from "./invitation-presentation.ts";
import { getDossierInvitationStatus } from "./invitation-status.ts";
import { canRecoverDossierInvitations } from "./invitation-recovery-policy.ts";
import * as callbackDestination from "../../lib/auth/callback-destination.ts";
import * as invitationDestination from "../../lib/auth/invitation-destination.ts";
import * as invitationRecovery from "../../lib/auth/invitation-recovery.ts";
import * as signupConfirmation from "../../lib/auth/signup-confirmation.ts";
import * as routePolicy from "../../lib/supabase/proxy-route-policy.ts";

const requireModule = createRequire(import.meta.url);
const { NextRequest } = requireModule("next/server");
const origin = "https://patrigest.example";
const userId = "fixture-user";
const email = "recette+collaborateur@example.test";
const token = "a".repeat(64);
const hash = createHash("sha256").update(token).digest("hex");
const invitationId = "80f1d052-d2ae-4bb1-a206-dc78b0cd965e";
const dossierId = "fixture-dossier";
const dossierPath = `/dossiers/${dossierId}/tableau-de-bord`;

class RedirectTo extends Error {
  constructor(path) {
    super(path);
    this.path = path;
  }
}
const navigation = { redirect: (path) => { throw new RedirectTo(path); } };
const components = {
  "next/navigation": navigation,
  "next/link": ({ children, prefetch, ...props }) => {
    void prefetch;
    return createElement("a", props, children);
  },
  "@/app/(auth)/actions": { logoutAction: () => {} },
  "@/components/auth/auth-shell": {
    AuthShell: ({ title, description, children }) =>
      createElement("main", null, createElement("h1", null, title), createElement("p", null, description), children),
  },
  "@/domains/access/components/invitation-decision-actions": {
    InvitationDecisionActions: ({ acceptLabel }) => createElement("button", null, acceptLabel),
  },
  "@/domains/access/invitation-presentation": { getInvitationRoleLabel, getDossierInvitationSentence },
  "@/lib/auth/invitation-destination": invitationDestination,
  "@/lib/auth/invitation-recovery": invitationRecovery,
};

const compiled = new Map();
function loadModule(path, imports) {
  if (!compiled.has(path)) {
    const url = new URL(path, import.meta.url);
    const { outputText } = ts.transpileModule(readFileSync(url, "utf8"), {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
        jsx: ts.JsxEmit.ReactJSX,
        esModuleInterop: true,
      },
      fileName: url.pathname,
    });
    compiled.set(path, runInThisContext(`(function (require, module, exports) { ${outputText}\n })`, { filename: url.pathname }));
  }
  const testModule = { exports: {} };
  const resolve = (name) => Object.hasOwn(imports, name) ? imports[name] : requireModule(name);
  compiled.get(path)(resolve, testModule, testModule.exports);
  return testModule.exports;
}

function harness({ role = "manager", intent = "collaborator", status = "pending", invitation = {}, includeInvitation = true } = {}) {
  const state = { session: false, confirmed: false, commercialRestricted: null, trialRestricted: false, shares: [], mutations: [] };
  const authorization = { user_id: userId, status, registration_intent: intent, account_mode: null };
  const invite = {
    id: invitationId, token_hash: hash, role, email, protected_person_id: dossierId, invited_by: null,
    accepted_at: null, revoked_at: null, declined_at: null, expires_at: "2099-01-01T00:00:00.000Z", ...invitation,
  };
  const tables = {
    application_user_authorizations: [authorization],
    platform_administrators: [],
    protected_person_invitations: includeInvitation ? [invite] : [],
    protected_persons: [{ id: dossierId, first_name: "Camille", last_name: "Recette" }],
    profiles: [],
  };
  function from(table) {
    let rows = tables[table];
    const query = {
      select: () => query,
      eq: (key, value) => { rows = rows.filter((row) => row[key] === value); return query; },
      is: (key, value) => query.eq(key, value),
      gt: (key, value) => { rows = rows.filter((row) => row[key] > value); return query; },
      in: (key, values) => { rows = rows.filter((row) => values.includes(row[key])); return query; },
      order: () => query,
      maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
      then: (resolve, reject) => Promise.resolve({ data: rows, error: null }).then(resolve, reject),
    };
    return query;
  }
  const supabase = {
    from,
    auth: {
      getClaims: async () => ({ data: state.session ? { claims: { sub: userId, email } } : null }),
      verifyOtp: async () => { state.session = state.confirmed = true; return { error: null }; },
      admin: { getUserById: async () => ({ data: { user: { email, email_confirmed_at: state.confirmed ? "confirmed" : null } }, error: null }) },
    },
    async rpc(name, args) {
      if (name === "get_current_account_trial_state") return { data: [{ enforcement_enabled: state.trialRestricted, state: "suspended" }] };
      if (name === "current_commercial_access_restricted") return { data: state.commercialRestricted };
      state.mutations.push(name);
      if (name === "complete_own_autonomous_trial_registration") return { error: null };
      assert.equal(name, "accept_protected_person_invitation");
      if (!includeInvitation || !state.session || !state.confirmed || invite.email !== email ||
          args.p_token_hash !== hash || getDossierInvitationStatus(invite) !== "pending") {
        return { data: null, error: { message: "Invitation invalide ou expirée." } };
      }
      assert.equal(authorization.registration_intent, "collaborator");
      authorization.status = "active";
      authorization.account_mode = "collaborator";
      invite.accepted_at = new Date().toISOString();
      state.shares.push(invite.role);
      return { data: dossierId, error: null };
    },
  };
  const db = {
    "@/lib/supabase/server": { createClient: async () => supabase },
    "@/lib/supabase/admin": { createAdminClient: () => supabase },
  };
  const services = loadModule("./services.ts", {
    ...db, "server-only": {}, "next/navigation": navigation,
    "@/domains/protected-persons/services/protected-person-service": {},
    "./invitation-status": { getDossierInvitationStatus },
    "./invitation-recovery-policy": { canRecoverDossierInvitations },
    "./share-limits": {},
    "./access-pagination": {},
  });
  const pageImports = { ...components, ...db, "@/domains/access/services": services };
  const proxy = loadModule("../../lib/supabase/proxy.ts", {
    "@supabase/ssr": { createServerClient: () => supabase },
    "./config": { getSupabaseConfig: () => ({ supabaseUrl: origin, supabaseAnonKey: "fixture" }) },
    "./proxy-route-policy": routePolicy,
  });
  const callback = loadModule("../../app/auth/callback/route.ts", {
    ...pageImports,
    "@/lib/auth/callback-destination": callbackDestination,
    "@/lib/auth/signup-confirmation": signupConfirmation,
    "@/domains/administration/services/registration-review-notification-service": { trySendPendingRegistrationNotification: async () => {} },
  });
  const actions = loadModule("./actions.ts", {
    ...db, "next/navigation": navigation, "next/cache": { revalidatePath: () => {} },
    "@/lib/auth/redirects": {}, "@/lib/auth/invitation-destination": invitationDestination,
    "./invitation-email": {}, "./services": services, "./share-limits": {},
  });
  const invitations = loadModule("../../app/invitations/page.tsx", pageImports).default;
  const waiting = loadModule("../../app/acces-en-attente/page.tsx", pageImports).default;
  const direct = loadModule("../../app/invitation/[token]/page.tsx", {
    ...pageImports, "@/domains/access/actions": actions,
  }).default;
  const props = { searchParams: Promise.resolve({}) };
  function request(path) { return new NextRequest(new URL(path, origin)); }
  async function render(path) {
    const url = new URL(path, origin);
    const response = await proxy.updateSession(request(path));
    if (response.headers.has("location")) {
      const destination = new URL(response.headers.get("location"));
      return { redirect: destination.pathname + destination.search };
    }
    try {
      if (url.pathname === "/invitations") return { html: renderToStaticMarkup(await invitations(props)) };
      if (url.pathname === "/acces-en-attente") return { html: renderToStaticMarkup(await waiting(props)) };
      if (url.pathname === `/invitation/${token}`) {
        return { html: renderToStaticMarkup(await direct({ params: Promise.resolve({ token }) })) };
      }
      return { allowed: true, status: response.status };
    } catch (error) {
      if (error instanceof RedirectTo) return { redirect: error.path };
      throw error;
    }
  }
  return {
    state, authorization, invite, actions, render,
    async confirm(next = null) {
      const params = new URLSearchParams({ token_hash: "c".repeat(64), type: "signup" });
      if (next) params.set("next", next);
      const response = await callback.GET(request(`/auth/callback?${params}`));
      return new URL(response.headers.get("location")).pathname;
    },
  };
}

for (const role of ["manager", "read_only"]) {
  test(`confirmation puis acceptation explicite du rôle ${role}, avec ou sans next`, async () => {
    for (const next of [null, `/invitation/${token}`]) {
      const flow = harness({ role });
      const destination = await flow.confirm(next);
      assert.equal(destination, next ?? "/invitations");
      const page = await flow.render(destination);
      assert.match(page.html, new RegExp(getInvitationRoleLabel(role)));
      assert.match(page.html, /Accepter/);
      assert.deepEqual(flow.state.mutations, []);
      assert.deepEqual(flow.state.shares, []);
      assert.equal(flow.authorization.status, "pending");
      assert.equal(flow.authorization.account_mode, null);
      assert.equal((await flow.render(dossierPath)).redirect, "/acces-en-attente");
      const accept = next ? flow.actions.acceptDossierInvitationAction(token) : flow.actions.acceptRecoveredDossierInvitationAction(invitationId);
      await assert.rejects(accept, { path: dossierPath });
      assert.deepEqual(flow.state.mutations, ["accept_protected_person_invitation"]);
      assert.deepEqual(flow.state.shares, [role]);
      assert.equal(flow.authorization.account_mode, "collaborator");
      assert.equal((await flow.render(dossierPath)).allowed, true);
    }
  });
}

test("une session collaborateur en attente sort de l'écran d'attente sans boucle", async () => {
  const flow = harness();
  flow.state.session = flow.state.confirmed = true;
  assert.equal((await flow.render("/acces-en-attente")).redirect, "/invitations");
  assert.match((await flow.render("/invitations")).html, /Accepter cette invitation/);
  for (const route of [
    dossierPath, "/invitations/autre", "/api/dossiers/fixture/comptes/account/releves/statement",
    "/api/dossiers/fixture/operations/transaction/justificatif", "/api/dossiers/fixture/comptes-de-gestion/report/document",
  ]) assert.equal((await flow.render(route)).redirect, "/acces-en-attente", route);
});

test("une session absente ou expirée conserve la destination et l'invitation d'origine propose la connexion", async () => {
  const flow = harness();
  assert.equal((await flow.render("/invitations")).redirect, "/connexion?next=%2Finvitations");
  assert.equal((await flow.render(dossierPath)).redirect, "/connexion");
  const direct = (await flow.render(`/invitation/${token}`)).html;
  assert.match(direct, /J’ai déjà un compte/);
  assert.match(direct, /connexion\?next=%2Finvitation%2F/);
  const result = await flow.actions.acceptRecoveredDossierInvitationAction(invitationId);
  assert.match(result.message, /session a expiré/);
  assert.deepEqual(flow.state.mutations, []);
});

test("sans invitation valide, la reprise collaborateur se termine avec une action adaptée", async () => {
  for (const options of [
    { includeInvitation: false },
    { invitation: { expires_at: "2000-01-01T00:00:00.000Z" }, message: /a expiré/ },
    { invitation: { revoked_at: "2025-01-01T00:00:00.000Z" }, message: /a été annulée/ },
    { invitation: { email: "autre@example.test" }, message: /destinée à/ },
  ]) {
    const flow = harness(options);
    flow.state.session = flow.state.confirmed = true;
    assert.equal((await flow.render("/acces-en-attente")).redirect, "/invitations");
    const listed = (await flow.render("/invitations")).html;
    assert.match(listed, /Aucune invitation active.*Se déconnecter pour changer de compte/);
    assert.doesNotMatch(listed, /essai gratuit|validation par|Accepter cette invitation/);
    if (options.message) assert.match((await flow.render(`/invitation/${token}`)).html, options.message);
    const denied = await flow.actions.acceptRecoveredDossierInvitationAction(invitationId);
    assert.equal(denied.status, "error");
    assert.deepEqual(flow.state.mutations, []);
    assert.deepEqual(flow.state.shares, []);
  }
});

test("une session authentifiée sans adresse confirmée ne retrouve aucun partage", async () => {
  const flow = harness();
  flow.state.session = true;
  assert.match((await flow.render("/invitations")).html, /Aucune invitation active/);
  assert.equal((await flow.actions.acceptRecoveredDossierInvitationAction(invitationId)).status, "error");
  assert.deepEqual(flow.state.mutations, []);
});

test("l'inscription autonome reste en validation et les accès existants des comptes suspendus sont préservés", async () => {
  const pending = harness({ intent: "autonomous", includeInvitation: false });
  assert.equal(await pending.confirm(), "/acces-en-attente");
  assert.match((await pending.render("/acces-en-attente")).html, /Votre inscription est en cours de validation/);
  assert.deepEqual(pending.state.mutations, ["complete_own_autonomous_trial_registration"]);
  const suspended = harness({ intent: "autonomous", status: "active", includeInvitation: false });
  suspended.state.session = suspended.state.confirmed = true;
  suspended.state.commercialRestricted = true;
  for (const path of ["/mon-compte", "/parametres/compte", "/parametres/compte?vue=abonnement"]) {
    assert.equal((await suspended.render(path)).allowed, true, path);
  }
  assert.equal((await suspended.render(dossierPath)).redirect, "/parametres/compte?vue=abonnement");
  suspended.state.commercialRestricted = null;
  suspended.state.trialRestricted = true;
  assert.equal((await suspended.render("/parametres/compte?vue=abonnement")).allowed, true);
  assert.equal((await suspended.render(dossierPath)).redirect, "/parametres/compte?vue=abonnement");
});
