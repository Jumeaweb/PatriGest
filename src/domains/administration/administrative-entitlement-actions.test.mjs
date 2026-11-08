import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const actions = read("./administrative-entitlement-actions.ts");
const editor = read("./components/administration-user-entitlement-editor.tsx");

test("les six mutations utilisent exclusivement les RPC auditées avec la session administrateur", () => {
  assert.match(actions, /requirePlatformAdministrator\(\)/);
  assert.doesNotMatch(actions, /createAdminClient|from\("account_administrative_/);
  for (const rpc of [
    "assign_administrative_plan", "replace_administrative_plan", "revoke_administrative_plan",
    "assign_administrative_entitlement_override", "replace_administrative_entitlement_override", "revoke_administrative_entitlement_override",
  ]) assert.match(actions, new RegExp(`rpc\\(\"${rpc}\"`));
});

test("l'action valide le motif, la révision, l'idempotence et interdit l'auto-modification", () => {
  assert.match(actions, /reason: z\.string\(\)\.trim\(\)\.min\(1/);
  assert.match(actions, /expectedRevision: z\.coerce\.number\(\)\.int\(\)\.nonnegative\(\)/);
  assert.match(actions, /requestId: z\.uuid\(\)/);
  assert.match(actions, /input\.ownerId === userId/);
  assert.match(actions, /revalidatePath\("\/administration\/utilisateurs"\)/);
});

test("l'éditeur conserve la requête lors d'un rejeu et la renouvelle si l'intention change", () => {
  assert.match(editor, /setRequestId\(\(current\) => current \?\? crypto\.randomUUID\(\)\)/);
  assert.match(editor, /function intentChanged\(\)[\s\S]*?setRequestId\(null\)/);
  assert.match(editor, /Vérifiez les valeurs avant de confirmer/);
  assert.match(editor, /<Comparison before=\{before\} after=\{after\}/);
  assert.match(editor, /router\.refresh\(\)/);
});
