import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  isProtectedApplicationRoute,
  requiresApplicationAccess,
} from "./proxy-route-policy.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("l'historique est public sans session et conserve la présentation privée avec une session", () => {
  assert.equal(isProtectedApplicationRoute("/historique-versions"), false);
  assert.equal(requiresApplicationAccess("/historique-versions", false), false);
  assert.equal(requiresApplicationAccess("/historique-versions", true), true);

  const page = source("../../app/historique-versions/page.tsx");
  assert.match(page, /if \(authenticated\)[\s\S]*?<PrivateShell current="history"/);
  assert.match(page, /<PublicHeader \/>[\s\S]*?<PublicFooter \/>/);
  assert.doesNotMatch(page, /\.from\(|createAdminClient/);
});

test("les autres espaces privés restent protégés avec ou sans session", () => {
  for (const pathname of [
    "/tableau-de-bord",
    "/dossiers/dossier-test",
    "/administration/utilisateurs",
    "/parametres/compte",
    "/mon-compte",
    "/invitations",
    "/api/dossiers/dossier-test",
  ]) {
    assert.equal(isProtectedApplicationRoute(pathname), true, pathname);
    assert.equal(requiresApplicationAccess(pathname, false), true, pathname);
    assert.equal(requiresApplicationAccess(pathname, true), true, pathname);
  }
});

test("les autres pages publiques ne deviennent pas des espaces protégés", () => {
  for (const pathname of ["/", "/tarifs", "/mentions-legales", "/connexion"] ) {
    assert.equal(isProtectedApplicationRoute(pathname), false, pathname);
    assert.equal(requiresApplicationAccess(pathname, false), false, pathname);
  }
});

