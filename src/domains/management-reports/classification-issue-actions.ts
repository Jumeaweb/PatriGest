import type { ManagementReportStatus } from "@/types/database";
import type { StableClassificationIssue } from "./stable-calculations.ts";

export function getClassificationIssueActions(
  personId: string,
  reportId: string,
  status: ManagementReportStatus,
  counts: { unclassified: number; needsPrecision: number },
  canManage: boolean,
) {
  if (status !== "draft") return [];
  const issues: { issue: StableClassificationIssue; count: number; label: string }[] = [
    { issue: "unclassified", count: counts.unclassified, label: "Classer les opérations concernées" },
    { issue: "needs_precision", count: counts.needsPrecision, label: "Préciser les opérations concernées" },
  ];
  return issues.filter((item) => item.count > 0).map((item) => ({
    issue: item.issue,
    count: item.count,
    label: canManage ? item.label : "Voir les opérations concernées",
    href: `/dossiers/${personId}/operations?reportId=${reportId}&classificationIssue=${item.issue}`,
  }));
}
