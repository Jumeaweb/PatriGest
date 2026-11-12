import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { sortFinancialAccountsByName } from "./utils/financial-account-sort.ts";

const account = (id, accountName) => ({ id, account_name: accountName });

test("trie les noms selon l'ordre alphabétique français sans tenir compte de la casse", () => {
  const result = sortFinancialAccountsByName([
    account("z", "Zéphyr"),
    account("b", "banque courante"),
    account("a", "Assurance-vie"),
    account("l", "livret A"),
  ]);
  assert.deepEqual(result.map(({ id }) => id), ["a", "b", "l", "z"]);
});

test("ignore les accents et conserve l'ordre initial des noms équivalents", () => {
  const accounts = [
    account("accent", "Épargne"),
    account("lower", "epargne"),
    account("upper", "EPARGNE"),
    account("after", "Livret"),
  ];
  const result = sortFinancialAccountsByName(accounts);
  assert.deepEqual(result.map(({ id }) => id), ["accent", "lower", "upper", "after"]);
  assert.deepEqual(accounts.map(({ id }) => id), ["accent", "lower", "upper", "after"]);
});

test("la page trie séparément les comptes actifs et clôturés avant le rendu des cartes", () => {
  const page = readFileSync(
    new URL("../../app/dossiers/[protectedPersonId]/comptes/page.tsx", import.meta.url),
    "utf8",
  );
  assert.match(page, /const active = sortFinancialAccountsByName\(accounts\.filter\(\(account\) => account\.status === "active"\)\)/);
  assert.match(page, /const closed = sortFinancialAccountsByName\(accounts\.filter\(\(account\) => account\.status === "closed"\)\)/);
  assert.match(page, /<AccountSection title="Comptes actifs" accounts=\{active\}/);
  assert.match(page, /<AccountSection title="Comptes clôturés" accounts=\{closed\}/);
});

test("la carte Comptes du patrimoine trie les comptes actifs avec le même utilitaire", () => {
  const page = readFileSync(
    new URL("../../app/dossiers/[protectedPersonId]/page.tsx", import.meta.url),
    "utf8",
  );

  assert.match(page, /import \{ sortFinancialAccountsByName \} from "@\/domains\/financial-accounts\/utils\/financial-account-sort"/);
  assert.match(page, /const activeAccounts = sortFinancialAccountsByName\(accounts\.filter\(\(account\) => account\.status === "active"\)\)/);
  assert.match(page, /activeAccounts\.map\(\(account\) =>/);
  assert.match(page, /const currentPatrimony = getCurrentPatrimonyValue\(accounts\)/);
});
