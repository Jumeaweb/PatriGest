import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("la création d'un relevé accepte l'absence de PDF sans appeler Storage", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/route.ts");
  assert.match(route, /readPdf\(form,false\)/);
  assert.match(route, /original_file_name:pdf\.file\?\.name\?\?null/);
  assert.match(route, /if\(pdf\.file&&pdf\.bytes\)\{const upload=/);
});

test("un relevé sans PDF n'expose pas d'action document ni d'appel Storage", () => {
  const component = source("./components/bank-statement-manager.tsx");
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/route.ts");
  assert.match(component, /hasDocument=.*original_file_name!==null/);
  assert.match(component, /Aucun PDF/);
  assert.match(route, /Aucun PDF n’est associé à ce relevé/);
  assert.match(route, /if\(value\.statement\.original_file_name\)\{const downloaded=/);
});

test("le champ PDF est facultatif à la création comme à la modification", () => {
  const component = source("./components/bank-statement-manager.tsx");
  assert.match(component, /Fichier PDF \(facultatif\)/);
  assert.doesNotMatch(component, /required=\{!item\}/);
});
