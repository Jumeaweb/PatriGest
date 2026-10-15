import type {
  DataExportManifest,
  DataExportScope,
  DataExportSection,
  ExportDocumentDescriptor,
  ExportDocumentIndex,
  ExportDocumentIndexEntry,
  ExportDocumentProvider,
  ExportDocumentProviderContext,
  ExportDocumentLink,
  ExportPhysicalFileDescriptor,
  ExportPhysicalFileIndexEntry,
} from "./contracts";

export const DATA_EXPORT_SCHEMA_VERSION = 1 as const;

const UTF8_BOM = new Uint8Array([0xef, 0xbb, 0xbf]);
const FORBIDDEN_MANIFEST_KEYS = new Set([
  "api_key",
  "authorization",
  "cookie",
  "password",
  "secret",
  "service_role",
  "service_role_key",
  "signed_url",
  "storage_path",
  "token",
  "token_hash",
]);
const FORBIDDEN_MANIFEST_KEY_PART = /(^|_)(api_?key|authorization|cookies?|password|secret|service_role|signed_url|storage_path|token(?:_hash)?)(_|$)/;
const WINDOWS_RESERVED_NAME = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DANGEROUS_CSV_CELL = /^[\t\r\n ]*[=+\-@]/;

export class DataExportContractError extends Error {}

export function assertSafeZipPath(path: string) {
  if (!path || path.startsWith("/") || path.startsWith("\\") || /^[a-z]:/i.test(path)) {
    throw new DataExportContractError("Chemin ZIP absolu interdit.");
  }
  if (path.includes("\\") || /[\u0000-\u001f\u007f]/.test(path)) {
    throw new DataExportContractError("Chemin ZIP invalide.");
  }
  const segments = path.split("/");
  if (segments.some((segment) => !segment || segment === "." || segment === "..")) {
    throw new DataExportContractError("Traversée de chemin ZIP interdite.");
  }
  if (segments.some((segment) => (
    /[<>:"|?*]/.test(segment)
    || /[. ]$/.test(segment)
    || WINDOWS_RESERVED_NAME.test(segment)
  ))) {
    throw new DataExportContractError("Segment de chemin ZIP invalide.");
  }
}

export function sanitizeZipSegment(value: string, fallback = "fichier") {
  const normalize = (input: string) => input
    .normalize("NFKC")
    .replace(/[<>:"/\\|?*\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[. ]+$/g, "")
    .slice(0, 120);
  let result = normalize(value);
  if (!result || result === "." || result === "..") result = normalize(fallback) || "fichier";
  if (WINDOWS_RESERVED_NAME.test(result)) result = `_${result}`;
  return result;
}

export function createZipPathAllocator() {
  const allocated = new Set<string>();

  return (directory: string, originalName: string) => {
    assertSafeZipPath(directory);
    const sanitized = sanitizeZipSegment(originalName);
    const dot = sanitized.lastIndexOf(".");
    const hasExtension = dot > 0 && dot < sanitized.length - 1;
    const base = hasExtension ? sanitized.slice(0, dot) : sanitized;
    const extension = hasExtension ? sanitized.slice(dot) : "";
    let candidate = `${directory}/${sanitized}`;
    let suffix = 2;

    while (allocated.has(candidate.normalize("NFKC").toLowerCase())) {
      candidate = `${directory}/${base} (${suffix})${extension}`;
      suffix += 1;
    }
    assertSafeZipPath(candidate);
    allocated.add(candidate.normalize("NFKC").toLowerCase());
    return candidate;
  };
}

export function toExportMoney(amount: number) {
  if (!Number.isFinite(amount)) throw new DataExportContractError("Montant invalide.");
  const cents = Math.round(amount * 100);
  if (!Number.isSafeInteger(cents)) throw new DataExportContractError("Montant hors limites.");
  const absolute = Math.abs(cents);
  const sign = cents < 0 ? "-" : "";
  return {
    currency: "EUR" as const,
    cents,
    decimal: `${sign}${Math.floor(absolute / 100)}.${String(absolute % 100).padStart(2, "0")}`,
  };
}

export function toIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new DataExportContractError("Date invalide.");
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new DataExportContractError("Date invalide.");
  }
  return value;
}

export function toIsoTimestamp(value: string) {
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.valueOf())) throw new DataExportContractError("Horodatage invalide.");
  return timestamp.toISOString();
}

type CsvCell = string | number | boolean | null;

function csvCell(value: CsvCell) {
  if (typeof value === "number" && !Number.isFinite(value)) {
    throw new DataExportContractError("Valeur CSV invalide.");
  }
  let text = value === null ? "" : String(value);
  if (typeof value === "string" && DANGEROUS_CSV_CELL.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export function serializeCsvUtf8(
  headers: readonly string[],
  rows: readonly Readonly<Record<string, CsvCell>>[],
) {
  if (!headers.length || new Set(headers).size !== headers.length) {
    throw new DataExportContractError("Colonnes CSV invalides.");
  }
  const lines = [
    headers.map(csvCell).join(";"),
    ...rows.map((row) => headers.map((header) => csvCell(row[header] ?? null)).join(";")),
  ];
  const content = new TextEncoder().encode(`${lines.join("\r\n")}\r\n`);
  const result = new Uint8Array(UTF8_BOM.length + content.length);
  result.set(UTF8_BOM);
  result.set(content, UTF8_BOM.length);
  return result;
}

function stableJsonValue(value: unknown, parents: Set<object>): unknown {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new DataExportContractError("Nombre JSON invalide.");
    return value;
  }
  if (typeof value !== "object") throw new DataExportContractError("Valeur JSON non sérialisable.");
  if (parents.has(value)) throw new DataExportContractError("Référence JSON circulaire.");
  parents.add(value);
  if (Array.isArray(value)) {
    const result = value.map((item) => stableJsonValue(item, parents));
    parents.delete(value);
    return result;
  }
  if (Object.getPrototypeOf(value) !== Object.prototype) {
    throw new DataExportContractError("Objet JSON non pris en charge.");
  }
  const record = value as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const key of Object.keys(record).sort()) {
    if (record[key] === undefined) throw new DataExportContractError("Valeur JSON indéfinie.");
    result[key] = stableJsonValue(record[key], parents);
  }
  parents.delete(value);
  return result;
}

export function serializeJsonUtf8(value: unknown) {
  const stable = stableJsonValue(value, new Set());
  return new TextEncoder().encode(`${JSON.stringify(stable, null, 2)}\n`);
}

function assertNoSensitiveManifestData(value: unknown) {
  if (Array.isArray(value)) {
    value.forEach(assertNoSensitiveManifestData);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, item] of Object.entries(value)) {
    const normalizedKey = key
      .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
      .toLowerCase();
    if (FORBIDDEN_MANIFEST_KEYS.has(normalizedKey) || FORBIDDEN_MANIFEST_KEY_PART.test(normalizedKey)) {
      throw new DataExportContractError("Donnée technique sensible interdite dans le manifeste.");
    }
    assertNoSensitiveManifestData(item);
  }
}

export function serializeManifestJsonUtf8(manifest: DataExportManifest) {
  assertNoSensitiveManifestData(manifest);
  return serializeJsonUtf8(manifest);
}

export function createDataExportManifest(input: {
  exportId: string;
  requestId: string;
  requestedBy: string;
  requestedAt: string;
  generatedAt: string;
  scope: DataExportScope;
  sections: readonly DataExportSection[];
  documentIndex: ExportDocumentIndex;
}): DataExportManifest {
  if (input.documentIndex.schemaVersion !== DATA_EXPORT_SCHEMA_VERSION) {
    throw new DataExportContractError("Version d’index documentaire incompatible.");
  }
  const dossierIds = new Set<string>();
  for (const dossier of input.scope.dossiers) {
    if (!UUID.test(dossier.dossierId) || (dossier.role !== "owner" && dossier.role !== "manager")) {
      throw new DataExportContractError("Périmètre d’export invalide.");
    }
    if (dossierIds.has(dossier.dossierId)) {
      throw new DataExportContractError("Dossier dupliqué dans le périmètre d’export.");
    }
    dossierIds.add(dossier.dossierId);
  }
  const sectionIds = new Set<string>();
  const sectionPaths = new Set<string>();
  for (const section of input.sections) {
    assertSafeZipPath(section.archivePath);
    if (!section.id || !Number.isSafeInteger(section.recordCount) || section.recordCount < 0) {
      throw new DataExportContractError("Section d’export invalide.");
    }
    if (sectionIds.has(section.id) || sectionPaths.has(section.archivePath.toLowerCase())) {
      throw new DataExportContractError("Section d’export dupliquée.");
    }
    sectionIds.add(section.id);
    sectionPaths.add(section.archivePath.toLowerCase());
  }
  const filePaths = new Set<string>();
  let totalBytes = 0;
  for (const file of input.documentIndex.files) {
    assertSafeZipPath(file.archivePath);
    const normalizedPath = file.archivePath.normalize("NFKC").toLowerCase();
    if (filePaths.has(normalizedPath)) throw new DataExportContractError("Chemin documentaire dupliqué.");
    filePaths.add(normalizedPath);
    totalBytes += file.byteSize;
    if (!Number.isSafeInteger(totalBytes)) throw new DataExportContractError("Volume documentaire hors limites.");
  }

  const manifest: DataExportManifest = {
    schemaVersion: DATA_EXPORT_SCHEMA_VERSION,
    exportId: input.exportId,
    requestId: input.requestId,
    requestedBy: input.requestedBy,
    requestedAt: toIsoTimestamp(input.requestedAt),
    generatedAt: toIsoTimestamp(input.generatedAt),
    complete: true,
    scope: input.scope,
    sections: input.sections,
    documents: {
      indexPath: "documents/index.json",
      documentCount: input.documentIndex.documents.length,
      physicalFileCount: input.documentIndex.files.length,
      totalBytes,
    },
    files: input.documentIndex.files.map((file) => ({
      archivePath: file.archivePath,
      mimeType: file.mimeType,
      byteSize: file.byteSize,
      sha256: file.sha256,
    })),
  };
  assertNoSensitiveManifestData(manifest);
  return manifest;
}

const SHA256 = /^[0-9a-f]{64}$/i;

function stableKey(parts: readonly string[]) {
  return parts.join("\u0000");
}

function uniqueSorted(values: readonly string[]) {
  return [...new Set(values)].sort();
}

function uniqueLinks(links: readonly ExportDocumentLink[]) {
  const byKey = new Map<string, ExportDocumentLink>();
  for (const link of links) {
    if (!link.dossierId || !link.entityType || !link.entityId || !link.relationType) {
      throw new DataExportContractError("Rattachement documentaire invalide.");
    }
    byKey.set(stableKey([link.dossierId, link.entityType, link.entityId, link.relationType]), link);
  }
  return [...byKey.values()].sort((left, right) => stableKey([
    left.dossierId, left.entityType, left.entityId, left.relationType,
  ]).localeCompare(stableKey([
    right.dossierId, right.entityType, right.entityId, right.relationType,
  ])));
}

function validateFile(file: ExportPhysicalFileDescriptor) {
  if (!file.id || !file.originalName.trim() || !file.mimeType.trim()) {
    throw new DataExportContractError("Fichier documentaire invalide.");
  }
  if (!Number.isSafeInteger(file.byteSize) || file.byteSize < 0) {
    throw new DataExportContractError("Taille documentaire invalide.");
  }
  if (file.sha256 !== null && !SHA256.test(file.sha256)) {
    throw new DataExportContractError("Empreinte documentaire invalide.");
  }
}

function sameFile(left: ExportPhysicalFileDescriptor, right: ExportPhysicalFileDescriptor) {
  return left.versionId === right.versionId
    && left.originalName === right.originalName
    && left.mimeType === right.mimeType
    && left.byteSize === right.byteSize
    && left.sha256?.toLowerCase() === right.sha256?.toLowerCase();
}

function sameDocument(left: ExportDocumentDescriptor, right: ExportDocumentDescriptor) {
  return left.title === right.title
    && left.source.provider === right.source.provider
    && left.source.recordId === right.source.recordId
    && JSON.stringify(left.category) === JSON.stringify(right.category)
    && toIsoTimestamp(left.createdAt) === toIsoTimestamp(right.createdAt)
    && left.physicalFile.id === right.physicalFile.id;
}

export async function collectExportDocuments(
  providers: readonly ExportDocumentProvider[],
  context: ExportDocumentProviderContext,
) {
  const allowedDossierIds = new Set(context.scope.dossiers.map(({ dossierId }) => dossierId));
  const batches = await Promise.all(providers.map(async (provider) => {
    const documents = await provider.listDocuments(context);
    if (documents.some((document) => document.source.provider !== provider.source)) {
      throw new DataExportContractError("Source documentaire incohérente.");
    }
    if (documents.some((document) => (
      document.accessibleDossierIds.some((dossierId) => !allowedDossierIds.has(dossierId))
      || document.links.some(({ dossierId }) => !allowedDossierIds.has(dossierId))
    ))) {
      throw new DataExportContractError("Document hors du périmètre d’export demandé.");
    }
    return documents;
  }));
  return batches.flat();
}

export function buildExportDocumentIndex(
  descriptors: readonly ExportDocumentDescriptor[],
): ExportDocumentIndex {
  const documents = new Map<string, ExportDocumentDescriptor>();
  const files = new Map<string, ExportPhysicalFileDescriptor>();
  const fileDocumentIds = new Map<string, Set<string>>();

  for (const descriptor of descriptors) {
    if (!descriptor.documentId || !descriptor.title.trim() || !descriptor.source.recordId) {
      throw new DataExportContractError("Document invalide.");
    }
    validateFile(descriptor.physicalFile);
    const accessibleDossierIds = uniqueSorted(descriptor.accessibleDossierIds);
    if (!accessibleDossierIds.length) throw new DataExportContractError("Document sans dossier accessible.");
    const links = uniqueLinks(descriptor.links);
    if (!links.length || links.some((link) => !accessibleDossierIds.includes(link.dossierId))) {
      throw new DataExportContractError("Rattachement hors périmètre documentaire.");
    }
    const normalized: ExportDocumentDescriptor = {
      ...descriptor,
      createdAt: toIsoTimestamp(descriptor.createdAt),
      accessibleDossierIds,
      links,
      physicalFile: {
        ...descriptor.physicalFile,
        sha256: descriptor.physicalFile.sha256?.toLowerCase() ?? null,
      },
    };
    const existingDocument = documents.get(normalized.documentId);
    if (existingDocument && !sameDocument(existingDocument, normalized)) {
      throw new DataExportContractError("Identifiant documentaire contradictoire.");
    }
    documents.set(normalized.documentId, existingDocument ? {
      ...existingDocument,
      accessibleDossierIds: uniqueSorted([
        ...existingDocument.accessibleDossierIds,
        ...normalized.accessibleDossierIds,
      ]),
      links: uniqueLinks([...existingDocument.links, ...normalized.links]),
    } : normalized);

    const existingFile = files.get(normalized.physicalFile.id);
    if (existingFile && !sameFile(existingFile, normalized.physicalFile)) {
      throw new DataExportContractError("Identifiant de fichier physique contradictoire.");
    }
    files.set(normalized.physicalFile.id, existingFile ?? normalized.physicalFile);
    const ids = fileDocumentIds.get(normalized.physicalFile.id) ?? new Set<string>();
    ids.add(normalized.documentId);
    fileDocumentIds.set(normalized.physicalFile.id, ids);
  }

  const allocatePath = createZipPathAllocator();
  const indexedFiles: ExportPhysicalFileIndexEntry[] = [...files.values()]
    .sort((left, right) => left.id.localeCompare(right.id))
    .map((file) => ({
      ...file,
      archivePath: allocatePath(
        `documents/files/${sanitizeZipSegment(file.id, "fichier")}`,
        file.originalName,
      ),
      documentIds: [...(fileDocumentIds.get(file.id) ?? [])].sort(),
    }));
  const indexedDocuments: ExportDocumentIndexEntry[] = [...documents.values()]
    .sort((left, right) => left.documentId.localeCompare(right.documentId))
    .map(({ physicalFile, ...document }) => ({ ...document, physicalFileId: physicalFile.id }));

  return {
    schemaVersion: DATA_EXPORT_SCHEMA_VERSION,
    documents: indexedDocuments,
    files: indexedFiles,
  };
}
