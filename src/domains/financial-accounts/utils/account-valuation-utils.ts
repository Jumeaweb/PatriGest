import type { AccountValuation } from "@/types/database";

export function getCurrentValuationValue(
  initialBalance: number,
  valuations: AccountValuation[],
) {
  if (valuations.length === 0) {
    return { value: initialBalance, valuation: null };
  }

  const valuation = [...valuations].sort((a, b) =>
    b.valuation_date.localeCompare(a.valuation_date),
  )[0];
  return { value: valuation.value, valuation };
}

export function getAccountValuationAtDate(
  valuations: readonly AccountValuation[],
  valuationDate: string,
) {
  return valuations.find((valuation) => valuation.valuation_date === valuationDate) ?? null;
}
