import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { transactionMutationReasonSchema } from "./schemas/transaction-schema.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("le journal distingue les annulations sur ordinateur et mobile", () => {
  const journal = source("./components/transaction-journal.tsx");
  assert.match(journal, /function CancelledBadge/);
  assert.match(journal, />Annulée</);
  assert.match(journal, /line-through/);
  assert.match(journal, /opacity-80/);
  assert.match(journal, /const actionLabel = canEdit \? "Corriger" : "Historique"/);
  assert.match(journal, /aria-label=\{structural \? undefined : `\$\{actionLabel\} l’opération/);
});

test("correction et annulation exigent un motif humain", () => {
  assert.equal(transactionMutationReasonSchema.safeParse("   ").success, false);
  assert.equal(transactionMutationReasonSchema.safeParse("ok").success, false);
  assert.equal(transactionMutationReasonSchema.safeParse("Erreur de saisie").success, true);
  const form = source("./components/transaction-form.tsx");
  const deletion = source("./components/transaction-delete-button.tsx");
  assert.match(form, /Motif de la correction/);
  assert.match(form, /name="reason" required minLength=\{3\}/);
  assert.match(deletion, /Motif de l’annulation/);
  assert.match(deletion, /L’opération restera visible dans le journal et son historique/);
  assert.doesNotMatch(deletion, />Supprimer l’opération</);
});

test("les conversions sont explicites dans les deux sens", () => {
  const form = source("./components/transaction-form.tsx");
  assert.match(form, /conversion de cette/);
  assert.match(form, /dépense en recette/);
  assert.match(form, /recette en dépense/);
  assert.match(form, /window\.confirm/);
  assert.match(form, /value=\{mode\}/);
});

test("la fiche verrouille les annulations, archives, exercices clos et lecteurs", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/operations/[transactionId]/modifier/page.tsx");
  assert.match(page, /readOnly \|\| closedPeriod \|\| archived \|\| cancelled/);
  assert.match(page, /Opération annulée/);
  assert.match(page, /TransactionChangeHistory/);
  assert.match(page, /TransactionProofHistory/);
});

test("la fiche virement verrouille archives, clôtures, annulations et lecture seule", () => {
  const page = source("../../app/dossiers/[protectedPersonId]/operations/[transactionId]/page.tsx");
  assert.match(page, /person\.accessRole !== "read_only" && !archived && !closed && !cancelled/);
  assert.match(page, /transactionRevision=\{transfer\.revision\}/);
  assert.match(page, /Dossier archivé — consultation uniquement/);
  assert.match(page, /Exercice clôturé — consultation uniquement/);
  assert.match(page, /Accès en lecture seule/);
});

test("l’historique expose création, corrections, conversions, annulation et valeurs", () => {
  const component = source("./components/transaction-change-history.tsx");
  const service = source("./services/transaction-change-service.ts");
  assert.match(service, /from\("transaction_changes"\)/);
  assert.match(service, /order\("changed_at", \{ ascending: true \}\)/);
  assert.match(component, />Création</);
  assert.match(component, /Conversion en/);
  assert.match(component, /Annulation/);
  assert.match(component, /Motif :/);
  assert.match(component, /Avant :/);
  assert.match(component, /Après :/);
});

test("les justificatifs historiques restent consultables sans exposer leur chemin", () => {
  const component = source("./components/transaction-proof-history.tsx");
  const reads = source("./services/transaction-proof-read-service.ts");
  assert.match(component, /Justificatifs historiques/);
  assert.match(component, /Document indisponible/);
  assert.match(component, /versionId=\$\{item\.id\}/);
  assert.match(reads, /storage_path\.endsWith\("\/proof"\)/);
  assert.match(reads, /void storagePath/);
});
