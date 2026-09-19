import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (relativePath) => readFileSync(new URL(relativePath, import.meta.url), "utf8");
const actions = read("./actions.ts");
const invitationPage = read("../../app/invitation/[token]/page.tsx");
const authActions = read("../../app/(auth)/actions.ts");
const authForms = read("../../components/auth/auth-forms.tsx");
const callback = read("../../app/auth/callback/route.ts");
const acceptanceMigration = read("../../../supabase/migrations/20260901100000_create_application_user_authorizations.sql");

test("le nouvel utilisateur revient à l'invitation après confirmation", () => {
  assert.match(authActions, /emailRedirectTo:[\s\S]*getDossierInvitationPath\(invitationToken\.data\)/);
  assert.match(callback, /nextPath\?\.startsWith\("\/invitation\/"\)/);
});

test("les parcours de connexion secondaires conservent l'invitation", () => {
  assert.match(invitationPage, /getDossierInvitationLoginPath\(token\)/);
  assert.match(authForms, /getDossierInvitationLoginPath\(invitationToken\)/);
  assert.match(authForms, /mot-de-passe-oublie\?next=/);
});

test("l'acceptation ouvre le tableau de bord du dossier partagé", () => {
  assert.match(actions, /redirect\(`\/dossiers\/\$\{data\}\/tableau-de-bord`\)/);
  assert.doesNotMatch(actions, /redirect\(`\/dossiers\/\$\{data\}\/comptes`\)/);
});

test("l'acceptation conserve les garanties de rôle, d'identité et d'état", () => {
  assert.match(acceptanceMigration, /values \(invitation\.protected_person_id, auth\.uid\(\), invitation\.role, invitation\.invited_by\)/);
  assert.match(acceptanceMigration, /invitation_normalized_email <> caller_email/);
  assert.match(acceptanceMigration, /accepted_at is null/);
  assert.match(acceptanceMigration, /revoked_at is null/);
  assert.match(acceptanceMigration, /expires_at > now\(\)/);
});

test("l'acceptation ajoute un accès sans modifier les dossiers déjà possédés", () => {
  assert.match(acceptanceMigration, /insert into public\.protected_person_access/);
  assert.doesNotMatch(acceptanceMigration, /update public\.protected_persons/);
});

test("le comportement de conflit d'un accès existant reste inchangé", () => {
  assert.match(acceptanceMigration, /on conflict \(protected_person_id, user_id\) do nothing/);
});
