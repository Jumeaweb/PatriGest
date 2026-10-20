import type {
  BankStatementFinalization,
  DocumentContent,
  ExecuteDocumentOperationInput,
  ManagementReportFinalization,
  TransactionProofFinalization,
} from "./contracts";

function content(targetRole: "primary" | "destination", value: DocumentContent | null) {
  return value ? [{ targetRole, content: value }] : [];
}

export function transactionProofOperation(
  operationId: string,
  document: DocumentContent | null,
  finalization: Omit<TransactionProofFinalization, "kind">,
): ExecuteDocumentOperationInput {
  return {
    operationId,
    contents: content("primary", document),
    finalization: { kind: "transaction_proof", ...finalization },
  };
}

export function bankStatementOperation(
  operationId: string,
  document: DocumentContent | null,
  finalization: Omit<BankStatementFinalization, "kind">,
): ExecuteDocumentOperationInput {
  return {
    operationId,
    contents: content("primary", document),
    finalization: { kind: "bank_statement", ...finalization },
  };
}

function managementReportOperation(
  operationId: string,
  document: DocumentContent | null,
  targetRole: "primary" | "destination",
  finalization: Omit<ManagementReportFinalization, "kind">,
): ExecuteDocumentOperationInput {
  return {
    operationId,
    contents: content(targetRole, document),
    finalization: { kind: "management_report", ...finalization },
  };
}

export function managementReportGenerationOperation(
  operationId: string,
  document: DocumentContent,
  finalization: Omit<ManagementReportFinalization, "kind">,
) {
  return managementReportOperation(operationId, document, "primary", finalization);
}

export function managementReportFinalizationOperation(
  operationId: string,
  document: DocumentContent,
  finalization: Omit<ManagementReportFinalization, "kind">,
) {
  return managementReportOperation(operationId, document, "destination", finalization);
}

export function managementReportResumeOperation(
  operationId: string,
  finalization: Omit<ManagementReportFinalization, "kind">,
) {
  return managementReportOperation(operationId, null, "primary", finalization);
}
