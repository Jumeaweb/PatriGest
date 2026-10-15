import type { DossierAccessRole } from "@/types/database";

export type DataExportSchemaVersion = 1;
export type DataExportRequestStatus = "requested" | "collecting" | "building" | "ready" | "failed" | "expired";
export type DataExportFormat = "json" | "csv";
export type DataExportAllowedRole = Extract<DossierAccessRole, "owner" | "manager">;

export type DataExportSafeErrorCode =
  | "unauthenticated"
  | "forbidden"
  | "invalid_scope"
  | "data_unavailable"
  | "document_unavailable"
  | "archive_generation_failed"
  | "expired"
  | "technical";

export type DataExportSafeError = {
  code: DataExportSafeErrorCode;
  message: string;
  retryable: boolean;
};

export type DataExportDossierScope = {
  dossierId: string;
  role: DataExportAllowedRole;
};

export type DataExportScope = {
  dossiers: readonly DataExportDossierScope[];
};

export type DataExportRequest = {
  id: string;
  requestedBy: string;
  requestedAt: string;
  status: DataExportRequestStatus;
  schemaVersion: DataExportSchemaVersion;
  scope: DataExportScope;
  failure: DataExportSafeError | null;
};

export type DataExportSection = {
  id: string;
  format: DataExportFormat;
  archivePath: string;
  recordCount: number;
};

export type ExportDocumentSource =
  | "transaction_proof"
  | "bank_statement"
  | "management_report"
  | "generic_document";

export type ExportDocumentCategory = {
  id: string | null;
  label: string;
};

export type ExportDocumentLink = {
  dossierId: string;
  entityType: string;
  entityId: string;
  relationType: string;
};

export type ExportPhysicalFileDescriptor = {
  id: string;
  versionId: string | null;
  originalName: string;
  mimeType: string;
  byteSize: number;
  sha256: string | null;
};

export type ExportDocumentDescriptor = {
  documentId: string;
  title: string;
  source: {
    provider: ExportDocumentSource;
    recordId: string;
  };
  category: ExportDocumentCategory | null;
  createdAt: string;
  accessibleDossierIds: readonly string[];
  links: readonly ExportDocumentLink[];
  physicalFile: ExportPhysicalFileDescriptor;
};

export type ExportDocumentIndexEntry = Omit<ExportDocumentDescriptor, "physicalFile"> & {
  physicalFileId: string;
};

export type ExportPhysicalFileIndexEntry = ExportPhysicalFileDescriptor & {
  archivePath: string;
  documentIds: readonly string[];
};

export type ExportDocumentIndex = {
  schemaVersion: DataExportSchemaVersion;
  documents: readonly ExportDocumentIndexEntry[];
  files: readonly ExportPhysicalFileIndexEntry[];
};

export type ExportDocumentProviderContext = {
  requestedBy: string;
  scope: DataExportScope;
};

export interface ExportDocumentProvider {
  readonly source: ExportDocumentSource;
  listDocuments(context: ExportDocumentProviderContext): Promise<readonly ExportDocumentDescriptor[]>;
}

export type DataExportManifest = {
  schemaVersion: DataExportSchemaVersion;
  exportId: string;
  requestId: string;
  requestedBy: string;
  requestedAt: string;
  generatedAt: string;
  complete: true;
  scope: DataExportScope;
  sections: readonly DataExportSection[];
  documents: {
    indexPath: string;
    documentCount: number;
    physicalFileCount: number;
    totalBytes: number;
  };
  files: readonly {
    archivePath: string;
    mimeType: string;
    byteSize: number;
    sha256: string | null;
  }[];
};
