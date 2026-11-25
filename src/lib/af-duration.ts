/** AF:s kumulativa mått. Sekretessgränser får aldrig subtraheras som exakta tal. */
export type DurationRow = {
  geo_code: string;
  period: string;
  dimension_type: string;
  dimension_value: string;
  total: number | null;
  over6: number | null;
  over12: number | null;
  over24: number | null;
  lower6: boolean;
  lower12: boolean;
  lower24: boolean;
};
export type DurationMeasure = "over6" | "over12" | "over24";
export type DurationUnit = "count" | "share";
export const durationLabels = {
  over6: "Mer än 6 månader",
  over12: "Mer än 12 månader",
  over24: "Mer än 24 månader",
};
export const bandLabels = [
  "Högst 6 månader",
  "Mer än 6–12 månader",
  "Mer än 12–24 månader",
  "Mer än 24 månader",
];
export function isLower(row: DurationRow, measure: DurationMeasure) {
  return row[measure === "over6" ? "lower6" : measure === "over12" ? "lower12" : "lower24"];
}
export function durationValue(
  row: DurationRow | undefined,
  measure: DurationMeasure,
  unit: DurationUnit,
): number | null {
  if (!row || isLower(row, measure)) return null;
  const value = row[measure];
  if (value === null || value < 0 || (row.total !== null && value > row.total)) return null;
  if (unit === "count") return value;
  return row.total !== null && row.total > 0 ? (100 * value) / row.total : null;
}
export function durationBands(row: DurationRow, unit: DurationUnit): (number | null)[] {
  const values = [row.total, row.over6, row.over12, row.over24];
  if (
    row.lower6 ||
    row.lower12 ||
    row.lower24 ||
    values.some((v) => v === null || v < 0) ||
    values.some((v, i) => i > 0 && v! > values[i - 1]!)
  )
    return [null, null, null, null];
  const [total, six, twelve, twentyfour] = values as number[];
  const bands = [total! - six!, six! - twelve!, twelve! - twentyfour!, twentyfour!];
  return unit === "count"
    ? bands
    : total! > 0
      ? bands.map((v) => (100 * v) / total!)
      : [null, null, null, null];
}
export function formatDuration(value: number | null | undefined, unit: DurationUnit) {
  return value == null
    ? "Uppgift saknas"
    : value.toLocaleString("sv-SE", { maximumFractionDigits: unit === "share" ? 1 : 0 }) +
        (unit === "share" ? " %" : "");
}
export function durationText(
  row: DurationRow | undefined,
  measure: DurationMeasure,
  unit: DurationUnit,
) {
  if (row && isLower(row, measure))
    return unit === "count"
      ? row[measure] === 0
        ? "Sekretessmarkerat"
        : `Minst ${formatDuration(row[measure], unit)} (sekretess)`
      : "Kan inte beräknas (sekretess)";
  return formatDuration(durationValue(row, measure, unit), unit);
}
export function afPeriod(period: string) {
  return new Date(`${period}-01T12:00:00Z`).toLocaleDateString("sv-SE", {
    year: "numeric",
    month: "long",
    timeZone: "Europe/Stockholm",
  });
}
