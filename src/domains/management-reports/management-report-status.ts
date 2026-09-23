import type { ManagementReportStatus } from "@/types/database";

type ManagementReportStatusPresentation = {
  label: string;
  className: string;
};

const statusPresentations: Record<
  ManagementReportStatus,
  ManagementReportStatusPresentation
> = {
  draft: {
    label: "En préparation",
    className: "border-slate-200 bg-slate-100 text-slate-700",
  },
  ready: {
    label: "Prêt",
    className:
      "border-brand-accent/30 bg-brand-navigation/35 text-brand-foreground",
  },
  generated: {
    label: "Projet généré",
    className: "border-amber-200 bg-amber-50 text-amber-800",
  },
  finalized: {
    label: "Finalisé",
    className:
      "border-brand-accent/30 bg-brand-navigation/35 text-brand-foreground",
  },
  transmitted: {
    label: "Transmis",
    className:
      "border-brand-accent/30 bg-brand-navigation/35 text-brand-foreground",
  },
  approved: {
    label: "Approuvé",
    className: "border-emerald-200 bg-emerald-50 text-emerald-800",
  },
  difficulty: {
    label: "Difficulté signalée",
    className: "border-red-200 bg-red-50 text-red-800",
  },
};

export function getManagementReportStatusPresentation(
  status: ManagementReportStatus,
) {
  return statusPresentations[status];
}
