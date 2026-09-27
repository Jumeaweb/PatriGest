export type SuccessiveDraft = {
  transactionType: "income" | "expense";
  financialAccountId: string;
  transactionDate: string;
  label: string;
  amount: string;
  categoryId: string;
  classificationPrecision: string;
};

export function nextSuccessiveDraft(previous: SuccessiveDraft): SuccessiveDraft {
  return { transactionType: previous.transactionType, financialAccountId: previous.financialAccountId, transactionDate: previous.transactionDate, label: "", amount: "", categoryId: "", classificationPrecision: "" };
}

export function hasUnsavedSuccessiveDraft(current: SuccessiveDraft, initial: SuccessiveDraft) {
  return (Object.keys(initial) as (keyof SuccessiveDraft)[]).some((key) => current[key] !== initial[key]);
}
