import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const navigation = source("./private-navigation.tsx");
const dossierNavigation = source("../../domains/protected-persons/components/dossier-navigation.tsx");
const dossierList = source("../../app/dossiers/page.tsx");
const compatibilityList = source("../../app/dossiers/gestion/page.tsx");
const dashboard = source("../../app/tableau-de-bord/page.tsx");
const dossierActions = source("../../domains/protected-persons/actions.ts");
const categories = source("../../app/parametres/categories/page.tsx");
const sharing = source("../../app/dossiers/[protectedPersonId]/acces/page.tsx");
const sharingService = source("../../domains/access/services.ts");

test("Dossiers est l'unique entrée du menu utilisateur", () => {
  assert.match(navigation, /label: "Dossiers", href: "\/dossiers"/);
  assert.doesNotMatch(navigation, /label: "Gérer les dossiers"|href: "\/dossiers\/gestion"/);
});

test("/dossiers affiche la liste même pour un seul dossier actif", () => {
  assert.match(dossierList, /<ProtectedPersonList persons=\{persons\}/);
  assert.doesNotMatch(dossierList, /redirect\(/);
  assert.match(compatibilityList, /<ProtectedPersonList persons=\{persons\}/);
  assert.match(compatibilityList, /current="dossiers"/);
});

test("le tableau de bord mène à /dossiers et non à la route de compatibilité", () => {
  assert.match(dashboard, /<StatCard href="\/dossiers" title="Dossiers actifs"/);
  assert.match(dashboard, /href="\/dossiers">Voir tous les dossiers<\/Link>/);
  assert.doesNotMatch(dashboard, /\/dossiers\/gestion|>Gérer les dossiers<\/Link>/);
});

test("la suppression d'un dossier revient à la liste unique", () => {
  const action = dossierActions.match(/export async function deleteProtectedPersonAction[\s\S]*?\n}/)?.[0];
  assert.ok(action);
  assert.match(action, /revalidatePath\("\/dossiers"\)/);
  assert.match(action, /redirect\("\/dossiers"\)/);
  assert.doesNotMatch(action, /\/dossiers\/gestion/);
});

test("Catégories est directe sans groupe Paramètres", () => {
  assert.match(navigation, /label: "Catégories", href: "\/parametres\/categories"/);
  assert.doesNotMatch(navigation, /NavigationGroup label="Paramètres"/);
  assert.match(navigation, /label: "Mon compte"/);
  assert.match(navigation, /label: "Historique des versions"/);
  assert.match(navigation, /Déconnexion/);
  assert.doesNotMatch(categories, /label: "Paramètres"|>Paramètres<\/p>/);
});

test("Partage du dossier est le libellé visible sur les deux navigations et la page", () => {
  assert.match(navigation, /label: "Partage du dossier", href: `\/dossiers\/\$\{dossier\.id}\/?acces`/);
  assert.match(dossierNavigation, /label: "Partage du dossier"/);
  assert.match(sharing, /<h1>Partage du dossier<\/h1>/);
  assert.doesNotMatch(sharing, /<h1>Accès au dossier<\/h1>/);
});

test("owner et manager voient le partage, read_only est masqué et refusé", () => {
  assert.match(navigation, /dossier\.accessRole === "owner" \|\| dossier\.accessRole === "manager"/);
  assert.match(dossierNavigation, /accessRole === "owner" \|\| accessRole === "manager"/);
  assert.match(sharingService, /person\.accessRole === "read_only"\) notFound\(\)/);
});
