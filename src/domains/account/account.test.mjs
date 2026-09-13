import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  loadAccountDataForUser,
  updateOwnPasswordWithAuth,
  updateOwnProfileRow,
} from "./account-operations.ts";
import { passwordSchema, profileSchema } from "./schemas.ts";

function accountClient({
  email = "personne@example.test",
  firstName = "Marie",
  lastName = "Durand",
  administrator = null,
  profileUpdateResult = { data: { id: randomUUID() }, error: null },
  passwordResult = { data: { user: {} }, error: null },
} = {}) {
  const calls = [];

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
          return { data: { user: { email } }, error: null };
        },
        async updateUser(attributes) {
          calls.push(["auth.updateUser", attributes]);
          return passwordResult;
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
    isPlatformAdmin: false,
  });
  assert.ok(calls.some((call) => call[0] === "auth.getUser"));
  assert.ok(calls.some((call) => call[0] === "eq" && call[1] === "profiles" && call[2] === "id" && call[3] === userId));
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
  }]);
});

test("conserve les erreurs Auth internes dans la couche serveur", () => {
  const source = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(source, /Impossible de modifier le mot de passe\. Reconnectez-vous puis réessayez\./);
  assert.match(source, /Votre session n’est plus valide\. Reconnectez-vous puis réessayez\./);
  assert.doesNotMatch(source, /message:\s*error\.message/);
});

test("affiche l’e-mail en lecture seule sans action de changement", () => {
  const source = readFileSync(new URL("./components/profile-form.tsx", import.meta.url), "utf8");
  assert.match(source, /id="accountEmail"[^>]*type="email"[^>]*value=\{email\}[^>]*readOnly/);
  assert.doesNotMatch(source, /name="accountEmail"|name="email"/);
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
