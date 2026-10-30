import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (relativePath) => readFileSync(new URL(relativePath, import.meta.url), "utf8");
const page = source("./page.tsx");
const serverConfiguration = source("../../lib/legal-notice-config.ts");
const proxy = source("../../lib/supabase/proxy.ts");
const footer = source("../../components/marketing/public-footer.tsx");

test("la page reste publique, rendue côté serveur et possède ses métadonnées", () => {
  assert.doesNotMatch(page, /^\s*["']use client["']/m);
  assert.match(serverConfiguration, /import "server-only"/);
  assert.match(page, /title: "Mentions légales — PatriGest"/);
  assert.match(page, /description: "Informations légales relatives au site et au service PatriGest/);
  assert.doesNotMatch(proxy, /mentions-legales/);
});

test("la page n'affiche les données légales que depuis la configuration serveur", () => {
  for (const name of [
    "LEGAL_PUBLISHER_NAME",
    "LEGAL_PUBLISHER_ADDRESS",
    "LEGAL_PUBLISHER_SIREN",
    "LEGAL_PUBLICATION_DIRECTOR",
    "LEGAL_HOST_NAME",
    "LEGAL_HOST_ADDRESS",
    "LEGAL_HOST_PHONE",
  ]) {
    assert.match(serverConfiguration, new RegExp(`process\\.env\\.${name}`));
    assert.doesNotMatch(page, new RegExp(`process\\.env\\.${name}`));
  }
  assert.match(page, /Configuration juridique à finaliser/);
  assert.match(page, /Aucune coordonnée personnelle fictive ou incomplète n’est affichée/);
  assert.match(page, /target="_blank" rel="noopener noreferrer">Site de Jumeaweb/);
});

test("le pied de page expose les mentions légales sans altérer l'identification existante", () => {
  assert.match(footer, /href="\/mentions-legales">Mentions légales<\/Link>/);
  assert.match(footer, /© 2026 \{APP_NAME\}\. Tous droits réservés\. \{APP_NAME\} est édité par/);
  assert.match(footer, /target="_blank" rel="noopener noreferrer"/);
  assert.match(footer, /\{APP_NAME\} v\{APP_VERSION\}/);
});
