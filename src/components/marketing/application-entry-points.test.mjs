import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const dashboard = source("../../app/tableau-de-bord/page.tsx");
const dossierList = source("../../domains/protected-persons/components/protected-person-list.tsx");
const publicHeader = source("./public-header.tsx");
const publicFooter = source("./public-footer.tsx");
const authShell = source("../auth/auth-shell.tsx");
const privateNavigation = source("../layout/private-navigation.tsx");
const releaseNotice = source("../releases/release-notice.tsx");
const globals = source("../../app/globals.css");
const appIdentity = source("../../lib/app.ts");

test("ouvrir un dossier depuis les listes mène à son tableau de bord", () => {
  assert.match(dashboard, /href=\{`\/dossiers\/\$\{dossier\.id\}\/tableau-de-bord`\}>Ouvrir le dossier/);
  assert.match(dossierList, /href=\{`\/dossiers\/\$\{person\.id\}\/tableau-de-bord`\}/);
  assert.doesNotMatch(dashboard, /dossier\.nextAction\?\.href/);
  assert.doesNotMatch(dossierList, /href=\{`\/dossiers\/\$\{person\.id\}\/comptes`\}/);
});

test("le header mobile privilégie la connexion sur la route existante", () => {
  assert.match(publicHeader, /href="\/" className="focus-ring flex shrink-0 items-center rounded-xl bg-white\/85 p-1/);
  assert.match(publicHeader, /src="\/logos\/patrigest-symbol\.png"[^\n]+className="h-11 w-auto shrink-0"/);
  assert.match(publicHeader, /button button-secondary min-h-9! whitespace-nowrap px-3! sm:min-h-10! sm:px-5!" href="\/connexion">Se connecter/);
  assert.doesNotMatch(publicHeader, /mobile-hide" href="\/connexion"/);
  assert.match(publicHeader, /<span className="hidden sm:inline-flex"><Link className="button button-primary whitespace-nowrap" href="\/inscription">Créer un compte/);
  assert.doesNotMatch(publicHeader, /button button-primary hidden/);
});

test("l'inscription reste disponible plus bas sur la page publique", () => {
  const publicPage = source("../../app/page.tsx");
  assert.match(publicPage, /href="\/inscription">Créer un compte<\/Link>/);
});

test("la nouvelle identité visuelle est partagée sans modifier les destinations", () => {
  assert.match(globals, /--brand-background: #f8f6e9/);
  assert.match(globals, /--brand-foreground: #214660/);
  assert.match(globals, /--brand-navigation: #86b5af/);
  assert.match(globals, /--brand-accent: #377e84/);
  assert.match(globals, /--brand-gold: #bc9955/);
  assert.match(privateNavigation, /bg-brand-navigation/);
  assert.match(privateNavigation, /src="\/logos\/patrigest-symbol\.png"/);
  assert.match(authShell, /src="\/logos\/patrigest-logo-full\.png"/);
  assert.ok(existsSync(new URL("../../../public/logos/source/patrigest-logo.png", import.meta.url)));
  assert.ok(existsSync(new URL("../../../public/logos/source/patrigest-logo-texte.png", import.meta.url)));
});

test("le pied de page public identifie Jumeaweb et expose les contacts validés", () => {
  const identityLine = publicFooter.match(/<p className="mt-4 border-t[^"]*">[\s\S]*?<\/p>/)?.[0] ?? "";
  assert.match(appIdentity, /APP_PUBLISHER_NAME = "Jumeaweb"/);
  assert.match(appIdentity, /APP_PUBLISHER_URL = "https:\/\/jumeaweb\.fr"/);
  assert.match(appIdentity, /APP_CONTACT_EMAIL = "contact@jumeaweb\.fr"/);
  assert.match(appIdentity, /APP_SUPPORT_EMAIL = "support@jumeaweb\.fr"/);
  assert.match(identityLine, /© 2026 \{APP_NAME\}\. Tous droits réservés\. \{APP_NAME\} est édité par /);
  assert.match(identityLine, /href=\{`\$\{APP_PUBLISHER_URL\}\/`\} target="_blank" rel="noopener noreferrer"[\s\S]*?\{APP_PUBLISHER_NAME\}<\/a>\. <Link href="\/historique-versions"[\s\S]*?\{APP_NAME\} v\{APP_VERSION\}<\/Link>/);
  assert.doesNotMatch(identityLine, /<span|\bflex\b|\bgrid\b|justify-|\bgap-/);
  assert.doesNotMatch(publicFooter, /<Image|patrigest-logo-full|APP_SLOGAN/);
  assert.match(publicFooter, /<nav className="flex flex-wrap items-center justify-center[^"]*lg:justify-between"/);
  assert.match(publicFooter, /href=\{`mailto:\$\{APP_CONTACT_EMAIL\}`\}>Contact<\/a>/);
  assert.match(publicFooter, /href=\{`mailto:\$\{APP_SUPPORT_EMAIL\}`\}>Assistance<\/a>/);
  assert.doesNotMatch(publicFooter, /LRTeam83|jumeaweb@gmail\.com|jerome\.lucet@ik\.me/);
});

test("la bannière de nouveautés conserve volontairement son identité bleue", () => {
  assert.match(releaseNotice, /border-blue-100 bg-blue-50/);
  assert.match(releaseNotice, /text-blue-950/);
  assert.match(releaseNotice, /text-\[#2563EB\]/);
});
