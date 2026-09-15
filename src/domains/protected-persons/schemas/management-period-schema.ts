import { z } from "zod";

export const managementPeriodSchema = z
  .object({
    startDate: z.iso.date("Saisissez une date de début valide."),
    endDate: z.iso.date("Saisissez une date de fin valide."),
  })
  .refine((data) => data.endDate >= data.startDate, {
    message: "La date de fin doit être postérieure ou égale à la date de début.",
    path: ["endDate"],
  });

export type ManagementPeriodInput = z.infer<typeof managementPeriodSchema>;
