type Period = { start_date: string; end_date: string };
type Report = { period_start: string; period_end: string };

export function getReportPreparationGuidance<T extends Period>(
  periods: readonly T[],
  reports: readonly Report[],
) {
  const suggested = periods.find(
    (period) =>
      period.start_date.slice(0, 4) === period.end_date.slice(0, 4) &&
      period.end_date.endsWith("-12-31") &&
      !reports.some(
        (report) =>
          report.period_start === period.start_date &&
          report.period_end === period.end_date,
      ),
  ) ?? null;

  return {
    suggested,
    state: periods.length === 0 ? "no_period" : suggested ? "suggested" : "manual",
  } as const;
}
