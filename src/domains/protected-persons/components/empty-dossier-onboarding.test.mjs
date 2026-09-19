import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const dashboard = source("../../../app/tableau-de-bord/page.tsx");
const dossierPage = source("../../../app/dossiers/page.tsx");
const compatibilityPage = source("../../../app/dossiers/gestion/page.tsx");
const list = source("./protected-person-list.tsx");
const actions = source("../actions.ts");
const service = source("../services/protected-person-service.ts");
const context = source("../../administration/services/private-access-context.ts");

test("le tableau de bord sans dossier explique l'absence d'accès et garde la liste", () => {
  assert.match(dashboard, /dossiers\.length \? [\s\S]*?Aucun dossier accessible actuellement/);
  assert.match(dashboard, /href="\/dossiers">Voir tous les dossiers<\/Link>/);
  assert.doesNotMatch(dashboard, /Aucun dossier actif accessible/);
});

test("le CTA direct du tableau de bord crée le premier dossier uniquement si autorisé", () => {
  assert.match(dashboard, /\{canCreate && <Link className="button button-primary" href="\/dossiers\/nouveau">Créer mon premier dossier<\/Link>\}/);
  assert.match(dashboard, /<DossiersSection dossiers=\{data\.dossiers\} canCreate=\{!isPlatformAdmin\} \/>/);
  assert.match(dashboard, /if \(isPlatformAdmin\) return <PrivateShell current="dashboard"><AdministrationDashboard \/>/);
});

test("la liste formule l'état vide en termes d'accès et non de création", () => {
  assert.match(list, /persons\.length === 0 \? <section[\s\S]*?Aucun dossier accessible/);
  assert.doesNotMatch(list, /Aucun dossier n’a encore été créé/);
  assert.match(list, /\{canCreate \? "Créez votre premier dossier/);
});

test("la liste cache ses deux CTA de création sans droit, mais les conserve avec droit", () => {
  assert.match(list, /\{canCreate && <Link href="\/dossiers\/nouveau"[^>]*>[^<]*<Plus[^>]*\/>Nouveau dossier<\/Link>\}/);
  assert.match(list, /\{canCreate && <Link href="\/dossiers\/nouveau"[^>]*>[^<]*<Plus[^>]*\/>Créer mon premier dossier<\/Link>\}/);
});

test("les deux pages de liste réutilisent le contexte d'autorisation existant", () => {
  assert.match(context, /platform_administrators/);
  for (const page of [dossierPage, compatibilityPage]) {
    assert.match(page, /getPrivateAccessContext\(\)/);
    assert.match(page, /<ProtectedPersonList persons=\{persons\} canCreate=\{!isPlatformAdmin\} \/>/);
  }
  assert.match(service, /if \(administrator\) throw new Error\("Un administrateur de plateforme ne peut pas créer de dossier\."\)/);
});

test("les dossiers existants s'ouvrent sur leur tableau de bord", () => {
  assert.match(list, /persons\.map\(\(person\) => <Link key=\{person\.id\} href=\{`\/dossiers\/\$\{person\.id\}\/tableau-de-bord`\}/);
  assert.match(dashboard, /dossiers\.map\(\(dossier\) => <DossierCard key=\{dossier\.id\} dossier=\{dossier\} \/>/);
});

test("la création réussie ouvre toujours Informations du dossier", () => {
  const action = actions.match(/export async function createProtectedPersonAction[\s\S]*?(?=\nexport async function addProtectionMeasureAction)/)?.[0];
  assert.ok(action);
  assert.match(action, /person = await createProtectedPerson\(parsed\.data\)/);
  assert.match(action, /redirect\(`\/dossiers\/\$\{person\.id\}`\)/);
});
