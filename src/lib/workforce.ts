// Public aggregate: period/geography, sex, category, age, measure, value, SCB status.
export type WorkforceRow = [string, string, string, string, string, number | null, string];
export type WorkforceDataset = {
  table: string;
  label: string;
  updated: string;
  periods: string[];
  group: string;
  categories: Record<string, string>;
  ages: Record<string, string>;
  measures: Record<string, string>;
  sexes: string[];
  units: Record<string, { base: string; decimals: number }>;
  selection: Record<string, string[]>;
  source: string;
  notes: string[];
  cells: number;
  groups?: Record<string, string[]>;
};
export type WorkforceCatalog = {
  fetched: string;
  datasets: Record<string, WorkforceDataset>;
  geographies: Record<string, string>;
  files: Record<string, { path: string; sha256: string }>;
};
export function workforceValue(row: WorkforceRow | undefined) {
  return row && !row[6] ? row[5] : null;
}
export function workforcePoint(
  rows: WorkforceRow[],
  period: string,
  sex: string,
  category: string,
  age: string,
  measure: string,
) {
  return rows.find(
    (r) => r[0] === period && r[1] === sex && r[2] === category && r[3] === age && r[4] === measure,
  );
}
export function workforceChange(
  rows: WorkforceRow[],
  period: string,
  sex: string,
  category: string,
  age: string,
  measure: string,
  info: WorkforceDataset,
) {
  // U4 switches from RAMS to BAS in 2022. YREG adds imputed occupations and 65–69 in 2023.
  if (
    (info.table === "TAB6371" && period === "2022") ||
    (info.table === "TAB4435" && ["2023", "2024"].includes(period)) ||
    (info.table === "TAB5543" && period === "2024")
  )
    return null;
  const value = workforceValue(workforcePoint(rows, period, sex, category, age, measure));
  const previous = `${Number(period.slice(0, 4)) - 1}${period.slice(4)}`;
  const old = workforceValue(workforcePoint(rows, previous, sex, category, age, measure));
  return value == null || old == null ? null : value - old;
}
export function workforceSegment(table: string, period: string) {
  if (table === "TAB6371") return period < "2022" ? "rams" : "bas";
  if (table === "TAB4435")
    return period < "2023" ? "before2023" : period < "2024" ? "2023" : "2024";
  if (table === "TAB5543") return period < "2024" ? "before2024" : "2024";
  return "all";
}
