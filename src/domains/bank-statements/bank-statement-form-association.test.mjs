import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const requireModule = createRequire(import.meta.url);

function loadComponent(path, imports = {}) {
  const filename = new URL(path, import.meta.url);
  const { outputText } = ts.transpileModule(readFileSync(filename, "utf8"), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX },
    fileName: filename.pathname,
  });
  const loaded = { exports: {} };
  const resolveImport = (name) => Object.hasOwn(imports, name) ? imports[name] : requireModule(name);
  new Function("require", "module", "exports", outputText)(resolveImport, loaded, loaded.exports);
  return loaded.exports;
}

test("chaque formulaire de relevé possède son propre bouton et son champ PDF", () => {
  const dialog = loadComponent("../../components/ui/app-confirm-dialog.tsx");
  const { BankStatementManager } = loadComponent("./components/bank-statement-manager.tsx", {
    "next/navigation": { useRouter: () => ({ refresh() {} }) },
    "@/components/ui/app-confirm-dialog": dialog,
  });
  const items = [
    { id: "releve-a", statement_end_date: "2025-01-31", note: "Relevé A" },
    { id: "releve-b", statement_end_date: "2025-02-28", note: "Relevé B" },
  ].map((item) => ({
    ...item, statement_start_date: null, statement_balance: null,
    original_file_name: null, mime_type: null, file_size: null,
  }));
  const html = renderToStaticMarkup(createElement(BankStatementManager, {
    personId: "dossier-fictif", accountId: "compte-fictif", items, totalCount: items.length,
    reconciliations: [], canManage: true, durableOperationsEnabled: true,
  }));
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map(([, id]) => id);
  assert.equal(ids.length, new Set(ids).size, "les deux présentations coexistent dans le DOM");
  const forms = [...html.matchAll(/<dialog\b[^>]*>[\s\S]*?<\/dialog>/g)]
    .filter(([markup]) => /<form\b/.test(markup));
  assert.equal(forms.length, 5, "deux formulaires par relevé et le formulaire d’ajout");
  for (const [markup] of forms) {
    const formId = markup.match(/<form\b[^>]*\sid="([^"]+)"/)?.[1];
    const targetId = markup.match(/<button\b[^>]*type="submit"[^>]*\sform="([^"]+)"/)?.[1];
    assert.ok(formId);
    assert.equal(targetId, formId);
    assert.match(markup, /<label[^>]*><span[^>]*>Fichier PDF \(facultatif\)<\/span><input(?=[^>]*name="file")(?=[^>]*type="file")[^>]*>/);
  }
});
