import assert from "node:assert/strict";
import test from "node:test";
import { persistProof, ProofPersistenceError } from "./transaction-proof-persistence.ts";

function steps({ existing = false, uploadFails = false, databaseFails = false, compensationFails = false } = {}) {
  const calls = [];
  const previous = new Uint8Array([1, 2, 3]);
  return {
    calls,
    dependencies: {
      existing,
      backup: async () => { calls.push("backup"); return previous; },
      upload: async () => { calls.push("upload"); if (uploadFails) throw new Error("upload"); },
      writeDocument: async () => { calls.push("database"); if (databaseFails) throw new Error("database"); },
      remove: async () => { calls.push("remove"); if (compensationFails) throw new Error("cleanup"); },
      verifyRemoved: async () => { calls.push("verifyRemoved"); },
      restore: async (bytes) => { calls.push("restore"); assert.deepEqual(bytes, previous); if (compensationFails) throw new Error("restore"); },
      verifyRestored: async (bytes) => { calls.push("verifyRestored"); assert.deepEqual(bytes, previous); },
    },
  };
}

test("un nouveau justificatif écrit Storage avant la ligne documentaire", async () => {
  const { calls, dependencies } = steps();
  await persistProof(dependencies);
  assert.deepEqual(calls, ["upload", "database"]);
});

test("échec DB après upload : suppression Storage et vérification", async () => {
  const { calls, dependencies } = steps({ databaseFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "database");
  assert.deepEqual(calls, ["upload", "database", "remove", "verifyRemoved"]);
});

test("échec de nettoyage : incohérence signalée sans faux succès", async () => {
  const { calls, dependencies } = steps({ databaseFails: true, compensationFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "compensation");
  assert.deepEqual(calls, ["upload", "database", "remove"]);
});

test("remplacement réussi : sauvegarde préalable puis upload et DB", async () => {
  const { calls, dependencies } = steps({ existing: true });
  await persistProof(dependencies);
  assert.deepEqual(calls, ["backup", "upload", "database"]);
});

test("remplacement avec échec DB : ancien fichier restauré et contrôlé", async () => {
  const { calls, dependencies } = steps({ existing: true, databaseFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "database");
  assert.deepEqual(calls, ["backup", "upload", "database", "restore", "verifyRestored"]);
});

test("remplacement avec échec d'upload : restauration malgré une écriture incertaine", async () => {
  const { calls, dependencies } = steps({ existing: true, uploadFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "upload");
  assert.deepEqual(calls, ["backup", "upload", "restore", "verifyRestored"]);
});

test("échec d'upload initial : ne supprime pas l'objet éventuel d'une autre requête", async () => {
  const { calls, dependencies } = steps({ uploadFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "upload");
  assert.deepEqual(calls, ["upload"]);
});

test("remplacement avec restauration échouée : erreur de compensation", async () => {
  const { dependencies } = steps({ existing: true, databaseFails: true, compensationFails: true });
  await assert.rejects(persistProof(dependencies), (error) => error instanceof ProofPersistenceError && error.stage === "compensation");
});
