import assert from "node:assert/strict";
import test from "node:test";

import { shouldRecoverInvitedAuthAccount } from "./invited-signup-recovery.ts";

test("un nouveau compte invité conserve la confirmation d'inscription", () => {
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: true,
    signUpErrorCode: undefined,
    identityCount: 1,
  }), false);
});

test("un compte Auth existant explicite passe par la récupération", () => {
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: true,
    signUpErrorCode: "user_already_exists",
    identityCount: null,
  }), true);
});

test("un succès Supabase ambigu sans identité passe par la récupération", () => {
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: true,
    signUpErrorCode: undefined,
    identityCount: 0,
  }), true);
});

test("l'inscription ordinaire ne déclenche jamais la récupération implicite", () => {
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: false,
    signUpErrorCode: "user_already_exists",
    identityCount: null,
  }), false);
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: false,
    signUpErrorCode: undefined,
    identityCount: 0,
  }), false);
});

test("une autre erreur d'inscription reste une erreur", () => {
  assert.equal(shouldRecoverInvitedAuthAccount({
    isDossierInvitation: true,
    signUpErrorCode: "email_address_invalid",
    identityCount: null,
  }), false);
});
