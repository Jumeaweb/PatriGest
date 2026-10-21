import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("la création d'un relevé accepte l'absence de PDF sans appeler Storage", () => {
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/route.ts");
  const writeService = source("./bank-statement-write.ts");
  assert.match(route, /readPdf\(form, false\)/);
  assert.match(route, /pdf: pdf\.file && pdf\.bytes \? \{ file: pdf\.file, bytes: pdf\.bytes \} : null/);
  assert.match(writeService, /if \(!input\.pdf\) \{[\s\S]*?original_file_name: null/);
  const noPdfBranch = writeService.slice(
    writeService.indexOf("if (!input.pdf)"),
    writeService.indexOf("await runBankStatementDocumentWrite"),
  );
  assert.doesNotMatch(noPdfBranch, /storage\.from|reserveBankStatementOperation/);
});

test("un relevé sans PDF n'expose pas d'action document ni d'appel Storage", () => {
  const component = source("./components/bank-statement-manager.tsx");
  const route = source("../../app/api/dossiers/[protectedPersonId]/comptes/[accountId]/releves/[statementId]/route.ts");
  const writeService = source("./bank-statement-write.ts");
  assert.match(component, /hasDocument\s*=\s*item\.original_file_name\s*!==\s*null/);
  assert.match(component, /Aucun PDF/);
  assert.match(route, /Aucun PDF n’est associé à ce relevé/);
  assert.match(route, /deleteBankStatement\(/);
  assert.match(writeService, /if \(!durableEnabled && documentMetadata\(input\.statement\)\)/);
});

test("le champ PDF est facultatif à la création comme à la modification", () => {
  const component = source("./components/bank-statement-manager.tsx");
  assert.match(component, /Fichier PDF \(facultatif\)/);
  assert.doesNotMatch(component, /required=\{!item\}/);
});
