import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { runInThisContext } from "node:vm";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const requireModule = createRequire(import.meta.url);
const token = "d".repeat(64);
const email = "patrigest+recette@gmail.com";
const password = "UnMotDePasseFictif123!";

function loadModule(relativePath, imports) {
  const url = new URL(relativePath, import.meta.url);
  const { outputText } = ts.transpileModule(readFileSync(url, "utf8"), {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      jsx: ts.JsxEmit.ReactJSX,
      esModuleInterop: true,
    },
    fileName: url.pathname,
  });
  const testModule = { exports: {} };
  const resolve = (name) => {
    if (Object.hasOwn(imports, name)) return imports[name];
    if (["zod", "react", "react/jsx-runtime", "react-dom"].includes(name)) {
      return requireModule(name);
    }
    throw new Error(`Import de test non prévu : ${name}`);
  };
  runInThisContext(`(function (require, module, exports) { ${outputText}\n })`, {
    filename: url.pathname,
  })(resolve, testModule, testModule.exports);
  return testModule.exports;
}

function signupHarness(invitation = null) {
  const calls = { signups: [], consentUsers: [], validatedTokens: [], recoveryCookies: [] };
  const { signupAction } = loadModule("../../app/(auth)/actions.ts", {
    "next/navigation": {},
    "next/headers": { cookies: async () => ({ set: (...args) => calls.recoveryCookies.push(args) }) },
    "@/lib/auth/errors": {},
    "@/lib/auth/redirects": { getAuthCallbackOrigin: async () => "https://patrigest.example" },
    "@/lib/auth/invitation-destination": { getDossierInvitationPath: (value) => `/invitations/${value}` },
    "@/lib/auth/invitation-recovery": { INVITATION_RECOVERY_COOKIE: "invitation-recovery" },
    "@/lib/auth/invited-signup-recovery": { shouldRecoverInvitedAuthAccount: () => false },
    "@/lib/supabase/server": {
      createClient: async () => ({
        auth: {
          signUp: async (payload) => {
            calls.signups.push(payload);
            return { data: { user: { id: "fixture-user", identities: [{}] } }, error: null };
          },
        },
      }),
    },
    "@/domains/access/actions": {
      validateSignupInvitation: async (value) => {
        calls.validatedTokens.push(value);
        return invitation;
      },
    },
    "@/domains/access/services": {},
    "@/domains/trials/services": { recordAccountTrialTermsAcceptance: async (id) => calls.consentUsers.push(id) },
    "@/domains/trials/constants": { ACCOUNT_TRIAL_TERMS_VERSION: "test-terms" },
    "@/domains/administration/services/registration-review-notification-service": {},
  });
  return {
    calls,
    signup(fields = {}) {
      const formData = new FormData();
      for (const [name, value] of Object.entries({
        email,
        firstName: "Gestionnaire",
        lastName: "PAT-STRIPE-RECETTE",
        password,
        passwordConfirmation: password,
        ...fields,
      })) formData.set(name, value);
      return signupAction({ status: "idle", message: "" }, formData);
    },
  };
}

test("l'inscription autonome exige la valeur explicite on", async () => {
  const valid = signupHarness();
  assert.equal((await valid.signup({ trialTermsAccepted: "on" })).status, "success");
  assert.equal(valid.calls.signups[0].options.data.patrigest_registration_intent, "autonomous");
  assert.equal(valid.calls.signups[0].options.data.patrigest_trial_terms_accepted, true);
  assert.deepEqual(valid.calls.consentUsers, ["fixture-user"]);
  assert.deepEqual(valid.calls.validatedTokens, []);

  for (const fields of [{}, { trialTermsAccepted: "yes" }]) {
    const attempt = signupHarness();
    const result = await attempt.signup(fields);
    assert.equal(result.status, "error");
    assert.match(result.fieldErrors.trialTermsAccepted[0], /Acceptez les conditions/);
    assert.deepEqual(attempt.calls.signups, []);
    assert.deepEqual(attempt.calls.consentUsers, []);
  }
});

for (const role of ["manager", "read_only"]) {
  test(`l'invitation ${role} accepte un alias Gmail et ne transmet ni consentement ni rôle à Auth`, async () => {
    const { calls, signup } = signupHarness({ kind: "dossier", id: "fixture-invitation", email, role });
    const result = await signup({ invitationToken: token });
    assert.equal(result.status, "success");
    assert.match(result.message, /Confirmez votre adresse e-mail.*acceptation de votre invitation/);
    assert.deepEqual(calls.validatedTokens, [token]);
    assert.equal(calls.signups.length, 1);
    const [request] = calls.signups;
    assert.equal(request.email, email);
    assert.deepEqual(request.options.data, {
      first_name: "Gestionnaire",
      last_name: "PAT-STRIPE-RECETTE",
      patrigest_registration_intent: "collaborator",
    });
    assert.equal(new URL(request.options.emailRedirectTo).searchParams.get("next"), `/invitations/${token}`);
    assert.deepEqual(calls.consentUsers, []);
    assert.equal(calls.recoveryCookies[0][1], "fixture-invitation");
  });
}

test("un jeton invalide ou expiré est refusé avant la création Auth", async () => {
  for (const value of ["court", token]) {
    const { calls, signup } = signupHarness();
    const result = await signup({ invitationToken: value });
    assert.equal(result.status, "error");
    assert.match(result.message, /invitation est invalide ou a expiré/);
    assert.deepEqual(calls.validatedTokens, value === token ? [token] : []);
    assert.deepEqual(calls.signups, []);
  }
});

test("une adresse divergente ou une confirmation incorrecte bloque la création Auth", async () => {
  const { calls, signup } = signupHarness({ kind: "dossier", id: "fixture-invitation", email, role: "manager" });
  const addressError = await signup({ invitationToken: token, email: "autre+recette@gmail.com" });
  assert.match(addressError.message, /adresse email associée à cette invitation/);
  const passwordError = await signup({ invitationToken: token, passwordConfirmation: "ConfirmationDifférente" });
  assert.match(passwordError.fieldErrors.passwordConfirmation[0], /ne correspondent pas/);
  assert.deepEqual(calls.signups, []);
});

test("le résumé accessible renvoie aux champs visibles et conserve leurs messages locaux", () => {
  const state = {
    status: "error",
    message: "Vérifiez les informations saisies.",
    fieldErrors: {
      passwordConfirmation: ["Les mots de passe ne correspondent pas."],
      trialTermsAccepted: ["Acceptez les conditions de l’essai gratuit pour poursuivre."],
    },
  };
  const controls = loadModule("../../components/auth/form-controls.tsx", {});
  const { SignupForm } = loadModule("../../components/auth/auth-forms.tsx", {
    "next/link": "a",
    "next/navigation": {},
    react: { useActionState: () => [state, () => {}] },
    "@/app/(auth)/actions": {},
    "@/components/ui/app-confirm-dialog": {},
    "@/lib/auth/invitation-destination": {
      getDossierInvitationLoginPath: () => "/connexion",
      getDossierInvitationPath: () => "/invitations/fixture",
    },
    "@/lib/auth/state": {},
    "./form-controls": controls,
  });
  const invited = renderToStaticMarkup(createElement(SignupForm, { collaboratorInvitation: true }));
  const autonomous = renderToStaticMarkup(createElement(SignupForm));
  for (const html of [invited, autonomous]) {
    assert.match(html, /role="alert"[^>]*>[\s\S]*href="#passwordConfirmation"[^>]*>Confirmation du mot de passe<\/a> : Les mots de passe ne correspondent pas/);
    assert.match(html, /aria-describedby="passwordConfirmation-error"/);
    assert.match(html, /id="passwordConfirmation-error"[^>]*><p[^>]*>Les mots de passe ne correspondent pas/);
  }
  assert.doesNotMatch(invited, /trialTermsAccepted|Conditions de l’essai gratuit/);
  assert.match(autonomous, /href="#trialTermsAccepted"[^>]*>Conditions de l’essai gratuit<\/a>/);
});
