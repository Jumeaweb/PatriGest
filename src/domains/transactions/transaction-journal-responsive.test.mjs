import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const journal = readFileSync(new URL("./components/transaction-journal.tsx", import.meta.url), "utf8");

test("conserve les cartes jusqu'au breakpoint lg puis affiche le tableau", () => {
  assert.match(journal, /hidden overflow-hidden[^\n]+lg:block/);
  assert.match(journal, /\} lg:hidden/);
  assert.doesNotMatch(journal, /hidden overflow-hidden[^\n]+md:block/);
  assert.doesNotMatch(journal, /\} md:hidden/);
});

test("affiche la classification mobile sur une ligne qui peut revenir à la ligne", () => {
  assert.match(journal, /<p className="mt-1\.5 break-words text-\[11px\] text-\[#64748B\]">\{classificationLabel\(item\)\}<\/p>/);
  assert.doesNotMatch(journal, /className="truncate text-\[11px\] text-\[#64748B\]">\{classificationLabel\(item\)\}/);
});

test("préserve montant, solde, pièces et comportements des deux journaux", () => {
  assert.match(journal, /\{formatCurrency\(item\.amount\)\}/);
  assert.match(journal, /Solde \{formatCurrency\(balance\)\}/);
  assert.match(journal, /<AttachmentIndicator count=\{item\.attachmentCount\}/);
  assert.match(journal, /ordered\.map\(\(item\) => <Row/);
  assert.match(journal, /ordered\.map\(\(item\) => <Card/);
  assert.match(journal, /withTransactionReturnTo\(baseHref, returnTo\)/);
});
