import { z } from "zod";

export const financialAccountTypes = ["checking", "livret_a", "ldds", "csl", "lep", "pel", "term_account", "life_insurance", "other_investment", "securities_account"] as const;

const optionalText = (maximum: number) => z.string().trim().max(maximum).optional().transform((value) => value || null);
const optionalDate = z.string().optional().transform((value) => value || null).refine((value) => value === null || /^\d{4}-\d{2}-\d{2}$/.test(value), "Saisissez une date valide.");
const amount = z.string().trim().min(1, "Saisissez le solde initial.").refine((value) => /^-?\d+(?:[.,]\d{1,2})?$/.test(value), "Saisissez un montant valide avec deux décimales maximum.").transform((value) => Number(value.replace(",", "."))).refine((value) => Number.isFinite(value) && Math.abs(value) < 1_000_000_000_000, "Le montant est trop élevé.");

export const financialAccountSchema = z.object({
  accountType: z.enum(financialAccountTypes, { message: "Choisissez un type de compte." }),
  accountName: z.string().trim().min(1, "Saisissez un intitulé.").max(200),
  institutionName: z.string().trim().min(1, "Saisissez un établissement.").max(200),
  accountReference: optionalText(100),
  initialBalance: amount,
  initialBalanceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Saisissez la date du solde initial."),
  openingDate: optionalDate,
  notes: optionalText(2000),
});

export const closeFinancialAccountSchema = z.object({ closingDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Saisissez une date de clôture valide.") });

export type FinancialAccountInput = z.infer<typeof financialAccountSchema>;
