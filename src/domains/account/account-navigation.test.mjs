import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { ACCOUNT_VIEW_ITEMS, getAccountSection, getAccountView, getAccountViewHref } from "./account-navigation.ts";

test("présente les cinq onglets Mon compte dans l’ordre validé", () => {
  assert.deepEqual(ACCOUNT_VIEW_ITEMS.map(({ label }) => label), [
    "Profil",
    "Abonnement",
    "Factures",
    "Résiliation",
    "Mes données",
  ]);
});

test("utilise Profil par défaut et refuse les vues inconnues", () => {
  assert.equal(getAccountView(undefined), "profile");
  assert.equal(getAccountView("inconnue"), "profile");
  assert.equal(getAccountView(["email", "suppression"]), "email");
  assert.equal(getAccountView("abonnement"), "subscription");
  assert.equal(getAccountView("factures"), "invoices");
  assert.equal(getAccountView("resiliation"), "cancellation");
  assert.equal(getAccountView("donnees"), "data");
  for (const view of ["profile", "email", "security", "deletion"]) assert.equal(getAccountSection(view), "profile");
  assert.equal(getAccountSection("subscription"), "subscription");
});

test("construit les destinations canoniques de chaque vue", () => {
  assert.equal(getAccountViewHref("profile"), "/parametres/compte");
  assert.equal(getAccountViewHref("email"), "/parametres/compte?vue=email");
  assert.equal(getAccountViewHref("security"), "/parametres/compte?vue=securite");
  assert.equal(getAccountViewHref("deletion"), "/parametres/compte?vue=suppression");
  assert.equal(getAccountViewHref("subscription"), "/parametres/compte?vue=abonnement");
  assert.equal(getAccountViewHref("invoices"), "/parametres/compte?vue=factures");
  assert.equal(getAccountViewHref("cancellation"), "/parametres/compte?vue=resiliation");
  assert.equal(getAccountViewHref("data"), "/parametres/compte?vue=donnees");
});

test("rend une seule vue contextuelle et la même navigation pour tous les comptes", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  assert.match(page, /const current = getAccountView\(query\.vue\)/);
  assert.match(page, /<AccountNavigation current=\{current\} \/>/);
  assert.match(page, /current === "profile"/);
  assert.match(page, /current === "email"/);
  assert.match(page, /current === "security"/);
  assert.match(page, /current === "deletion"/);
  assert.match(page, /current === "subscription"/);
  assert.match(page, /current === "invoices"/);
  assert.match(page, /current === "cancellation"/);
  assert.match(page, /current === "data"/);
  assert.doesNotMatch(page, /isPlatformAdmin\s*\?\s*<AccountNavigation/);
});

test("conserve les réglages existants dans Profil et une navigation horizontale accessible", () => {
  const page = readFileSync(new URL("../../app/parametres/compte/page.tsx", import.meta.url), "utf8");
  const navigation = readFileSync(new URL("./components/account-navigation.tsx", import.meta.url), "utf8");
  const navigationConfig = readFileSync(new URL("./account-navigation.ts", import.meta.url), "utf8");
  assert.match(page, /currentProfileView && <AccountProfileNavigation current=\{currentProfileView\}/);
  for (const label of ["Informations personnelles", "Adresse e-mail", "Sécurité", "Suppression du compte"]) assert.match(navigationConfig, new RegExp(label));
  assert.match(navigation, /HorizontalNavigationScroll activeKey=\{currentSection\}/);
  assert.match(navigation, /HorizontalNavigationScroll activeKey=\{current\}/);
  assert.match(navigation, /aria-current=\{active \? "page" : undefined\}/);
  assert.match(navigation, /min-h-11[^"]*shrink-0[^"]*whitespace-nowrap/);
});

test("les futurs services restent informatifs et réutilisent la tarification centrale", () => {
  const views = readFileSync(new URL("./components/account-service-views.tsx", import.meta.url), "utf8");
  assert.match(views, /import \{ DOSSIER_CAPACITIES, PRICING_PLANS \} from "@\/lib\/pricing"/);
  assert.match(views, /Les abonnements PatriGest ne sont pas encore disponibles/);
  assert.match(views, /aucun forfait attribué/);
  assert.match(views, /href="\/tarifs"/);
  assert.match(views, /Aucune facture n’est disponible/);
  assert.match(views, /Aucune action de résiliation n’est nécessaire ou possible actuellement/);
  assert.match(views, /Export ZIP à venir/);
  assert.match(views, /inclus sans supplément dans tous les forfaits/);
  assert.match(views, /PAT-EXPORT-01/);
  assert.doesNotMatch(views, /Télécharger|Résilier maintenant|S’abonner|date de renouvellement :|Visa|Mastercard/i);
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
