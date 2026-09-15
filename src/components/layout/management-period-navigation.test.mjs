import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

const desktopMenu = source("./private-navigation.tsx");
const mobileMenu = source("../../domains/protected-persons/components/dossier-navigation.tsx");
const dossierInfo = source("../../app/dossiers/[protectedPersonId]/page.tsx");
const reportList = source("../../app/dossiers/[protectedPersonId]/comptes-de-gestion/page.tsx");
const exercises = source("../../app/dossiers/[protectedPersonId]/exercices/page.tsx");

test("Exercices de gestion disparaît des deux menus permanents", () => {
  assert.doesNotMatch(desktopMenu, /label: "Exercices de gestion"|href: `\/dossiers\/\$\{dossier\.id\}\/exercices`/);
  assert.doesNotMatch(mobileMenu, /label: "Exercices de gestion"|href: `\/dossiers\/\$\{protectedPersonId\}\/exercices`/);
  assert.match(desktopMenu, /label: "Gestion financière"/);
  assert.match(mobileMenu, /label: "Gestion financière"/);
});

test("Informations du dossier conserve le lien existant vers les exercices", () => {
  assert.match(dossierInfo, /<Link href=\{`\/dossiers\/\$\{protectedPersonId\}\/exercices`\}[^>]*>Gérer les exercices<\/Link>/);
});

test("le listing des comptes de gestion donne un accès explicite à la même route", () => {
  assert.match(reportList, /<Link href=\{`\/dossiers\/\$\{protectedPersonId\}\/exercices`\}[^>]*>\s*Gérer les exercices\s*<\/Link>/);
  assert.match(reportList, /Vérifiez les exercices du dossier avant de préparer un compte de gestion/);
});

test("la route des exercices, le breadcrumb et les droits restent présents", () => {
  assert.match(exercises, /export default async function ManagementPeriodsPage/);
  assert.match(exercises, /label: "Exercices de gestion"/);
  assert.match(exercises, /person\.accessRole === "read_only" \? <div/);
  assert.match(exercises, /<ManagementPeriodManager protectedPersonId=\{protectedPersonId\}/);
  assert.match(reportList, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(reportList, /\{canManage && \(\s*<ManagementReportCreateForm/);
});

test("la navigation du partage reste réservée au propriétaire et au gestionnaire", () => {
  assert.match(desktopMenu, /dossier\.accessRole === "owner" \|\| dossier\.accessRole === "manager"/);
  assert.match(mobileMenu, /accessRole === "owner" \|\| accessRole === "manager"/);
});
