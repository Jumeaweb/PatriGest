import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = source("../../app/tarifs/page.tsx");
const selector = source("./pricing-selector.tsx");
const pricing = source("../../lib/pricing.ts");
const header = source("./public-header.tsx");
const footer = source("./public-footer.tsx");
const privateNavigation = source("../layout/private-navigation.tsx");

test("la page Tarifs réutilise l’enveloppe publique et expose les sections attendues", () => {
  assert.match(page, /<PublicHeader \/>/);
  assert.match(page, /<PublicFooter \/>/);
  for (const text of [
    "Des tarifs simples et accessibles",
    "Prix par utilisateur",
    "Commencez avec Essentiel",
    "Une résiliation claire et prévisible",
    "Questions fréquentes",
  ]) assert.match(page + selector, new RegExp(text));
  assert.doesNotMatch(page, /Capacité du compte|Ajoutez les dossiers dont vous avez besoin|DOSSIER_CAPACITIES/);
  assert.doesNotMatch(page + selector, /S’abonner|S'abonner|Stripe|paiement/);
});

test("les six prix et les économies annuelles proviennent de la configuration unique", () => {
  for (const [name, monthly, annual, savings] of [
    ["Essentiel", 3, 30, 6],
    ["Confort", 5, 50, 10],
    ["Premium", 6, 60, 12],
  ]) {
    const planPattern = new RegExp(`name: "${name}"[\\s\\S]*?monthlyPrice: ${monthly},[\\s\\S]*?annualPrice: ${annual},[\\s\\S]*?annualSavings: ${savings},[\\s\\S]*?discountPercent: 17`);
    assert.match(pricing, planPattern);
  }
  assert.match(selector, /useState<BillingCycle>\("monthly"\)/);
  assert.match(selector, /aria-pressed=\{active\}/);
  assert.match(selector, /cycle === "monthly" \? plan\.monthlyPrice : plan\.annualPrice/);
});

test("Essentiel reste disponible tandis que Confort et Premium sont grisés", () => {
  assert.match(pricing, /id: "essential"[\s\S]*?subscriptionAvailability: "available"/);
  assert.match(pricing, /id: "comfort"[\s\S]*?subscriptionAvailability: "planned"/);
  assert.match(pricing, /id: "premium"[\s\S]*?subscriptionAvailability: "planned"/);
  assert.match(selector, />Indisponible<\/p>/);
  assert.match(selector, /Cette formule sera proposée ultérieurement/);
});

test("les fonctionnalités futures sont distinctes des fonctions disponibles", () => {
  assert.match(pricing, /Importation et préparation automatisée[\s\S]*?availability: "upcoming"/);
  assert.match(pricing, /Gestion documentaire et classement[\s\S]*?availability: "upcoming"/);
  assert.match(selector, />À venir<\/span>/);
  assert.match(page, /La souscription en ligne n’est pas encore disponible/);
});

test("la navigation publique expose Tarifs sur ordinateur et mobile sans toucher au privé", () => {
  assert.equal((header.match(/href="\/tarifs">Tarifs<\/Link>/g) ?? []).length, 2);
  assert.match(header, /lg:hidden" href="\/tarifs">Tarifs/);
  assert.match(footer, /href="\/tarifs">Tarifs<\/Link>/);
  assert.doesNotMatch(privateNavigation, /href: "\/tarifs"|label: "Tarifs"/);
});

test("la résiliation reste informative, prudente et prévoit la récupération des données", () => {
  assert.match(page, /renouvellement s’arrête après la période déjà payée/);
  assert.match(page, /sans remboursement ordinaire[\s\S]*?droits légaux applicables/);
  assert.match(page, /décès de la dernière personne protégée ou de fin de la dernière mesure/);
  assert.match(page, /remboursement au prorata de la période non utilisée/);
  assert.match(page, /récupérer les données et documents/);
  assert.match(page, /futures conditions générales de vente/);
});
