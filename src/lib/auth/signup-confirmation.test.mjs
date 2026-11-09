import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { parseSignupConfirmationParams } from "./signup-confirmation.ts";

const tokenHash = "a".repeat(64);

test("accepte les confirmations Supabase email et signup par token_hash", () => {
  assert.deepEqual(parseSignupConfirmationParams(new URLSearchParams({
    token_hash: tokenHash,
    type: "email",
  })), { tokenHash, type: "email" });

  assert.deepEqual(parseSignupConfirmationParams(new URLSearchParams({
    token_hash: tokenHash,
    type: "signup",
  })), { tokenHash, type: "signup" });
});

test("refuse les jetons incomplets et les autres flux Auth", () => {
  for (const params of [
    {},
    { token_hash: tokenHash },
    { token_hash: tokenHash, type: "recovery" },
    { token_hash: tokenHash, type: "email_change" },
    { token_hash: "court", type: "email" },
    { token_hash: `${tokenHash} espace`, type: "signup" },
  ]) {
    assert.equal(parseSignupConfirmationParams(new URLSearchParams(params)), null);
  }
});

test("le callback accepte token_hash sans supprimer le flux PKCE existant", () => {
  const callback = readFileSync(new URL("../../app/auth/callback/route.ts", import.meta.url), "utf8");

  assert.match(callback, /parseSignupConfirmationParams/);
  assert.match(callback, /verifyOtp\(\{[\s\S]*token_hash: confirmation!?\.tokenHash,[\s\S]*type: confirmation!?\.type/);
  assert.match(callback, /exchangeCodeForSession\(code\)/);
  assert.match(callback, /hasApplicationAccess \? "\/tableau-de-bord" : "\/acces-en-attente"/);
});
