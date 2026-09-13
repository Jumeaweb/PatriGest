import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  EmailReauthenticationError,
  EmailUnchangedError,
  loadAccountDataForUser,
  requestOwnEmailChangeWithAuth,
  updateOwnPasswordWithAuth,
  updateOwnProfileRow,
} from "./account-operations.ts";
import { emailChangeSchema, emailChangeSchemaForCurrentEmail, passwordSchema, profileSchema } from "./schemas.ts";

function accountClient({
  userId = randomUUID(),
  email = "personne@example.test",
  newEmail = null,
  firstName = "Marie",
  lastName = "Durand",
  administrator = null,
  profileUpdateResult = { data: { id: randomUUID() }, error: null },
  passwordResult = { data: { user: {} }, error: null },
  reauthenticationResult,
  emailChangeResult,
} = {}) {
  const calls = [];
  const defaultReauthenticationResult = { data: { user: { id: userId } }, error: null };
  const defaultEmailChangeResult = {
    data: { user: { id: userId, email, new_email: "nouvelle@example.test" } },
    error: null,
  };

  function selection(table) {
    const query = {
      select(columns) {
        calls.push(["select", table, columns]);
        return this;
      },
      eq(column, value) {
        calls.push(["eq", table, column, value]);
        return this;
      },
      async single() {
        calls.push(["single", table]);
        return { data: { first_name: firstName, last_name: lastName }, error: null };
      },
      async maybeSingle() {
        calls.push(["maybeSingle", table]);
        return { data: administrator, error: null };
      },
    };
    return query;
  }

  const updateQuery = {
    update(values) {
      calls.push(["update", "profiles", values]);
      return this;
    },
    eq(column, value) {
      calls.push(["update-eq", "profiles", column, value]);
      return this;
    },
    select(columns) {
      calls.push(["update-select", "profiles", columns]);
      return this;
    },
    async single() {
      calls.push(["update-single", "profiles"]);
      return profileUpdateResult;
    },
  };

  return {
    calls,
    client: {
      auth: {
        async getUser() {
          calls.push(["auth.getUser"]);
          return { data: { user: { id: userId, email, new_email: newEmail } }, error: null };
        },
        async signInWithPassword(credentials) {
          calls.push(["auth.signInWithPassword", credentials]);
          return reauthenticationResult ?? defaultReauthenticationResult;
        },
        async updateUser(attributes, options) {
          calls.push(["auth.updateUser", attributes, options]);
          return attributes.email ? emailChangeResult ?? defaultEmailChangeResult : passwordResult;
        },
      },
      from(table) {
        calls.push(["from", table]);
        return table === "profiles" && calls.some(([operation]) => operation === "profile-update-start")
          ? updateQuery
          : selection(table);
      },
    },
    beginProfileUpdate() {
      calls.push(["profile-update-start"]);
    },
  };
}

test("charge le profil et l’e-mail de l’utilisateur courant", async () => {
  const userId = randomUUID();
  const { client, calls } = accountClient();
  const account = await loadAccountDataForUser(client, userId);

  assert.deepEqual(account, {
    firstName: "Marie",
    lastName: "Durand",
    email: "personne@example.test",
    pendingEmail: null,
    isPlatformAdmin: false,
  });
  assert.ok(calls.some((call) => call[0] === "auth.getUser"));
  assert.ok(calls.some((call) => call[0] === "eq" && call[1] === "profiles" && call[2] === "id" && call[3] === userId));
});

test("charge et expose une adresse e-mail en attente distincte", async () => {
  const userId = randomUUID();
  const { client } = accountClient({ userId, newEmail: "nouvelle@example.test" });
  assert.equal((await loadAccountDataForUser(client, userId)).pendingEmail, "nouvelle@example.test");
});

test("charge aussi le compte d’un administrateur de plateforme", async () => {
  const userId = randomUUID();
  const { client } = accountClient({ administrator: { user_id: userId } });
  assert.equal((await loadAccountDataForUser(client, userId)).isPlatformAdmin, true);
});

test("valide et normalise un profil", () => {
  assert.deepEqual(profileSchema.parse({ firstName: "  Marie  ", lastName: "  Durand " }), {
    firstName: "Marie",
    lastName: "Durand",
  });
  assert.equal(profileSchema.safeParse({ firstName: "", lastName: "Durand" }).success, false);
});

test("met à jour uniquement l’utilisateur issu de la session avec cardinalité stricte", async () => {
  const userId = randomUUID();
  const { client, calls, beginProfileUpdate } = accountClient();
  beginProfileUpdate();

  await updateOwnProfileRow(client, userId, { firstName: "Marie", lastName: "Durand" });

  assert.deepEqual(calls.slice(-5), [
    ["from", "profiles"],
    ["update", "profiles", { first_name: "Marie", last_name: "Durand" }],
    ["update-eq", "profiles", "id", userId],
    ["update-select", "profiles", "id"],
    ["update-single", "profiles"],
  ]);

  const serviceSource = readFileSync(new URL("./services.ts", import.meta.url), "utf8");
  assert.match(serviceSource, /export async function updateOwnProfile\(input: ProfileInput\)/);
  assert.match(serviceSource, /const \{ supabase, userId \} = await getAuthenticatedUser\(\)/);
  assert.match(serviceSource, /updateOwnProfileRow\(supabase, userId, input\)/);
});

test("rejette explicitement une mise à jour de profil à zéro ligne", async () => {
  const { client, beginProfileUpdate } = accountClient({
    profileUpdateResult: { data: null, error: { code: "PGRST116" } },
  });
  beginProfileUpdate();
  await assert.rejects(
    updateOwnProfileRow(client, randomUUID(), { firstName: "Marie", lastName: "Durand" }),
    /Impossible de modifier le profil/,
  );
});

test("rejette les mots de passe invalides ou dont la confirmation diffère", () => {
  assert.equal(passwordSchema.safeParse({ currentPassword: "ancien", newPassword: "court", passwordConfirmation: "court" }).success, false);
  assert.equal(passwordSchema.safeParse({ currentPassword: "ancien", newPassword: "nouveau-solide", passwordConfirmation: "différent" }).success, false);
  assert.equal(passwordSchema.safeParse({ currentPassword: "identique-solide", newPassword: "identique-solide", passwordConfirmation: "identique-solide" }).success, false);
});

test("transmet le mot de passe actuel et le nouveau à Supabase Auth", async () => {
  const { client, calls } = accountClient();
  await updateOwnPasswordWithAuth(client, {
    currentPassword: "ancien-secret",
    newPassword: "nouveau-secret",
    passwordConfirmation: "nouveau-secret",
  });
  assert.deepEqual(calls.at(-1), ["auth.updateUser", {
    password: "nouveau-secret",
    current_password: "ancien-secret",
  }, undefined]);
});

test("valide, normalise et confirme la nouvelle adresse e-mail", () => {
  assert.deepEqual(emailChangeSchema.parse({
    currentPassword: "secret",
    newEmail: "  NOUVELLE@EXAMPLE.TEST ",
    emailConfirmation: "nouvelle@example.test",
  }), {
    currentPassword: "secret",
    newEmail: "nouvelle@example.test",
    emailConfirmation: "nouvelle@example.test",
  });
  assert.equal(emailChangeSchema.safeParse({ currentPassword: "secret", newEmail: "incorrecte", emailConfirmation: "incorrecte" }).success, false);
  assert.equal(emailChangeSchema.safeParse({ currentPassword: "secret", newEmail: "a@example.test", emailConfirmation: "b@example.test" }).success, false);
});

test("rejette une adresse identique à l’adresse Auth actuelle", async () => {
  assert.equal(emailChangeSchemaForCurrentEmail("Personne@Example.Test").safeParse({
    currentPassword: "secret",
    newEmail: " personne@example.test ",
    emailConfirmation: "personne@example.test",
  }).success, false);

  const userId = randomUUID();
  const { client, calls } = accountClient({ userId });
  await assert.rejects(
    requestOwnEmailChangeWithAuth(client, userId, {
      currentPassword: "secret",
      newEmail: "personne@example.test",
      emailConfirmation: "personne@example.test",
    }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"),
    EmailUnchangedError,
  );
  assert.equal(calls.some((call) => call[0] === "auth.signInWithPassword"), false);
});

test("réauthentifie l’utilisateur de session avant de demander le changement", async () => {
  const userId = randomUUID();
  const redirect = "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte";
  const { client, calls } = accountClient({ userId });
  const result = await requestOwnEmailChangeWithAuth(client, userId, {
    currentPassword: "secret-actuel",
    newEmail: "nouvelle@example.test",
    emailConfirmation: "nouvelle@example.test",
  }, redirect);

  assert.deepEqual(result, { status: "pending", pendingEmail: "nouvelle@example.test" });
  assert.deepEqual(calls.filter((call) => call[0].startsWith("auth.")), [
    ["auth.getUser"],
    ["auth.signInWithPassword", { email: "personne@example.test", password: "secret-actuel" }],
    ["auth.updateUser", { email: "nouvelle@example.test" }, { emailRedirectTo: redirect }],
  ]);
});

test("une réauthentification échouée interrompt le changement d’adresse", async () => {
  const userId = randomUUID();
  const { client, calls } = accountClient({
    userId,
    reauthenticationResult: { data: { user: null }, error: { code: "invalid_credentials", message: "raw" } },
  });
  await assert.rejects(
    requestOwnEmailChangeWithAuth(client, userId, {
      currentPassword: "incorrect",
      newEmail: "nouvelle@example.test",
      emailConfirmation: "nouvelle@example.test",
    }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"),
    EmailReauthenticationError,
  );
  assert.equal(calls.some((call) => call[0] === "auth.updateUser"), false);
});

test("refuse une réauthentification qui ne correspond pas à l’utilisateur de session", async () => {
  const userId = randomUUID();
  const { client, calls } = accountClient({
    userId,
    reauthenticationResult: { data: { user: { id: randomUUID() } }, error: null },
  });
  await assert.rejects(
    requestOwnEmailChangeWithAuth(client, userId, {
      currentPassword: "secret",
      newEmail: "nouvelle@example.test",
      emailConfirmation: "nouvelle@example.test",
    }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"),
    EmailReauthenticationError,
  );
  assert.equal(calls.some((call) => call[0] === "auth.updateUser"), false);
});

test("reconnaît uniquement une adresse immédiatement effective prouvée par Auth", async () => {
  const userId = randomUUID();
  const { client } = accountClient({
    userId,
    emailChangeResult: { data: { user: { id: userId, email: "nouvelle@example.test", new_email: null } }, error: null },
  });
  assert.deepEqual(await requestOwnEmailChangeWithAuth(client, userId, {
    currentPassword: "secret",
    newEmail: "nouvelle@example.test",
    emailConfirmation: "nouvelle@example.test",
  }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"), { status: "updated" });
});

test("ne déduit pas un changement effectif de la seule absence d’erreur", async () => {
  const userId = randomUUID();
  const { client } = accountClient({
    userId,
    emailChangeResult: { data: { user: { id: userId, email: "personne@example.test", new_email: null } }, error: null },
  });
  await assert.rejects(
    requestOwnEmailChangeWithAuth(client, userId, {
      currentPassword: "secret",
      newEmail: "nouvelle@example.test",
      emailConfirmation: "nouvelle@example.test",
    }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"),
    /indéterminé/,
  );
});

test("masque une erreur Auth indiquant qu’une adresse est déjà utilisée", async () => {
  const userId = randomUUID();
  const { client } = accountClient({
    userId,
    emailChangeResult: {
      data: { user: null },
      error: { code: "email_exists", message: "A user with this email address has already been registered" },
    },
  });
  await assert.rejects(
    requestOwnEmailChangeWithAuth(client, userId, {
      currentPassword: "secret",
      newEmail: "nouvelle@example.test",
      emailConfirmation: "nouvelle@example.test",
    }, "https://patrigest.fr/auth/callback?next=%2Fparametres%2Fcompte"),
    (error) => error.message === "Impossible de demander le changement d’adresse e-mail.",
  );
});

test("conserve les erreurs Auth internes dans la couche serveur", () => {
  const source = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(source, /Impossible de modifier le mot de passe\. Reconnectez-vous puis réessayez\./);
  assert.match(source, /Votre session n’est plus valide\. Reconnectez-vous puis réessayez\./);
  assert.match(source, /Impossible d’enregistrer la demande de changement d’adresse e-mail\. Réessayez ultérieurement\./);
  assert.doesNotMatch(source, /message:\s*error\.message/);
});

test("affiche les adresses actuelle et pending dans un formulaire sans identifiant métier", () => {
  const source = readFileSync(new URL("./components/email-form.tsx", import.meta.url), "utf8");
  assert.match(source, /Adresse e-mail actuelle/);
  assert.match(source, /Changement en attente/);
  assert.match(source, /\{pendingEmail\}/);
  assert.doesNotMatch(source, /name="(?:userId|profileId|dossierId)"/);
});

test("ne duplique ni ne propage l’adresse Auth dans les tables métier", () => {
  const operations = readFileSync(new URL("./account-operations.ts", import.meta.url), "utf8");
  const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.doesNotMatch(operations, /from\("(?:protected_person_invitations|account_requests)"\)/);
  assert.doesNotMatch(actions, /protected_person_invitations|account_requests/);
  assert.doesNotMatch(operations, /update\(\{[^}]*email/);
});

test("retourne des messages distincts pour les états pending et immédiat sans erreur brute", () => {
  const source = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(source, /Votre demande de changement d’adresse e-mail a été enregistrée\./);
  assert.match(source, /Votre adresse e-mail a été mise à jour\./);
  assert.doesNotMatch(source, /error\.message/);
});

test("construit le redirect Auth vers la route canonique sans domaine codé en dur", () => {
  const source = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(source, /getAuthCallbackOrigin\(\)/);
  assert.match(source, /\/auth\/callback\?next=\$\{encodeURIComponent\("\/parametres\/compte"\)\}/);
  assert.doesNotMatch(source, /https:\/\/patrigest\.fr\/auth\/callback/);
});

test("le changement d’adresse ne dépend d’aucun rôle dossier ou privilège service", () => {
  const source = readFileSync(new URL("./services.ts", import.meta.url), "utf8");
  assert.match(source, /requestOwnEmailChange\(input: EmailChangeInput, emailRedirectTo: string\)/);
  assert.match(source, /const \{ supabase, userId \} = await getAuthenticatedUser\(\)/);
  assert.doesNotMatch(source, /can_manage|protected_person|service.?role/i);
});

test("expose la route canonique et redirige l’ancienne route côté serveur", () => {
  const canonical = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  const legacy = readFileSync(new URL("../../app/mon-compte/page.tsx", import.meta.url), "utf8");
  assert.match(canonical, /getAccountData\(\)/);
  assert.match(canonical, /<PrivateShell current="account">/);
  assert.match(legacy, /import \{ redirect \} from "next\/navigation"/);
  assert.match(legacy, /redirect\("\/parametres\/compte"\)/);
});

test("pointe la navigation permanente vers la route canonique", () => {
  const source = readFileSync(new URL("../../components/layout/private-navigation.tsx", import.meta.url), "utf8");
  assert.match(source, /label: "Mon compte", href: "\/parametres\/compte"/);
  assert.doesNotMatch(source, /label: "Mon compte", href: "\/mon-compte"/);
});

test("protège la route canonique tout en la laissant accessible au platform admin", () => {
  const source = readFileSync(new URL("../../lib/supabase/proxy.ts", import.meta.url), "utf8");
  assert.match(source, /"\/parametres"/);
  assert.match(source, /pathname\.startsWith\("\/parametres\/categories"\)/);
  assert.doesNotMatch(source, /pathname\.startsWith\("\/parametres\/compte"\)/);
});
