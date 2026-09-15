import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = source("../../../app/dossiers/page.tsx");
const actions = source("../actions.ts");
const dialog = source("./delete-protected-person.tsx");
const dossier = source("../../../app/dossiers/[protectedPersonId]/page.tsx");
const deletionAction = actions.match(/export async function deleteProtectedPersonAction[\s\S]*?\n}/)?.[0];

test("une suppression réussie seulement redirige vers la liste avec indicateur fixe", () => {
  assert.ok(deletionAction);
  assert.match(deletionAction, /try \{ await deleteProtectedPerson\(protectedPersonId\); \}/);
  assert.match(deletionAction, /revalidatePath\("\/dossiers"\);[\s\S]*?redirect\("\/dossiers\?deleted=1"\)/);
  assert.doesNotMatch(deletionAction, /\/dossiers\/gestion/);
});

test("l'échec retourne une erreur sûre sans redirection de succès", () => {
  assert.match(deletionAction, /catch \(error\) \{ return \{ status: "error", message:/);
  assert.ok(deletionAction.indexOf("catch (error)") < deletionAction.indexOf('redirect("/dossiers?deleted=1")'));
  assert.doesNotMatch(deletionAction, /error\.code|error\.details|error\.hint/);
});

test("le message apparaît seulement pour deleted égal à 1", () => {
  assert.match(page, /\(await searchParams\)\.deleted === "1"/);
  assert.match(page, /\{deletionConfirmed && <p role="status" aria-live="polite"/);
  assert.match(page, /Le dossier a bien été supprimé/);
  assert.doesNotMatch(page, /deleted \?\? "1"|deleted !== "0"/);
});

test("le mécanisme ne met aucune donnée personnelle dans le retour", () => {
  assert.equal(deletionAction.match(/redirect\("([^"\n]+)"\)/)?.[1], "/dossiers?deleted=1");
  assert.doesNotMatch(deletionAction, /redirect\(`|personName|first_name|last_name/);
});

test("confirmation préalable, permission owner et service de suppression sont préservés", () => {
  assert.match(dialog, /<AppConfirmDialog open=\{open\} title="Supprimer ce dossier \?"/);
  assert.match(dialog, /<FormMessage state=\{state\}/);
  assert.match(dossier, /person\.accessRole === "owner" && <section/);
  assert.match(source("../services/protected-person-service.ts"), /supabase\.rpc\("delete_empty_protected_person"/);
});
