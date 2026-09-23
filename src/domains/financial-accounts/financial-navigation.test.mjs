import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { getFinancialAccountEntryHref } from "./financial-account-entry.ts";
import { getFinancialNavigationItems } from "./financial-navigation-links.ts";

const personId = "11111111-1111-4111-8111-111111111111";
const accountId = "22222222-2222-4222-8222-222222222222";
const anotherAccountId = "33333333-3333-4333-8333-333333333333";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("les vues globales proposent uniquement Comptes et Opérations avec leurs routes existantes", () => {
  assert.deepEqual(getFinancialNavigationItems(personId, "accounts"), [
    { label: "Comptes", href: `/dossiers/${personId}/comptes`, active: true },
    { label: "Opérations", href: `/dossiers/${personId}/operations`, active: false },
  ]);
  assert.deepEqual(getFinancialNavigationItems(personId, "operations").map(({ active }) => active), [false, true]);
});

test("Relevés n'apparaît jamais sans compte", () => {
  for (const current of ["accounts", "operations"]) {
    assert.ok(getFinancialNavigationItems(personId, current).every(({ label }) => label !== "Relevés"));
  }
});

test("les quatre destinations contextualisées suivent l'ordre UX prévu", () => {
  assert.deepEqual(getFinancialNavigationItems(personId, "details", accountId), [
    { label: "Opérations du compte", href: `/dossiers/${personId}/comptes/${accountId}/operations`, active: false },
    { label: "Relevés", href: `/dossiers/${personId}/comptes/${accountId}/releves`, active: false },
    { label: "Rapprochements", href: `/dossiers/${personId}/comptes/${accountId}/rapprochements`, active: false },
    { label: "Informations du compte", href: `/dossiers/${personId}/comptes/${accountId}`, active: true },
  ]);
});

test("l'état actif suit chaque vue du compte", () => {
  assert.deepEqual(getFinancialNavigationItems(personId, "operations", accountId).map(({ active }) => active), [true, false, false, false]);
  assert.deepEqual(getFinancialNavigationItems(personId, "statements", accountId).map(({ active }) => active), [false, true, false, false]);
  assert.deepEqual(getFinancialNavigationItems(personId, "reconciliations", accountId).map(({ active }) => active), [false, false, true, false]);
  assert.deepEqual(getFinancialNavigationItems(personId, "details", accountId).map(({ active }) => active), [false, false, false, true]);
});

test("changer de compte modifie chaque lien contextualisé, sans retour implicite au global", () => {
  const first = getFinancialNavigationItems(personId, "operations", accountId);
  const second = getFinancialNavigationItems(personId, "operations", anotherAccountId);
  assert.ok(first.every(({ href }) => href.includes(accountId)));
  assert.ok(second.every(({ href }) => href.includes(anotherAccountId)));
  assert.ok(second.every(({ href }) => !href.includes(accountId)));
});

test("les contextes incomplets ou UUID invalides échouent au lieu de basculer en vue globale", () => {
  assert.throws(() => getFinancialNavigationItems(personId, "statements"));
  assert.throws(() => getFinancialNavigationItems(personId, "reconciliations"));
  assert.throws(() => getFinancialNavigationItems(personId, "details"));
  assert.throws(() => getFinancialNavigationItems(personId, "operations", "invalid"));
  assert.throws(() => getFinancialNavigationItems("invalid", "accounts"));
  assert.throws(() => getFinancialNavigationItems(personId, "accounts", accountId));
});

test("les comptes transactionnels ouvrent le journal et les comptes valorisés leur fiche", () => {
  assert.equal(getFinancialAccountEntryHref(personId, accountId, false), `/dossiers/${personId}/comptes/${accountId}/operations`);
  assert.equal(getFinancialAccountEntryHref(personId, accountId, true), `/dossiers/${personId}/comptes/${accountId}`);
  assert.throws(() => getFinancialAccountEntryHref(personId, "invalid", false));
});

test("la navigation réutilisable marque le lien actif de façon accessible", () => {
  const component = source("./components/financial-navigation.tsx");
  assert.match(component, /getFinancialNavigationItems\(protectedPersonId, current, accountId\)/);
  assert.match(component, /aria-current=\{item\.active \? "page" : undefined\}/);
  assert.match(component, /border-brand-accent bg-brand-navigation text-brand-foreground/);
  assert.match(component, /bg-transparent text-brand-foreground\/75 hover:bg-brand-navigation\/25/);
  assert.doesNotMatch(component, /border-\[#2563EB\] bg-blue-50 text-\[#2563EB\]/);
});

test("les menus dossier affichent Gestion financière sur la route Comptes", () => {
  const desktop = source("../../components/layout/private-navigation.tsx");
  const mobile = source("../protected-persons/components/dossier-navigation.tsx");
  assert.match(desktop, /label: "Gestion financière", href: `\/dossiers\/\$\{dossier\.id\}\/comptes`/);
  assert.match(mobile, /label: "Gestion financière", href: `\/dossiers\/\$\{protectedPersonId\}\/comptes`/);
  assert.match(mobile, /bg-brand-navigation text-brand-foreground ring-1 ring-brand-accent\/40/);
  assert.doesNotMatch(desktop, /label: "Comptes et patrimoine"|label: "Opérations", href: `\/dossiers/);
  assert.doesNotMatch(mobile, /label: "Comptes et patrimoine"|label: "Opérations", href: `\/dossiers/);
  assert.doesNotMatch(desktop, /label: "Exercices de gestion"/);
  assert.doesNotMatch(mobile, /label: "Exercices de gestion"/);
});

test("les pages globales et de compte insèrent la navigation au bon contexte", () => {
  const base = "../../app/dossiers/[protectedPersonId]/";
  for (const path of ["comptes/page.tsx", "comptes/nouveau/page.tsx", "operations/page.tsx"]) {
    const page = source(base + path);
    assert.match(page, /<FinancialNavigation protectedPersonId=\{protectedPersonId\} current="(?:accounts|operations)" \/>/);
  }
  for (const path of ["comptes/[accountId]/page.tsx", "comptes/[accountId]/modifier/page.tsx", "comptes/[accountId]/operations/page.tsx", "comptes/[accountId]/releves/page.tsx", "comptes/[accountId]/rapprochements/page.tsx"]) {
    const page = source(base + path);
    assert.match(page, /<FinancialNavigation[\s\S]*?protectedPersonId=\{protectedPersonId\}[\s\S]*?accountId=\{accountId\}[\s\S]*?current="(?:details|operations|statements|reconciliations)"[\s\S]*?\/>/);
  }
  assert.match(source(base + "operations/nouvelle/page.tsx"), /accountId=\{requestedAccountId\} current="operations"/);
});
