import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { getSafeInternalPath } from "./callback-destination.ts";

const actions = readFileSync(new URL("../../app/(auth)/actions.ts", import.meta.url), "utf8");
const forms = readFileSync(new URL("../../components/auth/auth-forms.tsx", import.meta.url), "utf8");
const dialog = readFileSync(new URL("../../components/ui/app-confirm-dialog.tsx", import.meta.url), "utf8");

test("la modification réussie attend la fermeture explicite du dialogue", () => {
  assert.match(forms, /<AppConfirmDialog/);
  assert.match(forms, /open=\{succeeded\}/);
  assert.match(forms, /description="Votre mot de passe a été modifié\."/);
  assert.match(forms, /cancelLabel="Fermer"/);
  assert.match(forms, /actions=\{null\}/);
  assert.match(forms, /requireExplicitClose/);
  assert.doesNotMatch(forms, /setTimeout/);
  assert.doesNotMatch(forms, /useEffect/);
  assert.doesNotMatch(forms, /Redirection en cours/);
});

test("seul le bouton Fermer peut déclencher la destination sûre", () => {
  assert.match(forms, /if \(state\.redirectTo\) router\.replace\(state\.redirectTo\)/);
  assert.match(forms, /onClose=\{closeSuccessDialog\}/);
  assert.equal(forms.match(/router\.replace/g)?.length, 1);
  assert.match(dialog, /onCancel=\{\(event\) => \{ event\.preventDefault\(\); if \(!requireExplicitClose\) onClose\(\); \}\}/);
  assert.match(dialog, /onClose=\{requireExplicitClose \? undefined : onClose\}/);
  assert.match(dialog, /\{!requireExplicitClose && <button[^>]+aria-label="Fermer la boîte de dialogue"/);
  assert.match(dialog, /<button ref=\{cancelButtonRef\}[^>]+onClick=\{onClose\}>\{cancelLabel\}<\/button>/);
  assert.match(actions, /getSafeNextPath\([^;]+, "\/tableau-de-bord"\)/);
  assert.equal(getSafeInternalPath("/dossiers/dossier-test"), "/dossiers/dossier-test");
  assert.equal(getSafeInternalPath("https://evil.example"), null);
  assert.equal(getSafeInternalPath("//evil.example"), null);
});

test("une erreur ou une validation échouée ne déclenche pas le dialogue de succès", () => {
  assert.match(forms, /state\.status === "success" && Boolean\(state\.redirectTo\)/);
  assert.match(actions, /if \(!parsed\.success\) return validationError\(parsed\.error\)/);
  assert.match(actions, /if \(error\) \{[\s\S]*status: "error"/);
  assert.match(actions, /auth\.updateUser\(\{ password: parsed\.data\.password \}\)/);
});
