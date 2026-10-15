export type PatrimonyInformationState = "unreported" | "confirmed_absent" | "complete" | "incomplete";

export type PatrimonyIncompleteReasonCode =
  | "no_financial_accounts"
  | "unconfirmed_real_estate_absence"
  | "missing_real_estate_estimates"
  | "unconfirmed_active_debt_absence"
  | "missing_active_debt_balances";

export type PatrimonyIncompleteReason = {
  code: PatrimonyIncompleteReasonCode;
  message: string;
  missingCount?: number;
};

export type PatrimonySummaryComponent = {
  state: PatrimonyInformationState;
  amount: number | null;
  incompleteReasons: PatrimonyIncompleteReason[];
};

export type PatrimonySummary = {
  banking: PatrimonySummaryComponent;
  realEstate: PatrimonySummaryComponent;
  activeDebts: PatrimonySummaryComponent;
  netEstimatedValue: number | null;
  incompleteReasons: PatrimonyIncompleteReason[];
};

type ComponentState = { informationState: PatrimonyInformationState };
type PropertyState = ComponentState & { missingActiveValues: number };
type DebtState = ComponentState & { missingBalances: number };

type PatrimonySummaryCoreInput = {
  bankingAmount: number | null;
  propertyState: PropertyState;
  propertyKnownValues: readonly number[];
  debtState: DebtState;
  debtKnownBalances: readonly number[];
};

const toCents = (amount: number) => Math.round(amount * 100);
const fromCents = (amount: number) => amount / 100;
const sumCents = (amounts: readonly number[]) => amounts.reduce((total, amount) => total + toCents(amount), 0);
const isComplete = (state: PatrimonyInformationState) => state === "complete" || state === "confirmed_absent";

export function assemblePatrimonySummary({
  bankingAmount,
  propertyState,
  propertyKnownValues,
  debtState,
  debtKnownBalances,
}: PatrimonySummaryCoreInput): PatrimonySummary {
  const bankingReasons: PatrimonyIncompleteReason[] = bankingAmount === null ? [{
    code: "no_financial_accounts",
    message: "Aucun compte bancaire ou placement n’est renseigné.",
  }] : [];
  const bankingCents = bankingAmount === null ? null : toCents(bankingAmount);
  const banking: PatrimonySummaryComponent = {
    state: bankingAmount === null ? "unreported" : "complete",
    amount: bankingCents === null ? null : fromCents(bankingCents),
    incompleteReasons: bankingReasons,
  };

  const propertyCents = propertyState.informationState === "confirmed_absent"
    ? 0
    : propertyKnownValues.length ? sumCents(propertyKnownValues) : null;
  const propertyReasons: PatrimonyIncompleteReason[] = propertyState.informationState === "unreported"
    ? [{ code: "unconfirmed_real_estate_absence", message: "L’absence de bien immobilier actif n’est pas confirmée." }]
    : propertyState.informationState === "incomplete"
      ? [{
        code: "missing_real_estate_estimates",
        message: propertyState.missingActiveValues > 1
          ? `${propertyState.missingActiveValues} biens immobiliers actifs ne disposent pas d’une estimation.`
          : "1 bien immobilier actif ne dispose pas d’une estimation.",
        missingCount: propertyState.missingActiveValues,
      }]
      : [];
  const realEstate: PatrimonySummaryComponent = {
    state: propertyState.informationState,
    amount: propertyCents === null ? null : fromCents(propertyCents),
    incompleteReasons: propertyReasons,
  };

  const debtCents = debtState.informationState === "confirmed_absent"
    ? 0
    : debtKnownBalances.length ? sumCents(debtKnownBalances) : null;
  const debtReasons: PatrimonyIncompleteReason[] = debtState.informationState === "unreported"
    ? [{ code: "unconfirmed_active_debt_absence", message: "L’absence de dette active n’est pas confirmée." }]
    : debtState.informationState === "incomplete"
      ? [{
        code: "missing_active_debt_balances",
        message: debtState.missingBalances > 1
          ? `${debtState.missingBalances} dettes actives ne disposent pas d’un solde courant.`
          : "1 dette active ne dispose pas d’un solde courant.",
        missingCount: debtState.missingBalances,
      }]
      : [];
  const activeDebts: PatrimonySummaryComponent = {
    state: debtState.informationState,
    amount: debtCents === null ? null : fromCents(debtCents),
    incompleteReasons: debtReasons,
  };

  const incompleteReasons = [...bankingReasons, ...propertyReasons, ...debtReasons];
  const netEstimatedValue = isComplete(banking.state) && isComplete(realEstate.state) && isComplete(activeDebts.state)
    ? fromCents(bankingCents! + propertyCents! - debtCents!)
    : null;

  return { banking, realEstate, activeDebts, netEstimatedValue, incompleteReasons };
}
