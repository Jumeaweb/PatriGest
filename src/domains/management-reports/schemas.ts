import { z } from "zod";
const optionalBoolean = z.preprocess(
  (value) => (value === "true" ? true : value === "false" ? false : null),
  z.boolean().nullable(),
);
export const managementReportCreateSchema = z
  .object({ managementPeriodId: z.uuid() });
export const managementReportUpdateSchema = z.object({
  residenceChanged: optionalBoolean,
  representativeAddressChanged: optionalBoolean,
  realEstateConfirmed: optionalBoolean,
  financialInvestmentsConfirmed: optionalBoolean,
  observations: z
    .string()
    .trim()
    .max(10000)
    .transform((value) => value || null),
  signaturePlace: z
    .string()
    .trim()
    .max(255)
    .transform((value) => value || null),
});

export const managementReportTransmissionSchema = z.object({
  transmissionDate: z.iso.date(),
  transmissionMethod: z.enum([
    "postal_mail",
    "hand_delivery",
    "email",
    "external_platform",
    "other",
  ]),
  recipient: z.string().trim().min(1).max(500),
  note: z.string().trim().max(5000).transform((value) => value || null),
});

export const managementReportApprovalSchema = z.object({
  approvalDate: z.iso.date(),
  reviewerName: z.string().trim().min(1).max(500),
  reviewerRole: z.string().trim().max(500).transform((value) => value || null),
  note: z.string().trim().max(5000).transform((value) => value || null),
});

export const managementReportDifficultySchema = z.object({
  difficultyDate: z.iso.date(),
  reason: z.string().trim().min(1).max(5000),
  recipient: z.string().trim().max(500).transform((value) => value || null),
  note: z.string().trim().max(5000).transform((value) => value || null),
});

export const managementReportAccountSelectionSchema = z.object({
  financialAccountId: z.uuid(),
  selectionMode: z.enum(["auto", "included_manual", "excluded_manual"]),
  reason: z.string().trim().max(2000, "La justification ne peut pas dépasser 2 000 caractères."),
}).superRefine((value, context) => {
  if (value.selectionMode !== "auto" && !value.reason) {
    context.addIssue({
      code: "custom",
      path: ["reason"],
      message: "La justification est obligatoire.",
    });
  }
});
