// Public SCB aggregate: period, sex, location perspective, category, count,
// published employment rate, count status, rate status.
export type EmploymentRow = [
  string,
  string,
  string,
  string,
  number | null,
  number | null,
  string,
  string,
];
export type EmploymentMetric = "count" | "share" | "rate" | "change" | "percent";
export type EmploymentDataset = {
  table: string;
  label: string;
  updated: string;
  periods: string[];
  categories: Record<string, string>;
  total: string | null;
  age: string;
  dimension: string;
  perspectives: string[];
  rate: boolean;
  selection: Record<string, string[]>;
  source: string;
  rate_checks: number;
};
export type EmploymentCatalog = {
  fetched: string;
  datasets: Record<string, EmploymentDataset>;
  geographies: Record<string, string>;
  files: Record<string, { path: string; sha256: string }>;
};
export const metricNames: Record<EmploymentMetric, string> = {
  count: "Antal",
  share: "Andel av sysselsatta",
  rate: "Sysselsättningsgrad",
  change: "Förändring i antal",
  percent: "Procentuell förändring",
};
export function previousEmploymentPeriod(period: string) {
  return `${Number(period.slice(0, 4)) - 1}${period.slice(4)}`;
}
export function employmentValue(
  row: EmploymentRow | undefined,
  metric: EmploymentMetric,
  previous?: EmploymentRow,
  total?: EmploymentRow,
): number | null {
  if (!row) return null;
  if (metric === "rate") return row[7] ? null : row[5];
  const n = row[6] ? null : row[4];
  if (n === null) return null;
  if (metric === "count") return n;
  if (metric === "share")
    return total && !total[6] && total[4] !== null && total[4] > 0 ? (100 * n) / total[4] : null;
  const old = previous && !previous[6] ? previous[4] : null;
  if (old == null) return null;
  return metric === "change" ? n - old : old > 0 ? (100 * (n - old)) / old : null;
}
export function employmentSeries(
  rows: EmploymentRow[],
  info: EmploymentDataset,
  sex: string,
  perspective: string,
  category: string,
  metric: EmploymentMetric,
) {
  const subset = rows.filter((r) => r[1] === sex && r[2] === perspective);
  const byPeriod = new Map(subset.filter((r) => r[3] === category).map((r) => [r[0], r]));
  const totals = new Map(subset.filter((r) => r[3] === info.total).map((r) => [r[0], r]));
  return info.periods.map((period) => {
    const row = byPeriod.get(period);
    const previous = previousEmploymentPeriod(period);
    // Never bridge the RAMS 2011 break (older years are not imported), or a
    // missing year. Data sets and geographic perspectives are never combined.
    const methodBreak =
      ["TAB3204", "TAB3260", "TAB1786"].includes(info.table) && ["2022", "2024"].includes(period);
    const value =
      methodBreak && (metric === "change" || metric === "percent")
        ? null
        : employmentValue(row, metric, byPeriod.get(previous), totals.get(period));
    const status = row?.[metric === "rate" ? 7 : 6] ?? "";
    return { period, value, status };
  });
}
export function employmentNumber(value: number | null | undefined, status = "", decimals = 0) {
  if (status) return `Uppgift saknas (SCB: ${status})`;
  return value == null
    ? "Uppgift saknas"
    : value.toLocaleString("sv-SE", { maximumFractionDigits: decimals });
}
