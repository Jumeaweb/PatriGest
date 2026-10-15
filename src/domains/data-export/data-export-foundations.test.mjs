import assert from "node:assert/strict";
import test from "node:test";

import { getDossierExportAuthorization } from "./authorization.ts";
import {
  assertSafeZipPath,
  buildExportDocumentIndex,
  collectExportDocuments,
  createDataExportManifest,
  createZipPathAllocator,
  DATA_EXPORT_SCHEMA_VERSION,
  DataExportContractError,
  serializeCsvUtf8,
  serializeJsonUtf8,
  serializeManifestJsonUtf8,
  toExportMoney,
  toIsoDate,
} from "./serialization.ts";

const decoder = new TextDecoder();
const dossierId = "10000000-0000-4000-8000-000000000001";

function document(overrides = {}) {
  return {
    documentId: "20000000-0000-4000-8000-000000000001",
    title: "Décision de protection",
    source: { provider: "generic_document", recordId: "30000000-0000-4000-8000-000000000001" },
    category: { id: "decision", label: "Décision judiciaire" },
    createdAt: "2026-10-15T10:00:00+02:00",
    accessibleDossierIds: [dossierId],
    links: [{ dossierId, entityType: "protection_measure", entityId: "40000000-0000-4000-8000-000000000001", relationType: "supporting_document" }],
    physicalFile: {
      id: "50000000-0000-4000-8000-000000000001",
      versionId: null,
      originalName: "Décision été.pdf",
      mimeType: "application/pdf",
      byteSize: 1234,
      sha256: "a".repeat(64),
    },
    ...overrides,
  };
}

test("le propriétaire et le gestionnaire peuvent exporter, contrairement au lecteur", () => {
  assert.deepEqual(getDossierExportAuthorization(dossierId, "owner"), {
    allowed: true,
    scope: { dossierId, role: "owner" },
  });
  assert.deepEqual(getDossierExportAuthorization(dossierId, "manager"), {
    allowed: true,
    scope: { dossierId, role: "manager" },
  });
  const reader = getDossierExportAuthorization(dossierId, "read_only");
  assert.equal(reader.allowed, false);
  assert.equal(reader.error.code, "forbidden");
  assert.match(reader.error.message, /lecture seule/);
  const invalid = getDossierExportAuthorization("pas-un-uuid", "owner");
  assert.equal(invalid.allowed, false);
  assert.equal(invalid.error.code, "invalid_scope");
});

test("les chemins absolus, traversées et séparateurs Windows sont interdits", () => {
  for (const path of [
    "/etc/passwd",
    "../secret",
    "documents/../secret",
    "C:/secret",
    "documents\\secret",
    "documents//secret",
    "documents/CON",
    "documents/fichier. ",
    "documents/fichier?.pdf",
  ]) {
    assert.throws(() => assertSafeZipPath(path), DataExportContractError);
  }
  assert.doesNotThrow(() => assertSafeZipPath("documents/index.json"));
});

test("les noms identiques sont désambiguïsés sans perdre les accents", () => {
  const allocate = createZipPathAllocator();
  assert.equal(allocate("documents/files/a", "Décision été.pdf"), "documents/files/a/Décision été.pdf");
  assert.equal(allocate("documents/files/a", "Décision été.pdf"), "documents/files/a/Décision été (2).pdf");
  assert.equal(allocate("documents/files/a", "../../CON.pdf"), "documents/files/a/.. .. CON.pdf");
});

test("les montants sont représentés en centimes et en décimal exact", () => {
  assert.deepEqual(toExportMoney(205_462.31), { currency: "EUR", cents: 20_546_231, decimal: "205462.31" });
  assert.deepEqual(toExportMoney(0.1 + 0.2), { currency: "EUR", cents: 30, decimal: "0.30" });
  assert.deepEqual(toExportMoney(-0.05), { currency: "EUR", cents: -5, decimal: "-0.05" });
});

test("les dates civiles invalides sont refusées", () => {
  assert.equal(toIsoDate("2026-10-15"), "2026-10-15");
  assert.throws(() => toIsoDate("2026-02-30"), DataExportContractError);
});

test("le CSV UTF-8 conserve les accents et neutralise les formules", () => {
  const bytes = serializeCsvUtf8(["libellé", "montant"], [
    { libellé: "Électricité", montant: 12.34 },
    { libellé: "=HYPERLINK(\"https://example.test\")", montant: -5 },
    { libellé: "  +CMD", montant: 0 },
  ]);
  assert.deepEqual([...bytes.slice(0, 3)], [0xef, 0xbb, 0xbf]);
  const csv = decoder.decode(bytes);
  assert.match(csv, /Électricité/);
  assert.match(csv, /'=HYPERLINK/);
  assert.match(csv, /'  \+CMD/);
  assert.match(csv, /"-5"/);
});

test("le JSON UTF-8 est déterministe et conserve les caractères français", () => {
  const json = decoder.decode(serializeJsonUtf8({ z: 1, étiquette: "Cédé", a: { y: 2, x: 1 } }));
  assert.ok(json.indexOf('"a"') < json.indexOf('"z"'));
  assert.ok(json.indexOf('"x"') < json.indexOf('"y"'));
  assert.match(json, /Cédé/);
  const circular = [];
  circular.push(circular);
  assert.throws(() => serializeJsonUtf8(circular), /circulaire/);
});

test("plusieurs rattachements logiques partagent un seul fichier physique", () => {
  const descriptor = document({
    links: [
      { dossierId, entityType: "protected_person", entityId: dossierId, relationType: "dossier_document" },
      { dossierId, entityType: "protection_measure", entityId: "40000000-0000-4000-8000-000000000001", relationType: "supporting_document" },
    ],
  });
  const index = buildExportDocumentIndex([descriptor]);
  assert.equal(index.documents.length, 1);
  assert.equal(index.documents[0].links.length, 2);
  assert.equal(index.files.length, 1);
  assert.deepEqual(index.files[0].documentIds, [descriptor.documentId]);
  assert.match(index.files[0].archivePath, /^documents\/files\//);
});

test("deux documents peuvent référencer le même fichier sans le dupliquer", () => {
  const first = document();
  const second = document({
    documentId: "20000000-0000-4000-8000-000000000002",
    title: "Copie classée dans le dossier",
    source: { provider: "generic_document", recordId: "30000000-0000-4000-8000-000000000002" },
  });
  const index = buildExportDocumentIndex([first, second]);
  assert.equal(index.documents.length, 2);
  assert.equal(index.files.length, 1);
  assert.deepEqual(index.files[0].documentIds, [first.documentId, second.documentId]);
});

test("un fournisseur documentaire générique simulé respecte le contrat extensible", async () => {
  const provider = {
    source: "generic_document",
    async listDocuments(context) {
      assert.equal(context.requestedBy, "60000000-0000-4000-8000-000000000001");
      assert.equal(context.scope.dossiers[0].dossierId, dossierId);
      return [document()];
    },
  };
  const descriptors = await collectExportDocuments([provider], {
    requestedBy: "60000000-0000-4000-8000-000000000001",
    scope: { dossiers: [{ dossierId, role: "owner" }] },
  });
  assert.equal(buildExportDocumentIndex(descriptors).documents.length, 1);
});

test("un fournisseur ne peut pas élargir le périmètre documentaire demandé", async () => {
  const foreignDossierId = "10000000-0000-4000-8000-000000000002";
  const provider = {
    source: "generic_document",
    async listDocuments() {
      return [document({
        accessibleDossierIds: [foreignDossierId],
        links: [{
          dossierId: foreignDossierId,
          entityType: "protected_person",
          entityId: foreignDossierId,
          relationType: "dossier_document",
        }],
      })];
    },
  };
  await assert.rejects(
    collectExportDocuments([provider], {
      requestedBy: "60000000-0000-4000-8000-000000000001",
      scope: { dossiers: [{ dossierId, role: "owner" }] },
    }),
    /hors du périmètre/,
  );
});

test("le manifeste versionné reflète exactement les sections et l’index", () => {
  const index = buildExportDocumentIndex([document()]);
  const manifest = createDataExportManifest({
    exportId: "70000000-0000-4000-8000-000000000001",
    requestId: "80000000-0000-4000-8000-000000000001",
    requestedBy: "60000000-0000-4000-8000-000000000001",
    requestedAt: "2026-10-15T08:00:00Z",
    generatedAt: "2026-10-15T08:05:00Z",
    scope: { dossiers: [{ dossierId, role: "manager" }] },
    sections: [{ id: "protected_persons", format: "json", archivePath: `dossiers/${dossierId}/dossier.json`, recordCount: 1 }],
    documentIndex: index,
  });
  assert.equal(manifest.schemaVersion, DATA_EXPORT_SCHEMA_VERSION);
  assert.equal(manifest.complete, true);
  assert.deepEqual(manifest.documents, {
    indexPath: "documents/index.json",
    documentCount: 1,
    physicalFileCount: 1,
    totalBytes: 1234,
  });
  assert.equal(manifest.files[0].archivePath, index.files[0].archivePath);
});

test("le manifeste refuse les clés techniques sensibles", () => {
  const index = buildExportDocumentIndex([document()]);
  const manifest = createDataExportManifest({
    exportId: "70000000-0000-4000-8000-000000000001",
    requestId: "80000000-0000-4000-8000-000000000001",
    requestedBy: "60000000-0000-4000-8000-000000000001",
    requestedAt: "2026-10-15T08:00:00Z",
    generatedAt: "2026-10-15T08:05:00Z",
    scope: { dossiers: [{ dossierId, role: "owner" }] },
    sections: [],
    documentIndex: index,
  });
  assert.doesNotThrow(() => serializeManifestJsonUtf8(manifest));
  assert.throws(
    () => serializeManifestJsonUtf8({ ...manifest, storage_path: "private/internal/object" }),
    /Donnée technique sensible/,
  );
  assert.throws(
    () => serializeManifestJsonUtf8({ ...manifest, nested: { token: "secret" } }),
    /Donnée technique sensible/,
  );
  assert.throws(
    () => serializeManifestJsonUtf8({ ...manifest, nested: { accessToken: "secret" } }),
    /Donnée technique sensible/,
  );
});
