import type { FinancialAccount } from "@/types/database";

const frenchAccountNameCollator = new Intl.Collator("fr", {
  sensitivity: "base",
  usage: "sort",
});

export function sortFinancialAccountsByName<T extends Pick<FinancialAccount, "account_name">>(
  accounts: readonly T[],
) {
  return accounts
    .map((account, initialIndex) => ({ account, initialIndex }))
    .sort((left, right) =>
      frenchAccountNameCollator.compare(left.account.account_name, right.account.account_name)
      || left.initialIndex - right.initialIndex,
    )
    .map(({ account }) => account);
}
