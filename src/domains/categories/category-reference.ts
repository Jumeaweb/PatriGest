import type { Category } from "@/types/database";
import type { FinancialAccountType, TransactionType } from "@/types/database";

export type ResolvedCategoryReference = {
  personalCategory: Category | null;
  officialCategory: Category;
  officialCode: string;
};

export function resolveCategoryReference(category: Category, officialCategories: readonly Category[]): ResolvedCategoryReference | null {
  const officialCategory = category.is_system ? category : officialCategories.find((candidate) => candidate.id === category.official_category_id);
  if (!officialCategory?.official_code) return null;
  return { personalCategory: category.is_system ? null : category, officialCategory, officialCode: officialCategory.official_code };
}

const placementAccountTypes: readonly FinancialAccountType[] = ["life_insurance", "other_investment", "securities_account"];

export function resolveTransferOfficialCodeForFutureReport(input: {
  transactionType: TransactionType;
  accountType: FinancialAccountType;
}): "DEP-8-01" | null {
  // Le mouvement reste un virement dans PatriGest. Ce classement n'est destiné
  // qu'au futur moteur du compte de gestion et ne modifie aucune transaction.
  return input.transactionType === "transfer_in" && placementAccountTypes.includes(input.accountType)
    ? "DEP-8-01"
    : null;
}
