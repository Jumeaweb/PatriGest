import assert from "node:assert/strict";
import test from "node:test";
import { MAX_PROOF_FILE_SIZE, prepareProofFile, ProofFileError } from "./transaction-proof-file.ts";

const file = (bytes, type, name = "preuve") => new File([new Uint8Array(bytes)], name, { type });

test("un PDF avec sa signature est accepté", async () => {
  const prepared = await prepareProofFile(file([37, 80, 68, 70, 45, 49], "application/pdf"), false);
  assert.equal(prepared?.extension, "pdf");
});

test("un JPEG avec sa signature est accepté", async () => {
  const prepared = await prepareProofFile(file([255, 216, 255, 0], "image/jpeg"), false);
  assert.equal(prepared?.extension, "jpg");
});

test("un PNG avec sa signature est accepté", async () => {
  const prepared = await prepareProofFile(file([137, 80, 78, 71, 13, 10, 26, 10], "image/png"), false);
  assert.equal(prepared?.extension, "png");
});

test("un type non autorisé est rejeté", async () => {
  await assert.rejects(prepareProofFile(file([1, 2, 3], "text/plain"), false), ProofFileError);
});

test("une signature incompatible avec le type déclaré est rejetée", async () => {
  await assert.rejects(prepareProofFile(file([255, 216, 255], "application/pdf"), false), ProofFileError);
});

test("un fichier de plus de 10 Mo est rejeté avant lecture", async () => {
  assert.equal(MAX_PROOF_FILE_SIZE, 10 * 1024 * 1024);
  await assert.rejects(prepareProofFile(new File([new Uint8Array(MAX_PROOF_FILE_SIZE + 1)], "gros.pdf", { type: "application/pdf" }), false), ProofFileError);
});

test("un justificatif est facultatif uniquement lorsque le champ est vide", async () => {
  assert.equal(await prepareProofFile(null, true), null);
  assert.equal(await prepareProofFile(new File([], "", { type: "" }), true), null);
  await assert.rejects(prepareProofFile(new File([], "vide.pdf", { type: "application/pdf" }), true), ProofFileError);
});
