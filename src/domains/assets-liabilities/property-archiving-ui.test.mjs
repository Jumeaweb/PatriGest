import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { propertyArchiveChangeSchema } from "./schemas.ts";

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("le motif d’archivage ou de restauration est obligatoire et borné", () => {
  assert.equal(propertyArchiveChangeSchema.safeParse({ reason: "" }).success, false);
  assert.equal(propertyArchiveChangeSchema.safeParse({ reason: "  " }).success, false);
  assert.equal(propertyArchiveChangeSchema.safeParse({ reason: "Correction du périmètre courant" }).success, true);
  assert.equal(propertyArchiveChangeSchema.safeParse({ reason: "x".repeat(2001) }).success, false);
});

test("l’action serveur valide les identifiants, la révision, le motif et appelle le service sécurisé", () => {
  const actions = source("./actions.ts");
  const action = actions.slice(actions.indexOf("export async function changePropertyArchiveStateAction"), actions.indexOf("export async function saveDebtAction"));
  assert.match(action, /ids\(personId,propertyId\)/);
  assert.match(action, /Number\.isSafeInteger\(expectedRevision\)/);
  assert.match(action, /propertyArchiveChangeSchema\.safeParse/);
  assert.match(action, /changePropertyArchiveState\(personId,propertyId,expectedRevision,p\.data,operation\)/);
  assert.match(action, /refresh\(personId,propertyId\)/);
  assert.doesNotMatch(action, /e\.message/);
});

test("le service utilise exclusivement les RPC d’archivage et de restauration avec la révision attendue", () => {
  const services = source("./services.ts");
  const lifecycle = services.slice(services.indexOf("export async function changePropertyArchiveState"), services.indexOf("export async function getDebts"));
  assert.match(lifecycle, /archive_real_estate_property/);
  assert.match(lifecycle, /restore_real_estate_property/);
  assert.match(lifecycle, /p_protected_person_id:personId/);
  assert.match(lifecycle, /p_property_id:propertyId/);
  assert.match(lifecycle, /p_expected_revision:expectedRevision/);
  assert.match(lifecycle, /p_reason:input\.reason/);
  assert.match(lifecycle, /error\.code === "40001"/);
  assert.match(lifecycle, /PropertyArchiveChangeError\("inconsistent"\)/);
});

test("les dialogues exigent une confirmation explicite et expliquent les effets non destructifs", () => {
  const component = source("./components/property-archive-actions.tsx");
  assert.match(component, /Archiver le bien/);
  assert.match(component, /Restaurer le bien/);
  assert.match(component, /Confirmer l’archivage/);
  assert.match(component, /Confirmer la restauration/);
  assert.match(component, /sans suppression de ses données/);
  assert.match(component, /name="reason"/);
  assert.match(component, /required/);
  assert.match(component, /archiveRevision/);
});

test("la liste courante reste filtrée et fournit un accès séparé aux archives", () => {
  const services = source("./services.ts");
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/page.tsx");
  assert.match(services, /getProperties[\s\S]*?\.is\("archived_at",null\)/);
  assert.match(services, /getArchivedProperties[\s\S]*?\.not\("archived_at","is",null\)/);
  assert.match(page, /Biens archivés/);
  assert.match(page, /patrimoine-immobilier\/archives/);
  assert.match(page, /getPropertyCompleteness\(items\)/);
});

test("la vue des archives distingue les biens actifs et cédés et ouvre leur fiche", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/archives/page.tsx");
  assert.match(page, /getArchivedProperties/);
  assert.match(page, /item\.status === "disposed"/);
  assert.match(page, /"Cédé" : "Actif"/);
  assert.match(page, /patrimoine-immobilier\/\$\{item\.id\}/);
  assert.match(page, /ne sont pas inclus dans le patrimoine courant/);
  assert.match(page, /md:grid-cols-2 xl:grid-cols-3/);
});

test("la fiche archivée affiche le bandeau et le journal tout en masquant les modifications", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/[propertyId]/page.tsx");
  assert.match(page, /Bien archivé — Ce bien n’apparaît plus dans le patrimoine courant/);
  assert.match(page, /currentArchive\?\.changed_by_name/);
  assert.match(page, /property\.archive_reason/);
  assert.match(page, /Historique des archivages/);
  assert.match(page, /property\.archiveChanges\.map/);
  assert.match(page, /!isArchived && <PropertyActions/);
  assert.equal((page.match(/!isArchived && person\.accessRole !== "read_only"/g) ?? []).length, 3);
});

test("les droits de l’interface permettent la consultation mais réservent les mutations", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/[propertyId]/page.tsx");
  assert.match(page, /person\.accessRole !== "read_only" && <div[\s\S]*?<PropertyArchiveAction/);
  assert.match(page, /property\.archiveChanges\.length > 0/);
  assert.doesNotMatch(source("../../app/dossiers/[protectedPersonId]/patrimoine-immobilier/archives/page.tsx"), /accessRole !== "read_only"/);
});
