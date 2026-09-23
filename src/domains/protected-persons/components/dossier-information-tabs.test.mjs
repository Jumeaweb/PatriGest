import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = source("../../../app/dossiers/[protectedPersonId]/page.tsx");
const navigation = source("./dossier-information-navigation.tsx");
const service = source("../services/protected-person-service.ts");
const deletion = source("./delete-protected-person.tsx");

test("les quatre vues contextuelles utilisent la route Informations du dossier", () => {
  assert.match(navigation, /label: "Personne protégée", href: baseHref/);
  assert.match(navigation, /label: "Situation patrimoniale", href: `\$\{baseHref\}\?vue=patrimoine`/);
  assert.match(navigation, /label: "Gestion", href: `\$\{baseHref\}\?vue=gestion`/);
  assert.match(navigation, /label: "Suppression du dossier", href: `\$\{baseHref\}\?vue=suppression`/);
  assert.match(navigation, /aria-label="Informations du dossier"/);
  assert.match(page, /<DossierInformationNavigation protectedPersonId=\{protectedPersonId\} current=\{currentView\} canDelete=\{canDelete\} \/>/);
});

test("le breadcrumb reste hiérarchique et le bouton Tableau de bord disparaît", () => {
  assert.match(page, /label: "Dossiers", href: "\/dossiers"/);
  assert.match(page, /href: `\/dossiers\/\$\{protectedPersonId\}\/tableau-de-bord`/);
  assert.match(page, /label: "Informations du dossier"/);
  assert.doesNotMatch(page, /LayoutDashboard|>Tableau de bord<\/Link>/);
});

test("Personne protégée conserve les trois cartes et les modifications autorisées", () => {
  assert.match(page, /currentView === "person"/);
  for (const title of ["Identité", "Domicile et résidence", "Mesure de protection"]) {
    assert.match(page, new RegExp(`title="${title}"`));
  }
  assert.match(page, /const canManage = person\.accessRole !== "read_only"/);
  assert.match(page, /action=\{canManage \? <EditProtectedPersonButton/);
  assert.match(page, /action=\{canManage \? <EditProtectionMeasureButton/);
});

test("Situation patrimoniale synthétise les comptes sans requête par compte", () => {
  for (const title of ["Patrimoine actuel", "Comptes", "Patrimoine immobilier", "Dettes et emprunts"]) {
    assert.match(page, new RegExp(`title="${title}"`));
  }
  assert.match(page, /activeAccounts\.length[\s\S]*closedAccountCount/);
  assert.match(page, /activeAccounts\.map\(\(account\)/);
  assert.match(page, /getCurrentAccountValue\(account, account\.valuations, account\.transactions\)/);
  assert.match(page, />Voir les comptes →<\/Link>/);
  assert.match(page, /getDossierPropertyState\(properties\)/);
  assert.match(page, /getDossierDebtState\(debts\)/);
});

test("Gestion charge en parallèle le rapport lié et reste une synthèse", () => {
  assert.match(service, /supabase\.from\("management_reports"\)\.select\("\*"\)\.eq\("protected_person_id", id\)/);
  assert.match(service, /Promise\.all\(\[/);
  assert.match(page, /report\.management_period_id === openPeriod\.id/);
  assert.match(page, /title="Exercice de gestion"/);
  assert.match(page, /title="Compte de gestion"/);
  assert.match(page, /reportStatusLabels\[currentReport\.status\]/);
});

test("la suppression est isolée, destructive et strictement réservée au propriétaire", () => {
  assert.match(page, /const canDelete = person\.accessRole === "owner"/);
  assert.match(navigation, /\.\.\.\(canDelete \? \[/);
  assert.match(page, /requestedView === "suppression" && canDelete/);
  assert.match(page, /currentView === "deletion" && canDelete && <section/);
  assert.match(page, /Suppression définitive du dossier/);
  assert.match(page, /Cette action est irréversible et réservée au propriétaire/);
  assert.match(deletion, /className="button button-danger"/);
  assert.match(deletion, /<AppConfirmDialog/);
});
