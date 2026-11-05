import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { getProofWriteDenial } from "./transaction-proof-access.ts";
import { createTransactionWithOptionalProof } from "./transaction-proof-create.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const service = source("./transaction-proof-service.ts");
const route = source("../../../app/api/dossiers/[protectedPersonId]/operations/[transactionId]/justificatif/route.ts");
const action = source("../actions.ts");
const form = source("../components/transaction-form.tsx");
const nextConfig = source("../../../../next.config.ts");
const allowed = { personId: "dossier", transactionPersonId: "dossier", transactionType: "expense", transferId: null, proofReference: "2026-0001", role: "owner", closed: false };
const proof = { bytes: new Uint8Array([1]), mimeType: "application/pdf", extension: "pdf", size: 1 };

test("owner et manager peuvent écrire, read_only est refusé", () => {
  assert.equal(getProofWriteDenial(allowed), null);
  assert.equal(getProofWriteDenial({ ...allowed, role: "manager" }), null);
  assert.equal(getProofWriteDenial({ ...allowed, role: "read_only" }), "read_only");
});

test("autre dossier, recette et virement ne peuvent recevoir le justificatif", () => {
  assert.equal(getProofWriteDenial({ ...allowed, transactionPersonId: "autre" }), "not_found");
  assert.equal(getProofWriteDenial({ ...allowed, transactionType: "income" }), "not_found");
  assert.equal(getProofWriteDenial({ ...allowed, transferId: "virement" }), "not_found");
});

test("un exercice clôturé interdit ajout et remplacement côté service", () => {
  assert.equal(getProofWriteDenial({ ...allowed, closed: true }), "closed");
  assert.match(service, /getProofWriteDenial\(/);
  assert.match(service, /isDateInClosedPeriod\(context\.transaction\.transaction_date, context\.person\.managementPeriods\)/);
  assert.match(service, /writeDocument: async \(\) => \{[\s\S]*?getProofWriteDenial\(/);
});

test("la route API existante utilise les validations et le service partagés", () => {
  assert.match(route, /const formData = await request\.formData\(\)/);
  assert.match(route, /await saveTransactionProof\(protectedPersonId, transactionId, proof,/);
  assert.match(route, /getTransactionProofDescriptor\(protectedPersonId, transactionId/);
  assert.match(route, /listTransactionProofHistory\(protectedPersonId, transactionId\)/);
  assert.match(service, /protected-persons\/\$\{personId\}\/transactions\/\$\{transactionId\}/);
  assert.match(service, /storage\.upload\(path, file\.bytes/);
  assert.match(service, /\.from\("transaction_documents"\)/);
  assert.match(route, /await deleteTransactionProof\(protectedPersonId, transactionId\)/);
});

test("le champ fichier existe seulement pour une dépense en création", () => {
  assert.match(form, /mode === "expense" && !transaction && <ProofFileField/);
  assert.match(form, /id="proofFile" name="proofFile" type="file"/);
  assert.match(form, /accept="application\/pdf,image\/jpeg,image\/png"/);
  assert.match(form, /un seul PDF, JPEG ou PNG de 10 Mo maximum/);
  assert.doesNotMatch(form, /mode === "income"[^\n]+name="proofFile"/);
  assert.doesNotMatch(form, /mode === "transfer"[^\n]+name="proofFile"/);
  assert.match(nextConfig, /bodySizeLimit: "11mb"/);
});

test("dépense sans fichier : création existante et aucun upload", async () => {
  const calls = [];
  const result = await createTransactionWithOptionalProof(async () => { calls.push("create"); return { id: "created" }; }, null, async () => { calls.push("upload"); });
  assert.deepEqual(calls, ["create"]);
  assert.equal(result.proofSaved, true);
});

test("dépense avec fichier : création puis association documentaire", async () => {
  const calls = [];
  const result = await createTransactionWithOptionalProof(async () => { calls.push("create"); return { id: "created" }; }, proof, async (id) => { calls.push(`upload:${id}`); });
  assert.deepEqual(calls, ["create", "upload:created"]);
  assert.equal(result.proofSaved, true);
});

test("échec transaction : aucun upload n'est lancé", async () => {
  let uploads = 0;
  await assert.rejects(createTransactionWithOptionalProof(async () => { throw new Error("create"); }, proof, async () => { uploads += 1; }));
  assert.equal(uploads, 0);
});

test("échec upload : transaction conservée et réussite partielle", async () => {
  let creates = 0;
  const result = await createTransactionWithOptionalProof(async () => { creates += 1; return { id: "created" }; }, proof, async () => { throw new Error("upload"); });
  assert.deepEqual(result, { transaction: { id: "created" }, proofSaved: false });
  assert.equal(creates, 1);
  assert.match(action, /if \(!result\.proofSaved\)/);
  assert.match(action, /proofUploadFailed: true/);
  assert.match(action, /if \(_state\.proofUploadFailed\) return \{ status: "error"/);
  assert.match(form, /if \(state\.proofUploadFailed\) return <section/);
  assert.match(form, /Ajouter le justificatif à cette dépense/);
});

test("validation du fichier précède l'INSERT, succès complet conserve le retour", () => {
  const validation = action.indexOf("prepareProofFile(formData.get(\"proofFile\"), true)");
  const creation = action.indexOf("createTransactionWithOptionalProof(");
  assert.ok(validation >= 0 && creation > validation);
  assert.match(form, /!state\.proofUploadFailed\) \{ router\.push\(returnHref\); router\.refresh\(\)/);
  assert.match(form, /defaultAccountId \? `\/dossiers\/\$\{personId\}\/comptes\/\$\{defaultAccountId\}\/operations` : `\/dossiers\/\$\{personId\}\/operations`/);
});

test("une erreur récupérable conserve les champs et le fichier du formulaire", () => {
  assert.match(form, /const \[state, formAction, pending\] = useActionState/);
  assert.match(form, /const submit = \(event: FormEvent<HTMLFormElement>\)/);
  assert.match(form, /event\.preventDefault\(\);[\s\S]*const formData = new FormData\(event\.currentTarget\);[\s\S]*startTransition\(\(\) => formAction\(formData\)\)/);
  assert.match(form, /<form className="grid gap-3 sm:grid-cols-2" onSubmit=\{submit\}/);
  assert.doesNotMatch(form, /<form action=\{formAction\}/);
  assert.match(form, /disabled=\{pending\}/);
  assert.doesNotMatch(form, /\.reset\(|reset\(/);
  assert.match(action, /prepareProofFile\(formData\.get\("proofFile"\), true\)[\s\S]*createTransactionWithOptionalProof/);
});

test("le justificatif facultatif est mono-fichier, remplaçable et retirable avant création", () => {
  assert.match(form, /const \[proofFile, setProofFile\] = useState<File \| null>\(null\)/);
  assert.match(form, /event\.target\.files\?\.\[0\] \?\? null/);
  assert.doesNotMatch(form, /multiple/);
  assert.match(form, /file\?\.name \?\? "Aucun fichier sélectionné"/);
  assert.match(form, /file \? "Remplacer" : "Choisir"/);
  assert.match(form, /aria-label=\{`Retirer le justificatif \$\{file\.name\}`\}/);
  assert.match(form, /inputRef\.current\.value = ""/);
  assert.match(form, /if \(!proofFile\) formData\.delete\("proofFile"\)/);
});
