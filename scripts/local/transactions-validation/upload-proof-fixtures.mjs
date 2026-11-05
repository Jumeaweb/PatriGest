import { createClient } from "@supabase/supabase-js";
import { createTransactionFixturePdf, hasReadablePdfStructure } from "./fixture-pdf.mjs";

const url = process.env.PAT_LOCAL_SUPABASE_URL;
const anonKey = process.env.PAT_LOCAL_ANON_KEY;
const serviceRoleKey = process.env.PAT_LOCAL_SERVICE_ROLE_KEY;
if (url !== "http://127.0.0.1:54321" || !anonKey || !serviceRoleKey) {
  throw new Error("Chargement refusé : configuration Supabase locale invalide.");
}

const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });

async function createLocalSession(email) {
  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const tokenHash = link?.properties?.hashed_token;
  if (linkError || !tokenHash) {
    throw new Error(`Impossible de préparer la session locale ${email}.`);
  }

  const client = createClient(url, anonKey, { auth: { persistSession: false } });
  const { error: authenticationError } = await client.auth.verifyOtp({
    type: "magiclink",
    token_hash: tokenHash,
  });
  if (authenticationError) {
    throw new Error(`Impossible d'ouvrir la session locale ${email}.`);
  }
  return client;
}

const owner = await createLocalSession("transactions-validation-owner@example.test");
const accountId = "97000000-0000-4000-8300-000000000301";
const { data: transactions, error } = await owner
  .from("transactions")
  .select("id,transaction_date,transaction_type,amount")
  .eq("financial_account_id", accountId)
  .in("transaction_date", ["2026-10-02", "2026-10-05"]);
if (error) {
  throw new Error(`Lecture RLS des transactions fictives impossible (${error.code ?? "erreur inconnue"}).`);
}

const expectedTransactions = [
  { transaction_date: "2026-10-02", amount: 40 },
  { transaction_date: "2026-10-05", amount: 12 },
];
const resolvedTransactions = expectedTransactions.map((expected) => {
  const matches = (transactions ?? []).filter(
    (transaction) =>
      transaction.transaction_date === expected.transaction_date &&
      Number(transaction.amount) === expected.amount,
  );
  if (matches.length !== 1) {
    throw new Error(
      `Transaction fictive non résolue de manière unique (${expected.transaction_date}, ${expected.amount} EUR).`,
    );
  }
  return matches[0];
});

const pdf = await createTransactionFixturePdf();
const reader = await createLocalSession("transactions-validation-reader@example.test");
const missingTransactions = [];
const invalidTransactions = [];
for (const transaction of resolvedTransactions) {
  const path = `protected-persons/97000000-0000-4000-8100-000000000101/transactions/${transaction.id}/proof`;
  const existing = await reader.storage.from("transaction-proofs").download(path);
  if (existing.error || !existing.data) {
    missingTransactions.push(transaction);
  } else {
    const bytes = new Uint8Array(await existing.data.arrayBuffer());
    if (!hasReadablePdfStructure(bytes)) invalidTransactions.push(transaction);
  }
}

if (invalidTransactions.length) {
  const dates = invalidTransactions.map((transaction) => transaction.transaction_date).join(", ");
  throw new Error(
    `PDF fictifs invalides détectés (${dates}). Aucune écriture effectuée : une réparation locale autorisée est nécessaire.`,
  );
}

for (const transaction of missingTransactions) {
  const path = `protected-persons/97000000-0000-4000-8100-000000000101/transactions/${transaction.id}/proof`;
  const result = await owner.storage.from("transaction-proofs").upload(path, pdf, {
    contentType: "application/pdf",
    upsert: false,
  });
  if (result.error && !/already exists|duplicate/i.test(result.error.message)) {
    throw new Error(`Impossible de charger le justificatif fictif du ${transaction.transaction_date}.`);
  }
}

for (const transaction of resolvedTransactions) {
  const path = `protected-persons/97000000-0000-4000-8100-000000000101/transactions/${transaction.id}/proof`;
  const { data, error: downloadError } = await reader.storage.from("transaction-proofs").download(path);
  const downloadedBytes = data ? new Uint8Array(await data.arrayBuffer()) : null;
  if (downloadError || !downloadedBytes || !hasReadablePdfStructure(downloadedBytes)) {
    throw new Error(`Le justificatif fictif du ${transaction.transaction_date} n'est pas lisible avec les droits prévus.`);
  }
}

console.log("Deux justificatifs fictifs sont disponibles et lisibles dans Storage local.");
