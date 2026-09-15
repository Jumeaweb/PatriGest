import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { getSafeTransactionReturnTo } from "./return-to.ts";

const personId = "11111111-1111-4111-8111-111111111111";
const accountId = "22222222-2222-4222-8222-222222222222";
const globalJournal = `/dossiers/${personId}/operations`;
const accountJournal = `/dossiers/${personId}/comptes/${accountId}/operations`;

function source(relativePath) {
  return readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("un virement lancé depuis le journal global revient au journal global", () => {
  assert.equal(getSafeTransactionReturnTo(personId, globalJournal), globalJournal);
  const form = source("./components/transaction-form.tsx");
  assert.match(form, /const returnHref = returnTo \?\? \(defaultAccountId \? `\/dossiers\/\$\{personId\}\/comptes\/\$\{defaultAccountId\}\/operations` : `\/dossiers\/\$\{personId\}\/operations`\)/);
  assert.match(form, /createTransferAction\.bind\(null, personId, returnHref\)/);
});

test("un virement lancé depuis un compte revient au journal de ce compte", () => {
  assert.equal(getSafeTransactionReturnTo(personId, accountJournal), accountJournal);
  const page = source("../../app/dossiers/[protectedPersonId]/operations/nouvelle/page.tsx");
  assert.match(page, /defaultAccountId=\{requestedAccountId\}/);
  assert.match(page, /accounts\.some\(\(account\) => account\.id === search\.account\)/);
});

test("un returnHref externe ou invalide retombe sur la destination interne sûre", () => {
  for (const invalid of ["https://example.com/evil", "//example.com/evil", "/dossiers/other/operations", `/dossiers/${personId}/comptes/not-an-uuid/operations`, `/dossiers/${personId}/operations?returnTo=https://example.com`]) {
    assert.equal(getSafeTransactionReturnTo(personId, invalid), globalJournal);
  }
});

test("un retour contextualisé garde ses filtres autorisés, sans admettre une destination extérieure", () => {
  assert.equal(getSafeTransactionReturnTo(personId, `${accountJournal}?start=2026-01-01&q=test`), `${accountJournal}?start=2026-01-01&q=test`);
  assert.equal(getSafeTransactionReturnTo(personId, "https://example.com/evil", accountId), accountJournal);
});

test("l'action réutilise le validateur après création, sans modifier le chemin de création", () => {
  const actions = source("./actions.ts");
  const action = actions.match(/export async function createTransferAction[\s\S]*?(?=\nexport async function deleteTransactionAction)/)?.[0];
  assert.ok(action);
  assert.match(action, /transferSchema\.safeParse\(transferValues\(formData\)\)/);
  assert.match(action, /await createTransfer\(personId, parsed\.data\)/);
  assert.match(action, /refresh\(personId\);\s*redirect\(getSafeTransactionReturnTo\(personId, returnHref\)\)/);
  assert.doesNotMatch(action, /redirect\(`\/dossiers\/\$\{personId\}\/operations`\)/);
});

test("les redirections d'UPDATE et de DELETE gardent le validateur existant", () => {
  const actions = source("./actions.ts");
  assert.match(actions, /redirect\(getSafeTransactionReturnTo\(personId, returnTo\)\)/);
  assert.equal((actions.match(/redirect\(getSafeTransactionReturnTo\(personId, returnHref\)\)/g) ?? []).length, 3);
});
