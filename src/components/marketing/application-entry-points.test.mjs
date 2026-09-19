import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const dashboard = source("../../app/tableau-de-bord/page.tsx");
const dossierList = source("../../domains/protected-persons/components/protected-person-list.tsx");
const publicHeader = source("./public-header.tsx");

test("ouvrir un dossier depuis les listes mène à son tableau de bord", () => {
  assert.match(dashboard, /href=\{`\/dossiers\/\$\{dossier\.id\}\/tableau-de-bord`\}>Ouvrir le dossier/);
  assert.match(dossierList, /href=\{`\/dossiers\/\$\{person\.id\}\/tableau-de-bord`\}/);
  assert.doesNotMatch(dashboard, /dossier\.nextAction\?\.href/);
  assert.doesNotMatch(dossierList, /href=\{`\/dossiers\/\$\{person\.id\}\/comptes`\}/);
});

test("le header mobile privilégie la connexion sur la route existante", () => {
  assert.match(publicHeader, /button button-secondary whitespace-nowrap" href="\/connexion">Se connecter/);
  assert.doesNotMatch(publicHeader, /mobile-hide" href="\/connexion"/);
  assert.match(publicHeader, /button button-primary hidden whitespace-nowrap px-4 sm:inline-flex sm:px-5" href="\/inscription">Créer un compte/);
});

test("l'inscription reste disponible plus bas sur la page publique", () => {
  const publicPage = source("../../app/page.tsx");
  assert.match(publicPage, /href="\/inscription">Créer un compte<\/Link>/);
});
