type DebtPeriod = {
  start_date: string | null;
  settled_at: string | null;
  status: "active" | "settled";
};

type DatedBalance = {
  balance_date: string;
  cancelled_at: string | null;
  remaining_balance: number;
};

type DebtPeriodPresentation = {
  status: string;
  settlementDate?: string;
  warnings?: string[];
};

export function getDebtForReportPeriod<Balance extends DatedBalance>(
  debt: DebtPeriod & { balances: readonly Balance[] },
  periodStart: string,
  periodEnd: string,
): { balance: Balance | null; presentation: DebtPeriodPresentation } | null {
  const { start_date: startDate, settled_at: recordedSettlement } = debt;
  if (startDate && startDate > periodEnd) return null;

  const settlement = debt.status === "settled" && recordedSettlement &&
    (!startDate || recordedSettlement >= startDate) ? recordedSettlement : null;
  if (settlement && settlement < periodStart) return null;

  const settlementDate = settlement && settlement <= periodEnd ? settlement : undefined;
  const uncertainStatus = settlement === null && (debt.status === "settled" || recordedSettlement !== null);
  const status = uncertainStatus ? "Statut historique indéterminé" : settlementDate ? "Soldée" : "Active";
  const warnings: string[] = [];
  if (!startDate) warnings.push("Date de début non renseignée.");
  if (uncertainStatus) warnings.push("Date de clôture absente ou incohérente.");

  let balance: Balance | null = null;
  let beforeStart = false;
  let afterSettlement = false;
  for (const candidate of debt.balances) {
    if (candidate.cancelled_at !== null || candidate.balance_date > periodEnd) continue;
    if (startDate && candidate.balance_date < startDate) {
      beforeStart = true;
      continue;
    }
    if (settlementDate && candidate.balance_date > settlementDate) {
      afterSettlement = true;
      continue;
    }
    if (balance === null || candidate.balance_date > balance.balance_date) balance = candidate;
  }

  if (beforeStart) warnings.push("Situation antérieure au début de la dette ignorée.");
  if (afterSettlement) warnings.push("Situation postérieure à la clôture de la dette ignorée.");
  if (settlementDate && (balance?.balance_date !== settlementDate || balance.remaining_balance !== 0)) {
    warnings.push("Aucune situation à 0 € à la date de clôture.");
  }

  return {
    balance,
    presentation: {
      status,
      ...(settlementDate ? { settlementDate } : {}),
      ...(warnings.length ? { warnings } : {}),
    },
  };
}
