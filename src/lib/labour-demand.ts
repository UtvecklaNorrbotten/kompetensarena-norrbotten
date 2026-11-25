import { monthOffset, type AfValue } from "./af-unemployment.ts";

export type DemandSelection = {
  field: string;
  group: string;
  metric: "new" | "remaining";
  duration: "all" | "10" | "source";
};
export type DemandModel = {
  totals: [string, string, AfValue, AfValue, AfValue, AfValue][];
  fields: [string, string, string, string, AfValue, AfValue, AfValue, AfValue][];
  groups: [string, string, string, string, AfValue][];
};
export type DemandPoint = { period: string; value: AfValue };
export type DemandRank = {
  code: string;
  label: string;
  value: AfValue;
  previous: AfValue;
  change: number | null;
};
export const demandNumber = (v: AfValue | undefined, decimals = 0): string =>
  v === "<5"
    ? "Sekretess (<5)"
    : v == null
      ? "Uppgift saknas"
      : v.toLocaleString("sv-SE", { maximumFractionDigits: decimals });
export const demandValue = (v: AfValue | undefined) => (typeof v === "number" ? v : null);
export function sumDemand(values: AfValue[]): AfValue {
  if (!values.length || values.some((v) => v === null)) return null;
  if (values.includes("<5")) return "<5";
  return (values as number[]).reduce((a, b) => a + b, 0);
}
export function demandSeries(
  model: DemandModel,
  selection: DemandSelection,
  periods?: string[],
): DemandPoint[] {
  const buckets = new Map<string, AfValue[]>();
  const { field, group, metric, duration } = selection;
  const push = (p: string, v: AfValue) => buckets.set(p, [...(buckets.get(p) ?? []), v]);
  if (group) {
    if (metric !== "remaining" || duration !== "source") return [];
    for (const [p, f, g, , v] of model.groups ?? [])
      if ((!field || f === field) && g === group) push(p, v);
  } else {
    const index = (duration === "10" ? 2 : 0) + (metric === "remaining" ? 1 : 0);
    if (field) {
      for (const [p, f, , , ...v] of model.fields ?? []) if (f === field) push(p, v[index]!);
    } else {
      for (const [p, , ...v] of model.totals) push(p, v[index]!);
    }
  }
  const sourceRows = group ? model.groups : field ? model.fields : model.totals;
  const times = periods ?? [...new Set((sourceRows ?? []).map((r) => r[0]))];
  return [...times]
    .sort()
    .map((period) => ({ period, value: sumDemand(buckets.get(period) ?? []) }));
}
export function rollingDemand(rows: DemandPoint[], metric: "new" | "remaining"): DemandPoint[] {
  const map = new Map(rows.map((r) => [r.period, r.value]));
  return rows.map((r) => {
    const values = Array.from({ length: 12 }, (_, i) => map.get(monthOffset(r.period, -i)) ?? null);
    const total = sumDemand(values);
    return {
      period: r.period,
      value: typeof total === "number" && metric === "remaining" ? total / 12 : total,
    };
  });
}
export function demandChange(value: AfValue, previous: AfValue): number | null {
  return typeof value === "number" && typeof previous === "number" ? value - previous : null;
}

export type DemandJsonStat = {
  id: string[];
  size: number[];
  value: (number | null)[];
  dimension: Record<
    string,
    { category: { index: Record<string, number>; label: Record<string, string> } }
  >;
};
export function decodeDemandLor(source: DemandJsonStat, geo: string) {
  const records: Record<string, string | number | null>[] = [];
  // JavaScript enumerates integer-like keys before other keys. JSON-stat's
  // category.index positions, not object insertion order, define cell order.
  const codes = source.id.map((id) =>
    Object.entries(source.dimension[id]!.category.index)
      .sort((a, b) => a[1] - b[1])
      .map(([code]) => code),
  );
  for (let flat = 0; flat < source.value.length; flat++) {
    let index = flat;
    const row: Record<string, string | number | null> = { value: source.value[flat] ?? null };
    for (let i = source.id.length - 1; i >= 0; i--) {
      row[source.id[i]!] = codes[i]![index % source.size[i]!]!;
      index = Math.floor(index / source.size[i]!);
    }
    if ((row["AARegion"] ?? row["Region"]) === geo) records.push(row);
  }
  return records;
}
