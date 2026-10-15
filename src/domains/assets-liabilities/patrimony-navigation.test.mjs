import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { getScrollLeftToRevealItem } from "../../components/ui/horizontal-navigation-scroll-position.ts";
import { getPatrimonyNavigationItems } from "./patrimony-navigation-links.ts";

const personId = "11111111-1111-4111-8111-111111111111";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("la navigation patrimoniale utilise les quatre routes existantes dans l'ordre attendu", () => {
  assert.deepEqual(getPatrimonyNavigationItems(personId, "patrimony"), [
    { label: "Patrimoine", href: `/dossiers/${personId}?vue=patrimoine`, active: true },
    { label: "Comptes bancaires", href: `/dossiers/${personId}/comptes`, active: false },
    { label: "Patrimoine immobilier", href: `/dossiers/${personId}/patrimoine-immobilier`, active: false },
    { label: "Dettes et emprunts", href: `/dossiers/${personId}/dettes`, active: false },
  ]);
});

test("chaque rubrique possède un unique état actif", () => {
  for (const current of ["patrimony", "accounts", "properties", "debts"]) {
    const items = getPatrimonyNavigationItems(personId, current);
    assert.equal(items.filter(({ active }) => active).length, 1);
  }
  assert.throws(() => getPatrimonyNavigationItems("invalid", "patrimony"));
});

test("le composant partagé est accessible et défile horizontalement sur petit écran", () => {
  const component = source("./components/patrimony-navigation.tsx");
  const scrollContainer = source("../../components/ui/horizontal-navigation-scroll.tsx");
  assert.match(component, /aria-label="Navigation patrimoniale"/);
  assert.match(component, /aria-current=\{item\.active \? "page" : undefined\}/);
  assert.match(component, /<HorizontalNavigationScroll activeKey=\{current\}>/);
  assert.match(component, /flex min-w-max gap-1/);
  assert.match(component, /min-h-11 shrink-0 items-center whitespace-nowrap/);
  assert.match(component, /focus-ring/);
  assert.match(scrollContainer, /max-w-full overflow-x-auto overscroll-x-contain/);
  assert.match(scrollContainer, /\[-ms-overflow-style:none\]/);
  assert.match(scrollContainer, /\[scrollbar-width:none\]/);
  assert.match(scrollContainer, /\[&::-webkit-scrollbar\]:hidden/);
  assert.match(scrollContainer, /querySelector<HTMLElement>\('\[aria-current="page"\]'\)/);
  assert.match(scrollContainer, /maxScrollLeft: viewport\.scrollWidth - viewport\.clientWidth/);
  assert.match(scrollContainer, /requestAnimationFrame\(revealActiveItem\)/);
  assert.match(scrollContainer, /document\.fonts\?\.ready/);
  assert.match(scrollContainer, /observer\?\.observe\(rail\)/);
  assert.doesNotMatch(scrollContainer, /scrollIntoView/);
});

test("le défilement horizontal révèle l'onglet actif sans déplacement inutile", () => {
  assert.equal(getScrollLeftToRevealItem({ viewportLeft: 0, viewportRight: 375, itemLeft: 80, itemRight: 240, currentScrollLeft: 0 }), 0);
  for (const width of [320, 375, 390]) {
    assert.ok(getScrollLeftToRevealItem({ viewportLeft: 0, viewportRight: width, itemLeft: 470, itemRight: 620, currentScrollLeft: 0 }) > 0);
  }
  assert.equal(getScrollLeftToRevealItem({ viewportLeft: 20, viewportRight: 355, itemLeft: 453, itemRight: 606, currentScrollLeft: 0, maxScrollLeft: 251 }), 251);
  assert.equal(getScrollLeftToRevealItem({ viewportLeft: 0, viewportRight: 390, itemLeft: -40, itemRight: 110, currentScrollLeft: 300 }), 252);
  assert.equal(getScrollLeftToRevealItem({ viewportLeft: 0, viewportRight: 768, itemLeft: 470, itemRight: 620, currentScrollLeft: 0 }), 0);
});

test("la navigation mobile du dossier réutilise le même conteneur sans perdre son accessibilité", () => {
  const dossierNavigation = source("../protected-persons/components/dossier-navigation.tsx");
  assert.match(dossierNavigation, /<HorizontalNavigationScroll activeKey=\{current\} className="pb-0\.5">/);
  assert.match(dossierNavigation, /aria-current=\{active \? "page" : undefined\}/);
  assert.match(dossierNavigation, /focus-ring/);
  assert.match(dossierNavigation, /flex min-w-max gap-2/);
  assert.match(dossierNavigation, /border-x border-t border-brand-accent\/20/);
});

test("les quatre pages affichent une seule navigation avec la bonne rubrique active", () => {
  const base = "../../app/dossiers/[protectedPersonId]/";
  const pages = [
    ["page.tsx", "patrimony"],
    ["comptes/page.tsx", "accounts"],
    ["patrimoine-immobilier/page.tsx", "properties"],
    ["dettes/page.tsx", "debts"],
  ];

  for (const [path, current] of pages) {
    const page = source(base + path);
    const instances = page.match(/<PatrimonyNavigation protectedPersonId=\{protectedPersonId\} current="[^"]+" \/>/g) ?? [];
    assert.equal(instances.length, 1, path);
    assert.match(instances[0], new RegExp(`current="${current}"`));
  }
});

test("l'intégration conserve les navigations et fonctionnalités propres à chaque page", () => {
  const base = "../../app/dossiers/[protectedPersonId]/";
  const overview = source(base + "page.tsx");
  const accounts = source(base + "comptes/page.tsx");
  const properties = source(base + "patrimoine-immobilier/page.tsx");
  const debts = source(base + "dettes/page.tsx");

  assert.match(overview, /<DossierInformationNavigation/);
  assert.match(overview, /currentView === "assets" && <PatrimonyNavigation/);
  assert.match(accounts, /<FinancialNavigation protectedPersonId=\{protectedPersonId\} current="accounts" \/>/);
  assert.ok(accounts.indexOf("<PatrimonyNavigation") < accounts.indexOf("<FinancialNavigation"));
  assert.match(properties, /<PatrimonyAbsenceConfirmationControl/);
  assert.match(properties, /<PropertyManager/);
  assert.match(debts, /<PatrimonyAbsenceConfirmationControl/);
  assert.match(debts, /<DebtManager/);
});
