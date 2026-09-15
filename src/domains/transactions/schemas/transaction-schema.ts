import { z } from "zod";
const optionalText = z.string().trim().max(500).transform((v) => v || null);
const classificationPrecision = z.string().trim().refine((value) => [...value].length <= 160, "La précision ne peut pas dépasser 160 caractères.").transform((value) => value || null);
export const transactionSchema = z.object({ financialAccountId: z.uuid("Compte invalide."), transactionDate: z.iso.date("Date invalide."), transactionType: z.enum(["income", "expense"]), label: z.string().trim().min(1, "Le libellé est obligatoire.").max(160), amount: z.coerce.number().positive("Le montant doit être strictement positif.").max(999999999999.99), categoryId: z.union([z.uuid(), z.literal("")]).transform((v) => v || null), classificationPrecision, proofReference: optionalText, comment: optionalText });
export type TransactionInput = z.infer<typeof transactionSchema>;
export type TransactionFilters = { startDate?: string; endDate?: string; accountId?: string; type?: "income" | "expense" | "transfer"; categoryId?: string; query?: string; limit?: number; reportAccountIds?: string[] };
