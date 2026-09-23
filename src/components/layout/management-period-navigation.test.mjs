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
const contextualNavigation = source("../../domains/management-reports/management-report-navigation.tsx");
const dossierDashboard = source("../../app/dossiers/[protectedPersonId]/tableau-de-bord/page.tsx");

test("Exercices de gestion disparaît des deux menus permanents", () => {
  assert.doesNotMatch(desktopMenu, /label: "Exercices de gestion"|href: `\/dossiers\/\$\{dossier\.id\}\/exercices`/);
  assert.doesNotMatch(mobileMenu, /label: "Exercices de gestion"|href: `\/dossiers\/\$\{protectedPersonId\}\/exercices`/);
  assert.match(desktopMenu, /label: "Gestion financière"/);
  assert.match(mobileMenu, /label: "Gestion financière"/);
});

test("Informations du dossier conserve son accès contextuel vers les exercices", () => {
  assert.match(dossierInfo, /<Link href=\{`\/dossiers\/\$\{protectedPersonId\}\/exercices`\}[^>]*>Voir les exercices →<\/Link>/);
});

test("les deux pages partagent les onglets comptes puis exercices avec un état actif accessible", () => {
  assert.ok(contextualNavigation.indexOf('label: "Comptes de gestion"') < contextualNavigation.indexOf('label: "Exercices de gestion"'));
  assert.match(contextualNavigation, /aria-current=\{active \? "page" : undefined\}/);
  assert.match(contextualNavigation, /overflow-x-auto/);
  assert.match(reportList, /<ManagementReportNavigation[\s\S]*?current="reports"/);
  assert.match(exercises, /<ManagementReportNavigation protectedPersonId=\{protectedPersonId\} current="periods"/);
});

test("le listing conserve l'aide et Légifrance sans bouton redondant", () => {
  assert.doesNotMatch(reportList, />\s*Gérer les exercices\s*<\/Link>/);
  assert.match(reportList, /Aucun exercice de gestion n&apos;est actuellement disponible/);
  assert.match(reportList, /Les dates du formulaire reprennent un exercice de gestion/);
  assert.match(reportList, /Consulter le modèle officiel sur Légifrance/);
  assert.doesNotMatch(exercises, /Légifrance/);
});

test("la route des exercices, le breadcrumb et les droits restent présents", () => {
  assert.match(exercises, /export default async function ManagementPeriodsPage/);
  assert.match(exercises, /label: "Exercices de gestion"/);
  assert.match(exercises, /person\.accessRole === "read_only" \? <div/);
  assert.match(exercises, /accessRole: person\.accessRole/);
  assert.match(exercises, /<ManagementPeriodManager protectedPersonId=\{protectedPersonId\}/);
  assert.match(reportList, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(reportList, /\{canManage && \(\s*<ManagementReportCreateForm/);
});

test("le tableau de bord du dossier ne duplique plus ses deux destinations de navigation", () => {
  assert.doesNotMatch(dossierDashboard, />Informations du dossier<\/Link>/);
  assert.doesNotMatch(dossierDashboard, />Comptes<\/Link>/);
  assert.match(dossierDashboard, /<DossierNavigation protectedPersonId=\{protectedPersonId\} current="dashboard"/);
});

test("la navigation du partage reste réservée au propriétaire et au gestionnaire", () => {
  assert.match(desktopMenu, /dossier\.accessRole === "owner" \|\| dossier\.accessRole === "manager"/);
  assert.match(mobileMenu, /accessRole === "owner" \|\| accessRole === "manager"/);
});
