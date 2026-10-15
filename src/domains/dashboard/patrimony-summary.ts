import type { AccountValuation, FinancialAccount, Transaction } from "@/types/database";
import type { PatrimonyAbsenceConfirmationState } from "@/domains/assets-liabilities/patrimony-absence";
import { getCurrentPatrimonyValue } from "@/domains/financial-accounts/utils/financial-account-utils";
import { getDossierDebtState, getDossierPropertyState } from "@/domains/protected-persons/dossier-information-states";
import { assemblePatrimonySummary, type PatrimonySummary } from "./patrimony-summary-core";

export type {
  PatrimonyIncompleteReason,
  PatrimonyIncompleteReasonCode,
  PatrimonyInformationState,
  PatrimonySummary,
  PatrimonySummaryComponent,
} from "./patrimony-summary-core";

type SummaryAccount = FinancialAccount & { valuations: AccountValuation[]; transactions: Transaction[] };
type SummaryProperty = { status: "active" | "disposed"; estimated_value: number | null; archived_at?: string | null };
type SummaryDebt = { status: "active" | "settled"; current_balance: number | null };

type PatrimonySummaryInput = {
  accounts: readonly SummaryAccount[];
  properties: readonly SummaryProperty[];
  debts: readonly SummaryDebt[];
  confirmations: PatrimonyAbsenceConfirmationState;
};

export function getPatrimonySummary({ accounts, properties, debts, confirmations }: PatrimonySummaryInput): PatrimonySummary {
  const propertyState = getDossierPropertyState(properties, confirmations.realEstate !== null);
  const debtState = getDossierDebtState(debts, confirmations.activeDebt !== null);

  return assemblePatrimonySummary({
    bankingAmount: accounts.length ? getCurrentPatrimonyValue([...accounts]) : null,
    propertyState,
    propertyKnownValues: properties.flatMap((property) =>
      property.archived_at == null && property.status === "active" && property.estimated_value !== null
        ? [property.estimated_value]
        : [],
    ),
    debtState,
    debtKnownBalances: debts.flatMap((debt) =>
      debt.status === "active" && debt.current_balance !== null ? [debt.current_balance] : [],
    ),
  });
}
