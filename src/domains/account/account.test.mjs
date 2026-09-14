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
import {
  AccountDeletionAdminError,
  AccountDeletionBlockedError,
  AccountDeletionReauthenticationError,
  AccountDeletionStorageError,
  deleteAccountWithVerifiedDependencies,
  getAccountDeletionEligibility,
  neutralizeCurrentUserStorageOwnership,
} from "./account-deletion-operations.ts";
import { accountDeletionSchema, emailChangeSchema, emailChangeSchemaForCurrentEmail, passwordSchema, profileSchema } from "./schemas.ts";

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

function deletionHarness({
  userId = randomUUID(),
  ownsDossier = false,
  isPlatformAdmin = false,
  passwordValid = true,
  adminDeleteError = null,
  unexpectedDeletedUser = false,
  recheckOwnsDossier = false,
  recreateFailure = false,
} = {}) {
  const calls = [];
  const bucket = "transaction-proofs";
  const path = `protected-persons/${randomUUID()}/transactions/${randomUUID()}/proof`;
  const fixtureBytes = new TextEncoder().encode("SEC02 fixture");
  const customMetadata = { purpose: "sec02", retained: true };
  const objects = new Map();
  objects.set(`${bucket}/${path}`, {
    bytes: fixtureBytes,
    ownerId: userId,
    contentType: "application/pdf",
    cacheControl: "86400",
    metadata: customMetadata,
    id: randomUUID(),
  });
  let originalRemovalObserved = false;
  let shouldFailRecreation = recreateFailure;
  let eligibilityChecks = 0;

  const session = {
    auth: {
      async getUser() {
        calls.push(["auth.getUser"]);
        return { data: { user: { id: userId, email: "sec02@example.test" } }, error: null };
      },
      async signInWithPassword(credentials) {
        calls.push(["auth.signInWithPassword", credentials]);
        return passwordValid
          ? { data: { user: { id: userId } }, error: null }
          : { data: { user: null }, error: { message: "raw invalid credentials" } };
      },
      async signOut(options) {
        calls.push(["auth.signOut", options]);
        return { error: null };
      },
    },
    from(table) {
      return {
        select() { return this; },
        eq() { return this; },
        limit() { return this; },
        async maybeSingle() {
          if (table === "protected_persons") {
            eligibilityChecks += 1;
            return { data: (ownsDossier || (recheckOwnsDossier && eligibilityChecks > 1)) ? { id: randomUUID() } : null, error: null };
          }
          return { data: isPlatformAdmin ? { user_id: userId } : null, error: null };
        },
      };
    },
    async rpc(name) {
      calls.push(["rpc", name]);
      const data = [...objects.entries()].flatMap(([key, object]) => {
        if (object.ownerId !== userId) return [];
        const separator = key.indexOf("/");
        return [{
          bucket_id: key.slice(0, separator),
          name: key.slice(separator + 1),
          metadata: { size: object.bytes.byteLength, mimetype: object.contentType, cacheControl: `max-age=${object.cacheControl}` },
          user_metadata: object.metadata,
        }];
      });
      return { data, error: null };
    },
  };

  const admin = {
    auth: {
      admin: {
        async deleteUser(id) {
          calls.push(["admin.deleteUser", id]);
          return adminDeleteError
            ? { data: { user: null }, error: adminDeleteError }
            : { data: { user: { id: unexpectedDeletedUser ? randomUUID() : id } }, error: null };
        },
      },
    },
    storage: {
      from(bucketId) {
        return {
          async download(name) {
            calls.push(["storage.download", bucketId, name]);
            const object = objects.get(`${bucketId}/${name}`);
            return object ? { data: new Blob([object.bytes]), error: null } : { data: null, error: { message: "missing" } };
          },
          async info(name) {
            calls.push(["storage.info", bucketId, name]);
            const object = objects.get(`${bucketId}/${name}`);
            return object ? { data: { id: object.id, name, bucketId, size: object.bytes.byteLength, contentType: object.contentType, cacheControl: `max-age=${object.cacheControl}`, metadata: object.metadata }, error: null } : { data: null, error: { message: "missing" } };
          },
          async upload(name, bytes, options) {
            calls.push(["storage.upload", bucketId, name, options]);
            const key = `${bucketId}/${name}`;
            if (objects.has(key) && !options.upsert) return { data: null, error: { message: "exists" } };
            if (name === path && originalRemovalObserved && shouldFailRecreation) {
              shouldFailRecreation = false;
              return { data: null, error: { message: "forced failure" } };
            }
            objects.set(key, { bytes: new Uint8Array(bytes), ownerId: null, contentType: options.contentType, cacheControl: options.cacheControl, metadata: options.metadata, id: randomUUID() });
            return { data: { path }, error: null };
          },
          async remove(names) {
            calls.push(["storage.remove", bucketId, names]);
            for (const name of names) {
              if (name === path) originalRemovalObserved = true;
              objects.delete(`${bucketId}/${name}`);
            }
            return { data: names.map((name) => ({ name })), error: null };
          },
          async exists(name) {
            calls.push(["storage.exists", bucketId, name]);
            return { data: objects.has(`${bucketId}/${name}`), error: null };
          },
        };
      },
    },
  };

  return { admin, bucket, calls, customMetadata, fixtureBytes, objects, path, session, userId };
}

test("valide le formulaire destructif sans accepter aucun identifiant utilisateur", () => {
  assert.equal(accountDeletionSchema.safeParse({ currentPassword: "", confirmation: "on" }).success, false);
  assert.equal(accountDeletionSchema.safeParse({ currentPassword: "secret", confirmation: null }).success, false);
  assert.deepEqual(accountDeletionSchema.parse({ currentPassword: "secret", confirmation: "on", userId: randomUUID() }), { currentPassword: "secret", confirmation: "on" });
});

test("détermine l’éligibilité depuis le propriétaire et le rôle plateforme réels", async () => {
  assert.equal(await getAccountDeletionEligibility(deletionHarness().session, randomUUID()), "eligible");
  assert.equal(await getAccountDeletionEligibility(deletionHarness({ ownsDossier: true }).session, randomUUID()), "blocked_owned_dossiers");
  assert.equal(await getAccountDeletionEligibility(deletionHarness({ isPlatformAdmin: true }).session, randomUUID()), "blocked_platform_admin");
});

test("les seuls accès manager ou read_only ne bloquent pas la suppression", async () => {
  const { session, userId } = deletionHarness();
  assert.equal(await getAccountDeletionEligibility(session, userId), "eligible");
  const source = readFileSync(new URL("./account-deletion-operations.ts", import.meta.url), "utf8");
  assert.match(source, /from\("protected_persons"\).*eq\("owner_id", userId\)/s);
  assert.doesNotMatch(source, /protected_person_access/);
});

test("neutralise un objet Storage sans changer chemin, octets ni métadonnées utiles", async () => {
  const harness = deletionHarness();
  const before = harness.objects.get(`${harness.bucket}/${harness.path}`);
  assert.equal(await neutralizeCurrentUserStorageOwnership(harness.session, harness.admin), 1);
  const after = harness.objects.get(`${harness.bucket}/${harness.path}`);
  assert.ok(after);
  assert.equal(after.ownerId, null);
  assert.deepEqual(after.bytes, before.bytes);
  assert.equal(after.contentType, before.contentType);
  assert.equal(after.cacheControl, before.cacheControl);
  assert.deepEqual(after.metadata, harness.customMetadata);
  assert.equal([...harness.objects.keys()].some((key) => key.includes(".sec02-backup-")), false);
  const backupUpload = harness.calls.findIndex((call) => call[0] === "storage.upload" && call[2].includes(".sec02-backup-"));
  const originalRemoval = harness.calls.findIndex((call) => call[0] === "storage.remove" && call[2].includes(harness.path));
  assert.ok(backupUpload >= 0 && originalRemoval > backupUpload);
});

test("une seconde neutralisation Storage est un no-op idempotent", async () => {
  const harness = deletionHarness();
  await neutralizeCurrentUserStorageOwnership(harness.session, harness.admin);
  const callsBefore = harness.calls.length;
  assert.equal(await neutralizeCurrentUserStorageOwnership(harness.session, harness.admin), 0);
  assert.equal(harness.calls.slice(callsBefore).some((call) => call[0].startsWith("storage.")), false);
});

test("restaure le chemin original et arrête la suppression après un échec de recréation", async () => {
  const harness = deletionHarness({ recreateFailure: true });
  await assert.rejects(neutralizeCurrentUserStorageOwnership(harness.session, harness.admin), AccountDeletionStorageError);
  const restored = harness.objects.get(`${harness.bucket}/${harness.path}`);
  assert.ok(restored);
  assert.equal(restored.ownerId, null);
  assert.deepEqual(restored.bytes, harness.fixtureBytes);
  assert.equal([...harness.objects.keys()].some((key) => key.includes(".sec02-backup-")), false);
});

test("supprime uniquement l’utilisateur issu de la session après tous les rechecks", async () => {
  const harness = deletionHarness();
  await deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "secret", confirmation: "on" });
  assert.deepEqual(harness.calls.find((call) => call[0] === "admin.deleteUser"), ["admin.deleteUser", harness.userId]);
  assert.deepEqual(harness.calls.at(-1), ["auth.signOut", { scope: "local" }]);
  const adminIndex = harness.calls.findIndex((call) => call[0] === "admin.deleteUser");
  assert.ok(harness.calls.slice(0, adminIndex).filter((call) => call[0] === "rpc").length >= 3);
});

test("un propriétaire ou platform admin est bloqué avant Storage et Admin", async () => {
  for (const options of [{ ownsDossier: true }, { isPlatformAdmin: true }]) {
    const harness = deletionHarness(options);
    await assert.rejects(deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "secret", confirmation: "on" }), AccountDeletionBlockedError);
    assert.equal(harness.calls.some((call) => call[0] === "rpc" || call[0] === "admin.deleteUser"), false);
  }
});

test("une réauthentification échouée arrête Storage et Admin sans exposer l’erreur brute", async () => {
  const harness = deletionHarness({ passwordValid: false });
  await assert.rejects(deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "incorrect", confirmation: "on" }), AccountDeletionReauthenticationError);
  assert.equal(harness.calls.some((call) => call[0] === "rpc" || call[0] === "admin.deleteUser"), false);
});

test("une nouvelle propriété de dossier au recheck arrête la suppression Auth", async () => {
  const harness = deletionHarness({ recheckOwnsDossier: true });
  await assert.rejects(deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "secret", confirmation: "on" }), AccountDeletionBlockedError);
  assert.equal(harness.calls.some((call) => call[0] === "admin.deleteUser"), false);
});

test("un échec Storage arrête toujours la suppression Auth", async () => {
  const harness = deletionHarness({ recreateFailure: true });
  await assert.rejects(deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "secret", confirmation: "on" }), AccountDeletionStorageError);
  assert.equal(harness.calls.some((call) => call[0] === "admin.deleteUser"), false);
});

test("une erreur ou une réponse Admin inattendue n’est jamais un succès", async () => {
  for (const options of [{ adminDeleteError: { message: "raw FK error" } }, { unexpectedDeletedUser: true }]) {
    const harness = deletionHarness(options);
    await assert.rejects(deleteAccountWithVerifiedDependencies(harness.session, harness.admin, harness.userId, { currentPassword: "secret", confirmation: "on" }), AccountDeletionAdminError);
    assert.equal(harness.calls.some((call) => call[0] === "auth.signOut"), false);
  }
});

test("confine la service-role au serveur et ne reçoit aucun userId du formulaire", () => {
  const services = readFileSync(new URL("./services.ts", import.meta.url), "utf8");
  const actions = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  const admin = readFileSync(new URL("../../lib/supabase/admin.ts", import.meta.url), "utf8");
  assert.match(services, /import "server-only"/);
  assert.match(services, /createAdminClient\(\)/);
  assert.match(services, /const \{ supabase, userId \} = await getAuthenticatedUser\(\)/);
  assert.match(admin, /process\.env\.SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(admin, /NEXT_PUBLIC_.*SERVICE/);
  assert.doesNotMatch(actions, /formData\.get\("(?:userId|profileId|authUserId)"\)/);
  assert.doesNotMatch(actions, /error\.message/);
});

test("affiche une zone dangereuse explicite sans identifiant utilisateur", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  const form = readFileSync(new URL("./components/account-deletion-form.tsx", import.meta.url), "utf8");
  assert.match(page, /Zone dangereuse/);
  assert.match(page, /irréversible/);
  assert.match(form, /Mot de passe actuel/);
  assert.match(form, /Supprimer mon compte/);
  assert.match(form, /confirmation/);
  assert.doesNotMatch(form, /name="(?:userId|profileId|authUserId)"/);
});

test("redirige publiquement après suppression et masque toutes les erreurs internes", () => {
  const source = readFileSync(new URL("./actions.ts", import.meta.url), "utf8");
  assert.match(source, /await deleteOwnAccount\(parsed\.data\)/);
  assert.match(source, /redirect\("\/"\)/);
  assert.match(source, /Impossible de supprimer votre compte\. Réessayez ultérieurement\./);
  assert.doesNotMatch(source, /message:\s*error\.message/);
});

test("préserve l’historique métier par la seule suppression Auth préparée par SEC-02B1", () => {
  const migration = readFileSync(new URL("../../../supabase/migrations/20260914100000_prepare_safe_user_account_deletion.sql", import.meta.url), "utf8");
  const operations = readFileSync(new URL("./account-deletion-operations.ts", import.meta.url), "utf8");
  assert.match(migration, /transactions_category_id_fkey[\s\S]*on delete set null/i);
  assert.match(migration, /on delete set null/g);
  assert.doesNotMatch(operations, /from\("(?:transactions|management_reports|management_report_documents|bank_statements|transaction_documents)"\)/);
  assert.doesNotMatch(operations, /storage\.objects/);
  assert.match(operations, /admin\.auth\.admin\.deleteUser\(userId\)/);
});
