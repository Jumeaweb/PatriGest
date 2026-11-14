type Period = {
  id: string;
  start_date: string;
  end_date: string;
  status: "open" | "closed";
};
type Report = { period_start: string; period_end: string };

export type ManagementReportPeriodOption<T extends Period = Period> = T & {
  covered: boolean;
};

export function getManagementReportPeriodOptions<T extends Period>(
  periods: readonly T[],
  reports: readonly Report[],
) : ManagementReportPeriodOption<T>[] {
  return [...periods]
    .sort((left, right) =>
      right.start_date.localeCompare(left.start_date) ||
      right.end_date.localeCompare(left.end_date) ||
      right.id.localeCompare(left.id),
    )
    .map((period) => ({
      ...period,
      covered: reports.some(
        (report) =>
          report.period_start <= period.end_date &&
          report.period_end >= period.start_date,
      ),
    }));
}
