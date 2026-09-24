import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { ACCOUNT_VIEW_ITEMS, getAccountView, getAccountViewHref } from "./account-navigation.ts";

test("présente les quatre vues Mon compte dans l’ordre validé", () => {
  assert.deepEqual(ACCOUNT_VIEW_ITEMS.map(({ label }) => label), [
    "Profil",
    "Adresse e-mail",
    "Sécurité",
    "Suppression du compte",
  ]);
});

test("utilise Profil par défaut et refuse les vues inconnues", () => {
  assert.equal(getAccountView(undefined), "profile");
  assert.equal(getAccountView("inconnue"), "profile");
  assert.equal(getAccountView(["email", "suppression"]), "email");
});

test("construit les destinations canoniques de chaque vue", () => {
  assert.equal(getAccountViewHref("profile"), "/parametres/compte");
  assert.equal(getAccountViewHref("email"), "/parametres/compte?vue=email");
  assert.equal(getAccountViewHref("security"), "/parametres/compte?vue=securite");
  assert.equal(getAccountViewHref("deletion"), "/parametres/compte?vue=suppression");
});

test("rend une seule vue contextuelle et la même navigation pour tous les comptes", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  assert.match(page, /const current = getAccountView\(query\.vue\)/);
  assert.match(page, /<AccountNavigation current=\{current\} \/>/);
  assert.match(page, /current === "profile"/);
  assert.match(page, /current === "email"/);
  assert.match(page, /current === "security"/);
  assert.match(page, /current === "deletion"/);
  assert.doesNotMatch(page, /isPlatformAdmin\s*\?\s*<AccountNavigation/);
});

test("intègre le statut au Profil sans conserver l’ancienne carte Compte", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  assert.match(page, /current === "profile"[\s\S]*Statut[\s\S]*Compte actif/);
  assert.doesNotMatch(page, /<AccountCard[^>]*title="Compte"/);
});

test("décrit fidèlement la suppression sans promettre l’effacement de l’historique", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  const form = readFileSync(new URL("./components/account-deletion-form.tsx", import.meta.url), "utf8");
  assert.match(page, /compte de connexion, votre profil et vos accès aux dossiers partagés seront supprimés/);
  assert.match(page, /détachées ou anonymisées/);
  assert.match(page, /historique métier sont conservés/);
  assert.match(page, /possédez un dossier/);
  assert.match(page, /administrateur PatriGest ne peut pas supprimer son propre compte/);
  assert.match(form, /Mot de passe actuel/);
  assert.match(form, /Je confirme vouloir supprimer définitivement mon compte PatriGest/);
  assert.match(form, /bg-\[#B91C1C\]/);
});

test("préserve les formulaires réels sans inventer de fonctions de sécurité", () => {
  const profile = readFileSync(new URL("./components/profile-form.tsx", import.meta.url), "utf8");
  const email = readFileSync(new URL("./components/email-form.tsx", import.meta.url), "utf8");
  const password = readFileSync(new URL("./components/password-form.tsx", import.meta.url), "utf8");
  assert.match(profile, /Enregistrer le profil/);
  assert.match(email, /Adresse e-mail actuelle/);
  assert.match(email, /Modifier mon adresse e-mail/);
  assert.match(password, /Modifier le mot de passe/);
  assert.doesNotMatch(`${profile}\n${email}\n${password}`, /MFA|double authentification|sessions actives/i);
});
